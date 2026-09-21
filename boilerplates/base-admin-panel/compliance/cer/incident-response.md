# Incident Response, Notification and Personnel Security

Requirements: `REQ-CER-06` (incident response and notification, named roles and escalation, aligned with the CRA runbook), `REQ-CER-07` (personnel security and access control).
Directive: [Directive (EU) 2022/2557](https://eur-lex.europa.eu/eli/dir/2022/2557/oj), Art. 14 and Art. 15.
Owner: **A18**. Reporting mechanics: `compliance/cra/reporting-runbook.md`.

## One process, two reporting outputs

There is **one** incident process, defined here. What leaves the building under
CRA Article 14 is defined in `compliance/cra/reporting-runbook.md`. A severe
incident under CRA Art. 14 and a significant disruption under CER Art. 15 can be
the same event, filed by two different parties on two clocks:

| Output | Filed by | To | Deadlines |
|---|---|---|---|
| CRA Art. 14 | **Manufacturer** | ENISA + coordinator CSIRT, via the Single Reporting Platform | 24 h early warning, 72 h notification, final report (14 days after a measure is available for a vulnerability; 1 month after the notification for an incident) |
| CER Art. 15 | **Operator** (the critical entity) | Its national competent authority | Initial notification no later than **24 h** from awareness, detailed report no later than **1 month** thereafter |
| Personal data breach | Controller — normally the **operator** | Its supervisory authority | 72 h (GDPR Art. 33). A third clock that gets forgotten; flag it at declaration |

Two parallel processes would produce two inconsistent accounts of the same
facts, which is worse than one late filing. So: one declaration, one timeline,
one evidence set, three possible filings.

## Named roles

| Role | Person | Deputy | Authority |
|---|---|---|---|
| Incident commander | `<<PLACEHOLDER: name, role, phone>>` | `<<PLACEHOLDER: name, phone>>` | Declares severity, owns the response, may take the service offline |
| Reporting officer | `<<PLACEHOLDER: name, role, phone>>` | `<<PLACEHOLDER: name, phone>>` | Owns the CRA Art. 14 filings and the operator notification |
| Technical lead | The owning agent's human maintainer (`contracts/ownership.md`) | `<<PLACEHOLDER>>` | Containment and the fix inside the owned path |
| Communications lead | `<<PLACEHOLDER: name, role>>` | `<<PLACEHOLDER>>` | All outbound wording; single voice |
| Security point of contact | `<<PLACEHOLDER: name, email>>` | `<<PLACEHOLDER>>` | Reporter contact, per `compliance/cra/cvd-policy.md` |
| Scribe | Assigned at declaration | — | The timeline. Not optional: an unrecorded response cannot be filed |
| Legal / regulatory | `<<PLACEHOLDER: name>>` | `<<PLACEHOLDER>>` | Reviews wording inside the window; **never** holds a filing past a deadline |
| Executive sponsor | `<<PLACEHOLDER: name>>` | — | Informed; consulted only on customer-impacting decisions |

**Escalation path.** Detector → incident commander (paged, 24/7 via
`<<PLACEHOLDER: paging mechanism>>`) → severity declared → for Sev-1 and Sev-2
the reporting officer and communications lead are paged immediately → executive
sponsor informed within `<<PLACEHOLDER: minutes>>`.

Acknowledgement targets: **Sev-1 15 minutes, Sev-2 30 minutes, Sev-3 1 business
hour, Sev-4 1 business day.** If the commander does not acknowledge, the deputy
is paged; if neither does,
`<<PLACEHOLDER: the third escalation contact — never let a page die>>`.

## Severity classification

Classify on **impact**, not on how hard it was to find.

| Sev | Definition | Examples | Immediate consequence |
|---|---|---|---|
| **Sev-1** | Confidentiality, integrity or availability lost across tenants, or evidence of active exploitation | Cross-tenant data access; authentication bypass; KEK disclosure; malicious code in a shipped image; total outage past the RTO | Commander paged; **assume the CRA 24 h clock is running**; notify affected operators now |
| **Sev-2** | Serious, bounded to one tenant or one function, or a credible potential for Sev-1 | Single-tenant data exposure; privilege escalation within a tenant; audit hash-chain break; sustained partial outage; secret in a log sink | Commander paged; reporting officer assesses the Art. 14 triggers within 2 h |
| **Sev-3** | Contained, no data loss, workaround exists | Degraded dependency past its expected window; failed restore rehearsal; rate-limit abuse without compromise | Business hours; recorded, reviewed at the next release |
| **Sev-4** | No security or availability impact | Hardening gap; noisy false positive; process deviation | Backlog with a REQ ID |

Re-classify freely as facts arrive — **upward immediately, downward only by the
commander with the reason recorded.** Severity here is the same scale used by
`compliance/cra/vulnerability-handling.md`, so a vulnerability report and an
incident cannot be rated differently for the same flaw.

## Detection sources

`/api/health/ready` (`REQ-FND-10`); the audit trail and failed-auth,
rate-limit-trip and impersonation events (`REQ-AUD-01`, `REQ-AUD-04`); the
per-tenant hash-chain verify job (`REQ-AUD-06`); the live SSE debug console
(`REQ-AUD-08`); syslog on the operator's collector (`REQ-AUD-07`); build-time
advisory and suspicious-code scans (`REQ-SUP-02`, `REQ-SUP-03`); the CVD intake
address (`REQ-CRA-04`); an operator's own report. Detection by an operator is
the most common route for a deployed instance, which is why their escalation
path to us is written into the contract, not improvised.

## The process

1. **Detect and raise.** Anyone may raise. Nobody is criticised for raising a
   non-incident; the failure mode this process fears is silence.
2. **Declare.** Commander assigns severity, opens the record, names a scribe,
   and starts the timeline with the awareness timestamp in UTC and
   `Europe/Stockholm` (`REQ-TIM-03`). **This timestamp starts every clock.**
3. **Assess the triggers, in parallel with the response.** Reporting officer
   walks the decision tree in `compliance/cra/reporting-runbook.md`, and asks
   the two further questions: is an operator's essential service significantly
   disrupted (their Art. 15 clock), and is personal data involved (a 72 h GDPR
   clock)?
4. **Contain.** Revoke sessions (`REQ-AUT-10`); revoke API keys
   (`REQ-API-07`); disable an affected auth method at the global tier
   (`REQ-AUT-04`); rotate the KEK (`REQ-SEC-06`); block an egress destination
   (`REQ-SEC-12`); take the service read-only or offline. Every containment step
   is an audited action, and containment never edits the audit trail — it is
   append-only by database privilege (`REQ-AUD-03`).
5. **Notify.** Per the matrix below. Notification runs **concurrently** with
   the technical work, never after it.
6. **Eradicate and fix.** Through `compliance/cra/vulnerability-handling.md`:
   failing test first, fix inside the owned path, both critics and both security
   reviewers, no self-approval (`REQ-GAT-01`, `REQ-GAT-07`).
7. **Recover.** Restore per `compliance/cer/resilience-plan.md` if data was lost
   or corrupted, including the full smoke test. Verify the hash chain before
   declaring recovery.
8. **Review.** Post-incident review within 10 business days for Sev-1 and
   Sev-2, written, blameless, and producing either a new requirement ID or an
   amendment to an existing one. A review whose only output is "be more careful"
   has not happened.

## Notification matrix

| Who | Notified by | When | Content |
|---|---|---|---|
| Affected deploying operators | Reporting officer | Sev-1 immediately, Sev-2 within 4 h | Facts they need to start their own Art. 15 clock, and the interim mitigation |
| ENISA + coordinator CSIRT | Reporting officer | ≤ 24 h from awareness where a CRA trigger is met | `compliance/cra/reporting-runbook.md` |
| All users of affected versions | Reporting officer | Without undue delay (CRA Art. 14(8)) | Affected versions, action now, fix timing |
| Tenant administrators inside a deployment | Operator | Operator's judgement | Operator's own comms |
| Competent authority under CER | **Operator** | ≤ 24 h, then 1 month | Ours to support with facts, never to file |
| Data protection supervisory authority | Controller (normally the operator) | ≤ 72 h if personal data is breached | Flagged at declaration so it is not discovered late |
| The reporter, if the incident came from a CVD report | Security point of contact | With each status change | Per `compliance/cra/cvd-policy.md` |

## Communication templates

### Internal declaration (opens the record)

```
INCIDENT <<PLACEHOLDER: id>>  —  SEV <<PLACEHOLDER: 1-4>>
Declared:            <<PLACEHOLDER: YYYY-MM-DD HH:mm:ss UTC>> by <<PLACEHOLDER: name>>
Awareness timestamp: <<PLACEHOLDER: YYYY-MM-DD HH:mm:ss UTC>>  ← all clocks run from here
What we know:        <<PLACEHOLDER: facts only>>
What we do not know: <<PLACEHOLDER: the open questions>>
Affected:            <<PLACEHOLDER: versions, tenants, operators>>
Commander:           <<PLACEHOLDER>>   Scribe: <<PLACEHOLDER>>
Clocks:  CRA Art.14 [ ] running / [ ] assessed not applicable — reason: <<PLACEHOLDER>>
         CER Art.15 [ ] operator notified at <<PLACEHOLDER>> / [ ] not applicable
         GDPR 72h   [ ] personal data involved / [ ] not
Next update due:     <<PLACEHOLDER: HH:mm UTC — every 60 min for Sev-1>>
```

### Operator notification (Sev-1 / Sev-2)

```
Subject: Security incident affecting <<PLACEHOLDER: product>> <<PLACEHOLDER: versions>> — action required

What happened:     <<PLACEHOLDER: two or three sentences, no hedging>>
When we became aware: <<PLACEHOLDER: YYYY-MM-DD HH:mm UTC>>
Affected versions: <<PLACEHOLDER>>
Are you affected:  <<PLACEHOLDER: how the operator checks their own deployment>>
What to do now:    <<PLACEHOLDER: numbered steps, most important first>>
Interim mitigation: <<PLACEHOLDER: or "none available">>
Fix:               <<PLACEHOLDER: version and expected date, or "in development">>
Your own obligations: If you are a designated critical entity, this may be a
  notifiable incident under Art. 15 of Directive (EU) 2022/2557 — initial
  notification within 24 hours of your awareness. We are sending this so your
  clock starts with our facts, not without them.
Our regulatory filing: <<PLACEHOLDER: filed / assessed not applicable>>
Contact:           <<PLACEHOLDER: reporting officer, direct phone and email>>
Next update:       <<PLACEHOLDER: date and time>>
```

### Status update (while open)

```
INCIDENT <<PLACEHOLDER: id>> — update <<PLACEHOLDER: n>> at <<PLACEHOLDER: UTC>>
Current status:  [ ] investigating  [ ] contained  [ ] fix in progress  [ ] resolved
Since last update: <<PLACEHOLDER>>
Changed conclusions: <<PLACEHOLDER: state corrections explicitly>>
Still unknown:   <<PLACEHOLDER>>
Next update:     <<PLACEHOLDER: UTC>>
```

### Post-incident review

```
INCIDENT <<PLACEHOLDER: id>> — post-incident review
Timeline:          <<PLACEHOLDER: awareness → declaration → containment →
                   notification → fix → recovery, timestamps in UTC>>
Impact:            <<PLACEHOLDER: tenants, records, duration, data loss>>
Root cause:        <<PLACEHOLDER: technical cause, not a person>>
Why detection took as long as it did: <<PLACEHOLDER>>
Deadlines met:     <<PLACEHOLDER: each filing, due vs sent>>
What worked:       <<PLACEHOLDER>>
Changes made:      <<PLACEHOLDER: control added or amended, with its REQ ID and
                   the owning agent>>
New or amended requirement: <<PLACEHOLDER: REQ ID. Requirement IDs are
                   permanent; a changed requirement gets a new ID>>
Review owner and date: <<PLACEHOLDER>>
```

## Personnel security and access control (REQ-CER-07)

This covers **manufacturer staff with access to the product, its build pipeline
or an operator's deployment**. Operator staff are the operator's, including any
background checks its Member State provides for under Art. 14 of the Directive
(`compliance/cer/applicability.md` §The split table).

### Background-check posture

| Role category | Check | Cadence |
|---|---|---|
| Any access to source or the build pipeline | `<<PLACEHOLDER: identity verification, right-to-work, reference checks>>` | On joining |
| Production or operator-deployment access, KEK custody, release signing | `<<PLACEHOLDER: the enhanced check performed, within what the law of the jurisdiction permits>>` | On joining and every `<<PLACEHOLDER: months>>` |
| Contractors and subcontractors | Same check as the equivalent employee role, evidenced by the supplier | On joining, and re-evidenced annually |
| Sensitive-role designation | `<<PLACEHOLDER: which roles are designated sensitive, and who decides>>` | Reviewed annually |

State honestly what is and is not done. An unverifiable claim of vetting is
worse than a stated limitation: a reviewer can plan around a limitation.

### Joiner / mover / leaver

| Event | Action | Deadline | Evidence |
|---|---|---|---|
| **Joiner** | Named role assigned; least-privilege grants only; MFA enrolled before first access (`REQ-AUT-05`); recovery codes issued and acknowledged (`REQ-AUT-06`) | Before first access | Role-change audit event with a before/after diff (`REQ-RBA-08`) |
| **Mover** | Old grants **removed** before new ones are added. Accumulated privilege is the most common finding in an access review | Same day as the move | Audit diff showing removal, not just addition |
| **Leaver** | All sessions killed (`REQ-AUT-10`); API keys revoked (`REQ-API-07`); OIDC account disabled at the IdP; passkeys unlinked; role grants removed; KEK custody transferred if held; release-signing identity revoked | **Same business day**; immediately on an involuntary departure | Audit events per revocation, plus a completed checklist at `<<PLACEHOLDER: checklist location>>` |
| **Any departure of a named role in this document set** | Update the named roles here, in `compliance/cra/reporting-runbook.md`, in `compliance/cra/cvd-policy.md`, in `SECURITY.md` and in `/.well-known/security.txt` | Same week | A document naming someone who left is a broken control |

### Privileged-access review

| Review | Scope | Cadence | Owner |
|---|---|---|---|
| Global-tier membership | Everyone holding a global-tier permission (`REQ-RBA-06`) | **Quarterly** | `<<PLACEHOLDER: named role>>` |
| Impersonation and tenant-entry use | Every entry/exit audit event, with reason and duration (`REQ-RBA-07`) | **Monthly** | `<<PLACEHOLDER>>` |
| High-risk permission grants | Hard delete, see-deleted, debug console, audit purge, KEK rotation | Quarterly | `<<PLACEHOLDER>>` |
| API keys | Owner of record, scopes, expiry, last-used; revoke anything unused for `<<PLACEHOLDER: days>>` (`REQ-API-07`) | Quarterly | `<<PLACEHOLDER>>` |
| Role and permission changes | The versioned before/after diffs since the last review (`REQ-RBA-08`) | Quarterly | `<<PLACEHOLDER>>` |
| Manufacturer access to operator deployments | Who has it, why, and whether it is still needed | Quarterly, and after every incident | `<<PLACEHOLDER>>` |

Each review records: date, reviewer, accounts examined, grants removed, and
exceptions accepted with an expiry date. A review with no removals over several
cycles is usually evidence that the review is not happening, not that the
estate is clean.

| Field | Value |
|---|---|
| Last privileged-access review | `<<PLACEHOLDER: YYYY-MM-DD>>` |
| Grants removed | `<<PLACEHOLDER: count>>` |
| **Next review due** | `<<PLACEHOLDER: YYYY-MM-DD>>` |

### Awareness (Art. 13(1)(f))

Everyone in a named role above rehearses the CRA reporting runbook at least
annually (`compliance/cra/reporting-runbook.md` §Rehearsal record) and reads
this file on joining. Training record:
`<<PLACEHOLDER: where attendance is recorded>>`.

## Sources

- [Directive (EU) 2022/2557](https://eur-lex.europa.eu/eli/dir/2022/2557/oj) — Art. 14 (background checks), Art. 15 (24-hour initial notification, one-month detailed report)
- [Regulation (EU) 2024/2847, Article 14](https://eur-lex.europa.eu/eli/reg/2024/2847/oj) — manufacturer reporting
