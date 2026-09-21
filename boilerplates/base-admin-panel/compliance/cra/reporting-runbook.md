# CRA Article 14 Reporting Runbook

Requirement: `REQ-CRA-06`. Article 14 of [Regulation (EU) 2024/2847](https://eur-lex.europa.eu/eli/reg/2024/2847/oj).
Owner: **A18**. Incident process: `compliance/cer/incident-response.md` — **one** process, two reporting outputs.

> **Status: IN FORCE.** The Article 14 reporting obligations apply from
> **11 September 2026** and the ENISA Single Reporting Platform is live.
> Today is 2026-09-21. This runbook is operational, not preparatory.
> Source: [European Commission — CRA reporting obligations](https://digital-strategy.ec.europa.eu/en/policies/cra-reporting).

## Named roles

A clock cannot be owned by a team. Each row is one person with one deputy.

| Role | Person | Deputy | Owns |
|---|---|---|---|
| Reporting officer | `<<PLACEHOLDER: name, role, phone, email>>` | `<<PLACEHOLDER: name, phone>>` | The decision to file, and the filing itself |
| Incident commander | `<<PLACEHOLDER: name, role, phone>>` | `<<PLACEHOLDER: name, phone>>` | Technical response; declares the trigger met |
| Security point of contact | `<<PLACEHOLDER: name, email — matches SECURITY.md and security.txt>>` | `<<PLACEHOLDER: name>>` | Reporter and user communication |
| Legal / regulatory | `<<PLACEHOLDER: name, role>>` | `<<PLACEHOLDER: name>>` | Reviews wording; **may not delay a filing past its deadline** |
| Executive sponsor | `<<PLACEHOLDER: name, role>>` | — | Informed, not consulted, inside the 24-hour window |

**Escalation is 24/7.** Out-of-hours route:
`<<PLACEHOLDER: on-call rota and paging mechanism>>`. Awareness at 02:00 on a
Saturday starts the same clock as awareness at 10:00 on a Tuesday.

## Trigger definitions

### Trigger A — actively exploited vulnerability

A vulnerability in the product for which there is **reliable evidence that a
malicious actor has exploited it in a system without the owner's permission**
(CRA Art. 3(42)).

Reliable evidence: logs from this product or an operator's deployment showing
the exploit path taken; a working exploit observed in the wild; credible
third-party reporting naming this product and version; inclusion in a
recognised exploited-vulnerability catalogue.

Not reliable evidence: a proof-of-concept with no observed use; a scanner
result; "it would be trivial to exploit"; a CVSS Exploitability metric.

### Trigger B — severe incident having an impact on the security of the product

An incident that negatively affects or is capable of negatively affecting the
product's ability to protect the availability, authenticity, integrity or
confidentiality of sensitive or important data or functions, **or** that has led
or may lead to the introduction or execution of malicious code in the product or
in a user's network (CRA Art. 3(44), Art. 14(5)).

Either condition suffices. "May lead" is in the text: a credible potential
counts.

### Worked examples for this product

| Event | Trigger | Why |
|---|---|---|
| Cross-tenant read via an RLS gap, observed in an operator's audit log | **A** | Exploited in the wild, defeats `REQ-RBA-04` |
| Compromise of the release signing identity | **B** | Capable of introducing malicious code into a user's network |
| Malicious code found in a dependency shipped in a released image | **B** | Malicious code present in the product (`REQ-SUP-03`) |
| KEK disclosure through a product defect | **A** if exploited, else **B** | Confidentiality of sensitive data (`REQ-SEC-06`) |
| Audit hash-chain break caused by a product defect | **B** | Integrity of a security function (`REQ-AUD-06`) |
| MFA bypass with a published exploit, no evidence of use | Neither yet | No reliable evidence of exploitation; handle under `vulnerability-handling.md`, re-evaluate hourly |
| Build-blocking critical advisory caught before release | Neither | Never placed on the market (`REQ-SUP-02`) |
| Operator misconfiguration, or a DDoS on one deployment | Neither, for the manufacturer | Not a product defect; may be a CER incident for the operator |

## "Awareness" — when the clock starts

The clock starts the moment the **incident commander or the reporting officer
receives information sufficient to conclude the trigger is met** — not when the
investigation concludes. Record the timestamp in UTC and in `Europe/Stockholm`
(`REQ-TIM-03`) with the person and the source, before the response starts. It is
the most contested fact in any later review and must not be reconstructed.

## Internal decision tree

```
Signal arrives (intake channel, gate finding, operator report, build scan)
│
├─ Does it concern a version placed on the market?
│    NO  → vulnerability-handling.md. No Article 14 duty. Record and stop.
│    YES ↓
│
├─ Reliable evidence of exploitation in the wild?   (Art. 3(42))
│    YES → TRIGGER A. Record awareness timestamp. 24h clock running. Go to FILE.
│    NO  ↓
│
├─ Does it negatively affect, or is it capable of negatively affecting, the
│  product's protection of availability / authenticity / integrity /
│  confidentiality of sensitive or important data or functions?
│    YES → TRIGGER B. Record awareness timestamp. 24h clock running. Go to FILE.
│    NO  ↓
│
├─ Has it led, or may it lead, to injection or execution of malicious code in
│  the product or in a user's network?
│    YES → TRIGGER B. Record awareness timestamp. 24h clock running. Go to FILE.
│    NO  ↓
│
├─ Uncertain? → Treat as TRIGGER B and start the clock. A withdrawn early
│    warning costs a correction; missing 24 hours is a breach. Where no duty is
│    triggered, consider voluntary reporting under Art. 15.
│
FILE ↓
├─ Reporting officer files the early warning via the ENISA Single Reporting
│  Platform, routed to ENISA and the coordinator CSIRT. ≤ 24h.
├─ Incident commander runs the response in parallel: the response never pauses
│  for the filing, and the filing never waits for the response.
├─ Also a significant disruption of an operator's essential service? YES → tell
│  that operator now. Their CER Art. 15 clock (24h to their competent
│  authority) is theirs to run and needs our facts.
└─ Users affected? → Art. 14(8) notification. See below.
```

## Deadline timeline

All deadlines run from **awareness**, except the vulnerability final report,
which runs from availability of a corrective or mitigating measure, and the
incident final report, which runs from the 72-hour notification.

| # | Trigger A — actively exploited vulnerability | Deadline | Trigger B — severe incident | Deadline |
|---|---|---|---|---|
| 1 | Early warning | **≤ 24 h** from awareness | Early warning | **≤ 24 h** from awareness |
| 2 | Vulnerability notification | **≤ 72 h** from awareness | Incident notification | **≤ 72 h** from awareness |
| 3 | Final report | **≤ 14 days** after a corrective or mitigating measure becomes available | Final report | **≤ 1 month** after the 72-hour notification |
| 4 | Inform affected users (Art. 14(8)) | Without undue delay after awareness | Inform affected users (Art. 14(8)) | Without undue delay after awareness |

Awareness at 2026-09-21 14:30 UTC therefore puts the early warning at
2026-09-22 14:30 UTC, the notification at 2026-09-24 14:30 UTC and a Trigger B
final report at 2026-10-24 14:30 UTC. Set those calendar entries when the
awareness timestamp is recorded, not later.

## Where the reports go

| Recipient | How | Notes |
|---|---|---|
| ENISA | ENISA **Single Reporting Platform** | The single entry point; live since 11 September 2026 |
| Coordinator CSIRT | Same submission, routed by the platform | The CSIRT designated as coordinator in the Member State where the manufacturer has its main establishment in the Union |
| Affected users | Direct, per Art. 14(8) | See below |
| Deploying operator that is a critical entity | Direct, immediately | So they can run their own CER Art. 15 clock |

Pre-conditions, true before an incident and not arranged during one:

- Platform account and credentials: `<<PLACEHOLDER: account holder, credential location, MFA method>>`
- Member State of main establishment and its coordinator CSIRT: `<<PLACEHOLDER: Member State, CSIRT name, contact route>>`
- Member States where the product is made available: `<<PLACEHOLDER: list — required early-warning content>>`
- Fallback if the platform is unreachable: `<<PLACEHOLDER: CSIRT direct channel, who confirms receipt>>`

## Content of each submission

### 1. Early warning — ≤ 24 hours

```
Manufacturer:            <<PLACEHOLDER: legal name, address, contact point>>
Product:                 <<PLACEHOLDER: product name, type, unique identifier>>
Affected versions:       <<PLACEHOLDER: version range, or "under assessment">>
Trigger:                 [ ] actively exploited vulnerability
                         [ ] severe incident having an impact on product security
Awareness timestamp:     <<PLACEHOLDER: YYYY-MM-DD HH:mm:ss UTC>>
Trigger A only — statement that the vulnerability is actively exploited, with
  the Member States where the product is made available, if known.
Trigger B only — whether the incident is suspected to be caused by unlawful or
  malicious acts.
Known at this time:      <<PLACEHOLDER: two or three sentences. No speculation.>>
Reporting officer:       <<PLACEHOLDER: name, direct phone, email>>
```

### 2. Notification — ≤ 72 hours

```
Reference:               <<PLACEHOLDER: platform reference of the early warning>>
General information about the product and the vulnerability/incident:
                         <<PLACEHOLDER>>
Trigger A — nature of the exploit; corrective or mitigating measures taken, and
  those available to users: <<PLACEHOLDER>>
Trigger B — nature of the incident; initial assessment of it; corrective or
  mitigating measures taken, and those available to users: <<PLACEHOLDER>>
Affected versions (confirmed): <<PLACEHOLDER>>
Number of deployments known to be affected: <<PLACEHOLDER: count or "unknown">>
Evidence relied on:      <<PLACEHOLDER: log excerpts, audit chain state, SBOM
                           match for the affected component>>
Corrections to the early warning: <<PLACEHOLDER: state them explicitly>>
```

### 3. Final report

```
Reference:               <<PLACEHOLDER: platform reference of the notification>>
Trigger A — description of the vulnerability, including severity and impact;
  information on the malicious actor, if available; details of the security
  update or other corrective measure: <<PLACEHOLDER>>
Trigger B — description of the incident, including severity and impact; the type
  of threat or root cause likely to have triggered it; applied and ongoing
  mitigation measures: <<PLACEHOLDER>>
Fixed version and release date: <<PLACEHOLDER>>
Advisory id and URL:     <<PLACEHOLDER: links to the published advisory>>
Timeline:                <<PLACEHOLDER: awareness → filing → fix → publication,
                           timestamps in UTC>>
Lessons and process changes: <<PLACEHOLDER: the control added, with its REQ ID>>
```

## Informing affected users (Art. 14(8))

Without undue delay after awareness, inform the users of the affected product
about the incident or vulnerability and, where necessary, about corrective
measures and risk-mitigation actions they can take.

- Channel: `<<PLACEHOLDER: operator notification channel>>`, using the recipient
  list at `<<PLACEHOLDER: where the list of deploying operators is maintained>>`.
- Content: affected versions, what to do now, the interim mitigation, and when
  the fix lands. Plain language, no hedging.
- The in-product announcement plus the deterministic update prompt
  (`REQ-PWA-05`) supplements the direct notification; it never replaces it, and
  an operator may not have logged in.

## Evidence log — one per report

Kept at `<<PLACEHOLDER: evidence log location, with access control and retention>>`.

| Field | Content |
|---|---|
| Internal reference | Tracking id from the vulnerability intake log |
| Trigger | A or B, with the subparagraph relied on |
| Awareness timestamp | UTC and `Europe/Stockholm`, plus who became aware and from what source |
| Decision record | Who declared the trigger met, when, and on what evidence |
| Submissions | Each filing: timestamp sent, platform reference, recipient, and the exact text as sent |
| Corrections | What the notification or final report corrected from an earlier filing |
| Notifications sent | Users and critical-entity operators: when, to whom, over which channel, with the text |
| Artefacts | SBOM match, advisory scan output, audit-chain verify result, gate verdicts |
| Fix and retention | Commit, version, signature record; retained for the support period plus 10 years |

## Rehearsal record (REQ-CRA-06 — "rehearsed")

An unrehearsed runbook is a document, not a capability. Rehearse at least
annually and after any change to the named roles above.

| Field | Value |
|---|---|
| Last rehearsal date | `<<PLACEHOLDER: YYYY-MM-DD>>` |
| Scenario | `<<PLACEHOLDER: e.g. cross-tenant read exploited in the wild, Trigger A>>` |
| Participants | `<<PLACEHOLDER: named roles present, and which deputy stood in>>` |
| Early-warning draft time | `<<PLACEHOLDER: HH:mm from awareness — target under 4 hours>>` |
| Result | `<<PLACEHOLDER: pass / fail, with the deviation>>` |
| Findings and fixes | `<<PLACEHOLDER: what broke, and what changed as a result>>` |
| Next rehearsal due | `<<PLACEHOLDER: YYYY-MM-DD>>` |

## Sources

- [Regulation (EU) 2024/2847, Article 14](https://eur-lex.europa.eu/eli/reg/2024/2847/oj) — triggers, deadlines, submission content
- [European Commission — CRA reporting obligations](https://digital-strategy.ec.europa.eu/en/policies/cra-reporting) — applicability from 11 September 2026
- [BSI — CRA Single Reporting Platform](https://www.bsi.bund.de/EN/Themen/Unternehmen-und-Organisationen/Informationen-und-Empfehlungen/Cyber_Resilience_Act/Single_Reporting_Platform-CRA/single_reporting_platform-cra.html) — platform routing and severe-incident conditions
