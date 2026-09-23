---
name: validate-tree
description: Runs the build's one validation command and produces the validation block a hand-off or a gate is accepted on — command, exit code, sha, the runner's own passed/failed/skipped/focused counts, suppression counts, output tail and red-first evidence. Load before writing any hand-off report, at every wave boundary, at every gate, when asked to "check the build", "does it compile", "run the tests", "validate before handing off", or when a report has arrived claiming success with nothing behind it.
---

# Validating the tree

Requirements: REQ-VAL-01 … REQ-VAL-14, REQ-TST-09, REQ-TST-12, REQ-TST-15.
Full reasoning in `spec/validation.md`; the testing rules in `spec/testing.md`.

**The failure this exists to prevent:** "implemented REQ-GRD-04, tests added"
about a tree that does not compile. It is the cheapest sentence in the build, it
reads exactly like the true version, and nothing downstream separates them until
a gate — by which point fourteen agents have built on it.

## 1. One command

```bash
pnpm validate --filter <your-package>   # before every hand-off
pnpm validate                           # wave boundaries and gates
pnpm validate:quick                     # A28's interval sweep: typecheck + lint
pnpm validate:full                      # A23 from G5: + integration, e2e, image
```

There is no second list of checks. A gate that assembles its own drifts from
what agents run, and the drift only shows up where the gate passes a tree that
does not build.

If `pnpm validate` does not exist, you are in Wave 0 and it is `A01`'s first
task (REQ-VAL-01) — not something to improvise around.

## 2. Produce the block, do not summarise the run

```bash
SHA=$(git rev-parse HEAD)
START=$(date -u +%FT%TZ)
set +e; OUT=$(pnpm validate --filter "$PKG" 2>&1); CODE=$?; set -e

TAIL=$(printf '%s\n' "$OUT" | tail -40)                     # verbatim (REQ-TST-15)
COUNTS=$(printf '%s\n' "$OUT" | grep -Eo '[0-9]+ (passed|failed|skipped)' | tail -5)

# suppressions, per class (REQ-VAL-07)
git grep -c '@ts-expect-error' -- '*.ts' '*.tsx' | awk -F: '{s+=$2} END {print s+0}'
git grep -c 'eslint-disable'   -- '*.ts' '*.tsx' | awk -F: '{s+=$2} END {print s+0}'
git grep -c '#\[allow('        -- '*.rs'         | awk -F: '{s+=$2} END {print s+0}'

# a stray .only reduces the suite to one test and reports green (REQ-TST-12)
git grep -nE '\b(it|test|describe)\.only\b|\b(it|test|describe)\.skip\b|\bxit\b' -- 'tests/**' 'packages/**'
```

Write it into `report.json` under `validation`, shaped by
`contracts/types/agent-report.md` §3a, and the raw output to
`build/validation/<wave>/<agent>/test-output.txt`.

Counts are the runner's own numbers. A paraphrase of test output is a claim
about test output, and keeping those two apart is the entire point.

## 3. Red first, and it cannot be back-filled

For every REQ you will claim `satisfied`:

```
1. write the test        → run → it fails, for the reason you expect.   record redSha
2. implement             → run → it passes.                             record greenSha
3. both shas + the assertion go in validation.redFirst
```

`redSha == greenSha` is not red-first evidence, and neither is a test that did
not exist at `redSha` — `A23` checks both at `G4` (REQ-TST-09). A test written
against code that already passes it is a regression guard, which is useful and
is not evidence about the requirement it cites.

## 4. What gets a hand-off rejected

| Condition | Why it is fatal |
|-----------|-----------------|
| no `validation` block | the claim has nothing behind it |
| `exitCode != 0` | everything else in the report describes a tree that does not build |
| `sha` != head | it was green somewhere else |
| `skipped > 0` or `focused > 0` | a suite of 400 with 40 skipped reports green and verifies 360 |
| no `redFirst` for a claimed REQ | the test was written against code that already passed |
| suppressions rose since the last gate | the ordinary way a red tree becomes green is not a fix |

The orchestrator applies these by reading the block, not the diff (REQ-VAL-03).

## 5. Three sentences you never write

"It compiles." "The tests pass." "This still works." — unless a command produced
that result **in this session, at this sha** (REQ-VAL-04). A result from round 2
is not evidence about round 3; the tree changed, which is what a round is.

## 6. When the shared tree is red

`packages/contracts`, the lockfile, the root tsconfig or the workspace config
red during a wide wave means every concurrent agent is building on a base that
does not compile. Stop dispatching into the wave, name the file and its owner
from `contracts/ownership.md`, route the fix there alone, resume on green
(REQ-VAL-11). Do not work around it in your own package — a local workaround for
a shared break is a second defect that outlives the first.
