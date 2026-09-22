# CRA Reporting Runbook

**This obligation is in force.** Regulation (EU) 2024/2847 Article 14 —
vulnerability and incident reporting — applies from **11 September 2026**, and
ENISA's Single Reporting Platform went live the same day. Today is 2026-09-22, so
this is not preparation for a future deadline; it is a rehearsed procedure that
must work now (REQ-CRA-06).

Confirmed externally 2026-09-22:
<https://www.freshfields.com/en/our-thinking/blogs/technology-quotient/cyber-resilience-act-reporting-obligations-take-effect-on-11-september-2026-102nzmk>,
<https://www.crowell.com/en/insights/client-alerts/its-live-the-cyber-resilience-act-reporting-is-mandatory-as-of-today-11-september-2026>,
<https://digital-strategy.ec.europa.eu/en/policies/cra-reporting>,
<https://www.hlc.com/en/publications/eu-cyber-resilience-act-vulnerability-and-incident-reporting-obligations-now-apply>.
The CRA's remaining obligations, including CE marking and the full Annex I set,
apply from 11 December 2027 —
<https://digital-strategy.ec.europa.eu/en/policies/cra-summary>.

Owner: `B13`. The remediation process this runs alongside is
`compliance/cra/vulnerability-handling.md`. One incident, two outputs: a fix and
a report.

## 1. Triggers

Two triggers, defined so that the on-call person does not have to interpret them
at 02:00.

**Trigger A — actively exploited vulnerability in our product.** A vulnerability
in the product for which there is any credible indication that it is being
exploited. Credible indication includes: a report describing exploitation in the
wild; exploitation observed in logs or a customer environment; a public exploit
being used against deployed instances; a third-party advisory stating the
vulnerability is exploited.

Not a trigger by itself: a high CVSS score, a proof-of-concept with no evidence
of use, a vulnerability in a dependency we do not compile in (check the SBOM —
REQ-SBM-01).

**Trigger B — severe incident having an impact on the security of the product.**
An incident that affects the product's security or the security of its users.
For this product the realistic shapes are:

- compromise of the **code-signing** credential or of the release pipeline
  (`spec/release.md` §4);
- compromise of the **update signing** key, or a signed manifest we did not
  publish appearing on either forge;
- a malicious artefact served from a release URL;
- a compromised dependency shipped in a release (`B11` pass 2 —
  `spec/supply-chain.md` §3).

**When in doubt, report.** A report that turns out to be unnecessary costs an
hour. A missed 24-hour window is a breach of an obligation that is already in
force. The Security Lead decides, and "we were not sure" is not a decision.

## 2. Roles

| Role | Holder | Responsibility |
|------|--------|----------------|
| Security Lead | `<<PLACEHOLDER: name, role, contact>>` | Declares the trigger, owns the report, signs off every submission |
| Deputy Security Lead | `<<PLACEHOLDER: name, role, contact>>` | Same authority when the Lead is unreachable within 1 hour. The deputy exists because a 24-hour clock does not pause for annual leave |
| Engineering Owner | `<<PLACEHOLDER: name>>` | Technical facts: affected versions, mechanism, mitigation, fix |
| Supply-Chain Owner | `<<PLACEHOLDER: name>>` | SBOM and dependency questions (`B11`'s outputs) |
| Comms Owner | `<<PLACEHOLDER: name>>` | User notification and the advisory (Annex I Part II point 4) |
| Reporting Contact | `<<PLACEHOLDER: name + Single Reporting Platform account holder>>` | Submits to the platform. The account must exist and be tested **before** an incident |

The platform account is the part most likely to be missing when it is needed.
Registering during an incident is how a 24-hour window is spent on a password
reset.

## 3. The timeline

| Stage | Deadline | Goes to | Contents |
|-------|----------|---------|----------|
| **Early warning** | **Within 24 hours** of becoming aware | The CSIRT designated as coordinator **and** ENISA, via the Single Reporting Platform | That it happened; whether exploitation is suspected; the Member States where the product is made available, as known at that point |
| **Notification** | Within 72 hours of becoming aware | Same | General information on the product, the nature of the vulnerability or incident, severity and impact, corrective or mitigating measures taken and available to users |
| **Final report** | For an actively exploited vulnerability: **no later than 14 days** after a corrective or mitigating measure is available. For a severe incident: **within one month** of the notification | Same | A description including severity and impact; where available, the actor; the applied and planned mitigations; the remediation |

"Becoming aware" starts the clock — not triage completion, not confirmation of
severity, not the fix. The intake timestamp in
`security/supply-chain/advisory-report.json` is the evidence of when awareness
began, which is why that field is mandatory
(`compliance/cra/vulnerability-handling.md` §6).

The deadlines above are reported consistently by the sources cited at the top of
this file. `unconfirmed`: the exact wording of Article 14's paragraphs, because
`eur-lex.europa.eu` was unreachable from the build container. **Check:** the
Reporting Contact reads Article 14 from the Official Journal, confirms the final
report deadlines, and records the confirmation date in §6 below.

## 4. Routing

One submission reaches both recipients: the Single Reporting Platform notifies
the CSIRT designated as coordinator and ENISA. Do not send two uncoordinated
reports; do not treat a national portal as a substitute without checking.

| Item | Value |
|------|-------|
| Platform | ENISA Single Reporting Platform (live since 11 September 2026) |
| Platform URL | `<<PLACEHOLDER: Single Reporting Platform URL, confirmed at registration>>` |
| Account holder | `<<PLACEHOLDER: Reporting Contact account identifier>>` |
| CSIRT designated as coordinator | `<<PLACEHOLDER: the CSIRT of the Member State of our main establishment in the EU>>` |
| Main establishment / Member State | `<<PLACEHOLDER: legal entity and Member State>>` |
| Fallback | `<<PLACEHOLDER: CSIRT direct contact for use if the platform is unavailable — and record the platform failure>>` |

If the platform is unavailable, report through the fallback contact **within the
same deadline** and record the platform's unavailability with timestamps. The
obligation is to report, not to have tried the platform.

Users are notified in parallel where the vulnerability or incident affects them,
with the advisory and, where available, the corrective measure
(`compliance/cra/vulnerability-handling.md` §5). The report to authorities and
the notice to users are separate obligations; neither satisfies the other.

## 5. Running it

1. Anyone who sees a possible trigger tells the Security Lead directly. No
   triage queue in front of this step.
2. The Lead declares Trigger A or B, or records a decision not to, with a reason,
   in the evidence log. A non-declaration is a logged decision.
3. Start the clock from the **awareness** timestamp and write it down before
   anything else.
4. The Engineering Owner establishes affected versions from the SBOM and the
   embedded dependency list (REQ-SBM-02) — from artefacts, not recollection.
5. The Reporting Contact submits the early warning. Incomplete but on time beats
   complete and late; the notification at 72 hours is where detail belongs.
6. Remediation runs in parallel on its own targets
   (`compliance/cra/vulnerability-handling.md` §3).
7. Submit the notification at 72 hours, then the final report at its deadline.
8. Close the log with the submission references and a short retrospective.

## 6. Evidence log, per report

One entry per report, `<<PLACEHOLDER: evidence log path, e.g. a records
repository outside this codebase>>`. This log is the evidence that the obligation
was met; a submission with no record of its timing is unverifiable.

| Field | Value |
|-------|-------|
| Internal id | Matches the vulnerability record id |
| Trigger | A or B, with the declaring role and timestamp |
| Awareness timestamp (UTC) | When the clock started |
| Early warning submitted (UTC) | Timestamp + platform reference |
| Notification submitted (UTC) | Timestamp + platform reference |
| Final report submitted (UTC) | Timestamp + platform reference |
| Recipients | CSIRT coordinator + ENISA, or fallback with the reason |
| Affected versions | From SBOM / embedded list |
| User notification | Channel and timestamp |
| Deadline met | Yes / No per stage, and if no, why |
| Article 14 wording confirmed against the Official Journal | Date + who |

## 7. Rehearsal

The runbook is rehearsed, not merely written (REQ-CRA-06). Until a rehearsal is
logged, the obligations matrix marks this row **weak** (REQ-CRA-10).

| Rehearsal | Date | Scenario | Result | Gaps found | Next due |
|-----------|------|----------|--------|-----------|----------|
| 1 | `<<PLACEHOLDER: date>>` | Update signing key compromise (Trigger B) | `<<PLACEHOLDER: result>>` | `<<PLACEHOLDER>>` | `<<PLACEHOLDER: +12 months>>` |
| 2 | `<<PLACEHOLDER: date>>` | Exploited vulnerability in a shipped dependency (Trigger A) | `<<PLACEHOLDER: result>>` | `<<PLACEHOLDER>>` | `<<PLACEHOLDER: +12 months>>` |

A rehearsal passes only if a draft early warning was produced within 24 hours of
the simulated awareness timestamp **using the real platform account**, and the
deputy was exercised in at least one rehearsal per year. Aligned with the CER
incident-response rehearsal in `compliance/cer/resilience.md` §5 so one exercise
produces both records.
