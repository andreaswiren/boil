# Backup and restore

Owner: `backup-restore-engineer`. Requirements: `SZ-HSM-011`, `SZ-HSM-012`,
`SZ-AUTH-007`, `SZ-OS-007`.

The design is NetHSM's (`docs/system-design.md` §Backup and Restore, commit
`2a1bac5d`), adapted to a Debian appliance. It is copied deliberately, because it
solves a problem most backup designs get wrong: **making automated backup safe.**

## 1. The property that drives everything

A backup job runs unattended, on a schedule, with stored credentials. So the
question is not "can we encrypt the backup" but **"what does an attacker get by
stealing the backup client?"**

The answer here is: nothing readable. The backup role can fetch backups forever
and decrypt none of them.

That is achieved by requiring **two independent secrets to read a backup**, held
by different parties, and giving the backup client neither:

| Secret | Held by | Used for |
|--------|---------|----------|
| **Backup Key** — derived from a Backup Passphrase | an administrator, at configuration time | the outer encryption layer |
| **Unlock Key** — derived from the Unlock Passphrase | the operator who unlocks the appliance (`SZ-HSM-008`) | the inner layer, via the Domain Key |
| *(neither)* | the backup client | fetching bytes |

## 2. Layers

A backup is **double-encrypted**, and the inner layer is not something the backup
process performs — it is the encryption the data is already under at rest.

```
backup file
└── AES-256-GCM under the Backup Key                      ← outer, added at backup time
    ├── application + audit + key-metadata stores          } already encrypted
    │   AES-256-GCM under the Domain Key                   } under the Domain Key
    ├── the locked Domain Key                              ← wrapped to the Unlock Key ONLY
    │   (not wrapped to this device's Device Key)
    ├── device id of the appliance the backup was taken on
    └── manifest: schema version, taken-at, appliance id, store versions
```

`signerd` **serialises without decrypting**. It never holds plaintext store
contents in order to back them up, which means a compromised backup path cannot
become a disclosure path.

## 3. The locked Domain Key is what makes a restore portable

At rest the Domain Key is wrapped to the Device Key, which is sealed to *this*
TPM. A backup containing only that would be restorable to exactly one machine —
the one that may have just burned down.

So the backup additionally carries the **locked Domain Key**: the Domain Key
wrapped to the Unlock Key alone, with no Device Key involved. That is what makes
the backup portable, and it is also precisely why reading a backup needs the
Unlock Passphrase.

**The trade, stated plainly:** restoring to different hardware requires the
Unlock Passphrase **that was current when the backup was taken**. An operator who
rotates the unlock passphrase and does not record which backups precede the
rotation has made those backups unrestorable to new hardware. `SZ-HSM-012`
requires the manifest to carry the passphrase epoch so the appliance can say
*which* passphrase a given backup needs, rather than failing with a decryption
error that reads like corruption.

## 4. The endpoint does not exist until it is safe

`POST /system/backup` returns **404 until a Backup Passphrase has been set** by
an administrator. Not 403, and not a backup encrypted with a default.

The failure mode this prevents is the one that actually happens: backups
configured on day one, the passphrase step deferred, and a year of unencrypted
backups on a NAS that nobody re-examined. An endpoint that is absent cannot be
called by accident.

Changing the Backup Passphrase does not re-encrypt existing backups. Old backups
remain readable with the old passphrase, so the passphrase is versioned in the
manifest (§3) and the retention policy states how long each epoch must be kept.

## 5. Restore has two shapes, and one of them deletes data

| From state | Shape | What happens |
|-----------|-------|--------------|
| `Unprovisioned` | **full restore** | Everything, including device-local configuration: network, TLS certificate, unlock passphrase, boot mode. The appliance becomes the backed-up appliance. |
| `Operational` | **partial restore** | Users, keys, namespaces and global configuration. Device-local configuration (network, TLS) is **not** touched, because it belongs to this box. |

**A partial restore is destructive and the operator is told so before it runs.**
Users, keys and namespaces that exist on the appliance and are absent from the
backup are **removed** — restore is "make the state match the backup", not
"merge". This is NetHSM's behaviour and it is the correct one: a merge-restore
silently resurrects a user that was deliberately deleted.

So the restore flow is:

1. Upload, decrypt the outer layer, parse the manifest. **Nothing is written.**
2. Present a diff: *this restore will remove 3 users and 1 key, and add 7 keys.*
   Named, not counted only.
3. Require step-up authentication against that diff (`SZ-AUTH-003`), so approval
   is bound to what was shown.
4. Write, inside one transaction, then re-derive the Domain Key from the supplied
   Unlock Passphrase.
5. Audit the whole thing, including the diff as presented (`SZ-AUD-001`).

A restore that cannot show the diff does not proceed. "Restore anyway" is not a
button.

## 6. Compatibility

**A backup taken by any previous version must remain restorable.** This is a
standing constraint on the schema, not a goal: the manifest carries a schema
version and a per-store version, and restore runs the migration chain forward
from whatever it finds. Dropping support for an old schema version is a
release-blocking decision, not a cleanup.

The corollary is that the backup format is a contract (`contracts/ownership.md`),
and changing it needs contract review like any other.

## 7. What a restore cannot recover

Stated because an operator will assume otherwise at the worst moment:

- **Private keys that never left the HSM.** A backup contains key *metadata*,
  policy and certificates. Non-exportable key material is recovered by the DKEK
  path (`spec/05-hsm-dkek.md`) against the secondary HSM — a different procedure,
  different secrets and a different ceremony. `SZ-HSM-001`…`005`.
- **The Device Key.** It is sealed to the TPM of the appliance it was generated
  on and is deliberately not in the backup. A restore onto new hardware generates
  a new one; that is the intent.

So full disaster recovery is **two** procedures, and the runbook must say so:
restore the backup *and* perform the DKEK restore. An operator who does only the
first has an appliance that knows about keys it cannot use.

## 8. How this is verified

- Backup fetched with `Backup`-role credentials cannot be decrypted with those
  credentials alone — asserted, not assumed.
- Backup + Backup Passphrase, without the Unlock Passphrase, does not yield store
  contents.
- Restore to a different appliance succeeds with the epoch-correct Unlock
  Passphrase and fails with a *named* error for the wrong epoch.
- Partial restore removes exactly what the diff said it would.
- A backup produced by the previous release restores onto the current one. This
  test is added at the release that creates the format and never deleted.
- `POST /system/backup` is absent before a Backup Passphrase exists.
