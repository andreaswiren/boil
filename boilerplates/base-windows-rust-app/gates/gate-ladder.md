# The Gate Ladder — H0 … H8

Fixed order. Per gate: entry condition, the exact checks, who runs them, the pass
criterion, where a failure loops back, whether a human is in the loop. Verdicts
land in `build/gates/<gate>/` (`verdict-schema.md`). Two criteria apply to every
gate below and are not repeated: the standing cost criterion in `README.md`, and
the rule that a check with no recorded command output is a claim, not a result.

---

## The validation criterion, at every gate

Every gate below carries this without repeating it:

> **The workspace is green at the sha under review** (REQ-VAL-05, REQ-VAL-08).
> `cargo xtask validate` has been run — this session, at this sha — and exited
> zero: `fmt --check` clean, `clippy -D warnings` clean, `check --all-targets
> --all-features` clean, `cargo test` with zero failures and **zero ignored**
> (REQ-TST-13). The record is at `build/validation/<gate>.json` with the command,
> the exit code, the counts, the duration and the output tail (REQ-VAL-12).

A gate does not pass on an agent's statement that the workspace builds. It passes
on an exit code someone obtained by running the command (REQ-VAL-04).

Three derived refusals, all mechanical:

- **Evidence spanning two shas does not pass** (REQ-VAL-08, REQ-GAT-09).
- **A suppression count that rose since the previous gate is a finding**
  (REQ-VAL-07) — `#[allow]`, `unsafe` blocks, `#[ignore]`, `.expect()` on a
  fallible path, each new occurrence named and its REQ trade read. On a build
  with an FFI surface, a growing `unsafe` count also means a surface T1 and T2
  already reviewed has changed since they reviewed it.
- **A stale capture does not pass** (REQ-CAP-10): every view the gate covers has
  a capture at this sha, with a clean log (REQ-CAP-07), and anything that could
  not be captured is named rather than dropped (REQ-CAP-11).

## The capture criterion, at every gate

> **The capture feed is current and delivered both ways** (REQ-CAP-01,
> REQ-CAP-04): images in the reply, `build/screenshots/` holding them with their
> sidecars, `index.md` regenerated. Both themes, high contrast as its own
> variant, the DPI ladder, and all five view states (REQ-CAP-08, REQ-CAP-09).

---

## H0 — Intake resolved

**Runs:** B00. **Entry:** the user's description exists. **Human:** yes — answers
the questions that change the build; the rest is defaulted loudly in
`build/scope.md`.

1. Purpose and scope resolved: what the app does, who runs it, what it touches.
   **Service mode** on or off — REQ-SVC-01 is the register's only `OPT`, and it
   decides whether Wave 3 is nine agents or eight.
2. **UI framework** with the stated default (`eframe`), able to express tokens in
   code with both themes first class (REQ-UI-01, REQ-DSN-02). **Forge endpoints**
   for GitHub and Gitea, credentials named but never read (REQ-REL-02).
   **End-of-support date** (REQ-CRA-08), **minimum supported Windows version**
   (REQ-FND-05), **cost ceiling** or an explicit none.
3. Every `build/waivers.md` entry cites the answer that granted it. The register is
   all `MUST` plus one `OPT`, so a non-empty waiver file means a `MUST` was waived
   — **that fails the build** rather than waiving.

4. **`cargo xtask validate` exists and exits zero on the empty workspace**
   (REQ-VAL-01). `B01` writes it in Wave 0, before there is anything to hide — a
   validation command first authored in Wave 3 is authored to pass.
5. **The capture pipeline is proven end to end** on a placeholder window
   (REQ-CAP-06): a binary builds, `request_screenshot` returns an image, the
   sidecar is written, `index.md` regenerates, and whether desktop capture is
   available in this session is recorded rather than assumed (REQ-CAP-11).
   Proving it on a window with nothing at stake is much cheaper than finding out
   at `H1` that it does not work.

**Pass:** `build/intake.md` and `build/scope.md` exist, the `OPT` has a value, the
ceiling and support date are recorded, zero waived `MUST`s, `validate` green and
the capture pipeline proven. **Fail →** B00 with the
unresolved item named; a missing human answer stalls the build, never guessed.

## H1 — Design approved

**Runs:** B16 (narrow pre-pass), B03 (tokens and themes), B04 (mockups),
B15 (build, run, capture).
**Entry:** H0 passed. **Human:** yes, decisively — **the human names the winner.**

The gate that makes this boilerplate what it is, the one most likely to feel like
a delay, and the only one whose output every later gate is measured against.

0. **B16's pre-pass, before B04 writes a `Cargo.toml`.** A mockup is a compiled
   program (REQ-MOC-02), so it needs the toolchain and the GUI framework crate,
   and H2 blocks every dependency line until a version is externally validated
   (REQ-VER-02, REQ-FND-08) — H2 is *after* this gate. Rather than let H1 break
   the rule H2 enforces, B16 runs first and narrowly: the Rust toolchain, the
   framework chosen at H0, and nothing else, validated against crates.io and the
   release channel and written into `versions/manifest.json` with source URL and
   timestamp like any other entry. Two entries validated is not a waiver of H2;
   it is H2's rule applied to the two crates H1 cannot proceed without. Anything
   the mockups do not need waits for the full pass.
1. **Three to five mockups**, differentiated by design **direction** — density,
   typographic scale, chrome weight, accent strategy — not by accent colour
   (REQ-MOC-06), each one screen with the token set and enough controls to show
   every state of REQ-DSN-10 (REQ-MOC-03).
2. **Each builds from clean.** `cargo build -p mockup-<n> --locked` in a checkout
   with no `target/`, output recorded per mockup (REQ-MOC-02, REQ-MOC-04). Clean is
   the check, not built: a warm `target/` links an artefact whose source no longer
   compiles, and "it built here" is the claim this gate exists to disprove.
3. **Each runs**, and B15 screenshots it in **light and dark** (REQ-MOC-05),
   presented in the chat reply, not only written to `build/screenshots/`
   (REQ-TST-04).
4. **The contrast test passes over the token table in both themes** at WCAG 2.2 AA
   (REQ-DSN-06, REQ-TST-05). A mockup that fails it is not a design direction, it
   is a proposal to ship an inaccessible product, and it is withdrawn before the
   human is asked.
5. **Each states its direction and its tradeoff** in its source header
   (REQ-MOC-07). Without one the human chooses between five claims that all say
   "clean and modern".

**Pass:** a human names one direction, or an explicit hybrid of two named ones,
recorded in `build/approvals.md` with who named it and when (REQ-MOC-08). The token
module is derived from that mockup, which stays in-tree as the reference D1 checks
drift against.

**Blocks: all feature work** (REQ-GAT-08, REQ-MOC-01). Nothing exists under
`crates/ui/**`, `crates/tray/**`, `crates/install/**` or any other Wave 3 path
before this gate closes — not scaffolding with a bit of UI, not "we restyle
later". **Accepting an image instead of a compile is accepting a claim instead of
a proof**: a picture proves a shape can be drawn, not that the framework's styling
model can express it, which is the only question this gate asks. **Fail →** B04 for
another round, or one narrowing question to the human. A human who cannot choose
was usually shown five variations of one direction, a REQ-MOC-06 failure.

## H2 — Version validation

**Runs:** B16. **Entry:** H1 passed. **Human:** only on a major jump (REQ-VER-04).

1. Latest **stable** for the toolchain and every crate — no prerelease, no RC, no
   git dependency (REQ-VER-01) — confirmed externally against crates.io and the
   Rust release channel (REQ-VER-02), each `versions/manifest.json` entry carrying
   its **source URL** and check **timestamp** (REQ-VER-03).
2. MSRV stated, not above the pinned toolchain, and not raised silently by a
   dependency (REQ-VER-05, REQ-VER-06); the `windows` / `windows-sys` pairing trap
   recorded in `versions/traps.json`.
3. A major jump carries a migration note. A `windows` major can rename types
   across every FFI call site, so the note is B01's task list, not paperwork.

**Pass:** zero entries without source URL and timestamp, zero prereleases, a
migration note per major jump. **Blocks:** every `Cargo.toml` dependency line and
the toolchain pin (REQ-FND-08) — **except** the toolchain and the framework crate
already validated by the H1 pre-pass, which this gate re-reads rather than
re-deciding. If the pre-pass entry is stale by `policy.staleAfterDays` it is
re-validated here, and a framework whose version moved under the mockups is a
finding against B16's pre-pass, not a licence to keep the old number.
**Fail →** B16; a version that cannot be confirmed externally is a hard fail,
never a fallback to memory.

## H3 — Contract freeze

**Runs:** B02. **Entry:** H2 passed, B01's scaffold and `crates/ffi` in place.
**Human:** only to arbitrate a breaking CCR (`contracts/README.md` §8).
1. Every `crates/<name>/contract.decl.toml` collected (`contracts/README.md` §3),
   with **zero collisions**: a duplicate type name, error code, exit code, config
   key, path id, IPC message tag or setting id stops assembly naming both claimants.
3. `config`, `errors`, `version`, `paths`, `ffi-boundary` and `design-tokens` all
   published, `contracts 1.0.0` published, Wave 3 pinning a caret range.
4. **Every contract enum is `#[non_exhaustive]`** (REQ-CTR-06). After the freeze the
   attribute cannot be added, because adding it breaks the same exhaustive `match`
   statements a new variant would (`contracts/README.md` §5).
5. Fixtures generated from the declarations, the update negatives included: bad
   signature, tampered artefact, downgrade manifest, interrupted swap (REQ-TST-03).
   The FFI-boundary lint configured and failing on a `windows` import outside
   `crates/ffi` (REQ-FND-03); breaking-change baseline armed on 1.0.0.

**Pass:** 1.0.0 published, zero collisions, fixtures generated, both checks armed.
**Blocks:** the launch of Wave 3 — nine agents do not start against a moving
contract (REQ-CTR-02). **Fail →** B02 plus the agent that declared the colliding
member.

## H4 — Crate self-test

**Runs:** each Wave 3 agent for its own crate, B14 for the interface tests.
**Entry:** Wave 3 reported complete. **Human:** no.

1. `cargo test -p <crate>` green for every Wave 3 crate and B14's interface tests
   green, run by both producer and consumer (REQ-TST-01, REQ-CTR-10);
   `cargo clippy --all-targets -- -D warnings` and `cargo fmt --check` clean
   workspace-wide (REQ-FND-07).
2. **FFI-boundary lint clean:** no `windows` or `windows-sys` entry in any
   `Cargo.toml` but `crates/ffi`'s, no `use windows::` anywhere else
   (REQ-FND-03), `#![forbid(unsafe_op_in_unsafe_fn)]` present, every `unsafe`
   block carrying its invariant comment (REQ-FND-06).
3. **No raw colour literal outside the token module** (REQ-DSN-09, REQ-TST-05) and
   contrast green in both themes (REQ-DSN-06); no dependency between agent-owned
   crates (REQ-CTR-01); breaking-change check clean against 1.0.0 (REQ-CTR-09).
4. `cargo deny` clean on licences, duplicates and advisories (REQ-SBM-07);
   `Cargo.lock` committed, build `--locked` (REQ-SBM-08); the no-telemetry
   assertion green including build-time network access (REQ-SBM-06, REQ-FND-10).

5. **Every Wave 3 hand-off carried a green validation block at its own sha**
   (REQ-VAL-02) — checked, not sampled. A hand-off accepted without one was
   accepted in error, and the work behind it is unverified (REQ-VAL-03).
6. **Red-first evidence for every claimed REQ** (REQ-TST-10): each agent's
   `redFirst` names the test, the sha at which it failed and the sha at which it
   passed. `B14` audits these — an entry whose `redSha` equals its `greenSha`, or
   whose test did not exist at `redSha`, is a finding against that agent.
7. **Zero ignored tests** across the workspace (REQ-TST-13), reported with the
   command that produced the count. `cargo test` prints `N ignored` and nobody
   reads it, which is what makes it the cheapest way past a gate.
8. **The trust-chain negatives run here, not first at `H5`** (REQ-TST-17): wrong
   signature, tampered artefact, downgrade, interrupted swap. An updater that
   stopped verifying signatures updates faster and looks identical.
9. **`build/validation/req-coverage.md` regenerated** (REQ-TST-12): every `MUST`
   maps to a test or to a recorded reason it cannot be tested.

**Pass:** every check above green for every crate. **Fail →** the single owning agent
the failing check names — localised failure is the point of running this before H5.

## H5 — Integration

**Runs:** B14, with B15 for capture. **Entry:** H4 passed. **Human:** no.
1. `cargo build --release --locked` for `x86_64-pc-windows-msvc` **and**
   `aarch64-pc-windows-msvc` (REQ-FND-04); ASLR/DEP, CFG and a stripped build
   verified (REQ-SEC-04); one self-contained exe (REQ-FND-12).
2. **Installs on a clean Windows image of each architecture.** Both targets build
   at step 1, and building for ARM64 proves nothing about installing on it: the
   install path touches the registry, ARP, shortcuts, the service account and
   WoW64 redirection, and a cross-compiled binary exercises none of that from an
   x64 runner. So steps 2 through 7 run on an x64 image **and** an ARM64 image,
   and a REQ ID verified on only one of them is reported `unverified` for the
   other rather than green (REQ-FND-04). Where no ARM64 image is available the
   gate records which REQ IDs that leaves unverified and names it as the reason —
   an absent runner is a stated gap, not a pass.
   Per-user with no elevation, machine-wide
   with one UAC prompt at the moment of need (REQ-INST-02, REQ-INST-04); ARP entry
   with a working uninstall command (REQ-INST-05); install log (REQ-INST-12); run
   twice leaves the same state (REQ-INST-07); a forced mid-install failure rolls
   back (REQ-INST-09); `--install --silent` returns its documented exit codes
   (REQ-INST-11).
3. **Runs and trays.** Placement restored, including onto a monitor that no longer
   exists (REQ-UI-03); the tray icon survives `taskkill /f /im explorer.exe` and
   re-registers (REQ-TRY-02, REQ-TST-06); a second launch focuses the running
   instance rather than adding an icon (REQ-TRY-06); Exit leaves no process and no
   ghost icon (REQ-TRY-07).
4. **Service mode**, where intake enabled it: install, start, stop, uninstall with
   their exit codes (REQ-SVC-02); least-privileged account (REQ-SVC-03); status
   accurate while initialising (REQ-SVC-04); the IPC endpoint reachable only by its
   intended caller and authenticating it (REQ-SVC-06, REQ-SEC-09); crash recovery,
   crash-loop detection and a refused version mismatch (REQ-SVC-10, REQ-SVC-05,
   REQ-TST-07).
5. **Updates from a real signed manifest**, and the negatives are the point: wrong
   signature, tampered artefact, downgrade attempt, interrupted swap (REQ-UPD-02 …
   REQ-UPD-06, REQ-TST-03). A service-mode update goes through B08's transition
   and reports failure rather than leaving the service stopped (REQ-UPD-10).
6. **Uninstalls completely** — binaries, shortcuts, registry, scheduled task,
   service, autostart entry — with the user-data prompt (REQ-INST-06), verified by
   a filesystem and registry diff against the pre-install snapshot.
7. **The upgrade path from the previous released version works** (REQ-TST-02):
   settings survive, the service is re-registered at the new version, the old ARP
   entry is replaced not duplicated. A fresh install alone tests the case a user
   meets once.
8. DPI at 100%, 150%, 200% and 250%, and a window dragged between monitors with
   different scale factors (REQ-TST-08, REQ-DSN-11); screenshots in both themes in
   chat (REQ-TST-04); a screen reader over the primary flows (REQ-TST-09).

9. **`cargo xtask validate --full` green** (REQ-VAL-14): the workspace validates,
   the MSI builds, installs on a clean image, upgrades from the previous release,
   and the installed binary launches. A workspace that compiles and an installer
   that works are two different claims, and the user only ever meets one of them.
10. **The capture feed covers every view at this sha** — five states, both
    themes, high contrast, the DPI ladder — with a clean log per capture
    (REQ-CAP-07 … REQ-CAP-10) and anything uncapturable in this session named
    rather than dropped (REQ-CAP-11).

**Pass:** every suite green, `validate --full` green, the capture feed current at
this sha, the upgrade path proven.
**Fail →** the owning agent per `contracts/ownership.md`; a failure spanning owners
goes to the orchestrator to split, never to whoever is nearest.

## H6 — Design & function critique

**Reviewers:** D1 and D2. **Entry:** H5 passed and its evidence exists. **Human:**
only on escalation after three failed rounds (REQ-GAT-05).

Both critics vote on **both** dimensions — four verdicts, all must pass
(REQ-GAT-01): `D1-design-r<N>`, `D1-function-r<N>`, `D2-design-r<N>`,
`D2-function-r<N>` in `build/gates/H6/`. D1 leads on the design system and its
honesty, judging against the direction the human named at H1; drift from
`build/approvals.md` is a finding whatever its quality. D2 leads on completeness
across install, update, service and tray, hunting the requirement satisfied on
the happy path only. Both record the Karpathy lens every build (REQ-GAT-06).

**Pass:** all four verdicts `blocking: false`, zero open `critical` or `high`
findings. **Fail →** each finding to the owner named in it, re-reviewed by the
**same** critic at round `N+1` (`loop-rules.md`).

## H7 — Security review

**Reviewers:** T1 and T2 independently, plus B11's report. **Entry:** H5 passed.
**Human:** only on escalation.

1. T1 and T2 launched **in the same message**, no shared context, neither seeing
   the other's findings before submitting (REQ-GAT-02).
2. Each states a **written review plan** first — common best practice, the FFI and
   `unsafe` surface, elevation and privilege boundaries, the update trust chain,
   IPC — then executes it in that order (REQ-GAT-03).
3. T1 covers privilege boundaries: manifest execution level (REQ-FND-11),
   elevation paths and their scope (REQ-INST-04), the service account
   (REQ-SVC-03), the IPC DACL and caller authentication (REQ-SEC-09), directory
   ACLs (REQ-SEC-05), DLL search order (REQ-SEC-06), and whether each `unsafe`
   block's stated invariant holds (REQ-FND-06).
4. T2 covers the trust chain and the data: signature verified **before** the swap
   against an embedded key (REQ-UPD-02, REQ-UPD-03), hash against the signed
   manifest over validated TLS (REQ-UPD-04, REQ-SEC-01), downgrade refused
   (REQ-UPD-05), atomic swap (REQ-UPD-06), secrets at rest (REQ-SEC-03), redaction
   everywhere output goes (REQ-SEC-08), untrusted-input parsing (REQ-SEC-07).
5. B11's report clean in the same round: SBOM complete and embedded (REQ-SBM-01,
   REQ-SBM-02), no critical or known-exploited advisory (REQ-SBM-03), the
   dependency-behaviour review done with a justification per new dependency
   (REQ-SBM-04, REQ-SBM-05).

**Pass:** `T1-code-r<N>.json` and `T2-code-r<N>.json` both `blocking: false`, B11's
report with zero blocking entries. **Fail →** the owning agent per finding; same
reviewer, round `N+1`. A finding both reviewers raise is a stronger signal, not a
duplicate to suppress.

## H8 — Release candidate

**Runs:** B17. **Entry:** H6 and H7 both passed. **Human:** yes — accepts the RC.
1. **Every `MUST` green** — never waived, the build fails instead — with four H6
   and two H7 verdicts on file, all passing **and all six naming the same
   `commit`** (REQ-GAT-09). Six passing verdicts spread across three commits certify a tree
   that was never reviewed: D1 approved the design at commit A, T2 cleared the
   updater at commit C, and whatever landed in between has no reviewer. The
   `commit` field in `gates/verdict-schema.md` exists for this assertion; it is
   also what decides whether a fix re-opens H6, so read it rather than
   remembering which round was last. `build/validation/req-coverage.md` shows a
   test or a recorded untestable-reason per `MUST` (REQ-TST-12); zero ignored and
   zero quarantined tests (REQ-TST-13, REQ-TST-15); the suppression ledger shows
   no unexplained rise across the ladder, `unsafe` blocks included (REQ-VAL-07).
2. Signed binaries for **both** architectures, the MSI, the SBOM, checksums, the
   signed manifest and release notes (REQ-REL-03, REQ-REL-04, REQ-INST-03), the
   signing key in no log, repository or unencrypted CI variable.
3. **The update manifest is published atomically and last**, after every artefact
   it references is retrievable (REQ-REL-10) — a manifest pointing at a missing
   artefact breaks every client at once.
4. **Both forges succeeded**, since a publish that succeeds on one and fails on the
   other fails the release (REQ-REL-01, REQ-REL-08).
5. **The published release is verified as a client** (REQ-REL-11), from outside
   CI, against each forge in turn: resolve the update manifest over HTTPS the way the shipped
   updater resolves it, download each artefact it names, check the SHA-256 and
   the byte count against the manifest, verify the minisign signature with the
   **embedded public key from the shipped binary** rather than a key on the
   release page, and verify Authenticode on the downloaded exe and MSI. Then run
   the shipped updater against the real published channel, once per forge and per
   architecture.
   Every step before this one verifies what CI built. None verifies what the
   forge serves, and the gap between them is where a correct updater meets a
   truncated upload, an asset attached to the wrong release, or a manifest whose
   URLs resolve only from inside the build network. It is the cheapest check in
   this gate and the only one that exercises the path every user takes.
6. Reproducibility procedure tested from the tag (REQ-FND-09, REQ-REL-06); release
   notes generated from the change record, security fixes separated from features
   (REQ-REL-07, REQ-UPD-13).
7. Compliance generated from repository state (REQ-CRA-10): Annex II/V/VII
   completed (REQ-CRA-09), the end-of-support date in About (REQ-CRA-08),
   vulnerability handling and the reporting runbook in place (REQ-CRA-05,
   REQ-CRA-06), the CER set with its reassessment date (REQ-CER-07).
8. Semver bumped with the reason recorded; `CHANGELOG.md`, `README.md`,
   `SECURITY.md`, `TODO.md`, `VERSION` updated in the same commit (REQ-REL-09); the
   build's cost total in the release record with its completeness flag and price
   confidence (REQ-COST-03, REQ-COST-04).

**Pass:** all of the above, and the human accepts. **Fail →** B17 for the record
files, the owning agent for a red `MUST`, back to H6 or H7 if a fix touched a
surface those gates voted on.
