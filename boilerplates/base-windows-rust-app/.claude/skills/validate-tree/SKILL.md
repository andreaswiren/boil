---
name: validate-tree
description: Runs the build's one validation command and produces the validation block a hand-off or a gate is accepted on — command, exit code, sha, cargo's own passed/failed/ignored counts, suppression counts for allow/unsafe/ignore/expect, output tail and red-first evidence. Load before writing any hand-off report, at every wave boundary, at every gate, when asked to "check the build", "does it compile", "run the tests", "validate before handing off", or when a report claims success with nothing behind it.
---

# Validating the workspace

Requirements: REQ-VAL-01 … REQ-VAL-14, REQ-TST-10, REQ-TST-13, REQ-TST-16.
Full reasoning in `spec/validation.md`; the testing rules in the register's TST
section.

**The failure this exists to prevent:** "implemented REQ-TRY-02, tests added"
about a workspace that does not compile. It is the cheapest sentence in the
build, it reads exactly like the true version, and nothing downstream separates
them until a gate — by which point other crates depend on it.

## 1. One command

```bash
cargo xtask validate -p <crate>   # before every hand-off
cargo xtask validate              # wave boundaries and gates
cargo xtask validate --quick      # the interval sweep: fmt + clippy + check
cargo xtask validate --full       # B14 from H5: + MSI, clean install, upgrade, launch
```

There is no second list of checks. A gate that assembles its own drifts from
what agents run, and the drift only surfaces where the gate passes a tree that
does not build.

If `cargo xtask validate` does not exist, you are in Wave 0 and it is `B01`'s
first task (REQ-VAL-01) — not something to improvise around.

## 2. Produce the block, do not summarise the run

```bash
SHA=$(git rev-parse HEAD)
set +e; OUT=$(cargo xtask validate -p "$CRATE" 2>&1); CODE=$?; set -e

printf '%s\n' "$OUT" | tail -40                       # verbatim (REQ-TST-16)
printf '%s\n' "$OUT" | grep -Eo '[0-9]+ (passed|failed|ignored)' | tail -3

# suppressions, per class (REQ-VAL-07)
git grep -c '#\[allow('  -- '*.rs' | awk -F: '{s+=$2} END {print "allow", s+0}'
git grep -c 'unsafe {'   -- '*.rs' | awk -F: '{s+=$2} END {print "unsafe", s+0}'
git grep -c '#\[ignore'  -- '*.rs' | awk -F: '{s+=$2} END {print "ignored", s+0}'
git grep -nE '\.(unwrap|expect)\(' -- '*.rs' | grep -v '/tests/'   # each needs its REQ trade
```

Counts are cargo's own numbers. A paraphrase of test output is a claim about
test output, and keeping those apart is the entire point.

**`ignored` is the one to look at.** `cargo test` prints `N ignored` in a line
nobody reads, which makes `#[ignore]` the cheapest way past a gate (REQ-TST-13).

## 3. Red first, and it cannot be back-filled

For every REQ you will claim satisfied:

```
1. write the test   → run → it fails, for the reason you expect.   record redSha
2. implement        → run → it passes.                             record greenSha
3. both shas + the assertion go in redFirst
```

`redSha == greenSha` is not red-first evidence, and neither is a test that did
not exist at `redSha` — `B14` checks both at `H4` (REQ-TST-10).

## 4. What gets a hand-off rejected

| Condition | Why it is fatal |
|-----------|-----------------|
| no `validation` block | the claim has nothing behind it |
| `exitCode != 0` | everything else in the report describes a tree that does not build |
| `sha` != head | it was green somewhere else |
| `ignored > 0` | the count nobody reads is the one that hides a skipped requirement |
| no `redFirst` for a claimed REQ | the test was written against code that already passed |
| a suppression class rose since the last gate | widening an `#[allow]` turns a red tree green; a growing `unsafe` count means a surface `T1` and `T2` reviewed has changed |

The orchestrator applies these by reading the block, not the diff (REQ-VAL-03).

## 5. Three sentences you never write

"It compiles." "The tests pass." "This still works." — unless a command produced
that result **in this session, at this sha** (REQ-VAL-04). A result from round 2
is not evidence about round 3; the tree changed, which is what a round is.

## 6. When the shared tree is red

`crates/contracts`, the workspace `Cargo.toml`, `Cargo.lock` or the token module
red during a wide wave means every concurrent agent is building on a base that
does not compile. Stop dispatching, name the file and its owner from
`contracts/ownership.md`, route the fix there alone, resume on green
(REQ-VAL-11). Do not work around it in your own crate — a local workaround for a
shared break is a second defect that outlives the first.
