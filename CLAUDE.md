# Operating instructions

This repo is a collection of boilerplates and skills. Read
[`CONVENTIONS.md`](CONVENTIONS.md) before changing anything in it.

## Where you are

- Working **inside a boilerplate** (`boilerplates/<name>/`) — that folder's
  `CLAUDE.md` governs. It is self-contained; do not reach outside it.
- Working **on the repo itself** — adding a boilerplate, editing shared skills,
  updating meta files — this file governs.

## Hard rules

1. **A boilerplate never reaches outside its own folder.** No `../` paths, no
   symlinks out, no dependency on a sibling boilerplate. Someone will clone that
   folder alone, and it has to work.
2. **Requirement IDs are permanent.** Never renumber `REQ-*` IDs. A changed
   requirement gets a new ID and the old one is marked superseded.
3. **Never write a dependency version from memory.** Validate it against the
   registry and record the source URL and timestamp.
4. **Every change bumps the semver and updates the changelog.** `VERSION`,
   `CHANGELOG.md`, and `TODO.md` are updated in the same commit as the work.
   `README.md` and `SECURITY.md` when they are affected.
5. **Commit and push.** Work left only in a container is lost work.

## Adding a boilerplate

Use the `boil-new-boilerplate` skill. It scaffolds the required structure from
`CONVENTIONS.md` §2 and verifies self-containment.

## Editing a boilerplate's requirements

`spec/requirements.md` is the source of truth for that boilerplate, and dozens of
other files cite its IDs. IDs are permanent: never renumber, and give a changed
requirement a new ID with the old one marked superseded.

After any edit, run the conformance check — it catches a dangling citation, a
requirement without a status, an ownership map naming an agent that does not
exist, and a broken internal reference:

```bash
cd boilerplates/<name>
python3 scripts/gen-traceability.py     # if it has a matrix
./scripts/check-boilerplate.sh          # the boilerplate's own check
cd - && ./scripts/check-conventions.sh  # every boilerplate, plus the repo checks
```

Both scripts ship *inside* each boilerplate, because a boilerplate has to work
cloned alone. `scripts/check-conventions.sh` at the root runs each one and then
checks what only makes sense from outside: that no boilerplate cites a file it
does not ship, that every boilerplate is in the README, and that the shipped
copies of the generator have not drifted.

Fix the register, never the citation. The citation is the thing that made you
notice.

A new requirement domain needs a row in `gen-traceability.py`'s `DOMAIN` table;
the generator fails loudly on an unmapped domain rather than silently leaving
those requirements unowned.

## Style

See `CONVENTIONS.md` §7. In short: decide, be specific, cite the requirement ID,
no filler.
