# Base Windows Rust App — Requirement Register

Every requirement has a stable ID. Nothing in this boilerplate refers to a
requirement by prose alone — agents cite `REQ-xxx-nn`, gates verify by ID, and
`spec/traceability.csv` maps every ID to an owner agent and a gate.

Status: `MUST` (release-candidate blocking), `SHOULD` (blocking unless intake
waives it), `OPT` (enabled per intake answer). A `MUST` cannot be waived; the
build fails instead.

---

## FND — Foundation & toolchain

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-FND-01 | MUST | Cargo workspace even for a single binary. Crates live at `crates/<name>/`, the shipped binary at `crates/app/`. |
| REQ-FND-02 | MUST | Rust stable, pinned in `rust-toolchain.toml` so every build and every CI run uses one compiler. A floating toolchain makes a reproducibility claim untestable. |
| REQ-FND-03 | MUST | `windows` (windows-rs) is the only route to Win32 and WinRT. No hand-declared `extern "system"` blocks, no second binding crate — one binding layer or the ABI assumptions diverge. |
| REQ-FND-04 | MUST | Target `x86_64-pc-windows-msvc` and `aarch64-pc-windows-msvc`. Both are built and both are released; ARM64 is not an afterthought. |
| REQ-FND-05 | MUST | A stated minimum supported Windows version, enforced at startup with a clear message rather than a missing-entry-point crash. |
| REQ-FND-06 | MUST | `#![forbid(unsafe_op_in_unsafe_fn)]` workspace-wide, `unsafe` confined to a named FFI boundary module per crate, and every `unsafe` block carrying a comment stating the invariant it relies on. |
| REQ-FND-07 | MUST | `#![deny(warnings)]` in CI, `clippy::pedantic` reviewed, and `cargo fmt --check` enforced. |
| REQ-FND-08 | MUST | All versions come from `versions/manifest.json`, externally validated (REQ-VER-01). |
| REQ-FND-09 | MUST | Reproducible release builds: locked dependencies, `--locked`, a recorded toolchain version, and a documented procedure for rebuilding a given release from its tag. |
| REQ-FND-10 | MUST | No telemetry, no phone-home, no crash reporting to a third party, from the app or from any dependency (REQ-SBM-06). |
| REQ-FND-11 | MUST | The app runs as a normal user. `asInvoker` in the application manifest. Only the installer path elevates (REQ-INST-04). An app that always runs elevated is a defect, not a convenience. |
| REQ-FND-12 | MUST | Single self-contained executable with no runtime installer prerequisite — no VC++ redistributable step, no .NET requirement. |
| REQ-FND-13 | MUST | A `.gitignore` is present **from the first commit**, not added once the tree is already dirty with build output. It excludes build output, installer artefacts, capture output, and — the line that matters — every private signing key and certificate. `REQ-REL-04` says the signing key never enters a repository and `REQ-UPD-02`'s whole trust chain rests on the update key staying secret; without this file nothing enforces either, and a git history is not something you can un-leak. |
| REQ-FND-14 | MUST | The `.gitignore` never excludes `build/`, `mockups/`, `crates/update/keys/*.pub` or `crates/update/tests/fixtures/`. `build/` is the conformity evidence cited at the strongest tier; the mockups are the compiled styling proofs the design is checked against (`REQ-MOC-08`); the **public** keys are `include_str!`'d at compile time (`REQ-UPD-03`), so ignoring them breaks the build outright; and the negative-test fixtures are committed deliberately because `minisign-verify` cannot sign and CI cannot regenerate them. The private/public asymmetry is the trap — a blanket `keys/` rule ignores both halves. |

## DSN — Design system

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-DSN-01 | MUST | A complete design system exists and is approved **before** feature decisions are made. Colours, typography, spacing, radii, elevation, iconography, motion and state styling are all settled first. |
| REQ-DSN-02 | MUST | The design system is expressed as **code** — a token module compiled into the binary — not as a document describing intentions. A token that cannot be compiled is a suggestion. |
| REQ-DSN-03 | MUST | Full light and dark themes, both designed. Dark is not the light theme inverted, and light is not dark with the numbers flipped. |
| REQ-DSN-04 | MUST | The theme follows the Windows system preference by default, switches live when the user changes it without restarting the app, and can be overridden to a fixed light or dark in app settings. |
| REQ-DSN-05 | MUST | Fonts are named, licence-cleared, and either embedded in the binary or resolved from a documented system fallback chain. A font that is not on the target machine and not embedded is a design that ships broken. |
| REQ-DSN-06 | MUST | Every colour pair used for text or meaningful iconography meets WCAG 2.2 AA contrast in **both** themes, asserted by a test over the token table rather than checked by eye. |
| REQ-DSN-07 | MUST | Colour is never the only carrier of meaning — state is also conveyed by shape, icon or text. |
| REQ-DSN-08 | MUST | Respect the system's reduced-motion and high-contrast settings. High-contrast mode replaces the palette rather than tinting it. |
| REQ-DSN-09 | MUST | A named, versioned token set with no raw hex outside the token module. A literal colour in a view is a lint failure. |
| REQ-DSN-10 | MUST | The system covers every interactive state — rest, hover, focus-visible, active, disabled, busy, error — for every control, because the states nobody designs are the ones that look broken. |
| REQ-DSN-11 | MUST | DPI scaling correct from 100% to 250% and across monitors with different scale factors, including a window dragged between them. |

## MOC — Mockups & approval

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-MOC-01 | MUST | The first build phase produces mockups for human approval. No feature work begins before a human approves the design direction. |
| REQ-MOC-02 | MUST | **Mockups are compiled programs, not pictures.** Each is a small Rust binary that builds and runs, proving the styling is achievable in the chosen stack. A mockup that cannot be compiled has proven nothing. |
| REQ-MOC-03 | MUST | Each mockup is deliberately minimal — one screen, the token set, and enough controls to show the states of REQ-DSN-10. It is a styling proof, not a prototype of the product. |
| REQ-MOC-04 | MUST | Every mockup builds with `cargo build -p mockup-<n>` from a clean checkout, and the build is part of the gate. A mockup that only builds on the author's machine has proven nothing either. |
| REQ-MOC-05 | MUST | Each mockup runs in both light and dark and is screenshotted in both, and the screenshots are presented in the chat response to the user. |
| REQ-MOC-06 | MUST | Between three and five mockups, differentiated by **design direction** — density, typographic scale, chrome weight, accent strategy — not by accent colour alone. |
| REQ-MOC-07 | MUST | Each mockup states, in its own source header, the direction it is testing and what it gives up to get there. A direction with no stated tradeoff has not been thought through. |
| REQ-MOC-08 | MUST | The winning direction is named by a human and recorded in `build/approvals.md`. The token module is then derived from that mockup, and the mockup is kept in-tree as the reference the design is checked against. |

## UI — Application surface

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-UI-01 | MUST | A GUI framework chosen at intake with a stated default, where the design system's tokens are expressible in code (REQ-DSN-02) and dark/light are first-class. |
| REQ-UI-02 | MUST | Native window behaviour: system chrome or a correctly implemented custom title bar with working snap, maximise, restore and keyboard window commands. |
| REQ-UI-03 | MUST | Window position, size and monitor are persisted and restored, and a window restored onto a monitor that no longer exists is brought back on-screen rather than opened off-screen. |
| REQ-UI-04 | MUST | Keyboard complete. Every action reachable without a mouse, a visible focus indicator, and standard Windows accelerators honoured. |
| REQ-UI-05 | MUST | Screen-reader accessible through UI Automation, with named controls and announced state changes. |
| REQ-UI-06 | MUST | The UI thread never blocks. Every I/O and long operation is off-thread with a visible progress and cancel path. A frozen window is the most common defect class in this kind of app. |
| REQ-UI-07 | MUST | Designed empty, loading, error and offline states for every view (REQ-DSN-10). |
| REQ-UI-08 | MUST | Multi-language ready: no user-visible literal in a view, all strings from a catalogue, and locale resolved from the system with an in-app override. |
| REQ-UI-09 | MUST | Settings UI covering theme, autostart, update channel and behaviour, service mode, and diagnostics. |

## TRY — System tray

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-TRY-01 | MUST | A tray icon with a context menu, correct light/dark and high-contrast icon variants, and correct rendering at every DPI. |
| REQ-TRY-02 | MUST | The tray icon survives an Explorer restart and re-registers itself. A tray app that vanishes when Explorer crashes is the defect users report most. |
| REQ-TRY-03 | MUST | Configurable close behaviour — minimise to tray or exit — with the choice discoverable rather than surprising, and a first-time explanation of where the window went. |
| REQ-TRY-04 | MUST | The menu reflects live state (running, paused, updating, error, service mode) and offers Open, state actions, Check for updates, Settings, About and Exit. |
| REQ-TRY-05 | MUST | Tray notifications through the Windows notification system, respecting Focus Assist and the user's notification settings, and never used for content that belongs in the window. |
| REQ-TRY-06 | MUST | Single-instance: launching again focuses the running instance rather than starting a second tray icon. |
| REQ-TRY-07 | MUST | Exit from the tray is a real exit — no orphaned process, no lingering tray icon, and any service left in its declared state. |

## INST — Installer & elevation

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-INST-01 | MUST | The shipped executable can install itself: `app.exe --install` performs a complete installation with no separate installer download. |
| REQ-INST-02 | MUST | Per-user install with no elevation as the default; machine-wide install available and elevating only then. Most users do not need Program Files, and asking for administrator when it is not needed trains people to grant it when it is. |
| REQ-INST-03 | MUST | An MSI is additionally produced for enterprise deployment, supporting silent install with the same options as the CLI. |
| REQ-INST-04 | MUST | Elevation is requested at the moment it is needed via a UAC prompt from a re-launched elevated instance, with the reason stated beforehand. The app's own manifest stays `asInvoker` (REQ-FND-11). |
| REQ-INST-05 | MUST | Installation registers Add/Remove Programs entries with publisher, version, size, icon and a working uninstall command. |
| REQ-INST-06 | MUST | Uninstall is complete and honest: binaries, shortcuts, registry entries, scheduled tasks, the service and the autostart entry all removed, with an explicit prompt about whether to keep user data. |
| REQ-INST-07 | MUST | Install, upgrade-in-place, repair and uninstall are all idempotent. Running any of them twice leaves the same state as running it once. |
| REQ-INST-08 | MUST | The installer verifies its own signature and the integrity of what it writes before activating anything (REQ-SEC-02). |
| REQ-INST-09 | MUST | Install is transactional: a failure rolls back to the previous state rather than leaving a half-installed application. |
| REQ-INST-10 | MUST | Start Menu shortcut always; desktop shortcut offered, not assumed. |
| REQ-INST-11 | MUST | A silent/unattended mode (`--install --silent`) with a documented exit-code table, for deployment tooling. |
| REQ-INST-12 | MUST | Every install, upgrade, repair and uninstall writes a log to a documented location, and the log is the first thing support asks for. |

## SVC — Service & autostart

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-SVC-01 | OPT | The app can install and run as a Windows service where the intake requires one, using the same binary in a different mode. |
| REQ-SVC-02 | MUST | Service install, start, stop and uninstall are explicit commands with an exit-code contract, and a service is never installed silently as a side effect of the app install. |
| REQ-SVC-03 | MUST | The service runs under the least-privileged account that works — `LocalService` or a virtual service account by default, never `LocalSystem` unless a stated requirement forces it and the reason is recorded. |
| REQ-SVC-04 | MUST | The service responds correctly to stop, shutdown and pause/continue, and reports accurate status rather than claiming to be running while it initialises. |
| REQ-SVC-05 | MUST | The service and the interactive app are the same version and detect a mismatch rather than interoperating across versions. |
| REQ-SVC-06 | MUST | Service↔UI communication is a local IPC channel with an access-controlled endpoint. It never listens on a network socket by default, and it authenticates the caller rather than trusting local origin. |
| REQ-SVC-07 | MUST | Autostart at user login is offered, default off, and implemented through a documented mechanism whose choice is stated: per-user registry `Run` for the simple case, Task Scheduler where a delay or elevation is needed. |
| REQ-SVC-08 | MUST | The autostart entry is created for the installing user only, is removed on uninstall, and is visible to the user in settings rather than being something they discover in Task Manager. |
| REQ-SVC-09 | MUST | Autostart launches the app minimised to tray, not with a window stealing focus during login. |
| REQ-SVC-10 | MUST | Service failure recovery is configured deliberately — restart policy and backoff stated — and a crash loop is detected and reported rather than restarting forever. |

## UPD — Auto-update

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-UPD-01 | MUST | Automatic update with no user intervention required, and a manual check available. |
| REQ-UPD-02 | MUST | **Every update artefact is cryptographically signed and the signature is verified before anything is executed or swapped in.** An auto-updater without signature verification is a remote code execution channel that ships enabled. |
| REQ-UPD-03 | MUST | The signing public key is embedded in the binary. A key fetched over the network at update time is not a trust anchor. |
| REQ-UPD-04 | MUST | Update transport is HTTPS with certificate validation, and the downloaded artefact's hash is checked against the signed manifest. |
| REQ-UPD-05 | MUST | Downgrade is refused unless explicitly forced by an operator, because a forced downgrade is how a patched vulnerability is reintroduced. |
| REQ-UPD-06 | MUST | The swap is atomic and survives a mid-update failure or power loss, leaving either the old or the new version working and never a mixture. |
| REQ-UPD-07 | MUST | Update channels — stable and at least one pre-release channel — selectable in settings, with the current channel visible. |
| REQ-UPD-08 | MUST | Update checks are staggered and rate-limited so a fleet does not synchronise into a thundering herd on release day. |
| REQ-UPD-09 | MUST | A running instance is updated safely: either on next restart, or with an explicit restart prompt. An update does not kill the user's in-progress work. |
| REQ-UPD-10 | MUST | Updating a service-mode installation stops, replaces and restarts the service in the right order, and reports failure rather than leaving it stopped. |
| REQ-UPD-11 | MUST | Update failures are visible, retried with backoff, and never silent. A silent update failure is how a deployment sits unpatched for months. |
| REQ-UPD-12 | MUST | An update can be disabled or pinned by policy for managed environments, and the policy is discoverable in the UI rather than mysterious. |
| REQ-UPD-13 | MUST | Security updates are distinguishable from feature updates in the manifest, so an operator can take one without the other (REQ-CRA-07). |

## REL — Release & deployment

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-REL-01 | MUST | One release pipeline publishes to **both** GitHub and Gitea from a single tag, without a second manual process that will drift. |
| REQ-REL-02 | MUST | Gitea is a first-class target, not a mirror. Its releases API is GitHub-compatible, so the publisher differs by endpoint and credential, not by code path. |
| REQ-REL-03 | MUST | Every release carries: signed binaries for both architectures, the MSI, the SBOM, checksums, the signed update manifest, and release notes. |
| REQ-REL-04 | MUST | Release artefacts are code-signed with a real certificate; the signing key never enters a build log, a repository, or an unencrypted CI variable. |
| REQ-REL-05 | MUST | Semantic versioning, with the version derived from the tag and compiled into the binary so a running instance can state exactly what it is. |
| REQ-REL-06 | MUST | The release is reproducible from its tag, and the procedure is documented and tested (REQ-FND-09). |
| REQ-REL-07 | MUST | Release notes are generated from the change record and separate security fixes from features (REQ-UPD-13). |
| REQ-REL-08 | MUST | A failed publish to either forge fails the release. A half-published release means the update manifest and the artefacts disagree, which is worse than no release. |
| REQ-REL-09 | MUST | `CHANGELOG.md`, `README.md`, `SECURITY.md` and `TODO.md` are updated every build, and the semver is bumped with the reason recorded. |
| REQ-REL-10 | MUST | The update manifest is published atomically and last, after every artefact it references is retrievable. A manifest pointing at a missing artefact breaks every client at once. |
| REQ-REL-11 | MUST | The published release is verified from outside CI, per forge and per architecture, exactly as a client does it: resolve the manifest over HTTPS, download each artefact, check hash and size against the manifest, verify the signature with the public key embedded in the shipped binary, verify Authenticode, then run the shipped updater against the real channel. Every other check verifies what CI built, not what the forge serves. |

## SBM — SBOM & supply chain

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-SBM-01 | MUST | A CycloneDX SBOM is generated per build and published per release (REQ-CRA-03). |
| REQ-SBM-02 | MUST | The dependency list is **embedded in the shipped binary** as well as published beside it, so an artefact found on a machine can be audited without access to the release page. |
| REQ-SBM-03 | MUST | Every dependency is checked against known-vulnerability sources on every build; a critical or known-exploited advisory blocks the release. |
| REQ-SBM-04 | MUST | An independent first-party review of dependency behaviour beyond advisory matching: build scripts, `proc-macro` crates, network access at build time, `unsafe` volume, and crates whose ownership or activity pattern changed recently. |
| REQ-SBM-05 | MUST | A new dependency is a reviewed decision with a recorded justification. In a Rust binary every dependency is compiled into the product, so this is a shipping decision rather than a development convenience. |
| REQ-SBM-06 | MUST | Telemetry and phone-home are disabled and **asserted by test**, including build-time network access by any crate (REQ-FND-10). |
| REQ-SBM-07 | MUST | `cargo deny` gates licences, duplicate versions, and advisories, with the policy committed and reviewed. |
| REQ-SBM-08 | MUST | `Cargo.lock` is committed and a release builds `--locked`. An unlocked release build is not the thing that was tested. |

## CTR — Contracts & parallel-build discipline

These make the nine-wide wave possible. They are about process as much as
product, and they are `MUST` because breaking one stalls every agent at once.

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-CTR-01 | MUST | A single contract crate, `crates/contracts`, is the only cross-crate coupling. Two domain crates never depend on each other directly. |
| REQ-CTR-02 | MUST | The contract crate is frozen at gate H3 before parallel work begins. After the freeze it changes only through a Contract Change Request. |
| REQ-CTR-03 | MUST | Contract changes are additive only. A published type, field, error variant, exit code or state transition is never edited or removed in place — a new one is added and the old deprecated with a removal version. |
| REQ-CTR-04 | MUST | Every path has exactly one owning agent, declared in `contracts/ownership.md`. An agent writing outside its ownership is a build defect, not a merge conflict. |
| REQ-CTR-05 | MUST | Crates consume each other through the contract and generated fixtures, never through a running instance or a sibling crate's internals. No agent waits for another agent to finish. |
| REQ-CTR-06 | MUST | **A public enum in the contract is `#[non_exhaustive]` from the start.** Adding a variant to an exhaustive enum breaks every `match` in every other crate, so in a compiled binary "additive" is not the same thing it is in a JSON schema. This is the Rust-specific trap this register exists to record. |
| REQ-CTR-07 | MUST | `crates/ffi` is a contract member, not a convenience. It is the only crate that calls `windows-rs` (REQ-FND-03), and needing a new Win32 call is a CCR for a wrapper rather than a `use` statement. |
| REQ-CTR-08 | MUST | A state transition is a contract member. The service stop/start sequence is called through the interface its owner published, never by shelling out — a direct call cannot know the restart policy or the crash-loop detection and gets the ordering right by luck (REQ-UPD-10). |
| REQ-CTR-09 | MUST | A breaking-change detector runs on the contract crate on every commit and fails the build on a removed or narrowed member, including a newly-exhaustive enum. |
| REQ-CTR-10 | MUST | Interface tests belong to the contract, not to either side, and both the producer and the consumer run them. |

## SEC — Security

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-SEC-01 | MUST | Everything that leaves or enters the process over a network is encrypted and certificate-validated. No cleartext HTTP for updates, manifests or any other fetch. |
| REQ-SEC-02 | MUST | Signature verification on every executable artefact the app itself writes, launches or swaps in — the updater, the installer, and any helper process. |
| REQ-SEC-03 | MUST | Secrets at rest use DPAPI or the Windows credential store, never a file the app can read in cleartext, and never the registry in plaintext. |
| REQ-SEC-04 | MUST | Binary hardening enabled and verified in CI: ASLR/DEP, CFG where supported, and a stripped release build. |
| REQ-SEC-05 | MUST | Files are written only to documented per-user or per-machine locations with correct ACLs. A world-writable directory on the search path of an elevated process is a privilege-escalation primitive. |
| REQ-SEC-06 | MUST | No DLL hijacking surface: fully qualified load paths, safe search mode, and no loading from the current working directory. |
| REQ-SEC-07 | MUST | Input from every external source — update manifest, IPC message, config file, command line — is parsed defensively and treated as untrusted. |
| REQ-SEC-08 | MUST | Logs and crash output never contain secrets, tokens or personal data, and the redaction is tested rather than assumed. |
| REQ-SEC-09 | MUST | The IPC endpoint between service and UI authenticates its caller and is not reachable by other users on a shared machine (REQ-SVC-06). |
| REQ-SEC-10 | MUST | A published coordinated vulnerability disclosure policy and a single point of contact (REQ-CRA-04). |

## OBS — Logging & diagnostics

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-OBS-01 | MUST | Structured logging to a documented per-user location with rotation and a size cap, so a long-running tray app cannot fill a disk. |
| REQ-OBS-02 | MUST | A log level adjustable at runtime without a restart or a registry edit. |
| REQ-OBS-03 | MUST | An in-app diagnostics view showing version, build, install mode, service state, update channel, last check and last error — the questions support asks, answered without asking the user to find a file. |
| REQ-OBS-04 | MUST | A one-action support bundle: logs, versions and configuration with secrets redacted (REQ-SEC-08), written to a file the user chooses. |
| REQ-OBS-05 | MUST | Crashes produce a local diagnostic record. Nothing is transmitted anywhere without an explicit, per-incident user action (REQ-FND-10). |
| REQ-OBS-06 | MUST | Service-mode logging goes to the same structured log and to the Windows Event Log for the events an administrator would look for there. |

## CRA — EU Cyber Resilience Act

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-CRA-01 | MUST | Documented conformity posture against Regulation (EU) 2024/2847, Annex I Part I and Part II. This product is squarely a product with digital elements placed on the market, so CE marking and the Annex I essential requirements apply directly rather than by analogy. |
| REQ-CRA-02 | MUST | Secure-by-default configuration, documented, with a reset-to-secure-state procedure. |
| REQ-CRA-03 | MUST | A CycloneDX SBOM per build, retained per release (REQ-SBM-01). |
| REQ-CRA-04 | MUST | A coordinated vulnerability disclosure policy with a documented single point of contact, published in `SECURITY.md`. |
| REQ-CRA-05 | MUST | A vulnerability handling process: intake, triage SLA, remediation, update distribution and advisory publication. |
| REQ-CRA-06 | MUST | Reporting readiness for the obligations in force since 11 September 2026 — actively exploited vulnerabilities and severe incidents to ENISA and the national CSIRT, with the 24-hour early warning — as a rehearsed runbook with named roles. |
| REQ-CRA-07 | MUST | Security updates separable from feature updates and signed (REQ-UPD-02, REQ-UPD-13). The auto-updater is the distribution mechanism this obligation is satisfied by, which makes REQ-UPD-02 a compliance control as well as a security one. |
| REQ-CRA-08 | MUST | A declared support period with the end-of-support date stated in the documentation and visible in the app's About view. |
| REQ-CRA-09 | MUST | Annex II user information, the Annex V EU declaration of conformity and Annex VII technical documentation kept as templates completed at release. |
| REQ-CRA-10 | MUST | Compliance documentation is generated from repository state rather than written by hand, so it cannot drift from the product. |

## CER — EU Critical Entities Resilience

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-CER-01 | MUST | Documented resilience posture supporting a deploying operator's obligations under Directive (EU) 2022/2557. The product is a supplier artefact, never itself a critical entity. |
| REQ-CER-02 | MUST | A criticality and dependency assessment: which essential service the app supports, what it depends on, and what fails when each dependency fails. |
| REQ-CER-03 | MUST | Documented degraded-mode behaviour: no network, no update server, no service, expired certificate, read-only disk. A desktop app's dependencies fail differently from a server's and are more often the user's own network. |
| REQ-CER-04 | MUST | Recovery procedures with stated RTO/RPO for user data, and a tested restore whose date and result are recorded. |
| REQ-CER-05 | MUST | Incident response with named roles and escalation, aligned to the CRA reporting runbook so there is one process with two reporting outputs. |
| REQ-CER-06 | MUST | An explicit split of which controls are the product's and which are the deploying operator's, including endpoint management, patching policy and physical security. |
| REQ-CER-07 | MUST | A four-yearly reassessment cadence recorded, with the next due date in the document. |

## VER — Version currency

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-VER-01 | MUST | Latest stable releases of the toolchain and every crate. No prereleases, no release candidates, no git dependencies in a release build. |
| REQ-VER-02 | MUST | Every version validated **externally** against crates.io and the Rust release channel at build time, never from memory. |
| REQ-VER-03 | MUST | The validation result is written to `versions/manifest.json` with the source URL and the timestamp of the check. |
| REQ-VER-04 | MUST | A major-version jump is a reviewed decision with a migration note. In this stack `windows` moves fast, and a major bump can change type names across every FFI call site. |
| REQ-VER-05 | MUST | Compatibility traps are recorded rather than rediscovered — the `windows` and `windows-sys` version pairing, and any crate whose latest version raises the MSRV above the pinned toolchain. |
| REQ-VER-06 | MUST | The MSRV is stated, tested in CI, and never silently raised by a dependency bump. |

## VAL — Validation, compilation & proof of progress

A build that reports progress it has not compiled is not reporting progress.
These exist because "done" is the cheapest word an agent can write, and nothing
elsewhere in this register forces it to be earned.

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-VAL-01 | MUST | **One validation command, defined in Wave 0, used by everyone.** `cargo xtask validate` runs `fmt --check`, `clippy -D warnings`, `check --all-targets --all-features`, `test`, and the release build for every crate in the workspace. Agents, gates, CI and the human run that and nothing else. A gate that assembles its own set of checks drifts from what developers run, and the drift only shows where the gate passes a tree that does not build. |
| REQ-VAL-02 | MUST | **Every hand-off is validated by the agent that wrote it, on the tree as it stands, immediately before the report**, which carries the command, the exit code, the duration, the commit sha and the output tail. A claim of success with no command behind it is prose. |
| REQ-VAL-03 | MUST | **An unvalidated hand-off is not accepted.** The orchestrator rejects a report whose validation block is missing, non-zero or taken at a different sha, and re-dispatches. The check is mechanical — it reads the block, it does not read the diff and decide whether the work looks finished. |
| REQ-VAL-04 | MUST | **No agent states a compile, clippy, test or build result it did not obtain by running the command in this session.** A result recalled from an earlier round is stale by construction: the tree changed, which is why there was another round. Reading the code and concluding it compiles is the failure this names. |
| REQ-VAL-05 | MUST | **Every phase ends green over the whole workspace, including the phases before the product exists.** The token module compiles and its contrast tests pass at `H1`; the contract crate compiles at `H3`; the mockup binaries build and run at `H1`. A phase that produces no shippable artefact still produces a compiling one. |
| REQ-VAL-06 | MUST | **Warnings are errors**: `cargo clippy --all-targets --all-features -- -D warnings`, `cargo fmt --check`, and `#![deny(unsafe_op_in_unsafe_fn)]` workspace-wide. A warning tolerated at `H4` is a warning nobody reads at `H8`, because by then there are four hundred and the real one is among them. |
| REQ-VAL-07 | MUST | **Suppression is a waiver, not a tactic.** Every `#[allow(...)]`, `#[ignore]`, `unsafe` block and `expect()` on a fallible path carries the REQ ID it trades against and a removal condition. Counts are reported at every gate and **a count that rose since the previous gate is a finding** — for `unsafe` and `#[allow(clippy::...)]` especially, since widening an allow is the fastest way to turn a red tree green. |
| REQ-VAL-08 | MUST | **The validated tree, the captured tree and the reviewed tree are one tree.** Every validation record, every screenshot sidecar (REQ-CAP-03) and every gate verdict names one commit sha (REQ-GAT-09). Evidence collected across a moving tree certifies a state that never existed. |
| REQ-VAL-09 | MUST | **Integration is validated against the real thing.** The Windows integration points are exercised against a real Windows session — a real service control manager, a real tray in a real Explorer, a real MSI on a clean image (REQ-TST-02). A mocked `winapi` call proves the code calls something, which is never the claim being made. |
| REQ-VAL-10 | MUST | **A debug build of the current tree is always runnable and always current**, rebuilt as work lands, so the human can launch what exists at any moment rather than waiting for a gate. A failing validation leaves the last green binary in place and says so, naming the failing command and the owning agent. |
| REQ-VAL-11 | MUST | **A red shared tree stops dispatch.** When `crates/contracts`, the workspace `Cargo.toml`, the lockfile or the token module goes red, no new task is dispatched into that wave until it is green — concurrent agents building on a base that does not compile produce hand-offs that all have to be redone, and the first to notice is always the gate. |
| REQ-VAL-12 | MUST | **The validation history is kept, not summarised**: `build/validation/<wave>/<agent>.json` per hand-off and `build/validation/<gate>.json` per gate, each with command, exit code, counts, duration, sha and output tail. A summary of validation history is a claim about validation history. |
| REQ-VAL-13 | MUST | **Generated artefacts are regenerated and diffed, never trusted**: the traceability matrix, the SBOM, the WiX fragment lists and any generated binding. A non-empty `git diff` after regeneration fails validation, because a generated file edited by hand is a fork of its source that nothing will reconcile. |
| REQ-VAL-14 | MUST | **Validation covers the shipped artefact, not only the source**: the MSI builds, installs on a clean image, upgrades from the previous released version, and the installed binary launches (REQ-INST-01, REQ-TST-02). A workspace that compiles and an installer that works are two different claims, and only one of them is what a user meets. |

## CAP — Continuous visual capture

Screenshots here are a **feed**, not a deliverable produced at `H1` and again at
`H5`. Two capture sets in a build that runs for hours leave everything between
them unobserved.

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-CAP-01 | MUST | **Capture is continuous.** Every UI-touching hand-off, every wave boundary and every gate produces a set — not only at a gate, never only on failure. A view nobody has looked at since the wave it was written in is a view nobody has looked at. (Supersedes the timing half of REQ-TST-04.) |
| REQ-CAP-02 | MUST | **A stable path convention**, so two captures of the same view sort next to each other and a regression is visible by scrolling: `build/screenshots/<wave>/<view>__<dpi>__<theme>__<sha>.png`. View names come from the view registry, never invented per run. |
| REQ-CAP-03 | MUST | **Every image has a sidecar** `.json`: view, state (empty / loading / error / offline / ready), theme, DPI scale, monitor configuration, commit sha, timestamp, the REQ IDs the view serves, the capture mechanism used (in-process or `PrintWindow`), and any log line at `warn` or above emitted during the capture. An image that cannot be tied to a tree is a picture, not evidence. |
| REQ-CAP-04 | MUST | **The feed is delivered both ways, every time**: the images presented in the chat reply (REQ-TST-04) **and** written to `build/screenshots/` with an index. The reply is immediate and scrolls away; the folder persists and nobody watches it unprompted. Dropping either loses one of those. |
| REQ-CAP-05 | MUST | **`build/screenshots/index.md` is generated and current**: newest first, grouped by view, each image beside its sidecar and beside the previous capture of the same view and state. A desktop app has no URL to serve the feed from, so the index is the artefact that makes the history scrollable. |
| REQ-CAP-06 | MUST | **Captures come from a built binary of the tree under review** (REQ-VAL-10), at a named sha — never from a hand-drawn mockup, never from a stale build left over from a previous wave, and the sidecar records which binary produced them. |
| REQ-CAP-07 | MUST | **A capture carries its log.** Any `warn` or `error` emitted while a view was captured is recorded with the image, and **a view captured with an error is reported as failing** rather than presented as a screenshot that happens to look right. A view whose data load failed and whose error state renders tidily photographs as a working feature. |
| REQ-CAP-08 | MUST | **Every set covers both themes and the DPI ladder** — light and dark for every view (REQ-DSN-06), high contrast as its own variant (REQ-DSN-08), and 100 / 150 / 200 / 250% for every gate set (REQ-TST-08). One capture at 100% in light is the configuration most likely to have been looked at during development and therefore least informative. |
| REQ-CAP-09 | MUST | **Capture states, not screens**: all five view states per view — empty, loading, error, offline, ready (REQ-UI-07) — plus the tray menu in each of its states (REQ-TRY-01). A view's ready state alone proves it renders and nothing about what it does when the thing it renders is missing. |
| REQ-CAP-10 | MUST | **A gate does not pass on a stale capture.** Every view the gate covers has a capture at the sha under review (REQ-VAL-08). Capture never blocks a wave — it runs alongside — and it always blocks a gate, because that is when the evidence is relied on. |
| REQ-CAP-11 | MUST | **What cannot be captured is stated, never silently skipped.** Desktop capture needs an interactive session; an agent in session 0 has none, and the honest report is which captures were taken in-process, which were skipped, and what therefore remains unverified — not a set that looks complete because the impossible ones were dropped. |

## TST — Testing & verification

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-TST-01 | MUST | Unit tests on logic, integration tests on the Windows integration points, and end-to-end tests on install, update and uninstall. |
| REQ-TST-02 | MUST | Install, upgrade, repair and uninstall are tested on a clean Windows image, including the upgrade path from the previous released version. Testing only a fresh install tests the case users encounter once. |
| REQ-TST-03 | MUST | The updater is tested against a real signed manifest, including the negative cases: wrong signature, tampered artefact, downgrade attempt, and interrupted swap. The negatives are the point. |
| REQ-TST-04 | MUST | Screenshots at each mockup and each UI change, in both themes, presented in the chat response to the user. **Extended by REQ-CAP-01 and REQ-CAP-04**: the reply is one of three required delivery points, and capture runs continuously rather than per change. |
| REQ-TST-05 | MUST | Design-token tests: contrast in both themes (REQ-DSN-06) and no raw colour literal outside the token module (REQ-DSN-09). |
| REQ-TST-06 | MUST | Tray behaviour tested including Explorer restart (REQ-TRY-02) and single-instance (REQ-TRY-06). |
| REQ-TST-07 | MUST | Service lifecycle tested: install, start, stop, uninstall, crash recovery and version mismatch. |
| REQ-TST-08 | MUST | DPI tested at 100%, 150%, 200% and 250%, including a window moved between monitors with different scale factors. |
| REQ-TST-09 | MUST | Accessibility verified with a real screen reader over the primary flows, not only by inspecting properties. |
| REQ-TST-10 | MUST | **A feature is not done until a test fails without it.** The owning agent records both runs — red before the change, green after — in its validation block. A test written afterwards against code that already passes it asserts that code's present behaviour, which is a different claim from the requirement it cites. |
| REQ-TST-11 | MUST | **Tests land in the same task as the behaviour, never in a later cleanup.** Each agent writes the tests for its own crate as it writes it; `B14` owns the fixtures, the cross-crate harness and the install/update/uninstall journeys. There is no phase in this build where testing catches up, because that is the phase that gets cut. |
| REQ-TST-12 | MUST | **Every `MUST` maps to a test, or to a named reason it cannot be tested**, in `build/validation/req-coverage.md`, generated from the register and the suites. At `H8` a `MUST` with neither fails the gate. An untested `MUST` is an unverified claim wearing the word MUST. |
| REQ-TST-13 | MUST | **No test is `#[ignore]`d, cfg'd out or commented to reach green.** The ignored count is reported at every gate and non-zero is a finding naming each test. `cargo test` prints `N ignored` and nobody reads it, which is what makes it the cheapest way to pass a gate. |
| REQ-TST-14 | MUST | **The suite runs every wave**, not only at `H4` and `H5`: the crate's own tests on every hand-off, the whole workspace at every wave boundary. A regression found three waves after it landed costs the three waves built on top of it. |
| REQ-TST-15 | MUST | **A flaky test is a defect with an owner** — investigated and fixed, not re-run until green. Quarantine is once, dated, owner named, and it blocks `H8`. On Windows the usual cause is a genuine race against the service control manager or the shell, which is exactly the class of bug that reaches users. |
| REQ-TST-16 | MUST | **Test output is kept as evidence**, not paraphrased: `build/validation/<wave>/<agent>/test-output.txt` with `cargo test`'s own passed/failed/ignored counts. A sentence claiming the suite passed and the suite passing are indistinguishable in a report. |
| REQ-TST-17 | MUST | **The trust-chain negatives run at every gate from `H4` onward**, not once at `H5`: wrong signature, tampered artefact, downgrade attempt, interrupted swap (REQ-TST-03), plus elevation boundary and IPC authentication. These fail silently — an updater that stopped verifying signatures updates faster and looks identical. |

## GAT — Quality gates

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-GAT-01 | MUST | Two harsh critique agents must both approve the design and the functions. Either rejection loops the work back with named defects. |
| REQ-GAT-02 | MUST | Two independent security expert agents review the code without seeing each other's findings before submitting. |
| REQ-GAT-03 | MUST | For a larger change, each security reviewer first states a review plan covering common best practice, the FFI and `unsafe` surface, elevation and privilege boundaries, the update trust chain, and IPC — then executes it. |
| REQ-GAT-04 | MUST | Verdicts are structured and per-REQ. "Looks good" is not a verdict. |
| REQ-GAT-05 | MUST | Three failed rounds on the same defect escalate to the human with the disagreement stated, rather than looping forever. |
| REQ-GAT-06 | MUST | Karpathy guidelines applied as a standing review lens: no overcomplication, surgical changes, surfaced assumptions, verifiable success criteria. |
| REQ-GAT-07 | MUST | No gate is self-approved. The agent that wrote the code never votes on it. |
| REQ-GAT-08 | MUST | The design gate is blocking and comes first: no feature work begins before the design system is approved (REQ-MOC-01, REQ-DSN-01). |
| REQ-GAT-09 | MUST | The verdicts that release a build must all name the same commit. Six passing verdicts spread across three commits certify a tree no reviewer saw, and whatever landed between them is unreviewed. |

## COST — Token accounting

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-COST-01 | MUST | Every agent's hand-off reports its token usage: input, output, cache-read and cache-write, plus the model and effort it ran at. |
| REQ-COST-02 | MUST | The orchestrator maintains a running cost table and presents it at every gate, not at the end. |
| REQ-COST-03 | MUST | Measured token counts and derived money are never conflated; every money figure cites the unit price it used and that price's confidence. |
| REQ-COST-04 | MUST | Where the runtime does not report usage, the cell reads `unreported` and the total is marked incomplete. `null` is not `0`. |
| REQ-COST-05 | MUST | Rework is attributed to the finding that caused it, so the cost of a defect is visible. |

## PORT — Runtime portability

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-PORT-01 | MUST | The prompt structure runs on more than one agent runtime. Claude Code is the reference implementation, not a dependency. |
| REQ-PORT-02 | MUST | Portability is a capability map: what the structure needs a runtime to do, not which product provides it. |
| REQ-PORT-03 | MUST | Where a target runtime cannot satisfy a capability, the adapter names the requirements that become unverifiable. |
| REQ-PORT-04 | MUST | Telemetry is disabled in the agent runtime as well as in the product (REQ-FND-10). |
