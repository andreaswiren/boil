# Validation & Compilation (SZ-VAL-001 … SZ-VAL-014)

Owner: `orchestrator`, with `release-engineer` for the shipped-artefact half.

`spec/14-testing.md` says what evidence exists that a requirement is true. This
says what evidence exists that the tree compiles at all — a separate and earlier
question, and the one that was being answered by assertion.

The failure it prevents has a shape. An agent writes nine files, reads them back,
concludes they are consistent, and reports "implemented `SZ-API-003`, tests
added". The tree does not compile. Nothing discovers it until a phase gate, by
which time other agents have built on the assumption that it did.

---

## 1. One command (SZ-VAL-001)

Written before the first phase, and green on the empty tree before the first
domain agent is dispatched. A validation command first authored mid-build, when
there is already something to hide, is authored to pass.

```
make validate            the whole tree
make validate SCOPE=<crate|package>
make validate-quick      fmt + clippy + typecheck only — the interval sweep
make validate-full       + the installer, a clean Debian 13 install, services up,
                         the wizard reachable over HTTPS (SZ-VAL-014)
```

What `make validate` covers:

| Part | Checks |
|------|--------|
| Rust workspace (`signerd`, `osd`, `dcui`) | `fmt --check`, `clippy --all-targets --all-features -D warnings`, `check`, `test` |
| Web workspace | `tsc --noEmit` under `strict`, ESLint `--max-warnings=0`, unit tests, production build |
| Database | migrations apply to an empty database and roll back; the migration lint (no table without its audit trigger) |
| Contracts | the OpenAPI document validates, the typed client regenerates to an empty diff (SZ-VAL-013) |
| Policy | the policy schema validates and its fixture set evaluates to the recorded verdicts |

There is no second list. A gate that assembles its own drifts from what agents
run, and the drift only surfaces where the gate passes a tree that does not
build.

## 2. The validation block (SZ-VAL-002, SZ-VAL-003)

Every hand-off carries one, machine-checked rather than read:

```json
{
  "validation": {
    "command": "make validate SCOPE=signerd",
    "exitCode": 0,
    "sha": "c3f1a92e7b40d58c6a1f2e3d4c5b6a7980f1e2d3",
    "startedAt": "2026-09-23T14:02:11Z",
    "durationMs": 241300,
    "counts": { "passed": 212, "failed": 0, "skipped": 0, "unverified": 4 },
    "suppressions": { "allow": 2, "unsafeBlocks": 0, "ignoredTests": 0,
                      "tsExpectError": 0, "eslintDisable": 1, "unwrapOnFallible": 0 },
    "outputTail": "…last 40 lines verbatim…",
    "redFirst": [
      { "req": "SZ-API-003", "test": "api::tests::rejects_digest_mismatch",
        "redSha": "9d0e…", "greenSha": "c3f1…",
        "assertion": "a body whose digest does not match the submitted bytes is refused before the HSM opens" }
    ]
  }
}
```

`unverified` is a first-class count here, not a synonym for skipped: it is how a
test that needs real hardware or a real appliance reports when that environment
is absent (SZ-TEST-007). `skipped` must be zero; `unverified` must be **named**,
per REQ ID, in the hand-off.

Rejected when the block is absent, `exitCode` is non-zero, `sha` is not head,
`counts.skipped` is non-zero (SZ-TEST-008), a claimed requirement has no
`redFirst` entry (SZ-TEST-002), or a suppression class rose since the previous
gate (SZ-VAL-007).

**Mechanical on purpose.** The orchestrator does not read the diff and form a
view about whether the work looks finished.

## 3. What may not be claimed (SZ-VAL-004)

- "It compiles." — `cargo check` and `tsc` said so, this session, at this sha.
- "The tests pass." — a runner printed counts.
- "This still works." — the suite ran after the change.

A result from round 2 is not evidence about round 3. The tree changed; that is
what a round is.

## 4. Suppressions, and why this appliance watches them harder (SZ-VAL-007)

Six classes, counted at every phase gate, each occurrence carrying the `SZ-*` ID
it trades against and a removal condition:

| Class | Why it is watched here specifically |
|-------|-------------------------------------|
| `#[allow(...)]` | widening an allow is the fastest way to turn a red tree green |
| `unsafe` blocks | `signerd` sits inside the signing boundary; a new block means a surface the two reviewers cleared has changed since |
| `#[ignore]` / `.skip` | the test most likely to be disabled for being inconvenient is a negative test, and a disabled negative test is a removed control (SZ-TEST-008) |
| `@ts-expect-error` | in the approval UI, a silenced type error is usually a silenced contract change |
| `eslint-disable` | same, one layer out |
| `.unwrap()` / `.expect()` on a fallible path in daemon code | each is a panic in a daemon that holds a signing session open |

A count that rose since the previous gate is a finding, read occurrence by
occurrence — not a note.

## 5. One sha (SZ-VAL-008)

Validation records, capture sidecars and review verdicts name one commit. A phase
gate whose evidence spans more than one does not pass: `security-reviewer`
cleared commit A, `adversarial-reviewer` cleared commit C, and whatever landed
between them has no reviewer at all.

## 6. The shared-tree stop (SZ-VAL-011)

The contract crate, the OpenAPI document, the migration set or the workspace
manifest going red means every concurrent agent is building on a base that does
not compile. Stop dispatching into the phase, name the file and its owner from
`contracts/ownership.md`, route the fix there alone, resume on green.

## 7. The shipped artefact (SZ-VAL-014)

From the installer phase onward, `make validate-full` at every gate: the
installer builds, installs on a clean Debian 13 image, the services start, the
setup wizard is reachable over HTTPS, and the appliance reports `Unprovisioned`.

A workspace that compiles and an appliance that boots are two different claims.
The operator only ever meets the second one.

## 8. The record (SZ-VAL-012)

```
build/validation/
├── <phase>/<agent>.json             one per hand-off
├── <phase>/<agent>/test-output.txt  the runner's own output (SZ-TEST-013)
├── <gate>.json                      one per gate, whole tree
├── req-coverage.md                  every MUST → its test (SZ-TEST-001)
├── unverified.md                    REQ IDs no environment could verify (SZ-TEST-007)
└── suppressions.md                  per gate, per class, with the delta
```

Kept, not summarised. A summary of validation history is a claim about
validation history, and claims were the problem.
