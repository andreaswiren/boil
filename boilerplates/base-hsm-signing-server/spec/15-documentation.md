# Documentation

Owner: `documentation-engineer`, which is also a **second deep expert on the
backend OS** (see its brief). Requirements: `SZ-DOC-001`…`003`, `SZ-SEC-005`.

## 1. Documentation is read when something is broken

That single observation decides the structure. Nobody opens the operator guide
on a good day. So:

- **The failure path comes before the happy path** in every procedure.
- **Exact strings** an operator will see, so they are searchable. Not "an error
  appears" — the message.
- **What a procedure cannot recover** is stated where it is not obvious
  (`spec/18-backup-restore.md` §7, `spec/05-hsm-dkek.md` §6).

## 2. The set

| Document | For | Must contain |
|----------|-----|--------------|
| `docs/README.md` | anyone | The map, and where to start for each role |
| `docs/operations/hardening.md` | administrator | The posture, and how to verify it rather than assume it |
| `docs/operations/recovery.md` | administrator under pressure | Unseal failure, DR restore, lost recovery key, locked-out network |
| `docs/hsm/nitrokey-hsm2.md` | administrator | Device setup, PIN policy, serial identification |
| `docs/hsm/dkek-backup-restore.md` | custodians | The ceremony, written to be followed by someone who has never done one |
| `docs/integrations/*.md` | CI engineers | Working configurations for GitHub Actions, GitLab/Forgejo, Windows/REST |
| `docs/certificates/*.md` | administrator | Enrollment with DigiCert, Sectigo, a generic CA |
| `docs/api/*` | integrators | Generated from OpenAPI, never hand-maintained |

## 3. The rules that keep it true

**Every command has been run** (`documentation-engineer` definition of done), or
is explicitly marked unverified with the reason. Version skew in `sc-hsm-tool`,
`systemd-cryptenroll` and `nft` is real and silent, and a command that has not
been executed is a command that does not work.

**No secret, and no realistic-looking placeholder secret** (`SZ-SEC-005`). A
copy-pasteable command containing `--pin 648219` is how a real PIN ends up in a
shell history — the placeholder is `<PIN>`, and it is deliberately not valid.
`SZ-DOC-002` requires the local-signing documentation to show the PIN reaching the
provider through a channel that does not appear in `/proc`.

**The document and the system are checked against each other.** Where they
disagree, that is a finding against the owning agent — not something to document
around. This is why the role needs OS depth rather than transcription skill.

**API documentation is generated** from the OpenAPI document, which is the
contract (`spec/07-rest-api.md`). Hand-written API docs drift within one release.

**Provider documentation links to the provider** (`SZ-DOC-003`). DigiCert and
Sectigo change their enrollment and HSM attestation requirements without notice,
so we document *our* side of the procedure precisely and link theirs rather than
copying it into a page that silently goes stale.

## 4. The two documents that carry the most risk

**`docs/operations/recovery.md`** — read by someone whose appliance will not
boot. It covers, failure-first: a disk that will not unseal after a kernel
update (the most likely brick — `SZ-OS-009`), a lost recovery key, a dead
primary HSM, a network lockout, and a restore. It states that **full DR is two
procedures** and that doing only the backup restore leaves an appliance that
knows about keys it cannot use.

**`docs/hsm/dkek-backup-restore.md`** — read by custodians under pressure, some
of whom have done this once. It must be unambiguous that all declared shares are
required (`n` of `n`), that the `(t,n)` threshold protects a share's password and
not the DKEK, and that the Key Check Values of primary and DR must be compared
and equal (`spec/05-hsm-dkek.md` §2). Getting any of those wrong produces a
backup that fails at the moment it is needed.

## 5. Architecture diagrams

Version-controlled source — Mermaid or authored SVG — never a screenshot of a
whiteboard. Theme-aware for light and dark, legible on a phone, and regenerated
when the architecture changes rather than annotated.

A diagram that disagrees with `spec/01-architecture.md` is a finding.

## 6. How this is verified

- Every command in every guide is executed in the documentation pipeline, or
  carries an explicit unverified marker with a reason.
- No string matching a secret pattern appears in any document, fixture or
  screenshot — scanned, not reviewed.
- API documentation regenerates identically from the current OpenAPI document;
  drift fails the build.
- Every procedure names its failure modes and the exact console or UI text.
- External provider links resolve; a dead link in a certificate guide is a broken
  enrollment procedure.
