# Validation & Compilation (REQ-VAL-01 … REQ-VAL-14)

The register says a build proves its progress. This says with what command, at
which moment, and what the record looks like.

The failure it prevents has a shape. An agent writes six files, reads them back,
concludes they are consistent, and reports "implemented REQ-TRY-02, tests added".
The workspace does not compile. Nothing discovers it until a gate two waves
later, by which time other crates depend on the assumption that it did.

---

## 1. One command (REQ-VAL-01)

`B01` writes `cargo xtask validate` in Wave 0, and it exits zero on the empty
workspace before the first domain agent is dispatched. A validation command
first authored in Wave 3, when there is already something to hide, is authored to
pass.

```
cargo xtask validate            fmt --check, clippy -D warnings, check --all-targets
                                --all-features, test, release build — the whole workspace
cargo xtask validate -p <crate> the same, scoped to one crate
cargo xtask validate --quick    fmt + clippy + check only; the supervisor's sweep
cargo xtask validate --full     + the MSI build, a clean-image install, the upgrade
                                from the previous release, and a launch of the
                                installed binary (REQ-VAL-14)
```

| Command | Who | When |
|---------|-----|------|
| `validate -p <crate>` | the owning agent | before every hand-off (REQ-VAL-02) |
| `validate` | the orchestrator | every wave boundary, every gate (REQ-VAL-05) |
| `validate --full` | `B14` | `H5` and every gate after it |

There is no second list. A gate that assembles its own drifts from what agents
run, and the drift only ever surfaces where the gate passes a tree that does not
build.

## 2. The validation block (REQ-VAL-02, REQ-VAL-03)

Every agent report carries one, and it is machine-checked rather than read:

```json
{
  "validation": {
    "command": "cargo xtask validate -p app-tray",
    "exitCode": 0,
    "sha": "9b1c4e77a0f2d3c5b6e8a9d0f1c2b3a4e5d6c7b8",
    "startedAt": "2026-09-23T14:02:11Z",
    "durationMs": 214800,
    "counts": { "passed": 87, "failed": 0, "ignored": 0 },
    "suppressions": { "allow": 3, "unsafeBlocks": 11, "ignoredTests": 0, "expectOnFallible": 0 },
    "outputTail": "…last 40 lines verbatim…",
    "redFirst": [
      { "req": "REQ-TRY-02", "test": "tray::tests::survives_explorer_restart",
        "redSha": "7a0c…", "greenSha": "9b1c…",
        "assertion": "TaskbarCreated is re-registered and the icon reappears" }
    ]
  }
}
```

Rejected when the block is absent, `exitCode` is non-zero, `sha` is not head,
`counts.ignored` is non-zero (REQ-TST-13), a claimed REQ has no `redFirst` entry
(REQ-TST-10), or a suppression class rose since the previous gate (REQ-VAL-07).

**Mechanical on purpose.** The orchestrator does not read the diff and form a
view about whether the work looks finished. Forming that view is what it did
before this requirement existed, and it was wrong in the one direction that costs
a wave.

## 3. What may not be claimed (REQ-VAL-04)

- "It compiles." — `cargo check` said so, this session, at this sha, or it is unknown.
- "The tests pass." — `cargo test` printed counts, or it is unknown.
- "This still works." — the suite ran after the change, or it is unknown.

A result from round 2 is not evidence about round 3. The tree changed; that is
what a round is.

## 4. Phase boundaries (REQ-VAL-05)

| Gate | What must compile or build, even before the product exists |
|------|------------------------------------------------------------|
| `H0` | `cargo xtask validate` exits zero on the empty workspace |
| `H1` | the token module compiles, its contrast tests pass, and the mockup binaries build and run (REQ-MOC-01, REQ-DSN-06) |
| `H2` | the workspace builds at the manifest's pinned toolchain and crate versions |
| `H3` | `crates/contracts` compiles and its generated artefacts regenerate to an empty diff (REQ-VAL-13) |
| `H4` | the whole workspace: fmt, clippy `-D warnings`, check, test |
| `H5` | `validate --full` — MSI builds, installs clean, upgrades from the previous release, the installed binary launches (REQ-VAL-14) |
| `H6`–`H8` | all of the above, re-run at the sha under review (REQ-VAL-08) |

## 5. Warnings and suppressions (REQ-VAL-06, REQ-VAL-07)

`-D warnings` on clippy, `cargo fmt --check`, and
`#![deny(unsafe_op_in_unsafe_fn)]` workspace-wide. A build that permits warnings
accumulates them until nobody reads the output, which is the state in which a
real one is missed.

Four suppression classes are counted at every gate, and a rise is a finding:

| Class | Why it is watched specifically |
|-------|--------------------------------|
| `#[allow(...)]` | widening an allow is the fastest way to turn a red tree green |
| `unsafe` blocks | this build has an FFI surface; T1 and T2 review every one, and a count that grows between gates means a reviewed surface changed after review |
| `#[ignore]` | `cargo test` prints `N ignored` and nobody reads it (REQ-TST-13) |
| `.expect()` / `.unwrap()` on a fallible path | each is a panic in a shipped desktop app, so each carries the REQ it trades against |

Each occurrence carries its trade:

```rust
// SAFETY / REQ-FND-05: PrintWindow requires a raw HWND; the handle is owned by
// this window and outlives the call. Remove when the safe wrapper lands. Owner: B01.
#[allow(unsafe_code)]
```

## 6. One sha (REQ-VAL-08)

Validation records, capture sidecars (REQ-CAP-03) and gate verdicts each name a
commit sha. A gate whose evidence spans more than one is refused (REQ-GAT-09):
each piece is true, and the tree they jointly describe never existed.

## 7. The shared-tree stop (REQ-VAL-11)

`crates/contracts`, the workspace `Cargo.toml`, `Cargo.lock` or the token module
going red means every concurrent agent is building on a base that does not
compile. The orchestrator stops dispatching into that wave, names the file and
its owner from `contracts/ownership.md`, routes the fix there alone, and resumes
on green. Agents already running are told, not killed, and their hand-offs
validate against the repaired tree.

## 8. The record (REQ-VAL-12)

```
build/validation/
├── wave-0/B01.json
├── wave-3/B06.json               one per hand-off
├── wave-3/B06/test-output.txt    cargo's own output (REQ-TST-16)
├── H4.json                       one per gate, whole workspace
├── req-coverage.md               every MUST → its test (REQ-TST-12)
└── suppressions.md               per gate, per class, with the delta
```

Kept, not summarised. A summary of validation history is a claim about
validation history, and claims were the problem.
