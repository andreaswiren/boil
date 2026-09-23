# Nitrokey HSM 2, PKCS#11 and the DKEK

Owner: `hsm-pkcs11-engineer` with `dkek-recovery-engineer`. Requirements:
`SZ-HSM-001`…`005`, `SZ-SEC-001`, `SZ-AUTH-003`.

Mechanism verified against OpenSC at `master` — `doc/tools/sc-hsm-tool.1.xml` and
`src/tools/sc-hsm-tool.c` — not from memory. The details below are the ones a
ceremony gets wrong.

## 1. The device, addressed by identity and not by order

Nitrokey HSM 2 is a SmartCard-HSM reached through PC/SC and OpenSC's PKCS#11
module. Two devices are present in the DR configuration (`SZ-HSM-002`), so
**never address a reader by enumeration index** — slot order changes when a
device is re-seated or a reader is added, and a DR unit that silently becomes
slot 0 is how a ceremony gets performed against the wrong device.

Address by the token serial, resolved once at daemon start and re-resolved on
every reconnect, and fail closed when the expected serial is absent
(`SZ-HSM-005`). `signerd` holds the only handle; nothing else opens the device
(`SZ-SEC-002`).

## 2. DKEK: what it actually is

The **Device Key Encryption Key** is the key under which the HSM wraps key
material for export. It is not a key you hold — it is assembled *inside* the
device from shares you import.

Three facts that decide every procedure below, each checkable in the source:

1. **The share count is fixed at initialisation and all of them are required.**
   `sc-hsm-tool --initialize --dkek-shares n` both enables wrap/unwrap and fixes
   `n`. Import is incremental: the status output reports
   `DKEK import pending, N share(s) still missing` until every declared share is
   in. There is no threshold — *n of n*, not *t of n*.
2. **The `(t,n)` threshold scheme protects a share's password, not the DKEK.**
   `--create-dkek-share` with `--pwd-shares-threshold` / `--pwd-shares-total`
   randomly generates that share's password and splits *the password*. Confusing
   these is the error that produces an unrecoverable backup: operators believe
   they have 3-of-5 recovery and actually have five mandatory shares, each of
   whose password needs 3 custodians present.
3. **The Key Check Value is the only proof two devices hold the same DKEK.** It
   is 8 bytes, and the tool prints it **only once `outstanding_shares` reaches
   zero**. Before that there is nothing to compare.

Key domains (`--create-dkek-key-domain`, `-d/--key-domain`, SmartCard-HSM v3 and
later) allow more than one DKEK per device. Where namespaces are enabled
(`SZ-AUTH-006`), a namespace maps to a key domain, so one tenant's wrapped
backups cannot be unwrapped into another tenant's domain.

## 3. Ordering that cannot be undone

**`SZ-HSM-003`: the DKEK is configured before any exportable production key
exists.** `--dkek-shares` is set at `--initialize`, and initialising removes all
existing keys, certificates and files. So a device that generated production keys
before its DKEK was configured has exactly two outcomes: those keys are never
backed up, or they are destroyed to fix it.

The installer refuses to generate a production key on a device whose status does
not show a DKEK with a settled Key Check Value. This is a hard stop, not a
warning: the failure is discovered months later when the primary dies.

## 4. The ceremony

Roles are separated because the control is separation, not procedure
(`SZ-AUTH-007`). A custodian holds a share; an administrator runs the device; no
one person holds enough to reconstruct the DKEK alone.

**Creation** — once, at provisioning, off the appliance:

1. Each custodian runs `--create-dkek-share` on their own trusted machine, sets
   their own password (or `--pwd-shares-threshold`/`--pwd-shares-total` to split
   it among sub-custodians), and keeps the resulting file.
2. **Share files never touch the appliance's disk.** They are presented to the
   import step from removable media and removed afterwards; the appliance writes
   no copy, and the audit event records the share's fingerprint, never its
   contents (`SZ-SEC-005`, `SZ-HSM-004`).
3. Every share is imported into the primary. The KCV appears only when the last
   one lands; it is recorded in the ceremony minutes and in the audit log.

**Replication to the DR unit** — the same shares, imported into the secondary,
with the same `--dkek-shares` count set at its initialisation. **Compare the two
Key Check Values.** Equal means the two devices can unwrap each other's keys;
unequal means the DR unit is decorative, and nothing but this comparison will
tell you.

**Wrapped export** — `--wrap-key` writes the key *together with its description
and certificate*, so the wrapped file is self-describing and a restore does not
depend on a separate metadata record that may have drifted.

**Restore** — `--unwrap-key` into a device whose DKEK KCV matches the one the
key was wrapped under. Requires step-up authentication (`SZ-AUTH-003`), is
audited on entry and exit, and is followed by a **proof-of-use**: sign a known
test vector with the restored key on the DR device and verify it against the
key's certificate. An unwrap that returns success is not evidence the key works.

## 5. What is never persisted

- DKEK shares in plaintext, anywhere on the appliance.
- Share passwords, in any form, including in a command line (`SZ-SEC-005` — a
  command line is world-readable on a running system).
- The assembled DKEK. It exists only inside the HSM.

Wrapped key blobs *may* be stored, with their KCV and metadata, because they are
useless without a device holding the matching DKEK. They are still covered by
`.gitignore` and by the state volume's encryption (`SZ-OS-009`) — defence in
depth, not because the blob alone is sensitive.

## 6. Where DKEK does not apply

`SZ-SEC-001` keeps production signing keys **non-exportable** unless DKEK backup
was explicitly configured for them. Non-exportable is the default and the safer
posture; the trade is that such a key cannot be recovered at all, only replaced,
with everything it signed re-examined.

Intake decides this per signing profile and records the decision
(`build/scope.md`), because it is a business continuity choice and not a
technical default. The appliance surfaces which profiles are recoverable and
which are not, so nobody discovers the answer during an outage.

## 7. How this is verified

- A device without a settled DKEK KCV refuses production key generation.
- KCVs of primary and secondary match after the replication ceremony; a
  deliberately mismatched pair is asserted to fail.
- No share file, password or plaintext DKEK appears on the appliance filesystem
  after a ceremony — checked by scanning, not by assertion.
- A wrapped key restored into the DR device signs a test vector that verifies
  against its certificate.
- The audit trail for a ceremony names the operators, the share fingerprints and
  the resulting KCV, and contains no secret.
