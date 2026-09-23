# Requirements

`spec/requirements.md` is the register and the only source of truth. Every
identifier is stable, never renumbered, and must be cited in review notes, commit
messages and acceptance tests.

## Families

| Prefix | Domain | Spec |
|--------|--------|------|
| `SZ-FUN-*` | Product behaviour | `00-product.md` |
| `SZ-SEC-*` | Security controls | `02-threat-model.md` |
| `SZ-HSM-*` | HSM, DKEK, appliance state | `05-hsm-dkek.md`, `18-backup-restore.md` |
| `SZ-AUTH-*` | Human and workload identity | `04-identity-auth.md` |
| `SZ-API-*` | API and integrations | `07-rest-api.md` |
| `SZ-OS-*` | Appliance, OS, DCUI | `11-os-appliance.md`, `12-dcui.md` |
| `SZ-AUD-*` | Audit | `10-audit.md` |
| `SZ-INS-*` | Install, setup, update | `13-installer-setup.md` |
| `SZ-PWA-*` | Mobile approval | `09-pwa-approvals.md` |
| `SZ-DOC-*` | Documentation | `15-documentation.md` |

## Why the prefix is `SZ-` and not `REQ-`

The repository's convention (`CONVENTIONS.md` §3) requires identifiers that are
**stable and never renumbered**. It does not require one spelling. These arrived
as `SZ-*` and are load-bearing across the tree, so renaming them would mean
rewriting every citation to gain nothing — which is precisely the
dangling-citation failure the convention exists to prevent.

The conformance check derives the prefix from this register rather than assuming
one, and so does `scripts/gen-traceability.py`.

## The generated artefact

`spec/traceability.csv` maps every requirement to its owning agent, its reviewers
and its spec document. It is **generated** by `scripts/gen-traceability.py` from
this register plus `spec/traceability-map.json`, and `scripts/check-boilerplate.sh`
fails if the committed copy has drifted — including if the generator itself
fails, which previously produced a silent "in sync".

Never hand-edit it. A matrix that can drift from the register is worse than no
matrix, because it is trusted.

## Adding a requirement

1. Next free number in its family. Never reuse, never renumber.
2. `MUST`, `SHOULD` or `OPT`. A `MUST` cannot be waived — the build fails instead.
3. Write the checkable form: what must be true, and how you would know. A
   requirement a test cannot check is an intention (`14-testing.md` §1).
4. Map it in `spec/traceability-map.json` if its owner or spec differs from its
   family default.
5. Regenerate the matrix and run the check.
