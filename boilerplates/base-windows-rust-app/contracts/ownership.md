# Ownership Map

Every path has exactly one owning agent. This is what lets Wave 3 run nine
agents at once: they do not coordinate, they do not merge, and they read each
other's work through the frozen contract.

**An agent writing outside its owned paths is a build defect.** The orchestrator
rejects the task result and reassigns rather than accepting the diff.

## Workspace root

| Path | Owner | Notes |
|------|-------|-------|
| `Cargo.toml` (workspace), `Cargo.lock`, `rust-toolchain.toml`, `.cargo/config.toml` | B01 | Version fields are B17's |
| `deny.toml` | B11 | |
| `.gitignore` | B01 | Present from the first commit. It never excludes `build/`, `mockups/`, the `*.pub` update keys or the updater test fixtures (REQ-FND-13, REQ-FND-14). |
| `crates/contracts/**` | B02 | Frozen at H3. CCR-only afterwards |
| `crates/app/` scaffold, `crates/ffi/**`, `build.rs`, the application manifest | B01 | The `unsafe`/FFI boundary policy lives here (REQ-FND-06) |
| `versions/manifest.json`, `versions/traps.json` | B16 | |
| `CHANGELOG.md`, `README.md`, `SECURITY.md`, `TODO.md`, `VERSION`, all version fields | B17 | No other agent edits these, ever |
| `.github/workflows/**` | B10, except the supply-chain workflow (B11) | |
| `build/costs.md`, `versions/pricing.json` | B18 | |

## Crates

| Path | Owner |
|------|-------|
| `crates/design/**`, `design/**` | B03 |
| `mockups/**` | B04 |
| `crates/ui/**` | B05 |
| `crates/tray/**` | B06 |
| `crates/install/**`, `packaging/wix/**` | B07 |
| `crates/service/**`, `crates/autostart/**` | B08 |
| `crates/update/**` | B09 |
| `ci/publish/**` | B10 |
| `security/supply-chain/**` | B11 |
| `crates/obs/**` | B12 |
| `compliance/**` | B13 |
| `crates/fixtures/**`, `tests/**` except `tests/visual/**` | B14 |
| `tests/visual/**`, `build/screenshots/**` | B15 |
| `portability/**` | orchestrator |

## The FFI boundary is owned, not shared

B01 owns `crates/ffi/**`, and it is the **only** crate that calls `windows-rs`
directly. Every other crate goes through a safe wrapper B01 publishes.

This is stricter than it looks and it is deliberate. Nine agents each writing
their own `unsafe` Win32 calls produces nine different assumptions about handle
lifetime, error conventions and string encoding, and the resulting bugs are
memory-unsafe rather than merely wrong. One owner for the boundary means one
place to review (`T1`'s lens) and one place to fix.

A Wave 3 agent that needs a Win32 call it does not have files a CCR for a
wrapper. It does not add `use windows::Win32::...` to its own crate.

## Registrations have one owner each

Three agents can change what a machine looks like after install, and the split
is by **state transition**, not by file:

| State | Owner | Nobody else may |
|-------|-------|-----------------|
| Files on disk, ARP entry, shortcuts | B07 | write to the install directory |
| The Windows service registration | B08 | call `sc.exe`, `CreateService`, or the service-control wrappers |
| The autostart entry | B08 | write the `Run` key or create a scheduled task |
| Replacing installed files | B09 | swap a binary |

An update of a service-mode installation crosses all three. It crosses them
**through the contract**: B09 reads `service-state` and invokes the stop/start
transition B08 published (REQ-UPD-10). An agent reaching for `sc.exe` directly
has bypassed a contract, and the reason that matters is ordering — B09 cannot
know B08's restart policy or its crash-loop detection, so a direct call gets the
sequence right by luck.

## Signing keys are nobody's

No agent owns a signing key. B09 embeds a **public** key (REQ-UPD-03) and B10
consumes a signing credential from CI secrets it never reads, logs or writes
(REQ-REL-04). An agent that needs a private key to do its job has been asked to
do the wrong job.

## Gate agents own nothing

`D1`, `D2`, `T1` and `T2` write only to `build/gates/`. They never edit product
code — they produce findings, and the owning agent fixes them (REQ-GAT-07).

`build/` is orchestrator-owned working state and it is **committed**, not
gitignored. It holds the intake, the human's design approval (REQ-MOC-08), every
gate verdict and the cost ledger, and `compliance/cra/obligations-matrix.md`
cites paths under it as `build-output` evidence — the strongest tier, on the
grounds that an auditor can check a path. An auditor cannot check a path that is
not in the repository. `target/` is gitignored; `build/` is the record.

## Conflict resolution

If two agents both believe they own a path, that is a bug in **this file**, not a
negotiation between agents. The orchestrator amends the map, states the amendment
in the build log, and reassigns.
