# Documentation

## Start here, by what you are doing

| You are | Read |
|---------|------|
| Setting up a new appliance | `operations/` — installation, then hardening verification |
| **Recovering from something broken** | [`operations/recovery.md`](operations/recovery.md) — failure cases first |
| Running a DKEK ceremony | [`hsm/dkek-backup-restore.md`](hsm/dkek-backup-restore.md) — read the first section before the first ceremony |
| Signing from CI | `integrations/` for your platform |
| Buying a code-signing certificate | `certificates/` — **confirm HSM acceptance with the CA first** |
| Integrating against the API | `api/`, generated from the OpenAPI document |

## Conventions

**Failure paths come first.** Documentation is read when something has already
broken, so "what it looks like when it goes wrong" is at the top of a procedure
rather than in an appendix.

**Commands here have been run.** Anything not executed against a real appliance
is marked `unconfirmed` with the check that would resolve it. Version skew in
`sc-hsm-tool`, `systemd-cryptenroll` and `nft` is real and silent.

**No secrets, and no realistic placeholders.** A copy-pasteable command with a
plausible PIN in it is how a real PIN reaches a shell history. Placeholders are
obviously invalid, like `<PIN>`.

**Where a document and the appliance disagree, the appliance is right and the
document is a bug** — report it rather than working around it.

## The two documents that carry the most risk

- [`operations/recovery.md`](operations/recovery.md) — because it is read under
  pressure, and because full disaster recovery is **two** procedures. Restoring a
  backup does not recover private key material.
- [`hsm/dkek-backup-restore.md`](hsm/dkek-backup-restore.md) — because the
  `n`-of-`n` versus `(t,n)` distinction is easy to get wrong and the error is
  invisible until a recovery.

## Design documents

These describe *why*, and live outside `docs/`:

- `spec/requirements.md` — the register everything cites
- `spec/02-threat-model.md` — what this is defended against, and what it is not
- `spec/11-os-appliance.md` — hardening, disk encryption, the TPM sealing policy
- `spec/17-nethsm-parity.md` — how this compares to NetHSM, including where it is
  weaker and what was declined on purpose
