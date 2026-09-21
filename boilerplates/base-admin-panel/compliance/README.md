# EU Regulatory Compliance — CRA and CER

Owner: **A18 `compliance-cra-cer`** (`spec/agents.md`, Wave 4).
Owned paths: `compliance/**` and nothing else (`contracts/ownership.md`).
Requirements covered: `REQ-CRA-01` … `REQ-CRA-10`, `REQ-CER-01` … `REQ-CER-09`.

## Disclaimer — read this first

This directory is **documentation scaffolding and evidence structure. It is not
legal advice.** Conformity is determined by a notified body, a market
surveillance authority or a competent authority — never by this repository, never
by a generator in it, and never by an agent that wrote a file in it. Every
statement below describes what the product does and where the proof lives. It
does not assert that any regulator has accepted that proof.

A release that ships with an unresolved `<<PLACEHOLDER: …>>` marker in this
directory is not a conforming release. The markers exist so a value cannot be
invented by accident.

## The two regimes, and who is obligated under each

| | CRA — Regulation (EU) 2024/2847 | CER — Directive (EU) 2022/2557 |
|---|---|---|
| What it regulates | Products with digital elements placed on the EU market | Critical entities providing essential services in 11 sectors |
| What this product is | **A product with digital elements.** The obligations bite. | **Not a critical entity.** A supplier artefact a critical entity may deploy. |
| Obligated party | Whoever **places the product on the market** — the manufacturer, which for a generated instance is the party that builds, brands and ships it | The **deploying operator** (the critical entity), supervised by its Member State competent authority |
| This repository's role | Produce the Annex I evidence, the vulnerability-handling process, the reporting runbook, and the Annex II/V/VII templates the manufacturer completes | Produce the supplier-side documentation the operator folds into **its** resilience plan and risk assessment |
| Where it lives | `compliance/cra/` | `compliance/cer/` |

The boilerplate itself places nothing on the market. The generated instance does.
So `compliance/cra/` is written as the manufacturer's working set, to be completed
at release by whoever signs the declaration of conformity (`REQ-CRA-09`).

`compliance/cer/` is written the other way round: it is a supplier pack. It never
claims the product satisfies an operator's obligation. Where a control is the
operator's, `compliance/cer/applicability.md` says so in the split table, and
`REQ-CER-08` puts physical and environmental controls squarely on the operator.

## CRA date posture

| Milestone | Date | Status today (2026-09-21) |
|---|---|---|
| Entry into force | 10 December 2024 | past |
| Article 14 reporting obligations apply; ENISA Single Reporting Platform live | **11 September 2026** | **IN FORCE — 10 days** |
| Full application: CE marking, Annex I essential requirements, conformity assessment | **11 December 2027** | 1 year, 2 months, 20 days away |

Sources: [Regulation (EU) 2024/2847](https://eur-lex.europa.eu/eli/reg/2024/2847/oj),
[Commission — CRA reporting obligations](https://digital-strategy.ec.europa.eu/en/policies/cra-reporting),
[ENISA — the CRA Single Reporting Platform is launched](https://www.enisa.europa.eu/news/the-cra-single-reporting-platform-is-launched).

What this means in practice, and it is the single most important line in this
file: **the reporting duty is live and the CE-marking duty is not.** A release
today must be able to file a 24-hour early warning (`REQ-CRA-06`,
`compliance/cra/reporting-runbook.md`). It does not yet need a completed EU
declaration of conformity — but the Annex V and Annex VII skeletons are
maintained now (`REQ-CRA-09`) because completing them for the first time under
deadline is how a conformity file ends up fabricated.

## Evidence is generated, not written (REQ-CRA-10)

Hand-written compliance prose drifts from the product within one release. So the
rule here is: **a document states a control and points at an artefact; the
artefact is produced by the build.**

| Evidence artefact | Produced by | Path | Requirement |
|---|---|---|---|
| CycloneDX SBOM, per build, retained per release | A19 | `security/supply-chain/sbom/<version>.cdx.json` | `REQ-CRA-03`, `REQ-SUP-01` |
| Advisory scan result (build-blocking) | A19 | `security/supply-chain/advisories/<version>.json` | `REQ-SUP-02` |
| First-party suspicious-code scan | A19 | `security/supply-chain/suspicious-code/<version>.json` | `REQ-SUP-03` |
| Externally validated version manifest with source URLs and check timestamps | A20 | `versions/manifest.json` | `REQ-VER-02`, `REQ-VER-03` |
| Documented egress surface | A01 | `docker/egress.md` | `REQ-SUP-08` |
| Env schema — the machine-readable statement of every security-relevant default | A01 | `packages/config/**` | `REQ-FND-07`, `REQ-CRA-02` |
| Structured per-REQ gate verdicts (design, function, security) | C1, C2, S1, S2 | `build/gates/<gate>/<reviewer>-<dimension>-r<round>.json` | `REQ-GAT-04` |
| Test results proving isolation, MFA enforcement, permission denial, audit emission | A23 | `tests/**` | `REQ-TST-05`, `REQ-TST-08` |
| Architecture views drawn from the code | A17 | `docs/architecture/**` | `REQ-DOC-06`, `REQ-DOC-08` |
| Supported versions, CVD policy, contact, CRA posture | A22 | `SECURITY.md` | `REQ-CRA-04`, `REQ-REL-05` |
| Release record with REQ IDs per change | A22 | `CHANGELOG.md`, `VERSION` | `REQ-REL-02`, `REQ-REL-03` |

The collector that assembles these into a per-release evidence bundle is
A18-owned and belongs at `compliance/tools/collect-evidence.ts`, writing
`compliance/generated/<version>/evidence-manifest.json`. **It is not present in
this scaffold yet.** Until it is, the "generated" claim in `REQ-CRA-10` is
satisfied only by the upstream artefacts above being build outputs; the bundling
step is manual. That gap is stated here rather than papered over.

## Where each artefact lives

```
compliance/
  README.md                       this file — the compliance model
  cra/
    obligations-matrix.md         Annex I Part I + Part II, row by row   REQ-CRA-01
    secure-by-default.md          shipped defaults and how to weaken them REQ-CRA-02
    vulnerability-handling.md     intake, triage SLA, remediation, SBOM  REQ-CRA-03/05/07
    reporting-runbook.md          Article 14, live since 11 Sep 2026     REQ-CRA-06
    cvd-policy.md                 publishable CVD policy + security.txt  REQ-CRA-04
    technical-documentation.md    Annex II / V / VII skeletons           REQ-CRA-08/09
  cer/
    applicability.md              who is obligated; product/operator split REQ-CER-01/08
    criticality-assessment.md     dependencies and failure modes         REQ-CER-02/09
    resilience-plan.md            RTO/RPO, restore rehearsal, degraded mode REQ-CER-03/04/05
    incident-response.md          one incident process, two outputs      REQ-CER-06/07
```

## The one process rule

There is **one** incident process. `compliance/cer/incident-response.md` defines
the roles, severities and escalation paths. `compliance/cra/reporting-runbook.md`
defines what leaves the building and when. A severe incident under CRA Article 14
and a significant disruption under CER Article 15 can be the same event with two
reporting outputs and two clocks. Two parallel processes would produce two
inconsistent reports on the same facts, which is worse than a late one.
