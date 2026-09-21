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

`spec/requirements.md` is the source of truth for that boilerplate, and dozens
of other files cite its IDs. After editing it, verify no citation dangles:

```bash
cd boilerplates/<name>
defined=$(grep -oE '^\| REQ-[A-Z0-9]+-[0-9]+' spec/requirements.md | sed 's/^| //' | sort -u)
used=$(grep -rhoE 'REQ-[A-Z0-9]+-[0-9]+' . --include='*.md' --include='*.csv' | sort -u)
comm -13 <(echo "$defined") <(echo "$used")   # must print nothing
```

## Style

See `CONVENTIONS.md` §7. In short: decide, be specific, cite the requirement ID,
no filler.
