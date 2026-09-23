---
name: validate-and-test
description: Runs the appliance's one validation command and produces the block a hand-off or a phase gate is accepted on — command, exit code, sha, passed/failed/skipped/unverified counts, suppression counts, output tail and red-first evidence — plus the negative-suite, requirement-coverage and mutation checks. Load before writing any hand-off, at every phase boundary and gate, when asked to "check the build", "does it compile", "run the tests", "validate before handing off", or when a report claims success with nothing behind it.
---

# Validating and testing the appliance

Requirements: `SZ-VAL-001` … `SZ-VAL-014`, `SZ-TEST-001` … `SZ-TEST-013`.
Reasoning: `spec/20-validation.md` and `spec/14-testing.md`.

Two separate questions, and they fail differently:

- **Does it build?** — `SZ-VAL-*`. The failure is a report saying "implemented,
  tests added" about a tree that does not compile. Cheap to write, identical to
  the true version, invisible until a phase gate.
- **Is it true?** — `SZ-TEST-*`. The failure is a requirement with a passing test
  that never exercised it, and on this appliance the tests that matter most are
  the ones that assert a **refusal**.

## 1. One command

```bash
make validate SCOPE=<crate|package>   # before every hand-off
make validate                          # phase boundaries and gates
make validate-quick                    # the interval sweep
make validate-full                     # installer → clean Debian 13 → services up → wizard over HTTPS
```

There is no second list. A gate that assembles its own drifts from what agents
run, and the drift only shows where the gate passes a tree that does not build.

## 2. Produce the block, do not summarise the run

```bash
SHA=$(git rev-parse HEAD)
set +e; OUT=$(make validate SCOPE="$SCOPE" 2>&1); CODE=$?; set -e
printf '%s\n' "$OUT" | tail -40                 # verbatim (SZ-TEST-013)

# suppressions, per class (SZ-VAL-007)
git grep -c '#\[allow('        -- '*.rs'            | awk -F: '{s+=$2} END {print "allow", s+0}'
git grep -c 'unsafe {'         -- '*.rs'            | awk -F: '{s+=$2} END {print "unsafe", s+0}'
git grep -c '#\[ignore'        -- '*.rs'            | awk -F: '{s+=$2} END {print "ignored", s+0}'
git grep -c '@ts-expect-error' -- '*.ts' '*.tsx'    | awk -F: '{s+=$2} END {print "tsExpectError", s+0}'
git grep -c 'eslint-disable'   -- '*.ts' '*.tsx'    | awk -F: '{s+=$2} END {print "eslintDisable", s+0}'

# nothing skipped to reach green (SZ-TEST-008)
git grep -nE '#\[ignore|\b(it|test|describe)\.(only|skip)\b|\bxit\b' -- 'tests' 'crates' 'apps'
```

`skipped` must be zero. `unverified` is legitimate — a test needing real hardware
or a real appliance — and must be **named per requirement ID** in
`build/validation/unverified.md` (`SZ-TEST-007`). Green, skipped and unverified
are three different states and only the first is a pass.

## 3. Red first (SZ-TEST-002)

```
1. write the test  → run → it fails, for the reason you expect.  record redSha
2. implement       → run → it passes.                            record greenSha
3. both shas + the assertion go in redFirst
```

`redSha == greenSha`, or a test that did not exist at `redSha`, is not red-first
evidence — `test-automation-engineer` audits both at every phase gate.

## 4. The negative suite is the suite (SZ-TEST-004)

It runs on **every commit**, not at a release gate. Digest mismatch; a repository
claim the workload token does not assert; an approval bound to another artefact;
self-approval; an expired approval; a push with no transaction proof; a `Metrics`
credential elsewhere; a `Backup` credential decrypting a backup; an out-of-profile
mechanism; a wrong-state operation returning `412` with both states named; rate
limits at their stated numbers per address and per username; a timestamp-authority
outage; an `UPDATE` on `audit_events`; an edited audit chain.

**A disabled negative test is a removed control** (`SZ-TEST-008`). That is why the
skip count is checked rather than trusted: the test most likely to be disabled
for being inconvenient is one of these fourteen.

## 5. Prove the suite can fail (SZ-TEST-012)

At every phase gate, disable one control — remove the digest re-check, bypass the
approval binding — and assert the suite goes red. Restore it. A suite nobody has
ever watched fail is evidence of nothing, and this is the cheapest way to find
out that a negative test has been asserting against the wrong thing all along.

## 6. What gets a hand-off rejected

| Condition | Why it is fatal |
|-----------|-----------------|
| no `validation` block | the claim has nothing behind it |
| `exitCode != 0` | everything else in the report describes a tree that does not build |
| `sha` != head | it was green somewhere else |
| `skipped > 0` | a disabled negative test is a removed control |
| `unverified` not named per REQ ID | unverified is fine; unverified and unstated is a silent gap |
| no `redFirst` for a claimed requirement | the test was written against code that already passed |
| a suppression class rose | a new `unsafe` block inside the signing boundary means a surface both reviewers cleared has changed since |

## 7. Three sentences you never write

"It compiles." "The tests pass." "This still works." — unless a command produced
that result **in this session, at this sha** (`SZ-VAL-004`). A result from round 2
is not evidence about round 3; the tree changed, which is what a round is.
