# Validation Rules

Full reasoning: `spec/20-validation.md`. IDs: `SZ-VAL-001` … `SZ-VAL-014`.

1. **One command**: `make validate` (`validate-quick` for a sweep,
   `validate-full` for the installed appliance). Agents, gates, CI and the human
   run that and nothing else (`SZ-VAL-001`).
2. **Every hand-off carries its validation block** — command, exit code, sha,
   counts, suppression counts, output tail, `redFirst` per claimed requirement —
   produced by running the command immediately before the report, not in an
   earlier round (`SZ-VAL-002`).
3. **An unvalidated hand-off is not accepted.** The orchestrator reads the
   block, not the diff, and re-dispatches on a missing, red, stale-sha or
   skip-carrying one (`SZ-VAL-003`).
4. **Three sentences you never write**: "it compiles", "the tests pass", "this
   still works" — unless a command produced that result in this session, at this
   sha (`SZ-VAL-004`). A result from round 2 is not evidence about round 3.
5. **Warnings are errors** (`SZ-VAL-006`): clippy `-D warnings`, `fmt --check`,
   TypeScript `strict` at zero, ESLint `--max-warnings=0`.
6. **Suppression is a waiver**, carrying the `SZ-*` ID it trades against and a
   removal condition; counts are reported per gate and **a rise is a finding**
   (`SZ-VAL-007`). A new `unsafe` block in `signerd` means a surface the two
   reviewers cleared has changed since they cleared it.
7. **One sha for all evidence** (`SZ-VAL-008`). Two reviewers clearing two
   different commits have jointly cleared nothing.
8. **A red shared tree stops dispatch** (`SZ-VAL-011`).
9. **Validate the shipped artefact, not only the source** (`SZ-VAL-014`). A tree
   that compiles and an appliance that boots are two claims, and the operator
   only meets the second.
