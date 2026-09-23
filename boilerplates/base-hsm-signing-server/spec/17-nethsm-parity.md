# NetHSM parity — gap analysis and what we adopt

Measured against **NetHSM** (`github.com/Nitrokey/nethsm`, commit
`2a1bac5d97b1156ed2f9523360c11e0441537c52`), reading `docs/system-design.md`,
`docs/developer-documentation.md` and `docs/nethsm-api.yaml` — 56 endpoints, 78
operations. The user guide at `docs.nitrokey.com/nethsm/` was not reachable from
the environment this was written in, so nothing here rests on it; every claim
below traces to a file in that repository at that commit.

The goal stated for this appliance is: **a standard, maintainable OS, hardened
to NetHSM's standard, with an API at least as feature-complete and as safe.**
Two of those three are achievable. The third is not, and this document says so
rather than implying parity we cannot deliver.

---

## 1. The architecture gap we cannot close, and what we do instead

NetHSM's security does not come from configuration. It comes from a trusted
computing base small enough to reason about:

| NetHSM | Us | Honest verdict |
|--------|----|----------------|
| **Muen separation kernel**, Ada, isolation properties formally verified in SPARK | Debian 13 kernel + systemd | **Not matchable.** Muen's guarantee is that a compromised Ethernet driver cannot reach the key store. Ours is that a compromised nginx must also defeat AppArmor, a UID boundary and seccomp. That is defence in depth, not isolation, and the difference is a proof versus a stack of mitigations. |
| **S-Keyfender**, a MirageOS unikernel in OCaml — no shell, no libc, no package manager | `signzone-signerd`, a Rust daemon on a full userland | Partly. Rust gives memory safety; the surrounding TCB does not shrink. We keep the signer small and give it the **only** path to the HSM, so the large TCB is not on the key path — but it is on the machine. |
| **Verified Boot**: RSA-4096 key in CBFS in Coreboot, Signed Block Stream via GRUB 2, unconditional signature verification, root of trust unmodifiable without reflashing | UEFI Secure Boot + dm-verity on the root image | Weaker and differently shaped. A Debian root is mutable by design; dm-verity over a read-only root recovers most of it, but the root of trust is the platform's key hierarchy, not a key fused into our firmware. |
| **Dual hardware entropy**: discrete TRNG over RS-232 plus TPM RNG, both fed to the pools; **system refuses to boot** if either is absent at first boot, halts if both fail in operation | Kernel CSPRNG, `getrandom(2)`, TPM RNG where present | Adoptable in the part that matters: the *refuse to proceed* behaviour. See `SZ-SEC-011`. |
| TCB = separation kernel + one unikernel | TCB = kernel, systemd, nginx, Node, Postgres, OpenSC, PC/SC | Orders of magnitude larger. This is the price of the maintainability the brief asks for, and it is a real price. |

**Where that leaves us.** We are not a NetHSM substitute for a threat model that
assumes a remote attacker with a kernel exploit. We are a maintainable appliance
whose *design decisions* are NetHSM's, on an OS an ordinary team can patch. The
threat model (`spec/02-threat-model.md`) must say that in those words, because a
compliance reader who sees "hardened to NetHSM standard" will otherwise assume
the isolation proof came with it.

---

## 2. The gap that matters most: **we have no Locked state**

NetHSM has four states — `Unprovisioned`, `Locked`, `Operational`, `Failed` —
and the `Locked` state is the whole design. A provisioned NetHSM boots with **no
access to its own key store**: the store's contents are encrypted with a *Domain
Key* which exists only in memory, recovered at boot either from a TPM-sealed
*Device Key* (unattended) or by an operator posting an *Unlock Passphrase* to
`/unlock` (attended).

We have `setup mode` and then "running". A stolen disk from our appliance yields
the Postgres database, the audit log and every wrapped-key backup, protected only
by whatever full-disk encryption the installer configured and by the HSM PIN for
the keys themselves. NetHSM's equivalent yields ciphertext.

This is portable to Debian in full, and it is the single highest-value thing to
adopt. `SZ-HSM-006` … `SZ-HSM-010` below.

The two-slot mechanism is worth copying exactly, because its failure mode is
designed: slot 1 holds the Domain Key wrapped to the Device Key alone
(unattended boot); slot 0 holds it wrapped to the Unlock Key, itself wrapped to
the Device Key (attended). Enabling unattended boot *populates* slot 1;
disabling it *overwrites* slot 1. Unattended decryption failure falls back to
attended rather than failing open. At no point is the passphrase or the derived
key persisted.

---

## 3. API gap

NetHSM exposes 78 operations. Ours specifies a signing-request lifecycle
(`SZ-API-001` … `SZ-API-004`) and nothing else. That is not a smaller API, it is
a different and much narrower product surface — and several of the missing pieces
are operational necessities rather than features.

**Missing and worth adopting:**

| NetHSM | Why it matters here | Requirement |
|--------|--------------------|-------------|
| `GET /health/alive`, `/health/ready`, `/health/state`, `/health/diagnose` | `state` is the one that matters: a caller must be able to learn we are `Locked` without authenticating, or every client failure looks identical. | `SZ-API-005` |
| `GET /metrics` with a dedicated **`Metrics`** role | Monitoring must not hold an operator credential. A role whose only power is reading counters is cheap and removes a standing privilege. | `SZ-API-006` |
| `POST /unlock`, `POST /lock` | Follows from §2. `lock` matters too: an operator who suspects compromise can return the appliance to ciphertext without a reboot. | `SZ-HSM-008` |
| `POST /provision` | One-shot initial provisioning as an API operation, not a wizard-only path, so a fleet can be built reproducibly. | `SZ-INS-005` |
| `POST /system/backup`, `POST /system/restore`, `PUT /config/backup-passphrase` | §4. | `SZ-HSM-011` |
| `POST /system/update` → `POST /system/commit-update` / `POST /system/cancel-update` | §5. | `SZ-OS-006` |
| `POST /system/factory-reset` | A defined, audited destruction path. Without one, decommissioning is improvised. | `SZ-OS-007` |
| `GET /keys/{id}/public.pem`, `POST /keys/{id}/csr.pem`, `GET/PUT/DELETE /keys/{id}/cert` | We have certificate *provider* docs but no key-object certificate lifecycle on the API. A signing appliance whose CSR step is manual will have its CSR step done wrong. | `SZ-API-007` |
| `PUT/DELETE /keys/{id}/restrictions/tags/{tag}` and `GET/PUT/DELETE /users/{id}/tags/{tag}` | Tag-based restriction: a key may only be used by a user carrying a matching tag. This is a second, orthogonal authorization axis to our policy engine and it is enforced at the key rather than in policy. | `SZ-AUTH-005` |
| `GET /namespaces`, `PUT/DELETE /namespaces/{id}` | Multi-tenant separation inside one appliance. Relevant the moment two teams share a device. | `SZ-AUTH-006` |
| `POST /random` | Deliberately **not adopted**. It turns the appliance into a general-purpose RNG service and widens the attack surface for no signing benefit. Recorded as a conscious divergence. | — |
| `POST /keys/{id}/encrypt`, `/decrypt` | **Not adopted.** A signing appliance that also decrypts is a decryption oracle; NetHSM is a general-purpose HSM and we are not. Recorded as a conscious divergence. | — |
| Cluster endpoints (`/cluster/*`) | **Not adopted.** NetHSM clusters through `etcd` and can enter `Failed` on quorum loss. Our DR story is a second HSM plus DKEK restore, which is simpler to operate and has no quorum failure mode. | — |

**Safety mechanisms in their API we lack:**

- **Rate limiting with stated numbers.** NetHSM: one failed unlock attempt per
  second per IP, and one failed authentication per second per IP *and username*.
  Ours says "rate limiting" in prose with no number, which is not checkable.
  `SZ-SEC-006`.
- **Explicit role enum.** `Administrator | Operator | Metrics | Backup`. Four
  roles, each with a stated power. `SZ-AUTH-007`.
- **A Backup role that cannot read what it backs up.** §4. `SZ-HSM-011`.

---

## 4. Backup: their design is better than ours and should be copied

NetHSM's backup is **double-encrypted**, and the outer layer exists to make
automated backup safe:

- The *Backup Key* is derived from a *Backup Passphrase* set by an administrator,
  and the backup endpoint **does not exist** until it has been set.
- The outer layer is the Backup Key. The inner layers are already-encrypted
  stores (Domain Key / Device Key).
- **Reading a backup requires both the Backup Key and an Unlock Key.** So a
  backup client holding only `Backup`-role credentials can fetch backups forever
  and decrypt none of them.
- The `locked Domain Key` travels *in* the backup so it can be restored to
  different hardware — with the trade stated plainly: restoring to another device
  requires the Unlock Passphrase that was current when the backup was taken.
- Partial (operational) restore **removes** users, keys and namespaces present on
  the device and absent from the backup. Destructive, documented, deliberate.
- A backup from any previous version must remain restorable.

Ours says wrapped backups "may be stored with checksum/metadata". That is not a
backup design. `SZ-HSM-011`, `SZ-HSM-012`.

---

## 5. Update: A/B with a separate commit step

NetHSM streams the image to the **inactive** partition while verifying its
signature and *eligibility* (downgrade across a major version is refused), and
**only if** both succeed does it enable the commit endpoint. Commit arms a
one-shot boot into the new partition; failure to boot falls back automatically.
Updates are manual — there is no OTA.

Ours has no specified update path at all. On Debian the same shape is available
(A/B root, `systemd-boot` or GRUB one-shot entry, `dm-verity` root hash checked
before commit), and the properties to preserve are: verify before write is
committed, separate the commit from the upload, one-shot boot, automatic
rollback, refuse downgrades that would migrate data backwards. `SZ-OS-006`.

---

## 6. What we have that NetHSM does not

Not a gap list in one direction. These are ours and they should not be lost while
chasing parity:

- **Authenticode and PowerShell signing on Linux** with RFC3161 timestamps.
  NetHSM signs digests; it has no opinion about PE files.
- **Approval workflow with transaction binding** — artifact digest, profile,
  requester, ref, expiry — and a PWA that approves against those details rather
  than a push notification. NetHSM has roles, not approvals.
- **Signing policy bound to CI identity** (workload OIDC), so a signature is
  authorized against *what is being built by whom*, not only *who called*.
- **Append-only hash-chained audit log** with remote syslog. NetHSM notes that
  `etcd` keeps a modification log and says plainly it is **"currently not used"**
  for accountability.
- **A DCUI on tty1** and a physical maintenance credential.

---

## 7. Divergences recorded on purpose

A parity document that lists only gaps invites someone to close them all. These
are decided:

| Not adopted | Because |
|-------------|---------|
| `POST /random` | A signing appliance is not an entropy service. |
| `encrypt` / `decrypt` operations | Would make it a decryption oracle. Out of product scope. |
| `/cluster/*` and `etcd` | Introduces a `Failed` state on quorum loss. Our DR is a second HSM plus DKEK restore. |
| Muen / MirageOS | The brief asks for a maintainable standard OS. This is the trade being made, and §1 states what it costs. |
| OTA updates | NetHSM does not do them either, and for the same reason. |
