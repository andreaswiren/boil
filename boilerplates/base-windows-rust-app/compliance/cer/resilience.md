# CER Resilience Posture

Directive (EU) 2022/2557, the Critical Entities Resilience Directive. In force
since January 2023, covering critical entities in **11 sectors** — energy,
transport, banking, financial market infrastructure, health, drinking water,
waste water, digital infrastructure, public administration, space and food — with
Member State risk assessments **at least every four years** and resilience
measures documented in a resilience plan.

Confirmed externally 2026-09-22:
<https://eur-lex.europa.eu/eli/dir/2022/2557/oj/eng>,
<https://www.deloitte.com/global/en/services/consulting-risk/perspectives/navigating-the-eu-critical-entities-resilience-directive.html>,
<https://www.ramboll.com/en-us/insights/resilient-societies-and-liveability/the-eu-cer-directive-understand-the-basics>.
`unconfirmed`: the Article numbering for risk assessment, resilience measures and
incident notification (`eur-lex.europa.eu` was unreachable from the build
container — egress policy denial). **Check:** read Articles 12–15 from the
Official Journal and record the confirmation in §7.

Owner: `B13`. Requirements: REQ-CER-01..07.

## 1. Applicability — we are a supplier, not a critical entity

**This product is a supplier artefact. It is never itself a critical entity**
(REQ-CER-01). The obligated party under the CER is the **operator** that a Member
State has designated as a critical entity. Nothing in this document transfers one
of their obligations to us, and nothing in it satisfies one on their behalf.

What we owe a deploying operator is inputs to their own work: a dependency and
failure-mode description they can put in their risk assessment, degraded-mode
behaviour they can plan around, recovery characteristics they can build an RTO
into, and an incident-response channel that lines up with their notification
duties.

Where a control is theirs, this document says so plainly. A supplier document
that claims an operator control is worse than a gap, because it stops the
operator looking (REQ-CER-06).

## 2. The control split

| Control | Product (ours) | Operator (theirs) |
|---------|----------------|-------------------|
| Signed, verified updates | Yes — signature verified before any swap (REQ-UPD-02) | Deciding the patch window and the update policy (REQ-UPD-12) |
| Update availability | Publishing artefacts and a signed manifest to both forges (REQ-REL-01) | Network reachability of the update endpoint from their estate |
| Least privilege at run time | `asInvoker`; service under `LocalService` or a virtual account (REQ-FND-11, REQ-SVC-03) | Local administrator policy, application control, endpoint management |
| File locations and ACLs | Documented per-user and per-machine paths with correct ACLs (REQ-SEC-05) | Disk encryption, drive layout, roaming profile policy |
| Logging | Structured local logs, rotation, size cap, Event Log for service events (REQ-OBS-01, REQ-OBS-06) | Log collection, retention, monitoring and alerting |
| User data backup | A documented data location and a restore procedure (§5) | **Performing backups.** The app does not back up user data |
| Physical security | Nothing | Everything |
| Endpoint hardening | Binary hardening, no DLL-hijacking surface (REQ-SEC-04, REQ-SEC-06) | OS patch level, EDR, secure boot, device compliance |
| Identity | Authenticated local IPC (REQ-SEC-09) | Directory, MFA, joiner/mover/leaver |
| Incident reporting | CRA reporting for the product (`compliance/cra/reporting-runbook.md`) | **CER notification to their competent authority** for disruption of their essential service |
| Resilience plan | This document as an input | Writing and maintaining the plan |

## 3. Criticality and dependency assessment

The app supports an essential service only **indirectly**: it is a client-side
tool on an operator's endpoints, not a component of service delivery. The
operator names the essential service in their own assessment
(`<<PLACEHOLDER: essential service and sector, from intake>>`), and the
criticality classification is theirs to make (REQ-CER-02).

What fails when each dependency fails:

| Dependency | Owned by | Failure | Effect on the app | Effect on the operator's service |
|-----------|----------|---------|-------------------|--------------------------------|
| Windows (minimum supported version) | Operator | Unsupported OS build | Refuses to start with a clear message rather than a missing-entry-point crash (REQ-FND-05) | None — the endpoint was out of policy |
| Local disk | Operator | Full or read-only | Logs stop with a capped, rotated footprint; see §4 | None |
| User's network | Operator / user | Offline | Update checks fail visibly and retry with backoff (REQ-UPD-11); the app keeps working | None |
| Update endpoint (both forges) | Us | Unreachable or 404 | No update; the installed version keeps running; the failure is visible, never silent | Delayed patching — the operator's patch window is affected, not the service |
| Update signing key | Us (custodian; no agent owns a key) | Compromised | Clients reject artefacts signed by anything else, because the public key is embedded (REQ-UPD-03) | Trigger B in the CRA runbook; operator notified |
| Code-signing certificate | Us | Expired or revoked | New artefacts fail signature verification; installed instances keep running; see §4 | Patching blocked until reissued |
| Windows service (if enabled) | Us | Stopped or crash-looping | Crash loop detected and reported rather than restarting forever (REQ-SVC-10); the UI reports service state | Loss of whatever the service does for them; the interactive app still runs |
| Shipped dependency crate | Us | Vulnerability or compromise | Advisory blocks the next release; a fix ships as a security-flagged update (REQ-SBM-03, REQ-UPD-13) | Patch urgency |
| Explorer / shell | Operator | Explorer restart | Tray icon re-registers itself (REQ-TRY-02) | None |

**A desktop app's dependencies fail differently from a server's**, and the
difference is who owns them. A server depends on a database and a load balancer
the operator runs deliberately. This app depends most often on **the user's own
network** — a hotel Wi-Fi portal, a VPN that is down, a proxy that MITMs TLS. So
the design target is not high availability; it is that the app remains fully
usable while the things around it are broken, and says what is wrong.

## 4. Degraded-mode behaviour

Documented, and tested where a test exists (REQ-CER-03). Every row is a state the
app must be in deliberately, not a state it happens to end up in.

| Condition | Behaviour | Never | REQ |
|-----------|-----------|-------|-----|
| **No network** | Full function. Update check fails, is shown in diagnostics as a last-check and last-error, retries with backoff | Blocks startup; a modal on every check; a silent failure | REQ-UPD-11, REQ-OBS-03, REQ-UI-07 |
| **No update server** (DNS fails, 404, both forges down) | Same as no network, distinguished in the error text so support can tell them apart | Falls back to an unverified source; retries in a tight loop | REQ-UPD-04, REQ-UPD-08 |
| **Update manifest present but artefact missing** | Refuses the update, reports it, keeps the installed version | Partially applies an update | REQ-REL-10, REQ-UPD-06 |
| **Signature invalid or artefact tampered** | Refuses and reports. This is the designed response, not an error condition to work around | Executes or swaps anything unverified — that is remote code execution | REQ-UPD-02, REQ-SEC-02 |
| **Expired or revoked signing certificate** | Installed instances keep running; the updater rejects the new artefact and reports "signature not valid" with the reason; operators are told a reissue is in progress | Silently accepts an expired chain; disables verification "temporarily" | REQ-UPD-02, REQ-SEC-02 |
| **No service** (not installed, stopped, or crash-looping) | Interactive app runs and reports service state in the tray and diagnostics; crash loop is detected and reported, not restarted forever | Silently reverts to a no-service mode that looks healthy | REQ-SVC-04, REQ-SVC-10, REQ-TRY-04 |
| **Service/app version mismatch** | Detected; both refuse to interoperate across versions and say so | Interoperates and hopes | REQ-SVC-05 |
| **Read-only or full disk** | Starts; logging degrades to in-memory with a visible warning; settings changes fail with a clear message; no data loss beyond the unwritten change | Crashes on a failed write; fills the disk (logs are rotated and capped) | REQ-OBS-01, REQ-UI-07 |
| **Read-only during an update** | Update aborts before any swap; old version intact | Leaves a half-swapped installation | REQ-UPD-06, REQ-INST-09 |
| **Explorer restart** | Tray icon re-registers | Vanishes until relaunch | REQ-TRY-02 |
| **Elevation refused** | Machine-wide install fails cleanly with an exit code and a stated reason; per-user install still offered | Retries elevation in a loop; leaves a half-install | REQ-INST-02, REQ-INST-09, REQ-INST-11 |

## 5. Recovery, RTO and RPO

For **user data this app holds locally**. The app is not a system of record; the
operator's backup policy is the actual control (§2).

| Item | Target | Basis |
|------|--------|-------|
| RTO — reinstall and restore settings on a replacement machine | `<<PLACEHOLDER: operator target, default 4 hours>>` | Self-installing binary: `app.exe --install` needs no separate download (REQ-INST-01) |
| RPO — user data | `<<PLACEHOLDER: operator target, default 24 hours>>` | Equals the operator's backup interval for the user profile. **We provide none** — no cloud sync, no telemetry, no server-side copy (REQ-FND-10) |
| RTO — failed update | Immediate | The swap is atomic: old or new, never a mixture (REQ-UPD-06) |
| RTO — corrupt settings | App start | Settings reset to secure defaults with the corruption logged (REQ-CRA-02) |
| RTO — service failure | Restart policy: `<<PLACEHOLDER: restart policy and backoff from intake>>` | Configured deliberately, crash loop detected (REQ-SVC-10) |

Restore procedure: install the same version from the release page (both forges
carry an identical artefact set — REQ-REL-02), restore the user data directory
from the operator's backup, start the app, confirm the version in `About`
(REQ-OBS-03).

### Rehearsal log (REQ-CER-04)

A restore that has not been tested is a hope. Until a row here carries a date and
a result, this section is **prose** and the obligations matrix marks it weak
(REQ-CRA-10).

| # | Date | Scenario | Result | Time to restore | Gaps | Next due |
|---|------|----------|--------|-----------------|------|----------|
| 1 | `<<PLACEHOLDER: date>>` | Clean Windows image, install from release, restore user data from backup | `<<PLACEHOLDER: pass/fail>>` | `<<PLACEHOLDER>>` | `<<PLACEHOLDER>>` | `<<PLACEHOLDER: +12 months>>` |
| 2 | `<<PLACEHOLDER: date>>` | Interrupted update (power loss mid-swap), then recovery | `<<PLACEHOLDER: pass/fail>>` | `<<PLACEHOLDER>>` | `<<PLACEHOLDER>>` | `<<PLACEHOLDER: +12 months>>` |
| 3 | `<<PLACEHOLDER: date>>` | Upgrade from the previous released version, not a fresh install (REQ-TST-02) | `<<PLACEHOLDER: pass/fail>>` | `<<PLACEHOLDER>>` | `<<PLACEHOLDER>>` | `<<PLACEHOLDER: +12 months>>` |

## 6. Incident response — one process, two outputs

Incident response is **the CRA runbook** (`compliance/cra/reporting-runbook.md`),
with the same named roles and the same trigger declaration (REQ-CER-05). There is
one process because two processes diverge, and the one that diverges is the one
nobody rehearsed.

The two outputs differ:

| Output | Obligated party | Goes to | Deadline |
|--------|----------------|---------|----------|
| CRA report — actively exploited vulnerability or severe incident in the product | **Us**, as manufacturer | CSIRT designated as coordinator + ENISA, via the Single Reporting Platform | 24h early warning, 72h notification, then the final report |
| CER notification — significant disruption of the operator's essential service | **The operator**, as critical entity | Their competent authority | Per their Member State's transposition — `<<PLACEHOLDER: operator's national deadline>>` |
| Supplier notice to the operator | Us | `<<PLACEHOLDER: operator security contact>>` | Within `<<PLACEHOLDER: contractual notification period>>` of declaring a trigger |

Escalation: Security Lead → Deputy after 1 hour unreachable → `<<PLACEHOLDER:
executive escalation>>`. The supplier notice is what lets the operator start
their own clock, so it is sent when the trigger is declared, not when the fix is
ready.

## 7. Reassessment cadence

The CER frames risk assessment on a **four-yearly** cycle, so this document is
reassessed on the same cadence and whenever a trigger below fires (REQ-CER-07).

| Field | Value |
|-------|-------|
| Last full reassessment | `<<PLACEHOLDER: date of first completed assessment>>` |
| Cadence | Every 4 years, or on a trigger |
| **Next due** | `<<PLACEHOLDER: last reassessment + 4 years>>` |
| Triggers for early reassessment | A new dependency class; service mode enabled or removed; a change of update or signing mechanism; a CRA Trigger A or B incident; an operator entering a new CER sector; the Official Journal check at the head of this document changing a stated obligation |
| Article numbering confirmed against the Official Journal | `<<PLACEHOLDER: date + who>>` |
| Annual lighter review | Degraded-mode table (§4) and rehearsal log (§5), so four years never passes with an untested restore |
