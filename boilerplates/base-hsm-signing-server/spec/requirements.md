# base-hsm-signing-server — Requirement Register

Every requirement has a stable ID. Nothing in this boilerplate refers to a
requirement by prose alone — agents cite `SZ-<DOMAIN>-<nnn>`, gates verify by ID,
and `spec/traceability.csv` maps every ID to an owner and a gate.

**The ID prefix here is `SZ-`, not `REQ-`.** It arrived that way and it is
load-bearing across 161 documents, so renaming it would mean rewriting every
citation to gain nothing — which is the dangling-citation failure the convention
exists to prevent. `CONVENTIONS.md` §3 requires IDs that are stable and never
renumbered; it does not require one spelling, and the conformance check derives
the prefix from this file rather than assuming one.

Status: `MUST` (release-candidate blocking), `SHOULD` (blocking unless intake
waives it), `OPT` (enabled per intake answer). A `MUST` cannot be waived; the
build fails instead.

**This file is the only register.** It previously coexisted with a
`spec/requirements.md` holding a second copy and with two "source" documents that
contained nothing but pointers to it. The YAML had already drifted — 37 entries
against this file's 59 — which is what a duplicated source of truth always does,
so it was removed rather than resynchronised. The machine-readable artefact is
`spec/traceability.csv`, and that one is *generated* from this file and
drift-checked, which is the difference that matters.

---


## LIV — The live instance

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-LIV-001 | MUST | **A live instance runs before the first agent produces anything visible, and stays up for the whole build.** Started at the beginning, not when the UI is ready, and never torn down between phases. From the first moment the URL serves a **build status page** — current phase, each agent's state, what is waiting on a human — progressively replaced by the appliance's own surface as it comes to exist. A build the human can only follow by reading agent reports is a build they cannot follow. |
| SZ-LIV-002 | MUST | **The URL and the test logins are told to the human in the reply**, when the instance first comes up and again at every phase boundary — not written to a file they must find, and not stated once at the start of a build that runs for hours. In full: the address, each seeded account, its role and its password. |
| SZ-LIV-003 | MUST | **The same instance is used for development, debugging and screenshot capture.** No agent starts a second, ephemeral server. A freshly started process with empty caches and no accumulated state is the one configuration no operator ever meets, so it hides exactly the defects that appear after an hour of use — and a screenshot from a different process is not evidence about what the human looked at. |
| SZ-LIV-004 | MUST | The instance is checked continuously, restarted when it dies, and **a build whose live instance is down is reported down** rather than continuing silently. The human watching the URL must not be the mechanism that discovers it died. |
| SZ-LIV-005 | MUST | **The development instance never holds real key material.** It runs against a software PKCS#11 token or an HSM emulator, never a production Nitrokey HSM 2, and never a production DKEK (`spec/14-testing.md` §4). A development appliance wired to a real signing key is a signing oracle with seeded logins and a URL. |
| SZ-LIV-006 | MUST | **Seeded test credentials exist only in a non-production build**, gated on an explicit build flag, and a production build containing any seeded account **fails the release gate**. On a signing appliance a standing credential with a known address is not a tidiness problem: it is authorization to sign. The control is mechanical, never a habit of deleting them later — that habit fails exactly once. |


## VAL — Validation, compilation & proof of progress

A build that reports progress it has not compiled is not reporting progress.
These exist because "done" is the cheapest word an agent can write, and nothing
elsewhere in this register forces it to be earned.

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-VAL-001 | MUST | **One validation command, defined before the first phase, used by everyone.** `make validate` runs the Rust workspace (`fmt --check`, `clippy -D warnings`, `check --all-targets`, `test`), the web workspace (typecheck, lint at zero warnings, unit tests, production build), the SQL migration lint and the OpenAPI lint. Agents, gates, CI and the human run that and nothing else. A gate assembling its own set of checks drifts from what developers run, and the drift only shows where the gate passes a tree that does not build. |
| SZ-VAL-002 | MUST | **Every hand-off is validated by the agent that wrote it, on the tree as it stands, immediately before the report**, which carries the command, the exit code, the duration, the commit sha and the output tail. A claim of success with no command behind it is prose. |
| SZ-VAL-003 | MUST | **An unvalidated hand-off is not accepted.** The orchestrator rejects a report whose validation block is missing, non-zero, taken at a different sha, or carrying skipped tests, and re-dispatches. The check is mechanical — it reads the block, it does not read the diff and decide whether the work looks finished. |
| SZ-VAL-004 | MUST | **No agent states a compile, lint, test or build result it did not obtain by running the command in this session.** A result recalled from an earlier round is stale by construction: the tree changed, which is why there was another round. Reading the code and concluding it compiles is the failure this names. |
| SZ-VAL-005 | MUST | **Every phase ends green over the whole tree, including the phases before the appliance exists.** The contract crate and the OpenAPI document validate at the contract freeze; the web workspace builds before any UI review; the migration set applies to an empty database. A phase that produces no installable artefact still produces a compiling one. |
| SZ-VAL-006 | MUST | **Warnings are errors**: `cargo clippy --all-targets --all-features -- -D warnings`, `cargo fmt --check`, TypeScript `strict` with zero errors, ESLint at `--max-warnings=0`. A warning tolerated at the first phase gate is a warning nobody reads at release, because by then there are four hundred and the one that mattered is among them. |
| SZ-VAL-007 | MUST | **Suppression is a waiver, not a tactic.** Every `#[allow(...)]`, `@ts-expect-error`, `eslint-disable`, `#[ignore]`, `unsafe` block and `.unwrap()` on a fallible path in daemon code carries the `SZ-*` ID it trades against and a removal condition. Counts are reported at every phase gate and **a rise is a finding** — on this appliance a widened `#[allow]` or a new `unsafe` block sits inside the signing boundary, and it is also the ordinary way a red tree becomes green. |
| SZ-VAL-008 | MUST | **The validated tree, the captured tree and the reviewed tree are one tree.** Every validation record, every screenshot sidecar (SZ-CAP-003) and every review verdict names one commit sha. A phase gate whose evidence spans more than one does not pass: `security-reviewer` cleared commit A, `adversarial-reviewer` cleared commit C, and whatever landed between them has no reviewer. |
| SZ-VAL-009 | MUST | **Integration is validated against the real dependency**: a real PostgreSQL with the real migrations and the real roles, a real browser for the approval flows, the real `signerd` over its real IPC transport, and a real PKCS#11 module — the software token in CI (SZ-TEST-006), the Nitrokey HSM 2 before a release. A mocked PKCS#11 call proves the code called something, which is never the claim. |
| SZ-VAL-010 | MUST | **The live instance is rebuilt from the validated tree and never left broken** (SZ-LIV-001). A failing validation rolls it back to the last green build and the status page says so, naming the failing command and the owning agent. A URL serving a broken appliance teaches the human to stop looking at the URL, which costs more than the failure did. |
| SZ-VAL-011 | MUST | **A red shared tree stops dispatch.** When the contract crate, the OpenAPI document, the migration set or the workspace manifest goes red, no new task is dispatched into that phase until it is green — concurrent agents building on a base that does not compile produce hand-offs that all have to be redone, and the first to notice is always the gate. |
| SZ-VAL-012 | MUST | **The validation history is kept, not summarised**: `build/validation/<phase>/<agent>.json` per hand-off and `build/validation/<gate>.json` per gate, each with command, exit code, counts, duration, sha and output tail. A summary of validation history is a claim about validation history. |
| SZ-VAL-013 | MUST | **Generated artefacts are regenerated and diffed, never trusted**: the traceability matrix, the typed API client, the SBOM and the OpenAPI-derived types. A non-empty `git diff` after regeneration fails validation, because a generated file edited by hand is a fork of its source that nothing will ever reconcile. |
| SZ-VAL-014 | MUST | **Validation covers the shipped artefact, not only the source**: the installer builds, installs on a clean Debian 13 image, the services start, the setup wizard reaches its first screen over HTTPS, and the appliance reports `Unprovisioned` (SZ-INS-001, SZ-OS-010). A workspace that compiles and an appliance that boots are two different claims, and the operator only ever meets one of them. |


## TEST — Testing as evidence

`spec/14-testing.md` holds the reasoning. These are its IDs, so that a gate can
verify it and an agent can cite it — a testing document nothing in the register
points at is a document, not a control.

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-TEST-001 | MUST | **Every `MUST` in this register maps to at least one citing test, or to a named reason it cannot be tested automatically plus the manual procedure that covers it.** The report is generated, and a `MUST` with neither fails the build. A requirement without a test is an intention (`spec/14-testing.md` §1). |
| SZ-TEST-002 | MUST | **A feature is not done until a test fails without it.** The owning agent records the run that failed before the change and the run that passed after, both with their shas. A test written afterwards against code that already passes it asserts that code's present behaviour, which is a different claim from the requirement it cites. |
| SZ-TEST-003 | MUST | **Tests land in the same task as the behaviour**, never in a later cleanup phase — rule 17 of the operating rules, made checkable. The phase that would catch up on testing is the first one cut when a phase runs long, and it is cut by an orchestrator that has already reported the features done. |
| SZ-TEST-004 | MUST | **The negative suite is the suite** (`spec/14-testing.md` §3), and it runs on every commit, not at a release gate: digest mismatch, wrong repository claim, approval bound to another artefact, self-approval, expired approval, push without transaction proof, a `Metrics` credential elsewhere, a `Backup` credential decrypting a backup, an out-of-profile mechanism, a wrong-state operation returning `412` with both states named, rate limits at their stated numbers per address and per username, a timestamp-authority outage, an `UPDATE` on `audit_events`, and an edited audit chain. For a signing appliance most of the value is in what it refuses. |
| SZ-TEST-005 | MUST | **Every security finding gets a test that fails on the unfixed code before the fix lands**, citing the finding (`spec/14-testing.md` §6). It is the only mechanism that stops a fixed vulnerability returning during a refactor two years later, and it is cheap exactly once — while the finding is still understood. |
| SZ-TEST-006 | MUST | **HSM-dependent tests run in two modes** (SZ-HSM-001): software by default against an emulator or software PKCS#11 token so the whole suite runs in CI, and real-HSM explicitly tagged before a release. **What software mode cannot prove is written down** — DKEK ceremonies, Key Check Value comparison across two physical devices, PIN retry counters, reader enumeration — and a release that has not run those says so rather than implying the suite passed. |
| SZ-TEST-007 | MUST | **An environment-dependent test reports `unverified`, never green and never silently skipped.** TPM sealing, verity, unseal and firewall tests need a real or virtualised appliance; when it is absent the REQ IDs they cover are reported unverified. A skipped test that reports green is worse than a missing test, because the missing one is visible. |
| SZ-TEST-008 | MUST | **No test is skipped, `#[ignore]`d, `.only`-scoped or cfg'd out to reach green.** Counts are reported at every phase gate and non-zero is a finding naming each test. On this appliance the test most likely to be disabled for being inconvenient is a negative test, and **a disabled negative test is a removed control** (`spec/14-testing.md` §5). |
| SZ-TEST-009 | MUST | **A flaky test is a defect with an owner**, investigated and fixed rather than re-run until green. Quarantine is once, dated, owner named — and **a quarantined negative test blocks the release**. Flakiness here is a security problem precisely because the remedy people reach for is disabling the test. |
| SZ-TEST-010 | MUST | **Determinism is constructed, not hoped for** (`spec/14-testing.md` §5): time is injected and never read from the clock, so expiry tests are exact; entropy is seeded and the seed is logged; the updater's negative fixtures — wrong key, mutated signature, tampered artefact — are generated out of band and committed, because the verifying tools cannot produce them in CI. |
| SZ-TEST-011 | MUST | **Line coverage is reported and is not a gate; requirement coverage is** (`spec/14-testing.md` §7). A signing appliance at 95% line coverage with no negative test for approval replay is not tested, and the number invites the conclusion that it is. |
| SZ-TEST-012 | MUST | **The suite is tested by breaking what it guards**: a deliberately disabled control — a removed digest re-check, a bypassed approval binding — must fail the suite, and that mutation is run at every phase gate. A suite nobody has ever seen fail is a suite nobody has evidence about. |
| SZ-TEST-013 | MUST | **Test output is kept as evidence, not paraphrased**: `build/validation/<phase>/<agent>/test-output.txt` with the runner's own passed/failed/skipped counts. A sentence claiming the suite passed and the suite passing are indistinguishable in a report. |


## CAP — Continuous visual capture

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-CAP-001 | MUST | **Capture is continuous**: every UI-touching hand-off, every phase boundary and every gate produces a set, from the live instance (SZ-LIV-003) — not once at a design review and again at release, which leaves everything between unobserved. |
| SZ-CAP-002 | MUST | **A stable path convention**, so two captures of the same surface sort next to each other and a regression is visible by scrolling: `build/screenshots/<phase>/<surface>__<viewport>__<theme>__<sha>.png`. Surface names come from the route, never invented per run. |
| SZ-CAP-003 | MUST | **Every image has a sidecar** `.json`: URL, viewport, theme, commit sha, timestamp, the appliance state the surface was in (`Unprovisioned` / `Locked` / `Operational` / `Failed`), the `SZ-*` IDs it serves, the interaction that preceded it, and the console and network errors observed. An image that cannot be tied to a tree and a state is a picture, not evidence. |
| SZ-CAP-004 | MUST | **The feed is delivered both ways, every time**: images in the chat reply **and** written to `build/screenshots/`, with the feed served at `/_build/screenshots` on the live instance. The reply is immediate and scrolls away; the folder persists and nobody watches it unprompted. |
| SZ-CAP-005 | MUST | **Capture the appliance's states, not only its screens.** A surface that behaves differently per appliance state is captured in each state it supports, and the wrong-state refusal is captured too — `412` with both states named is a user-visible behaviour (SZ-API-004) and it is the one nobody looks at. The approval flow is captured on the PWA viewport as well as desktop. |
| SZ-CAP-006 | MUST | **A capture carries its console**, and a surface captured with a page error or a failed request is **reported as failing** rather than presented as a screenshot that happens to look right. A page whose fetch fails and whose error boundary renders tidily photographs as a working feature. |
| SZ-CAP-007 | MUST | **Captures never contain real secrets.** The development instance holds no real key material (SZ-LIV-005), and a capture is additionally checked for a PIN, a share, a recovery code, a session token or a live QR enrolment payload before it is written — screenshots are committed, and a screenshot is a durable, greppable copy of whatever was on screen. |
| SZ-CAP-008 | MUST | **A gate does not pass on a stale capture**: every surface the gate covers has a capture at the sha under review (SZ-VAL-008). Capture never blocks a phase — it runs alongside — and it always blocks a gate, because that is when the evidence is relied on. |

## FUN — Product & functional surface

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-FUN-001 | MUST | The system shall provide user and administrator dashboards for signing activity and appliance health. |
| SZ-FUN-002 | MUST | Signing requests shall follow an explicit server-side state machine. |


## SEC — Security posture

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-SEC-001 | MUST | Production private signing keys shall remain non-exportable except encrypted DKEK-wrapped backup where supported and explicitly configured. |
| SZ-SEC-002 | MUST | The Next.js web process shall run unprivileged and shall not execute arbitrary OS commands or access HSM device nodes directly. |
| SZ-SEC-003 | MUST | No generic remote shell, command execution API, or raw network HSM/PKCS#11 interface shall be exposed. |
| SZ-SEC-004 | MUST | Security-sensitive operations shall fail closed and require explicit authorization. |
| SZ-SEC-005 | MUST | Secrets shall never be stored in logs, audit payloads, command-line arguments, URLs, browser storage, source control, or telemetry. |
| SZ-SEC-006 | MUST | Failed-authentication rate limits are stated as numbers, not as the word "rate limiting": **one failed unlock attempt per second per source address**, and **one failed authentication per second per source address and username** (NetHSM's figures, `docs/system-design.md` §Rate Limiting). A limit without a number cannot be tested, and an untested limit is an assumption. |
| SZ-SEC-007 | MUST | The web surface enforces a strict Content Security Policy — per-request nonces, no `unsafe-inline`, no `unsafe-eval` — and the application works without them rather than needing an exception. The approval screen is where a human decides what gets signed, so a script injected into that page can lie about what is being approved; WebAuthn step-up narrows this because the assertion binds to a challenge derived from the request, but the CSP is what stops the injection. No secret reaches the client bundle, asserted by scanning the built output rather than by convention. |
| SZ-SEC-011 | MUST | The appliance **refuses to become operational without its entropy sources**. On first provisioning, the Device Key is not generated until the TPM RNG and the kernel CSPRNG have both been confirmed healthy; if a source required at boot is absent, the system logs to the console and stops in a non-operational state rather than proceeding with degraded entropy. NetHSM halts rather than generating a key it cannot vouch for, and a signing key generated from weak entropy is unrecoverable — it must be rotated, and everything it signed re-examined. |


## HSM — Nitrokey HSM 2, PKCS#11 and DKEK

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-HSM-001 | MUST | Nitrokey HSM 2 shall be supported through OpenSC/PCSC/PKCS#11 on Debian 13. |
| SZ-HSM-002 | MUST | The system shall support a designated primary and secondary/DR Nitrokey HSM 2. |
| SZ-HSM-003 | MUST | DKEK shall be configured before exportable production keys are generated. |
| SZ-HSM-004 | MUST | DKEK share ceremonies, wrapped-key export/import, and DR restore verification shall be supported without persisting plaintext shares. |
| SZ-HSM-005 | MUST | HSM devices shall be identified by stable identity/serial rather than enumeration order. |
| SZ-HSM-006 | MUST | The appliance has four explicit states — `Unprovisioned`, `Locked`, `Operational`, `Failed` — and the state is a first-class value in the API, the DCUI and the audit log, not an inference from whether requests succeed. |
| SZ-HSM-007 | MUST | **A provisioned appliance boots Locked.** The application, audit and key-metadata stores are encrypted at rest under a *Domain Key* that exists only in memory and is never written to disk unencrypted. A disk removed from the appliance yields ciphertext. This is the control that makes the difference between an appliance and a server with an HSM in it. |
| SZ-HSM-008 | MUST | The Domain Key is recovered at boot from a TPM-sealed *Device Key* using two slots: slot 1 holds it wrapped to the Device Key alone (**unattended boot**), slot 0 wrapped to an *Unlock Key* which is itself wrapped to the Device Key (**attended boot**). Enabling unattended boot populates slot 1; disabling it overwrites slot 1. A failed unattended decryption **falls back to attended**, never to open. Neither the Unlock Passphrase nor the derived Unlock Key is ever persisted. |
| SZ-HSM-009 | MUST | `POST /unlock` and `POST /lock` are API operations. `lock` returns the appliance to ciphertext without a reboot, so an operator who suspects compromise has an action available that does not require physical access. |
| SZ-HSM-010 | MUST | The Device Key is sealed by the TPM against firmware measurements, so it does not unseal under modified firmware and a disk image is not portable to different hardware. Where no TPM is present the appliance starts in attended mode only and states that unattended boot is unavailable — it does not silently fall back to an unsealed key on disk. |
| SZ-HSM-011 | MUST | Backups are **double-encrypted and the backup role cannot read them**. An administrator sets a Backup Passphrase; the backup endpoint does not exist until they have. The outer layer is the derived Backup Key; the inner layers are the already-encrypted stores. Reading a backup requires **both** the Backup Key and an Unlock Key, so an automated client holding only backup credentials can fetch backups indefinitely and decrypt none of them. |
| SZ-HSM-012 | MUST | Restore behaviour is specified and its destructiveness is stated before it runs. Restoring into an operational appliance is a **partial restore**: users, keys and namespaces present on the device and absent from the backup are **removed**, and device-local configuration (network, TLS) is not touched. Restoring to different hardware requires the Unlock Passphrase current when the backup was taken. A backup taken by any previous version must remain restorable. |


## AUTH — Identity, step-up and RBAC

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-AUTH-001 | MUST | Local production users shall use password+TOTP or passkey; password-only login is prohibited. |
| SZ-AUTH-002 | MUST | Microsoft Entra ID OIDC login shall be supported using stable tenant+subject identities. |
| SZ-AUTH-003 | MUST | Sensitive actions shall require recent step-up authentication. |
| SZ-AUTH-004 | MUST | CI automation shall prefer workload OIDC, then mTLS, then narrowly scoped service credentials. |
| SZ-AUTH-005 | MUST | Tag-based key restriction is enforced **at the key**, independently of the policy engine: a key carries tags, a user carries tags, and use requires a match. Two independent authorization axes mean a policy-engine mistake does not by itself unlock every key. |
| SZ-AUTH-006 | SHOULD | Namespaces separate users and keys inside one appliance, so two teams can share a device without sharing a key store. Blocking unless intake states the appliance is single-tenant. |
| SZ-AUTH-007 | MUST | The role set is explicit and each role's power is stated: `Administrator`, `Operator`, `Metrics`, `Backup`. A role that is not in this list does not exist, and "admin" is not a synonym for "can read key material". |


## API — REST signing API and clients

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-API-001 | MUST | A versioned REST API with OpenAPI documentation shall support signing request submission, approval state, retrieval and verification. |
| SZ-API-002 | MUST | API signing requests shall bind repository/ref/build identity, artifact digest, profile and requester identity. |
| SZ-API-003 | MUST | The optional remote PKCS#11 compatibility client shall be policy constrained and shall not expose arbitrary HSM mechanisms or objects. |
| SZ-API-004 | MUST | REST mutating operations shall support idempotency keys where replay could duplicate effects. |
| SZ-API-005 | MUST | `GET /health/alive`, `/health/ready`, `/health/state` and `/health/diagnose` exist, and `state` is readable **without authentication**. A client that cannot distinguish "locked" from "broken" retries against a locked appliance forever, and the operator sees an outage instead of a prompt. |
| SZ-API-006 | MUST | `GET /metrics` is served to a dedicated `Metrics` role whose only power is reading counters. Monitoring never holds an operator credential; a standing privilege granted for graphing is a standing privilege. |
| SZ-API-007 | MUST | The key-object certificate lifecycle is on the API, not a manual procedure: retrieve the public key, generate a CSR for a key that never leaves the HSM, and store, retrieve and delete the issued certificate against that key. A signing appliance whose CSR step happens by hand is an appliance whose CSR step is eventually done wrong. |


## PWA — Approval app

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-PWA-001 | MUST | The web app shall be installable as a PWA and support Web Push signing approval notifications. |
| SZ-PWA-002 | MUST | Push notifications alone shall never authorize signing; approval shall use a transaction-bound challenge code and/or WebAuthn step-up. |
| SZ-PWA-003 | MUST | Approval UI shall show artifact name/digest suffix, requester, repository/ref, signing profile and expiry before acceptance. |


## AUD — Audit and tamper evidence

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-AUD-001 | MUST | Security and signing actions shall create canonical append-only audit events with tamper-evident chaining/checkpoints. |
| SZ-AUD-002 | MUST | Audit events shall be exportable and optionally forwarded to remote syslog/SIEM. |


## OS — Linux appliance and OS control

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-OS-001 | MUST | A privileged Rust OS daemon shall expose only typed allowlisted appliance operations over a Unix socket. |
| SZ-OS-002 | MUST | Network/firewall management changes shall be transactional with automatic rollback unless confirmed. |
| SZ-OS-003 | MUST | SSH shall be disabled by default and normal administration shall be possible from structured web controls. |
| SZ-OS-004 | MUST | A persistent fullscreen local DCUI shall run on tty1. |
| SZ-OS-005 | MUST | Local maintenance console access shall require a separate physical-console maintenance credential with rate limiting and auto-relock. |
| SZ-OS-006 | MUST | System updates are A/B with a **separate commit step**: the image is written to the inactive root while its signature and downgrade eligibility are verified, and the commit operation is only available once both have passed. Commit arms a one-shot boot; a failure to boot falls back to the previous root automatically. Downgrades that would migrate data backwards are refused. Updates are applied deliberately by an administrator — there is no over-the-air update path. |
| SZ-OS-007 | MUST | Factory reset is a defined, audited operation that destroys the Device Key and every encrypted store, so decommissioning is a procedure rather than an improvisation. Destroying the Device Key is what makes the remaining disk contents unrecoverable. |
| SZ-OS-008 | MUST | The root filesystem is **read-only and integrity-verified** — a `dm-verity` image whose root hash is carried in the signed UKI, in an A/B pair. Modification fails the read rather than being discouraged, so an attacker with code execution cannot persist into the root, and recovery from a corrupted root is a reboot into the other partition rather than a rebuild. All mutable state lives on one encrypted volume, so "is data at rest encrypted" has a single answer. |
| SZ-OS-009 | MUST | The state volume is LUKS2 (AES-256-XTS) with its key **sealed to the TPM against PCR 7 and PCR 11**, and additionally to a PIN in the attended profile. Because PCR 11 carries the boot-phase measurements, sealing against the pre-`ready` value means an attacker who obtains root on the *running* appliance cannot unseal it: the TPM refuses a policy that no longer matches. A recovery key is generated at provisioning, shown once and never stored on the appliance, and TPM re-enrolment happens inside the update transaction before commit — a kernel update changes the measurement, and that is the control working, not a fault. |
| SZ-OS-010 | MUST | The hardening posture is **asserted by tests, not described**: the root rejects writes, the disk refuses to unlock with Secure Boot disabled, the disk refuses to unlock from a shell on the running system, the nftables ruleset matches the committed policy including default-deny egress, every systemd unit carries a sandbox stanza, and AppArmor is in enforce for every profile. CIS benchmark deviations are recorded with a reason; a benchmark score is not a threat model. |


## INS — Installer and first-run setup

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-INS-001 | MUST | A root-run install.sh shall bootstrap a supported Debian 13 host from a git checkout. |
| SZ-INS-002 | MUST | Installation shall compile Next.js standalone output and Rust services, configure PostgreSQL/nginx/systemd and start one-time setup mode. |
| SZ-INS-003 | MUST | Setup mode shall use HTTPS, a cryptographically random one-time token, and become unavailable after initialization. |
| SZ-INS-004 | MUST | Installer and upgrade actions shall be idempotent where practical and shall not disable TLS verification. |
| SZ-INS-005 | MUST | Initial provisioning is available as an API operation and not only through the setup wizard, so a fleet can be provisioned reproducibly rather than by a human repeating a browser flow. It remains one-shot: once provisioned, the endpoint is gone until a factory reset (SZ-OS-007), which is the same property the wizard has (SZ-INS-003). |


## DOC — Documentation

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-DOC-001 | MUST | The repository shall document REST signing from Linux, Windows and CI systems. |
| SZ-DOC-002 | MUST | The repository shall document local OpenSSL 3/PKCS#11/osslsigncode signing without placing HSM PINs in commands or URIs. |
| SZ-DOC-003 | MUST | The repository shall document DigiCert and Sectigo code-signing enrollment/import procedures and link to current official provider documentation. |

