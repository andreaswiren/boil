# Technical Documentation — Annex II, V and VII Templates

Requirements: `REQ-CRA-09` (templates completed at release), `REQ-CRA-08` (declared support period).
Articles 13(18), 28 and 31 and Annexes II, V and VII of [Regulation (EU) 2024/2847](https://eur-lex.europa.eu/eli/reg/2024/2847/oj).
Owner: **A18**. Signed by the manufacturer, never by an agent.

These three documents are the manufacturer's conformity file. They are
maintained **now**, although CE marking and conformity assessment apply from
**11 December 2027**, because a conformity file first assembled under deadline is
how fabricated content gets into one. Every `<<PLACEHOLDER: …>>` below is
resolved by a human before a release is declared; an unresolved marker here
means the release does not conform (`compliance/README.md`).

## Completion procedure at release

1. A22 cuts the release: `VERSION`, `CHANGELOG.md` with REQ IDs (`REQ-REL-02`, `REQ-REL-03`).
2. A19's artefacts are in place: `security/supply-chain/sbom/<version>.cdx.json`,
   `advisories/<version>.json`, `suspicious-code/<version>.json`.
3. A18 copies the three skeletons below to
   `compliance/generated/<version>/annex-{ii,v,vii}.md` and resolves every
   placeholder from repository state; gate verdicts at `build/gates/**` attach
   as the Annex VII §6 test reports.
4. A named human reviews and signs the Annex V declaration. The signature is the
   assertion of conformity; nothing upstream of it is.
5. The support period and end-of-support date are recorded in the register below
   **and** in `SECURITY.md`.

---

## Annex II — Information and instructions to the user

Delivered with the product, in a form the operator can keep. Annex II requires
all nine items; none is optional.

```
=== ANNEX II — INFORMATION AND INSTRUCTIONS TO THE USER =====================

1. Manufacturer
   Name:                  <<PLACEHOLDER: legal entity name>>
   Postal address:        <<PLACEHOLDER: registered address>>
   Contact point:         <<PLACEHOLDER: email / web form>>
   Authorised representative in the Union (if any):
                          <<PLACEHOLDER: name and address, or "not applicable">>

2. Single point of contact for reporting vulnerabilities
   Address:               <<PLACEHOLDER: security@<domain> — same as security.txt>>
   Coordinated vulnerability disclosure policy:
                          <<PLACEHOLDER: public URL of the CVD policy>>
   (Source of truth: compliance/cra/cvd-policy.md)

3. Product identification
   Product name:          <<PLACEHOLDER: product name as placed on the market>>
   Type:                  Self-hosted multi-tenant web application, delivered as
                          a Docker Compose stack (app, db, smtp-relay,
                          reverse-proxy) — REQ-FND-04
   Version:               <<PLACEHOLDER: value of VERSION>>
   Image digests:         <<PLACEHOLDER: one sha256 digest per shipped image>>
   Build id:              <<PLACEHOLDER: deterministic NEXT_BUILD_ID / git SHA>>

4. Intended purpose, security environment, essential functionality and
   security properties
   Intended purpose:      <<PLACEHOLDER: from build/scope.md — what this instance
                          administers, for whom>>
   Intended users:        Tenant administrators and users, plus a global
                          operator tier (REQ-RBA-06)
   Security environment assumed by the manufacturer:
                          A multi-tenant deployment behind the operator's TLS
                          termination, on infrastructure the operator controls
                          physically and logically. Operator responsibilities:
                          compliance/cer/applicability.md.
   Essential functionality: <<PLACEHOLDER: the functions whose loss makes the
                          product unfit — from build/scope.md>>
   Security properties:   Encryption on every interface, inside the compose
                          network included (REQ-SEC-01, REQ-SEC-02, REQ-SEC-03);
                          envelope encryption with a rotatable KEK on sensitive
                          columns (REQ-SEC-06); MFA required by default
                          (REQ-AUT-05); deny-by-default server-side RBAC
                          (REQ-RBA-02) over FORCEd RLS with a non-owner app role
                          (REQ-RBA-04); append-only audit with a per-tenant hash
                          chain (REQ-AUD-03, REQ-AUD-06). Full per-subparagraph
                          mapping: compliance/cra/obligations-matrix.md.

5. Known or foreseeable circumstances that may lead to significant
   cybersecurity risks
   - Weakening a documented secure default. Each item, and what it costs, is in
     compliance/cra/secure-by-default.md.
   - Granting the hard-delete, see-deleted or debug-console permission broadly.
     All three ship granted to no role.
   - Widening EGRESS_ALLOWLIST beyond the documented egress surface
     (docker/egress.md, REQ-SUP-08).
   - Running against a database the operator has granted the app role ownership
     or BYPASSRLS on: tenant isolation is then not enforced (REQ-RBA-04).
   - Storing the KEK in the same backup as the ciphertext it protects. See
     compliance/cer/resilience-plan.md.
   - Operating past the end-of-support date in item 7.
   - <<PLACEHOLDER: instance-specific risks from build/scope.md>>

6. EU declaration of conformity
   Internet address:      <<PLACEHOLDER: URL where the Annex V declaration can
                          be accessed>>

7. Technical security support and the support period          [REQ-CRA-08]
   Support offered:       <<PLACEHOLDER: what support means here — security
                          updates, advisories, and what is not included>>
   Support period start:  <<PLACEHOLDER: YYYY-MM-DD — date placed on the market>>
   Support period length: <<PLACEHOLDER: months; at least 5 years unless the
                          expected use is shorter, with the reasoning recorded in
                          Annex VII §4>>
   End-of-support date:   <<PLACEHOLDER: YYYY-MM-DD>>
   After that date the manufacturer no longer handles vulnerabilities or issues
   security updates for this version. The operator's obligations do not end with
   it.

8. Instructions
   Secure commissioning and secure use over the lifetime:
                          <<PLACEHOLDER: URL or path — install and hardening guide>>
   How changes to the product affect the security of data:
                          <<PLACEHOLDER: URL or path>>
   How to install security-relevant updates:
                          <<PLACEHOLDER: URL or path>>
   Secure decommissioning, including secure removal of user data:
                          <<PLACEHOLDER: URL or path — tenant offboarding and
                          data-destruction procedure>>
   Turning off automatic installation of security updates:
                          Not applicable. This is self-hosted server software;
                          the product notifies the operator of an available
                          update and the operator applies it. There is no
                          automatic installation to turn off (REQ-PWA-05).
   Information for integrators, where the product is integrated into another
   product:               <<PLACEHOLDER: URL or path, or "not applicable">>

9. Software bill of materials
   The SBOM is made available to the operator at
                          security/supply-chain/sbom/<version>.cdx.json
                          (CycloneDX, per build, retained per release —
                          REQ-CRA-03, REQ-SUP-01).

=============================================================================
```

---

## Annex V — EU declaration of conformity

One page. It carries a human signature and nothing else in this repository does.

```
=== EU DECLARATION OF CONFORMITY ============================================

1. Product
   Name and type:         <<PLACEHOLDER: product name; self-hosted multi-tenant
                          web application>>
   Unique identification: <<PLACEHOLDER: version, image digests, build id>>

2. Manufacturer
   Name:                  <<PLACEHOLDER: legal entity name>>
   Address:               <<PLACEHOLDER: registered address>>
   Authorised representative (if any):
                          <<PLACEHOLDER: name and address, or "not applicable">>

3. This EU declaration of conformity is issued under the sole responsibility of
   the manufacturer.

4. Object of the declaration
   <<PLACEHOLDER: identification of the product allowing traceability — name,
   version, digests>>

5. The object of the declaration described above is in conformity with the
   relevant Union harmonisation legislation:
   Regulation (EU) 2024/2847 (Cyber Resilience Act)
   <<PLACEHOLDER: any other applicable Union legislation, or "none">>

6. References to the harmonised standards or other common specifications or
   cybersecurity certification schemes in relation to which conformity is
   declared
   <<PLACEHOLDER: standard references with version and date. Leave unresolved
   until the applicable harmonised standards are published and applied — do not
   name a standard that was not used.>>

7. Notified body (where a conformity assessment involving one was performed)
   Name and number:       <<PLACEHOLDER: or "not applicable — self-assessment
                          under Annex VIII Module A">>
   Procedure performed:   <<PLACEHOLDER>>
   Certificate:           <<PLACEHOLDER: identification of the certificate issued>>

8. Additional information
   Signed for and on behalf of:  <<PLACEHOLDER: legal entity name>>
   Place and date of issue:      <<PLACEHOLDER: place, YYYY-MM-DD>>
   Name and function:            <<PLACEHOLDER: name, function>>
   Signature:                    ____________________________

=============================================================================
```

Product class matters here and must be decided, not assumed: whether the
instance falls into Annex III (important products) or Annex IV (critical
products) determines the conformity assessment route. Decision and reasoning:
`<<PLACEHOLDER: product class determination — Annex III class I / class II /
Annex IV / neither, with the reasoning and who decided>>`.

---

## Annex VII — Technical documentation

Assembled per release at `compliance/generated/<version>/annex-vii.md`. Mostly
references, not prose: the artefacts already exist in the repository, and copying
them into a document is how they go stale (`REQ-CRA-10`).

| Annex VII § | Required content | Where it comes from |
|---|---|---|
| 1(a) | General description: intended purpose | Annex II §4 above, from `build/scope.md` |
| 1(b) | Versions of software affecting conformity | `VERSION`, `versions/manifest.json` (externally validated with source URL and timestamp — `REQ-VER-02`, `REQ-VER-03`), image digests |
| 1(c) | Photographs or illustrations of external features | Not applicable — no hardware. Substitute: the architecture views at `docs/architecture/**` (`REQ-DOC-06`, A17) |
| 1(d) | User information and instructions per Annex II | The Annex II template above |
| 2(a) | Design and development information, system architecture, how software components integrate | C4 context/container/component views, the auth-and-MFA sequence, the request-to-audit dataflow, the RLS/tenancy boundary diagram, the deployment topology and the normalization pipeline — `docs/architecture/**`, drawn from the code, not the plan (`REQ-DOC-08`) |
| 2(b) | Vulnerability handling processes: SBOM, CVD policy, evidence of a reporting contact address, secure update distribution | `compliance/cra/vulnerability-handling.md`, `compliance/cra/cvd-policy.md`, `security/supply-chain/sbom/<version>.cdx.json`, the release signature record |
| 2(c) | Production and monitoring processes and their validation | Reproducible build pinned by digest with `--frozen-lockfile` (`REQ-FND-09`), lockfile-integrity CI (`REQ-SUP-05`), the 9-gate ladder at `gates/gate-ladder.md`, structured per-REQ verdicts (`REQ-GAT-04`) |
| 3 | Cybersecurity risk assessment, and how each Annex I Part I requirement applies and is implemented | `compliance/cra/obligations-matrix.md` is the per-subparagraph implementation record; the risk assessment narrative is `<<PLACEHOLDER: risk assessment document path, assessor, date, and the assessment method used>>` |
| 4 | Information taken into account to determine the support period | `<<PLACEHOLDER: expected use period, operator upgrade cadence, upstream LTS windows for Node and PostgreSQL from versions/manifest.json, and the resulting decision>>` |
| 5 | Harmonised standards applied, and the solutions adopted where none were applied | `<<PLACEHOLDER: list, or the statement that no harmonised standard was available and how conformity was otherwise met>>` |
| 6 | Reports of the tests carried out to verify conformity of the product and of the vulnerability handling processes | `build/gates/<gate>/<reviewer>-<dimension>-r<round>.json`; suites for tenant isolation, permission denial, MFA enforcement and audit emission (`REQ-TST-05`); accessibility runs (`REQ-TST-06`); the CVD rehearsal record in `compliance/cra/reporting-runbook.md` |
| 7 | A copy of the EU declaration of conformity | The Annex V document above, signed |
| 8 | The SBOM, on reasoned request from a market surveillance authority | `security/supply-chain/sbom/<version>.cdx.json` |

Retention: the technical documentation and the declaration are kept at the
disposal of market surveillance authorities for **ten years** after the product
is placed on the market, or for the support period, whichever is longer.
Retention owner: `<<PLACEHOLDER: who holds the file, and where>>`.

---

## Support period register (REQ-CRA-08)

The end-of-support date is recorded in **four** places, and all four must agree.
A support date that exists in only one of them is how an operator ends up
running an unsupported version believing it is supported.

| Location | Field | Owner |
|---|---|---|
| Annex II §7 above, per release | Support period start, length, end-of-support date | A18 |
| `SECURITY.md` | Supported versions table with the end-of-support date per release line | A22 (`REQ-REL-05`) |
| Product UI | Shown to the global tier alongside the version | `<<PLACEHOLDER: surface where the version and EOS date are displayed>>` |
| `compliance/generated/<version>/annex-ii.md` | The released copy | A18 |

| Release line | Support period start | End of support | Basis |
|---|---|---|---|
| `<<PLACEHOLDER: version line, e.g. 1.x>>` | `<<PLACEHOLDER: YYYY-MM-DD>>` | `<<PLACEHOLDER: YYYY-MM-DD>>` | `<<PLACEHOLDER: reasoning recorded in Annex VII §4>>` |

The CRA expects a support period of at least five years unless the product's
expected use period is shorter; a shorter period must be justified, and the
justification belongs in Annex VII §4, not in a conversation.
