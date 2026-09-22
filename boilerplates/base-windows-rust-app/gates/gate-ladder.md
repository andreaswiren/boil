# The Gate Ladder — H0 … H8

Fixed order. Per gate: entry condition, the exact checks, who runs them, the pass
criterion, where a failure loops back, whether a human is in the loop. Verdicts
land in `build/gates/<gate>/` (`verdict-schema.md`). Two criteria apply to every
gate below and are not repeated: the standing cost criterion in `README.md`, and
the rule that a check with no recorded command output is a claim, not a result.

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

**Pass:** `build/intake.md` and `build/scope.md` exist, the `OPT` has a value, the
ceiling and support date are recorded, zero waived `MUST`s. **Fail →** B00 with the
unresolved item named; a missing human answer stalls the build, never guessed.

## H1 — Design approved

**Runs:** B03 (tokens and themes), B04 (mockups), B15 (build, run, capture).
**Entry:** H0 passed. **Human:** yes, decisively — **the human names the winner.**

The gate that makes this boilerplate what it is, the one most likely to feel like
a delay, and the only one whose output every later gate is measured against.
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
the toolchain pin (REQ-FND-08). **Fail →** B16; a version that cannot be confirmed
externally is a hard fail, never a fallback to memory.

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

**Pass:** every check above green for every crate. **Fail →** the single owning agent
the failing check names — localised failure is the point of running this before H5.

## H5 — Integration

**Runs:** B14, with B15 for capture. **Entry:** H4 passed. **Human:** no.
1. `cargo build --release --locked` for `x86_64-pc-windows-msvc` **and**
   `aarch64-pc-windows-msvc` (REQ-FND-04); ASLR/DEP, CFG and a stripped build
   verified (REQ-SEC-04); one self-contained exe (REQ-FND-12).
2. **Installs on a clean Windows image.** Per-user with no elevation, machine-wide
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

**Pass:** every suite green, the screenshot set complete, the upgrade path proven.
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
   and two H7 verdicts on file, all passing.
2. Signed binaries for **both** architectures, the MSI, the SBOM, checksums, the
   signed manifest and release notes (REQ-REL-03, REQ-REL-04, REQ-INST-03), the
   signing key in no log, repository or unencrypted CI variable.
3. **The update manifest is published atomically and last**, after every artefact
   it references is retrievable (REQ-REL-10) — a manifest pointing at a missing
   artefact breaks every client at once.
4. **Both forges succeeded**, since a publish that succeeds on one and fails on the
   other fails the release (REQ-REL-01, REQ-REL-08).
5. Reproducibility procedure tested from the tag (REQ-FND-09, REQ-REL-06); release
   notes generated from the change record, security fixes separated from features
   (REQ-REL-07, REQ-UPD-13).
6. Compliance generated from repository state (REQ-CRA-10): Annex II/V/VII
   completed (REQ-CRA-09), the end-of-support date in About (REQ-CRA-08),
   vulnerability handling and the reporting runbook in place (REQ-CRA-05,
   REQ-CRA-06), the CER set with its reassessment date (REQ-CER-07).
7. Semver bumped with the reason recorded; `CHANGELOG.md`, `README.md`,
   `SECURITY.md`, `TODO.md`, `VERSION` updated in the same commit (REQ-REL-09); the
   build's cost total in the release record with its completeness flag and price
   confidence (REQ-COST-03, REQ-COST-04).

**Pass:** all of the above, and the human accepts. **Fail →** B17 for the record
files, the owning agent for a red `MUST`, back to H6 or H7 if a fix touched a
surface those gates voted on.
