# Contract Law

Nine agents build this app at the same time and never speak to each other. They
speak to one crate. This file is the law that governs that crate: what may be in
it, who may put it there, when it freezes, and what may change afterwards.

`contracts/ownership.md` says who owns which path. This file says what crosses
between owners.

---

## 1. One coupling point

`crates/contracts` is the **only** crate two other crates may share. No crate
depends on another crate an agent owns. `crates/update` does not depend on
`crates/service`; it depends on `crates/contracts` and on the `service-state`
member declared there.

```
ui · tray · install · service · update · obs ──▶ crates/contracts
                                          └───▶ crates/ffi  (Win32 only, §6)
```

Two reasons, and the second bites hardest. Ownership: a crate-to-crate
dependency is two agents editing one interface with no arbitration. Cargo: a
dependency cycle does not compile, so by the time `crates/service` and
`crates/update` each want the other, one is rewritten rather than patched.

Checked at H4 over the workspace manifests — an agent-owned crate named in
another crate's `[dependencies]` fails the gate. An agent that "just needs one
type from `crates/service`" has found a missing member, not an exception.

## 2. What lives in the contract

One publishing agent per member. Nobody else declares it, not even additively.

| Member | What it fixes | Published by |
|--------|---------------|--------------|
| `config` | the settings schema, every default, and the load order file → registry → command line | B02 |
| `errors` | the error enum, the stable error-code taxonomy, the `Display` text users see | B02 |
| `version` | the compiled-in version, build id and target triple every component reports (REQ-REL-05) | B02 |
| `paths` | every directory the app resolves — install root, per-user data, logs, staging, crash records — and its ACL expectation (REQ-SEC-05) | B01 |
| `ffi-boundary` | the safe wrapper surface over Win32, and the rule that nothing else calls it (§6, REQ-FND-03) | B01 |
| `design-tokens` | colour, type, spacing, radius, elevation, motion and per-state tokens, both themes (REQ-DSN-02, REQ-DSN-09) | B03 |
| `install-mode` | per-user vs machine-wide, the install layout, the ARP record, the exit-code table (REQ-INST-02, REQ-INST-11) | B07 |
| `service-state` | the state machine and the stop/start transition, the restart policy, the crash-loop window (§7, REQ-SVC-04) | B08 |
| `ipc-contract` | the endpoint name, its DACL, the caller-authentication step, the frame, every message type (REQ-SVC-06, REQ-SEC-09) | B08 |
| `update-manifest` | the signed manifest schema, channel names, the security-vs-feature flag, the verification order (REQ-UPD-02, REQ-UPD-13) | B09 |
| `log-record` | the structured record, the level set, the redaction rule, the Event Log mapping (REQ-OBS-01, REQ-OBS-06) | B12 |
| `view-registry` | the view descriptors the shell and the tray both address, plus `settings-registry` (REQ-UI-09) | B05 |
| `tray-state` | the live state the menu renders — running, paused, updating, error, service mode (REQ-TRY-04) | B06 |

Deliberately not members: signing keys (nobody's), the release workflow (B10's
alone, consumed by nothing in the binary), anything under `build/`.

## 3. Declaration, then assembly

An agent never writes into `crates/contracts`. Only B02 does. Each agent writes
one declaration inside its own crate, `crates/<name>/contract.decl.toml`:

```toml
agent = "B08"
requirements = ["REQ-SVC-04", "REQ-SVC-06", "REQ-SVC-10"]

[[types]]
name = "ServiceState"; kind = "enum"; non_exhaustive = true
variants = ["Stopped", "StartPending", "Running", "StopPending", "Paused",
            "Failed { code: u32 }"]

[[transitions]]
name = "stop_then_start"
inputs = ["timeout: Duration", "reason: TransitionReason"]
guarantees = ["restart policy suspended for the window",
              "crash-loop counter not incremented",
              "Err rather than a service left stopped"]

[[errors]]
code = "SVC_STOP_TIMEOUT"; exit = 40
```

The declaration is **data, not Rust**, and that is what keeps assembly acyclic:
B02 generates `crates/contracts/src/**` from the declarations, so no agent-owned
crate is ever a build input to the contract crate. Generated files are never
hand-edited — regeneration must reproduce them byte for byte.

Collisions are a hard failure at assembly naming both claimants: duplicate type
name, error code, exit code, config key, path id, IPC message tag or setting id.
Assembly stops. It does not resolve by last write.

## 4. The freeze (gate H3)

At H3, B02 publishes `contracts 1.0.0` and the surface is frozen. Wave 3 launches
against the frozen version or it does not launch.

`config`, `errors`, `version`, `paths`, `ffi-boundary` and `design-tokens` must
all be present first: every Wave 3 crate consumes one of them on its first task.
A member missing at H3 becomes a CCR in the middle of a nine-wide wave, and CCR
volume is the measurement of how well H3 was run.

After the freeze, adding is a fast-path CCR, changing is arbitrated, removing is
not available.

## 5. Additive-only, and what "additive" means for a compiled binary

There is no wire here. There is one binary with every crate compiled into it, so
changes that are additive on an HTTP API are breaking in Rust — and the compiler
catches most of them, but not all.

**Allowed**
- A new type, error code, exit code, config key, path id, token, IPC message
  type, setting descriptor, function or wrapper.
- A new field on a struct already `#[non_exhaustive]` and carrying a `Default`.
- A new variant on an enum already `#[non_exhaustive]`.
- A new trait method **with** a default implementation.

**Breaking, whatever it looks like**
- **Adding a variant to an enum that is not `#[non_exhaustive]`.** Every
  exhaustive `match` in every other crate stops compiling. This is the trap: the
  author sees an addition, four consumers see a break. Every contract enum is
  declared `#[non_exhaustive]` at H3 — after the freeze you cannot add the
  attribute, because adding it breaks the same matches.
- **Adding a field to a struct without `#[non_exhaustive]`.** Struct-literal
  construction elsewhere stops compiling.
- Making an `Option` required, narrowing a numeric type, renaming anything,
  changing a signature, adding a trait method with no default.
- **Reordering variants or changing a discriminant** where the value is
  serialised — the update manifest, the IPC frame, the log record and the exit
  codes all are. The code compiles and the meaning moves. Exit code 40 meaning
  something else in 1.1.0 breaks the deployment scripts REQ-INST-11 exists for.
- **Changing what a value means while keeping its name.** No tool catches it. A
  semantic change gets a new name.

Rule of thumb: if your edit could make `cargo check --workspace` fail in a crate
you do not own, it is not additive. If it could *succeed* and change behaviour in
a crate you do not own, it is worse than not additive.

H4 runs the check against the 1.0.0 baseline — a `cargo public-api` diff over
`crates/contracts` plus an assertion that every serialised discriminant still
matches the frozen table. It is not advisory.

## 6. The FFI boundary is a contract member

`crates/ffi` is the only crate that calls `windows-rs` (REQ-FND-03), and the
wrapper surface it exposes is a contract member like any other. Needing a new
Win32 call is a **CCR for a wrapper**, not a `use` statement.

This is stricter than ordinary layering, and the reason is the failure mode, not
tidiness. Nine agents writing their own `unsafe` calls produce nine independent
sets of assumptions about three things:

- **Handle lifetime** — who closes it, whether it is closed twice, whether it
  outlives the struct holding it.
- **Error convention** — Win32 signals failure five ways: a `BOOL`, an `HRESULT`,
  a null handle, `INVALID_HANDLE_VALUE`, and a success return with
  `GetLastError()` set. Two crates will read the same call differently.
- **String encoding** — UTF-16 in, `PCWSTR` lifetime, NUL termination, and what
  comes back for a path that is not valid Unicode.

Get one of those wrong in a layered web app and the answer is wrong. Get one
wrong here and you get a double free, a use-after-free, or a buffer the OS wrote
past: memory-unsafe, non-deterministic, reproducible on one user's machine only.
One owner means the assumptions are written once and **`T1` reviews one place
instead of nine**.

A wrapper CCR states, and the wrapper documents: the exact Win32 function and
its header; who owns the returned handle and where `Drop` closes it; which of
the five failure conventions the call uses and its mapping into
`contracts::Error`; the string conversion in both directions; and the invariant
each `unsafe` block relies on, as a comment (REQ-FND-06).

Two consequences. `crates/ffi` **re-exports no `windows` type** across its API —
a wrapper returning `HANDLE` moved the boundary into its caller instead of
closing it. And the H4 lint is mechanical: a `windows` or `windows-sys` entry in
any `Cargo.toml` but `crates/ffi`'s, or a `use windows::` anywhere else, fails.

## 7. A state transition is a contract member

The stop/start transition B08 publishes under `service-state` is the interface
B09 calls during an update (REQ-UPD-10). A type is not the only thing that can be
a member; an ordering is one too.

```rust
contracts::service::stop_then_start(timeout, TransitionReason::Update { to: version })
```

What an agent reaches for instead is `Command::new("sc.exe").args(["stop", …])`.
That gets the ordering right by luck, because the caller cannot know three things
the owner knows:

- **The restart policy** (REQ-SVC-10). The SCM has recovery actions configured.
  Stop the service outside the transition and the SCM restarts it — on the old
  binary, mid-swap, holding the file the updater is replacing.
- **Crash-loop detection.** B08 counts unexpected stops in a window. An update's
  stop is expected; a `sc.exe` stop is indistinguishable from a crash, so the
  third update in a day trips a crash loop that never happened.
- **When "stopped" is true.** `sc stop` returns when the SCM accepted the control
  code, not when the process exited and released its files. REQ-SVC-04 forbids
  reporting a state the service has not reached, so the transition waits for the
  real thing — which is what lets the swap that follows be atomic (REQ-UPD-06).

The transition also refuses a cross-version pairing (REQ-SVC-05) and returns an
error rather than leaving the service stopped. Each of those is a declared
guarantee, not a comment in B09's code.

## 8. Contract Change Request

A CCR is a file in `build/ccr/<n>-<slug>.md`, stating: what changes, the kind
(additive or breaking), the requirement that forces it, why every consumer stays
correct without editing anything, the boundary facts of §6 where it is a wrapper,
and the rollout — who implements, who assembles, which version it lands in.

- **Additive CCR**: B02 approves and assembles. Wave 3 does not pause.
- **Breaking CCR**: the orchestrator arbitrates and **the default answer is no** —
  find the additive version. Where it is genuinely unavoidable it becomes one
  versioned change with a task for every affected agent, batched rather than
  dribbled.

Every decision is logged. More than a handful of breaking CCRs in a build is a
finding against the H3 freeze, and therefore against the orchestrator rather than
the agents who filed them.

## 9. Nobody waits

No agent calls another agent's code and none waits for another to finish.
Consumption is through artefacts that exist at H3:

1. **Generated types** from the declarations, present before any behaviour is.
2. **Fixtures** in `crates/fixtures`, generated by B14 from the same
   declarations so a fixture cannot drift from its member: a signed test manifest
   with its test key pair, one with a bad signature, a tampered artefact, a
   downgrade manifest, both install layouts, an IPC transcript per message type,
   a log record per level.
3. **Stub transitions.** `stop_then_start` resolves against a scripted service in
   the fixture until B08 lands the real one. Swapping stub for real is a flag in
   the test harness, not an edit in B09.

B09 finishes the updater without `crates/service` existing, because it was never
consuming `crates/service` — it was consuming `service-state` plus a fixture.
It is also why the negative update cases (REQ-UPD-02, REQ-TST-03) are testable on
day one: the bad-signature fixture is generated at H3, not written by hand at H5
when somebody remembers. Where a fixture and the real implementation disagree at
H5, the contract was ambiguous, and the fix is a clarifying CCR rather than a
patch on whichever side was looked at first.

## 10. Versioning the contract crate

`crates/contracts` carries its own semver, mechanically rather than by judgement:
additive member → minor; clarification, doc, fixture or test → patch; anything
the breaking-change check flags → major, with orchestrator sign-off.

Wave 3 pins a caret range on the minor. A major bump mid-wave is a build incident
with a written cause, and the cause is almost always an enum frozen without
`#[non_exhaustive]`.
