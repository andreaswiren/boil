# CRA Annex I — Obligations Matrix

Regulation (EU) 2024/2847. This product is a **product with digital elements
placed on the market**, so Annex I applies **directly**, not by analogy
(REQ-CRA-01). Full application, including CE marking and the whole Annex I set:
**11 December 2027** (<https://digital-strategy.ec.europa.eu/en/policies/cra-summary>).

Owner: `B13`. Generated from repository state, not written by hand (REQ-CRA-10).

## How to read a row

| Column | Meaning |
|--------|---------|
| Obligation | The Annex I point, in short form |
| Control | How this product satisfies it |
| REQ | The implementing requirement IDs from `spec/requirements.md` |
| Evidence | The artefact path an auditor can open |
| Owner | The agent that produces the evidence |
| Strength | `build-output` · `test-asserted` · `prose` (**weak**) · `pending` |

`prose` rows are marked **weak** deliberately. REQ-CRA-10 wants evidence
generated from repository state; a row whose only evidence is this document
describing an intention is a gap with a name, not a satisfied obligation.
`pending` means the cited path does not exist yet — a finding routed to the owner.

**Structure confirmed externally (2026-09-22):** Annex I has two parts — Part I,
properties of the product (a general obligation plus thirteen properties), and
Part II, eight vulnerability-handling requirements on the manufacturer
(<https://hr-st.com.tw/insights/en/cra-annex-i-part-i-essential-requirements>,
<https://cra-facts.com/blog/cra-annex-i-part-ii-vulnerability-handling-requirements>,
<https://streamlex.eu/annexes/cra-en-annex-i/>).

`unconfirmed`: the exact **point lettering** below. `eur-lex.europa.eu` was
unreachable from the build container (egress policy denial), so the lettering
comes from secondary sources. **Check:** read Annex I from the Official Journal
and correct the lettering before an Annex V declaration is signed. The substance
of each row does not depend on the letter.

---

## Part I — Properties of the product

### Part I.1 — Designed, developed and produced to an appropriate level of cybersecurity based on the risks

| Control | REQ | Evidence | Owner | Strength |
|---------|-----|----------|-------|----------|
| A risk-based design recorded in the requirement register and reviewed by two independent security agents who do not see each other's findings before submitting | REQ-CRA-01, REQ-GAT-02, REQ-GAT-03 | `build/gates/H7-security-alpha.md`, `build/gates/H7-security-beta.md` | `T1`, `T2` | `build-output` |
| `unsafe` confined to one named FFI boundary, every block carrying its invariant | REQ-FND-03, REQ-FND-06 | `crates/ffi/**`, `#![forbid(unsafe_op_in_unsafe_fn)]` in the workspace lints | `B01` | `test-asserted` |
| The Annex VII risk assessment narrative | REQ-CRA-09 | `<<PLACEHOLDER: path of the Annex VII technical documentation generated at H8>>` | `B13` | `pending` |

### Part I.2 — The thirteen properties

| # | Obligation | Control | REQ | Evidence | Owner | Strength |
|---|-----------|---------|-----|----------|-------|----------|
| (a) | Placed on the market without known exploitable vulnerabilities | Advisory matching on every build; a critical or known-exploited advisory blocks the release | REQ-SBM-03, REQ-SBM-07 | `security/supply-chain/advisory-report.json`, `deny.toml` | `B11` | `build-output` |
| (b) | Secure-by-default configuration, with a reset to a secure state | Runs as a normal user (`asInvoker`); per-user install without elevation; autostart off by default; no network listener by default; a documented reset procedure | REQ-CRA-02, REQ-FND-11, REQ-INST-02, REQ-SVC-07, REQ-SVC-06 | `crates/contracts` config defaults, the application manifest in `crates/app/`, `tests/secure_defaults.rs` | `B01`, `B07`, `B08`, `B14` | `test-asserted` |
| (c) | Vulnerabilities addressable through security updates, including automatic updates by default with an opt-out | The auto-updater: automatic by default, manual check available, policy-pinnable for managed fleets, and the opt-out discoverable in the UI rather than mysterious | REQ-UPD-01, REQ-UPD-12, REQ-UI-09, REQ-CRA-07 | `crates/update/**`, `crates/ui/**` settings view | `B09`, `B05` | `test-asserted` |
| (d) | Protection from unauthorised access, with authentication and access management | IPC endpoint authenticates its caller and is not reachable by other users on a shared machine; files written only to documented locations with correct ACLs | REQ-SVC-06, REQ-SEC-09, REQ-SEC-05 | `crates/service/**` IPC layer, `tests/ipc_acl.rs` | `B08`, `B14` | `test-asserted` |
| (e) | Confidentiality of stored, transmitted and processed data | HTTPS with certificate validation for everything over the network; secrets at rest via DPAPI or the Windows credential store, never a cleartext file or plaintext registry value | REQ-SEC-01, REQ-SEC-03 | `crates/update/**` transport, `keyring` usage per `versions/manifest.json` | `B09`, `B01` | `test-asserted` |
| (f) | Integrity of data, commands, programs and configuration | Signature verified before anything is executed or swapped in; artefact hash checked against the signed manifest; downgrade refused; every external input parsed as untrusted | REQ-UPD-02, REQ-UPD-04, REQ-UPD-05, REQ-SEC-02, REQ-SEC-07 | `crates/update/**` verification path, `tests/update_negative.rs` (wrong signature, tampered artefact, downgrade, interrupted swap — REQ-TST-03) | `B09`, `B14` | `test-asserted` |
| (g) | Process only data adequate, relevant and limited to the purpose | No telemetry, no phone-home, no third-party crash reporting, asserted by test including build-time network access; crash records stay local and nothing is transmitted without a per-incident user action | REQ-FND-10, REQ-SBM-06, REQ-OBS-05 | `security/supply-chain/**` telemetry assertion (offline vendored build, outbound allowlist test, source scan) | `B11` | `test-asserted` |
| (h) | Availability of essential and basic functions, including resilience against denial of service | The app runs without the update server, without the service and without a network; the swap survives interruption leaving old or new, never a mixture; the UI thread never blocks | REQ-CER-03, REQ-UPD-06, REQ-UI-06, REQ-UI-07 | `compliance/cer/resilience.md` degraded-mode table, `tests/update_interrupt.rs` | `B13`, `B09`, `B14` | `test-asserted` |
| (i) | Minimise the negative impact on the availability of services provided by other devices or networks | Update checks staggered and rate-limited so a fleet does not synchronise into a thundering herd; no network listener by default | REQ-UPD-08, REQ-SVC-06 | `crates/update/**` scheduling, `tests/update_stagger.rs` | `B09`, `B14` | `test-asserted` |
| (j) | Limit attack surfaces, including external interfaces | Single self-contained executable with no runtime prerequisite; one FFI boundary; no DLL-hijacking surface — fully qualified load paths, safe search mode, never the working directory; local IPC only | REQ-FND-12, REQ-FND-03, REQ-SEC-06, REQ-SVC-06 | `crates/ffi/**`, `tests/dll_search_order.rs` | `B01`, `B14` | `test-asserted` |
| (k) | Reduce the impact of an incident with exploitation mitigation mechanisms | Binary hardening enabled **and verified in CI**: ASLR/DEP, CFG where supported, stripped release build | REQ-SEC-04 | `.github/workflows/release.yml` hardening check, per-release verification output | `B10` | `build-output` |
| (l) | Provide security-relevant information by recording and monitoring internal activity, with an opt-out | Structured logging to a documented per-user location with rotation and a size cap; Windows Event Log for service-mode events an administrator looks for; level adjustable at runtime; user-visible | REQ-OBS-01, REQ-OBS-02, REQ-OBS-06, REQ-OBS-03 | `crates/obs/**`, `tests/log_rotation.rs` | `B12`, `B14` | `test-asserted` |
| (m) | Let users securely and permanently remove all data and settings, and transfer them securely | Uninstall removes binaries, shortcuts, registry entries, scheduled tasks, service and autostart entry, with an explicit prompt about keeping user data; the support bundle is the only export and it is redacted | REQ-INST-06, REQ-OBS-04, REQ-SEC-08 | `crates/install/**` uninstall path, `tests/uninstall_complete.rs` | `B07`, `B14` | `test-asserted` |

### Part I.3 — The risk assessment accompanies the product documentation

| Control | REQ | Evidence | Owner | Strength |
|---------|-----|----------|-------|----------|
| The cybersecurity risk assessment is recorded and carried into the Annex VII technical documentation and the Annex II user information | REQ-CRA-09, REQ-CRA-01 | `<<PLACEHOLDER: Annex VII technical documentation path, generated at H8>>` | `B13` | `pending` |

---

## Part II — Vulnerability handling by the manufacturer

| # | Obligation | Control | REQ | Evidence | Owner | Strength |
|---|-----------|---------|-----|----------|-------|----------|
| (1) | Identify and document components and vulnerabilities, including an SBOM in a commonly used machine-readable format covering at least top-level dependencies | CycloneDX SBOM per build from `Cargo.lock`, covering the **full resolved graph**, published per release — **and embedded in the shipped binary** by `cargo-auditable` 0.7.6, so an artefact found on a machine can be audited without the release page | REQ-SBM-01, REQ-SBM-02, REQ-CRA-03 | `app-<version>-<arch>.cdx.json` on both forges; `cargo audit bin app.exe` against the released artefact | `B11`, `B10` | `build-output` |
| (2) | Address and remediate vulnerabilities without delay, including by providing security updates | Triage SLA by severity and remediation targets, with the fix distributed by the auto-updater | REQ-CRA-05, REQ-CRA-07, REQ-UPD-01 | `compliance/cra/vulnerability-handling.md`; per-advisory records in `security/supply-chain/advisory-report.json` | `B13`, `B11` | `build-output` for the record, **weak** (`prose`) for the SLA itself |
| (3) | Apply effective and regular tests and reviews of the product's security | Two independent security reviewers with no shared context, each stating a review plan for a larger change and then executing it; negative-case updater tests; supply-chain passes on every build and daily | REQ-GAT-02, REQ-GAT-03, REQ-TST-03, REQ-SBM-03 | `build/gates/H7-*.md`, `tests/update_negative.rs`, the daily advisory run | `T1`, `T2`, `B14`, `B11` | `build-output` |
| (4) | Once a security update is available, share and publicly disclose information about the fixed vulnerability: description, affected versions, impact, severity, remediation | Release notes with a dedicated `## Security fixes` section carrying advisory id and severity, generated from the change record — the same set that sets the manifest's `security` flag | REQ-REL-07, REQ-UPD-13, REQ-CRA-05 | Release body on both forges; `CHANGELOG.md` | `B10`, `B17` | `build-output` |
| (5) | Put in place and enforce a policy on coordinated vulnerability disclosure | A published CVD policy with scope, safe harbour, expected response times and publication practice | REQ-CRA-04, REQ-SEC-10 | `compliance/cra/cvd-policy.md`, published in `SECURITY.md` and at `/.well-known/security.txt` | `B13`, `B17` | `prose` — **weak** until the policy is published at a resolvable URL, then `build-output` |
| (6) | Facilitate the sharing of information about potential vulnerabilities, including a contact address for reporting | A single documented point of contact, in `SECURITY.md`, in the RFC 9116 `security.txt`, and in the user information | REQ-CRA-04, REQ-SEC-10, REQ-CRA-09 | `compliance/cra/cvd-policy.md` (`security.txt` template), `SECURITY.md` | `B13`, `B17` | `prose` — **weak**; `<<PLACEHOLDER: security contact address>>` until intake supplies it |
| (7) | Provide mechanisms to securely distribute updates, in an automatic manner where applicable, so vulnerabilities are fixed in a timely way | **The auto-updater is this mechanism.** Every artefact signed and verified before execution or swap; public key embedded in the binary; HTTPS with certificate validation; atomic swap; staggered checks; failures visible and retried, never silent. This is why REQ-UPD-02 is a **compliance control as well as a security one** | REQ-UPD-02, REQ-UPD-03, REQ-UPD-04, REQ-UPD-06, REQ-UPD-11, REQ-CRA-07 | `crates/update/**`, `tests/update_negative.rs`, the signed `update-manifest.json.minisig` on both forges | `B09`, `B10`, `B14` | `test-asserted` |
| (8) | Disseminate security updates without delay and free of charge, with advisory messages telling users what to do; security updates separate from functionality updates where technically feasible | The manifest marks each entry `security: true` or not, so an operator can take a security fix without taking features; the notes' security section is the advisory | REQ-UPD-13, REQ-CRA-07, REQ-REL-07, REQ-UPD-12 | `update-manifest.json` schema and its `security` flag; release notes | `B09`, `B10` | `test-asserted` |

---

## Where this matrix is weak

Stated here rather than buried in a column, because the weak rows are what an
auditor will ask about first (REQ-CRA-10):

1. **Part II (2), the SLA.** The remediation targets are a commitment in prose.
   The per-advisory records are build outputs, but "triaged within 24 hours" is
   only evidenced once the record carries timestamps. **Fix:** timestamp intake,
   triage and fix in `advisory-report.json` so the SLA becomes measurable.
2. **Part II (5) and (6), the policy and the contact.** Weak until the policy is
   published at a resolvable URL and the contact is a real address. Both are
   placeholders that intake supplies (REQ-CRA-04).
3. **Part I.1 and Part I.3, the risk assessment narrative.** `pending` until the
   Annex VII documentation is generated at H8 (REQ-CRA-09).
4. **Point lettering.** `unconfirmed` against the Official Journal, as stated
   above.

## Cross-cutting obligations not in Annex I

| Obligation | Control | REQ | Evidence | Owner | Strength |
|-----------|---------|-----|----------|-------|----------|
| Support period declared, with the end-of-support date stated in the documentation and visible in About. The CRA sets a floor of five years unless the product is expected to be in use for less (<https://cra.orcwg.org/faq/official/manufacturers/support-period/>) | REQ-CRA-08 | `<<PLACEHOLDER: support period and end-of-support date (month and year) from intake>>`; About view in `crates/ui/**` | `B00`, `B05`, `B17` | `pending` |
| Reporting readiness for the obligations in force since 11 September 2026 | REQ-CRA-06 | `compliance/cra/reporting-runbook.md` and its rehearsal record | `B13` | `prose` — **weak** until a rehearsal is logged with a date |
| Annex II user information, Annex V declaration of conformity, Annex VII technical documentation | REQ-CRA-09 | Generated at H8 from `evidence-index` | `B13`, `B17` | `pending` |
