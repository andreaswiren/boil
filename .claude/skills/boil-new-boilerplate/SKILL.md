---
name: boil-new-boilerplate
description: Scaffolds a new boilerplate in the boil repository with the structure CONVENTIONS.md requires, then verifies it is self-contained and its requirement IDs resolve. Load when adding a boilerplate to this repo, when asked to "add a boilerplate", "scaffold a boilerplate", "start a new starter", or when checking whether an existing boilerplate still conforms to the conventions.
---

# Add a boilerplate

A boilerplate in this repo is a **prompt structure**, not a code template. It
carries the decisions — requirements, contracts, ownership, gates — and generates
the code fresh against validated current versions.

Read `CONVENTIONS.md` before you start. This skill implements it.

## 1. Name it

Lowercase, hyphenated, describes what it produces rather than what it is built
from: `base-admin-panel`, not `nextjs-starter`. The name is a directory and it
will be in a clone URL, so it is permanent in practice.

```bash
NAME=<name>
test ! -e "boilerplates/$NAME" || { echo "exists"; exit 1; }
```

## 2. Scaffold

```bash
mkdir -p boilerplates/$NAME/{.claude/{agents,skills},spec,prompts}
cd boilerplates/$NAME
```

Required files (`CONVENTIONS.md` §2):

| File | Purpose | Must contain |
|------|---------|--------------|
| `README.md` | For a human | What it produces, how to run it, how it builds |
| `CLAUDE.md` | For an agent | Where to start, the map, the non-negotiable rules |
| `AGENTS.md` | For a non-Claude agent | A pointer to `CLAUDE.md` |
| `spec/requirements.md` | The source of truth | Stable `REQ-<DOMAIN>-<nn>` IDs with `MUST`/`SHOULD`/`OPT` status |
| `prompts/00-master-orchestrator.md` | The build | Phases, gates, dispatch |

Add domain folders as the boilerplate needs them — `contracts/`, `gates/`,
`versions/`, `compliance/`. Do not create empty ones.

## 3. Write the requirements first

Everything else cites them, so they come first. One row per requirement:

```md
| ID | Status | Requirement |
|----|--------|-------------|
| REQ-FND-01 | MUST | Monorepo layout even for a single app. Apps live at `apps/<app-name>/`. |
```

Rules: IDs are permanent and never renumbered; a changed meaning gets a new ID
and the old is marked superseded; every requirement is `MUST`, `SHOULD` or `OPT`;
a `MUST` cannot be waived — the build fails instead.

**When this fails:** the common mistake is writing requirements as goals
("the app should be secure"). A requirement a gate cannot check is not a
requirement. Write the checkable form: what must be true, and how you would know.

## 4. Decide whether it needs parallelism

If the build dispatches more than one agent at a time, `CONVENTIONS.md` §5
requires an ownership map. Copy the pattern from
`boilerplates/base-admin-panel/`:

- `contracts/README.md` — the contract law: one shared package, declarations
  assembled centrally, a freeze gate, additive-only change afterwards
- `contracts/ownership.md` — every path, table and migration namespace mapped to
  exactly one agent
- The "registry, never a shared list" rule, so no two agents need the same file

If the build is single-agent, skip all of that. Do not add a contract package
for one consumer — that is the speculative generality the Karpathy lens exists
to catch.

## 5. Define at least one reviewer that did not write the code

`CONVENTIONS.md` §6. The minimum is one; `base-admin-panel` uses four (two
critics on design and function, two independent security reviewers). Gate agents
own no product code and write only to `build/gates/`.

## 6. Version policy

No version in prose. If the boilerplate installs anything, it needs a
`versions/manifest.json` with `latestStable`, `pin`, `source` and `checkedAt` per
entry, and a validator agent that regenerates it before anything is installed.

## 7. Verify

```bash
cd boilerplates/$NAME

# Self-containment: nothing may reach outside the folder (CONVENTIONS.md §1)
grep -rn '\.\./\.\.' . --include='*.md' --include='*.json' && echo "VIOLATION: escaping path"
find . -type l -exec readlink {} \; | grep -F '../' && echo "VIOLATION: symlink out"

# Required files present
for f in README.md CLAUDE.md AGENTS.md spec/requirements.md prompts/00-master-orchestrator.md; do
  test -f "$f" || echo "MISSING: $f"
done

# Every cited requirement ID is defined
defined=$(grep -oE '^\| REQ-[A-Z0-9]+-[0-9]+' spec/requirements.md | sed 's/^| //' | sort -u)
used=$(grep -rhoE 'REQ-[A-Z0-9]+-[0-9]+' . --include='*.md' --include='*.csv' | sort -u)
comm -13 <(echo "$defined") <(echo "$used")   # must print nothing

# If there is an ownership map, every agent it names must exist
if [ -f contracts/ownership.md ]; then
  for a in $(grep -o '\bA[0-9][0-9]\b' contracts/ownership.md | sort -u); do
    ls .claude/agents/ | grep -q "^$a-" || echo "MISSING AGENT: $a"
  done
fi
```

**When this fails:** a dangling requirement ID usually means a spec was written
before the register was updated. Fix the register, never the citation — the
citation is the thing that made you notice.

## 8. Register it and release

1. Add a row to the boilerplate table in the repo `README.md`.
2. Bump `VERSION` (a new boilerplate is a **minor** bump).
3. Add a `CHANGELOG.md` entry citing the requirement domains it introduces.
4. Update `TODO.md`.
5. Commit and push.
