# The Karpathy Lens

REQ-GAT-06. Not a gate, not a round, not a vote of its own: a standing lens that
**both** critics run on **every** build. D1 and D2 each record a `karpathyLens`
block in every verdict (`verdict-schema.md`) with four sub-verdicts:
`overcomplication`, `surgical`, `assumptions`, `verifiable`.

The four guidelines as they apply here:

- **No overcomplication** — the simplest thing that satisfies the requirement.
- **Surgical changes** — touch what the task names, nothing adjacent.
- **Surfaced assumptions** — an assumption is stated in the code or the report,
  or it is a hidden defect.
- **Verifiable success criteria** — "done" means a command someone else can run.

A sub-verdict fails on evidence, like any finding. A `fail` is written as a normal
finding against the REQ ID the smell damages — REQ-FND-03 for an FFI leak,
REQ-SBM-05 for a dependency, REQ-DSN-09 for a colour literal — and graded by that
requirement, not by the smell's name. The lens is how you find it; the
requirement is what blocks the gate.

## The checklist

Eight questions, each with an answer that settles it.

### 1. An abstraction over one Win32 call

**Ask:** what does this wrapper add over the call it wraps, and would the caller
be shorter without it?

**Settles it:** read the wrapper body. A `TrayIconManager` that holds one `HWND`
and forwards `Shell_NotifyIconW` with no state machine, no retry and no
re-registration is a rename, not a boundary. The legitimate wrapper is the one
that carries something: the handle's `Drop`, the error mapping, the UTF-16
conversion, the invariant (`contracts/README.md` §6). A wrapper with none of those
four is indirection, and the FFI boundary is exactly where indirection costs a
reader the most.

### 2. A trait with one implementor

**Ask:** how many types implement this trait, and which requirement names the
second one?

**Settles it:** `rg -n "impl .* for " crates | rg "<Trait>"` returns one, and no
REQ ID predicts another. An `UpdateTransport` trait with only HTTPS behind it
contradicts REQ-SEC-01, which permits nothing else. Required plurality is
different and is named by a requirement: two install modes (REQ-INST-02), two
targets (REQ-FND-04), two themes (REQ-DSN-03), two forges (REQ-REL-01), stable and
pre-release channels (REQ-UPD-07). A test double is not a second implementor
unless the fixture design says so (`contracts/README.md` §9).

### 3. A config knob nobody asked for

**Ask:** which intake answer or REQ ID created this setting, and what happens on a
user's machine if it is absent?

**Settles it:** the key is in the `config` member and in the settings UI but in no
requirement and no `build/scope.md` line, and its default is the only value ever
used. Delete it. Every setting is also a support-call surface and a line in the
diagnostics view (REQ-OBS-03). The inverse defect is worse: a security-relevant
value with a silent default — an update channel, a signature-verification switch,
an IPC ACL — which is a REQ-CRA-02 failure, not a missing knob.

### 4. `unsafe` where a safe wrapper already exists

**Ask:** does `crates/ffi` already publish this, and if not, why was a CCR not
filed?

**Settles it:**

```bash
rg -n "^\s*use windows(_sys)?::" crates --glob '!crates/ffi/**'
rg -n "windows(-sys)?\s*=" crates/*/Cargo.toml | rg -v "crates/ffi"
rg -n "unsafe \{" crates --glob '!crates/ffi/**'
```

Any hit is a REQ-FND-03 finding against that crate's owner and a missing wrapper
against B01. Then read the `unsafe` blocks that remain in `crates/ffi`: a block
whose `// SAFETY:` comment restates the call instead of stating the invariant
("SAFETY: calling the Win32 function") has documented nothing (REQ-FND-06).

### 5. A dependency added for one function

**Ask:** where is the recorded justification (REQ-SBM-05), and how much of the
crate is used?

**Settles it:** `git diff Cargo.lock` grew, the crate appears in one `use`, and
`security/supply-chain/` has no entry. In a Rust binary every dependency is
**compiled into the shipped product**, so this is a shipping decision, not a
development convenience: it enters the SBOM (REQ-SBM-01), the advisory surface
(REQ-SBM-03), the binary size, and the reproducibility claim (REQ-FND-09). A
date-formatting crate pulled in for one timestamp, or a registry crate where
`crates/ffi` already wraps `RegSetValueExW`, is both this smell and a REQ-FND-03
defect. Check transitive cost in B11's inventory, not only the direct line.

### 6. An `unwrap()` on something the user's machine controls

**Ask:** who produces this value, and what does the process do when it is absent
or malformed?

**Settles it:** `rg -n "\.unwrap\(\)|\.expect\(" crates --glob '!**/tests/**'`,
then classify each hit by its input's origin. An `unwrap()` on a compile-time
constant is fine. These are not, and each is a REQ-SEC-07 finding:

- `known_folder(...)` on a machine with a redirected or missing profile path.
- a config or manifest field after parsing (REQ-SEC-07).
- an environment variable, a command-line argument, or a registry read.
- a monitor, DPI or window-placement query for a display that was unplugged
  (REQ-UI-03, REQ-DSN-11).
- an `HWND`, a service handle or a pipe handle after the peer has gone.

A panic in a tray-resident process is a vanished icon with no window and no
message, which is the same defect class REQ-TRY-02 exists for. A panic in the
service is a restart the crash-loop detector counts (REQ-SVC-10).

### 7. A generated file edited by hand

**Ask:** does regenerating this file reproduce it byte for byte?

**Settles it:** regenerate and diff. Candidates: `crates/contracts/src/**`
(generated from the declarations, `contracts/README.md` §3), `crates/fixtures`,
the token module derived from the approved mockup (REQ-MOC-08), the SBOM
(REQ-SBM-01), the compliance set (REQ-CRA-10), `versions/manifest.json`
(REQ-VER-03), and `Cargo.lock`. A hand edit here survives every review because it
looks generated, and it breaks at the next regeneration — usually at H8, with the
release half-built.

### 8. A "done" with no way to check it

**Ask:** which command, test name or recorded artefact proves this claim, and does
it pass right now?

**Settles it:** re-run every claim you intend to mark `pass`. The agent's report
cites a REQ ID with no test path, or a test that asserts the implementation rather
than the behaviour. The easily faked claims in this codebase, each needing a
recorded artefact rather than a paragraph:

- tray survival across an Explorer restart (REQ-TRY-02) — the test kills
  `explorer.exe` or it proves nothing;
- single instance (REQ-TRY-06) — two launches, one icon;
- atomic swap under interruption (REQ-UPD-06) — the process is killed mid-swap;
- signature rejection (REQ-UPD-02) — the bad-signature fixture is used and
  refused, not merely present;
- uninstall completeness (REQ-INST-06) — a registry and filesystem diff, not a
  visual check;
- redaction (REQ-SEC-08) — a known secret is planted and the support bundle is
  searched for it;
- contrast (REQ-DSN-06) — the token-table test, both themes, not a screenshot
  that looks fine.

## Recording the lens

```json
"karpathyLens": { "overcomplication": "pass", "surgical": "pass",
                  "assumptions": "fail", "verifiable": "pass" }
```

- Mandatory in every D1 and D2 verdict, both dimensions, every round.
- A `fail` sub-verdict requires at least one finding in the same file whose
  `defect` states the smell concretely and whose `owner` comes from
  `contracts/ownership.md`. A `fail` with no finding is a malformed verdict.
- The lens never blocks on its own. It blocks through the requirement it damaged,
  at that requirement's severity; an unmet `MUST` is at least `high`.
- The lens is not a style opinion. "I would have written it differently" is not a
  `fail`. "`TrayIconManager` wraps one `Shell_NotifyIconW` call, holds no state,
  maps no error, and costs a reader two files to trace one call" is.
