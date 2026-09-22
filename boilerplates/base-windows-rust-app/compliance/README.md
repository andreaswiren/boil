# Compliance

Owner: `B13 compliance-cra-cer` (`contracts/ownership.md`). This directory is the
evidence structure for two EU regimes:

- **CRA** — Regulation (EU) 2024/2847, the Cyber Resilience Act.
- **CER** — Directive (EU) 2022/2557, the Critical Entities Resilience Directive.

Requirements: REQ-CRA-01..10, REQ-CER-01..07.

## This is evidence structure, not legal advice

Nothing here is legal advice, and nothing here declares conformity. A **notified
body** or a **competent authority** determines conformity — not this repository,
not the pipeline, and not the agent that wrote these files.

What this directory does is narrower and more useful: it maps each obligation to
the control that addresses it, the requirement ID that implements the control,
and the **path of the artefact that evidences it**. An auditor can check a path.
An auditor cannot check an assurance.

Every legal value that a human must supply — the manufacturer's legal identity,
the security contact, the PGP fingerprint, the national CSIRT routing, the
end-of-support date — is written as `<<PLACEHOLDER: …>>`. A release does not ship
with a placeholder in a declaration of conformity, and a placeholder is how that
stop is made visible. An invented legal value would ship.

## Who is obligated, under each regime

| Regime | Obligated party | This product's position |
|--------|----------------|------------------------|
| CRA | The **manufacturer** of the product with digital elements | We are the manufacturer. The product is a shipped binary **placed on the market**, so Annex I Part I and Part II and CE marking apply **directly**, not by analogy (REQ-CRA-01). |
| CER | The **critical entity** — the operator designated by a Member State | The product is a **supplier artefact and never itself a critical entity** (REQ-CER-01). Our obligation is to give a deploying operator what its own resilience obligations need. |

That split decides how each document reads. Under the CRA, an unmet Annex I point
is our defect. Under the CER, most controls belong to the operator — endpoint
management, patching policy, physical security, the resilience plan itself
(REQ-CER-06) — and `compliance/cer/resilience.md` says which are ours and which
are theirs. Claiming an operator control as satisfied by the product is worse
than leaving a gap, because it stops someone looking.

## The CRA date posture

Confirmed externally on 2026-09-22 (REQ-VER-02 discipline applies to dates as
well as versions: never from memory, always with a source):

| Date | What applies | Status today (2026-09-22) |
|------|-------------|---------------------------|
| 10 December 2024 | CRA entered into force | In force |
| **11 September 2026** | **Vulnerability and incident reporting obligations (Article 14): actively exploited vulnerabilities and severe incidents, via ENISA's Single Reporting Platform** | **Already in force — this is operational now** |
| 11 December 2027 | Full application: CE marking, conformity assessment, all Annex I essential requirements | Not yet applicable; preparation is in scope now |

Sources:

- Reporting obligations live from 11 September 2026, ENISA Single Reporting
  Platform operational the same day, early warning within 24 hours, full
  notification within 72 hours, final report thereafter —
  <https://www.freshfields.com/en/our-thinking/blogs/technology-quotient/cyber-resilience-act-reporting-obligations-take-effect-on-11-september-2026-102nzmk>,
  <https://www.crowell.com/en/insights/client-alerts/its-live-the-cyber-resilience-act-reporting-is-mandatory-as-of-today-11-september-2026>,
  <https://digital-strategy.ec.europa.eu/en/policies/cra-reporting>
- Full application 11 December 2027, CE marking incorporating cybersecurity —
  <https://digital-strategy.ec.europa.eu/en/policies/cra-summary>,
  <https://www.cyberresilienceact.eu/explained.html>

So the posture is two-speed, and the documents are ordered accordingly:
`compliance/cra/reporting-runbook.md` describes an obligation that is **live**
and must be rehearsed, while `compliance/cra/obligations-matrix.md` describes the
Annex I set we must be able to demonstrate by **11 December 2027**.

`unconfirmed`: `eur-lex.europa.eu`, `digital-strategy.ec.europa.eu` and
`enisa.europa.eu` were unreachable from the build container (egress policy
denial), so the Article and Annex point **lettering** used in the matrix comes
from secondary sources rather than the Official Journal. **Check:** `B13` reads
Annex I from the Official Journal text and corrects the lettering before an EU
declaration of conformity is signed.

## The updater is a compliance control

The auto-updater is the **mechanism by which the security-update obligation is
satisfied**. Annex I Part II requires that vulnerabilities be remediated without
delay, that security updates be distributed securely, and — where technically
feasible — separately from functionality updates.

That is `crates/update`, and it makes REQ-UPD-02's signature verification a
**compliance control as well as a security one** (REQ-CRA-07, REQ-UPD-13). An
updater that distributes a fix without verifying a signature does not merely have
a security defect; it fails the obligation it exists to satisfy, because an
unverified distribution channel is not a secure distribution channel.

## The files

| File | What it holds | REQ |
|------|--------------|-----|
| `cra/obligations-matrix.md` | Annex I Part I and Part II, row per obligation: control, REQ IDs, evidence path, owning agent, evidence strength | REQ-CRA-01, REQ-CRA-10 |
| `cra/vulnerability-handling.md` | Intake, triage SLA by severity, remediation targets, and how a security fix is distributed separately from features | REQ-CRA-05, REQ-CRA-07 |
| `cra/reporting-runbook.md` | The live obligation: triggers, named roles, 24h/72h/final timeline, ENISA + national CSIRT routing, per-report evidence log | REQ-CRA-06 |
| `cra/cvd-policy.md` | The publishable disclosure policy and an RFC 9116 `security.txt` template | REQ-CRA-04, REQ-SEC-10 |
| `cer/resilience.md` | Applicability, dependency assessment, degraded modes, recovery with RTO/RPO and a rehearsal log, incident response, control split, four-yearly cadence | REQ-CER-01..07 |

Annex II user information, the Annex V EU declaration of conformity and the
Annex VII technical documentation are templates completed at release
(REQ-CRA-09). They are generated at H8 from the same evidence index, and until
they are generated their values are placeholders.

## Evidence strength, and why it is marked

REQ-CRA-10 requires compliance documentation generated from repository state
rather than written by hand, so that it cannot drift from the product. Every
matrix row therefore carries a strength marker:

| Marker | Meaning |
|--------|---------|
| `build-output` | The evidence is a file the build produces — an SBOM, an advisory report, a signature verification log. Strongest. |
| `test-asserted` | A named test asserts the property and fails the build otherwise. |
| `prose` — **weak** | The evidence is this documentation describing an intention. **Marked weak on purpose.** |
| `pending` | The cited evidence path does not exist yet. A finding routed to the owning agent, not a compliance-text problem. |

A `prose` row is a gap with a name. Presenting one as satisfied would be the
exact drift REQ-CRA-10 exists to prevent, and it is the easiest thing in a
compliance document to get away with, which is why the marker is mandatory.

## Reading order

1. This file — the model and who is obligated.
2. `cra/reporting-runbook.md` — the obligation that is live today.
3. `cra/obligations-matrix.md` — the Annex I set and where it is weak.
4. `cra/vulnerability-handling.md` and `cra/cvd-policy.md` — the process behind
   the runbook.
5. `cer/resilience.md` — what a deploying operator needs from us.
