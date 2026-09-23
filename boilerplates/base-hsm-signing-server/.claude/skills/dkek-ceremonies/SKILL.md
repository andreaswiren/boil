---
name: dkek-ceremonies
description: SmartCard-HSM DKEK initialization, share ceremonies, wrapped-key backup, secondary-HSM restoration and recovery verification. Load for any DKEK, key-backup or DR work, and before writing anything a custodian will follow.
---

# DKEK ceremonies

Verified against OpenSC `master` — `doc/tools/sc-hsm-tool.1.xml` and
`src/tools/sc-hsm-tool.c`. Design: `spec/05-hsm-dkek.md`. Operator guide:
`docs/hsm/dkek-backup-restore.md`.

## The three facts everything depends on

1. **`n` of `n`, not `m` of `n`.** `--dkek-shares n` at `--initialize` fixes the
   count and **every** share must be imported. The tool reports
   `DKEK import pending, N share(s) still missing` until the last one lands.
2. **`(t,n)` protects a share's *password*, not the DKEK.**
   `--pwd-shares-threshold` / `--pwd-shares-total` split the password of one
   share. Someone who sets `--dkek-shares 5` believing they configured 3-of-5
   recovery has created five mandatory shares, and will not discover it until a
   recovery.
3. **The Key Check Value is 8 bytes and appears only when the last share lands.**
   It is the only proof primary and DR hold the same DKEK.

If you write documentation, code or a UI string that contradicts any of these,
you have introduced a defect that surfaces during a disaster.

## Ordering

`--dkek-shares` is fixed at `--initialize`, and initialising destroys all keys,
certificates and files. So the DKEK must exist **before** any exportable
production key (`SZ-HSM-003`), and the installer hard-stops rather than warns.

## Implementation rules

- Share material is processed **in memory only**. Never written to the
  appliance's disk, never in a temp file, never in a log.
- Never pass a password with `--password` in production code — it lands in
  `/proc/<pid>/cmdline` (`SZ-SEC-005`).
- Address devices by **serial**, never slot index (`SZ-HSM-005`).
- Show the KCV in the UI after every ceremony, and show primary and DR side by
  side. A mismatch must be impossible to miss.
- `--wrap-key` includes the certificate and description; keep them together.

## Definition of done

- [ ] A backup is never reported successful because a blob exists. Recovery is
      tested by unwrapping onto the DR token and **signing a test vector that
      verifies** against the certificate.
- [ ] Primary and DR KCVs are compared and recorded.
- [ ] No share, password or plaintext DKEK on the filesystem after a ceremony —
      verified by scanning.
- [ ] Audit records operators, share fingerprints and the KCV, and no secret.
