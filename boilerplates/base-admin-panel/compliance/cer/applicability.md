# CER Applicability — Who Is Obligated, and Who Owns Which Control

Requirements: `REQ-CER-01` (resilience posture as a supplier artefact), `REQ-CER-08` (physical and environmental assumptions stated explicitly).
Directive: [Directive (EU) 2022/2557](https://eur-lex.europa.eu/eli/dir/2022/2557/oj) on the resilience of critical entities. In force since January 2023.
Owner: **A18**.

## The framing, stated once and not softened

**This product is not a critical entity.** The CER Directive obligates
*entities*, designated by a Member State, that provide an essential service in
one of eleven sectors. Software is not designated. An operator is.

What this product can be is a **supplier artefact**: a component a designated
critical entity deploys in support of an essential service. That makes the CER
documentation in this directory a **supplier pack** — material the operator
folds into *its* risk assessment and *its* resilience plan. It never asserts
that the operator's obligation is met.

Two consequences, and both matter more than any control list:

1. **The product cannot satisfy an operator's obligation.** It can make it
   cheaper to satisfy, by arriving with a dependency inventory, failure modes,
   an RTO/RPO statement, degraded-mode behaviour and an incident process the
   operator can reference instead of reconstruct.
2. **Physical and environmental resilience is entirely the operator's**
   (`REQ-CER-08`). The product ships no control over power, cooling, site access
   or hardware. Where the split table below says "operator", that is not a gap
   in the product — it is the correct allocation, and pretending otherwise would
   leave a real control unowned.

## What the CER requires of the operator

| Obligation | Directive | What it means for a deployment of this product |
|---|---|---|
| Risk assessment, within 9 months of designation and **at least every four years** thereafter | Art. 12 | The panel and its dependencies appear as an asset in that assessment. Template: `compliance/cer/criticality-assessment.md` |
| Technical, security and organisational measures, described in a **resilience plan** or equivalent document | Art. 13 | Supplier-side input: `compliance/cer/resilience-plan.md` |
| Incident notification to the competent authority: **initial notification no later than 24 hours** after becoming aware, detailed report **no later than one month** thereafter | Art. 15 | The operator files. We supply the facts, fast: `compliance/cer/incident-response.md` |
| Background checks on personnel in sensitive roles, where the Member State provides for them | Art. 14 | Operator-run. Our posture: `compliance/cer/incident-response.md` §Personnel security |
| Cooperation with the competent authority, including on-site inspection | Art. 21 | The operator may be asked to evidence this product's controls. That is what this pack is for |

The Directive is minimum harmonisation: a Member State may go further, and
sector rules (financial services in particular) frequently do. The operator's
national transposition governs, not this file.

## The eleven sectors

From the Annex to Directive (EU) 2022/2557:

| # | Sector | Plausible deployment of this panel |
|---|---|---|
| 1 | Energy (electricity, district heating and cooling, oil, gas, hydrogen) | Field-asset and change administration for a grid or heating operator |
| 2 | Transport (air, rail, water, road, public transport) | Fleet, depot or signalling-estate administration |
| 3 | Banking | Internal operations administration |
| 4 | Financial market infrastructure | Internal operations administration |
| 5 | Health | Device estate, ward asset or supplier-access administration |
| 6 | Drinking water | SCADA-adjacent asset register and change history |
| 7 | Waste water | As above |
| 8 | Digital infrastructure | MSP or datacentre operations panel — the most likely deployment of all |
| 9 | Public administration | Municipal or agency internal administration |
| 10 | Space | Ground-segment operations administration |
| 11 | Production, processing and distribution of food | Plant and cold-chain administration |

Designation is per entity, not per sector: being active in a sector does not
make an entity critical. Member States identified their critical entities under
Art. 6, and an entity knows because it was notified.

## Determining whether a given deployment is in scope

The operator answers these. The product cannot.

1. Has the operator been **notified of designation** as a critical entity under
   Art. 6? If no, the CER obligations do not bite, though the operator may still
   be in scope of NIS2 — a different directive with its own reporting.
2. Which **essential service** does the operator provide? Name it.
3. Does this panel **support** that service — administratively, operationally,
   or by holding the record of the assets that deliver it? Supporting is enough;
   it need not be in the control path.
4. Would loss, corruption or compromise of this panel **disrupt or delay** the
   essential service, or the operator's ability to restore it? If yes, the panel
   belongs in the operator's risk assessment.
5. Is the operator subject to a **sectoral regime** (DORA, NIS2, a national
   transposition going beyond CER) whose requirements are stricter? Those apply
   in addition.

Recorded answer for this deployment:
`<<PLACEHOLDER: operator legal name; designated critical entity yes/no and the
notification date; Member State and competent authority; sector and sub-sector;
the essential service named; whether this panel is in scope>>`

## Supplier posture

What the manufacturer supplies to a critical-entity operator, on request and
without a separate negotiation:

| Artefact | Path | Requirement |
|---|---|---|
| Dependency and failure-mode assessment | `compliance/cer/criticality-assessment.md` | `REQ-CER-02` |
| RTO/RPO, backup and restore procedure, restore rehearsal record | `compliance/cer/resilience-plan.md` | `REQ-CER-03`, `REQ-CER-04` |
| Degraded-mode behaviour per dependency | `compliance/cer/resilience-plan.md` | `REQ-CER-05` |
| Incident process, roles, escalation and notification support | `compliance/cer/incident-response.md` | `REQ-CER-06` |
| Personnel security posture | `compliance/cer/incident-response.md` | `REQ-CER-07` |
| CRA conformity posture and Annex I mapping | `compliance/cra/obligations-matrix.md` | `REQ-CRA-01` |
| SBOM per release | `security/supply-chain/sbom/<version>.cdx.json` | `REQ-CRA-03` |
| Documented egress surface | `docker/egress.md` | `REQ-SUP-08` |
| CVD policy and security contact | `compliance/cra/cvd-policy.md`, `SECURITY.md` | `REQ-CRA-04` |

Contractual resilience and documentation terms a critical-entity operator will
push down to a supplier — notification windows, evidence rights, audit rights,
subcontractor disclosure, exit assistance — are recorded at
`<<PLACEHOLDER: path to the supplier contractual addendum, and who owns it>>`.
They are commercial commitments, not repository artefacts, and the repository
should not pretend to make them.

## The split table

`Product` means a control implemented in the shipped software and evidenced in
this repository. `Operator` means a control the deploying entity must implement;
the product neither provides nor verifies it.

| Control | Product's responsibility | Operator's responsibility |
|---|---|---|
| Physical site access to the host | **None** | All of it: access control, visitor handling, logging, CCTV, locked racks (`REQ-CER-08`) |
| Power, UPS, generator, cooling, fire suppression | **None** | All of it |
| Hardware procurement, maintenance, disposal, media sanitisation | **None** | All of it |
| Network perimeter, firewalling, DDoS protection, segmentation | Minimal egress surface and one allowlisted egress client (`REQ-SEC-12`, `REQ-SUP-08`) | The perimeter itself, upstream scrubbing, and what may reach the stack |
| Host OS and container-runtime patching | Images pinned by digest and reproducible; security releases published (`REQ-FND-09`, `REQ-CRA-07`) | Applying them, and patching everything below the container |
| TLS certificates and the trust anchor in production | Refuses to start without `sslmode=verify-full` and a pinned CA (`REQ-SEC-03`); ships a **dev** CA only | Production CA, issuance, renewal, revocation, and rotation before expiry |
| Transport encryption everywhere | Enforced in code on every interface, compose network included (`REQ-SEC-01`, `REQ-SEC-02`, `REQ-SEC-04`, `REQ-SEC-05`) | Not weakening it, and terminating TLS no further out than intended |
| Encryption at rest of sensitive columns | Envelope encryption with a rotatable KEK (`REQ-SEC-06`) | KEK custody, its backup, and its separation from the data backup — see `compliance/cer/resilience-plan.md` |
| Full-disk / volume encryption | **None** | Operator's, on the host and on backup media |
| Authentication and MFA | Password+TOTP, passkeys, OIDC; MFA required by default (`REQ-AUT-01`..`REQ-AUT-05`) | Identity provider availability, its own resilience, and its joiner/mover/leaver process |
| Authorisation and tenant isolation | Deny-by-default RBAC, RLS `FORCE`d, proven by test (`REQ-RBA-02`, `REQ-RBA-04`, `REQ-RBA-05`) | Role assignment, least privilege in practice, and periodic access review |
| Audit trail | Append-only, hash-chained, redacted, read-logging included (`REQ-AUD-01`..`REQ-AUD-06`) | Retention beyond the app, off-host collection, and reviewing it |
| Log collection and monitoring | RFC 5425 TLS syslog with local spooling and backpressure (`REQ-AUD-07`) | The collector, its capacity, its resilience, alerting, and who reads the alerts |
| Backups | A documented procedure that meets the stated RTO/RPO (`REQ-CER-03`) | **Running it**, storing copies off-host, testing restores, and holding the retention |
| Restore rehearsal | The procedure and the log template (`REQ-CER-04`) | Performing the rehearsal and recording date and result |
| Capacity and scaling | Server-side pagination above a declared threshold, guarded `all`, rate limits (`REQ-GRD-11`, `REQ-GRD-12`, `REQ-SEC-11`) | Provisioning, headroom, and DB sizing |
| Availability target | Degraded-mode behaviour per dependency (`REQ-CER-05`) | The SLA to its own users, redundancy, and failover |
| Personnel vetting of operator staff | **None** | All of it (`REQ-CER-07`, Art. 14) |
| Personnel vetting of manufacturer staff with product access | Documented posture (`compliance/cer/incident-response.md`) | Verifying it contractually |
| CER Art. 15 notification to the competent authority | Supplies the facts immediately, aligned to the CRA runbook | **Files it** — within 24 hours, then the one-month detailed report |
| CRA Art. 14 notification to ENISA and the CSIRT | **Files it** as manufacturer (`compliance/cra/reporting-runbook.md`) | Cooperates, supplies deployment-side evidence |
| Business continuity of the operator's essential service | Nothing. The panel is one asset in it | All of it |

## Physical and environmental assumptions, stated explicitly (REQ-CER-08)

The product assumes all of the following and verifies none of it. If an
assumption is false, the resilience claims in
`compliance/cer/resilience-plan.md` do not hold and the operator's risk
assessment must say so.

1. The host runs in a facility with controlled physical access; console access
   equals full compromise of the data at rest.
2. Power and cooling are conditioned and monitored; unplanned power loss is
   survivable only to the extent the documented RPO allows.
3. Storage is redundant at the block level; the product treats a corrupt volume
   as an unrecoverable event and falls back to restore-from-backup.
4. Backups are written to media **separate from the host**, and the KEK is
   **not** stored with them.
5. The host clock is synchronised to a trusted source. Audit ordering, the
   per-tenant hash chain, TOTP validation and session expiry all depend on it.
6. Time zone handling is the product's (`REQ-TIM-01`, `REQ-TIM-03`); clock
   correctness is the operator's.
7. Decommissioned disks and backup media are sanitised or destroyed by the
   operator. The product's data-removal path stops at the database.
8. Network paths to the identity provider, SMTP relay, syslog collector, push
   service and container registry are the operator's to provide and to restore.

## Reassessment

The operator reassesses at least every four years (Art. 12), and this pack is
reviewed on the same cadence plus at every release that changes a dependency.
Cadence and next due date: `compliance/cer/criticality-assessment.md`
(`REQ-CER-09`).

## Sources

- [Directive (EU) 2022/2557](https://eur-lex.europa.eu/eli/dir/2022/2557/oj) — sectors (Annex), Art. 12 risk assessment and four-yearly cadence, Art. 13 resilience measures, Art. 14 background checks, Art. 15 notification
