# CRA Annex I — Obligations Matrix

Requirement: `REQ-CRA-01`. Owner: **A18 `compliance-cra-cer`**.
Regulation: [Regulation (EU) 2024/2847](https://eur-lex.europa.eu/eli/reg/2024/2847/oj).
Read `compliance/README.md` first — the disclaimer there governs this file.

This is the centre of the CRA set. Every other file in `compliance/cra/` is the
long form of one or more rows below.

## Scope of this matrix

The generated instance is **a product with digital elements**: a self-hosted,
multi-tenant web application shipped as a Docker Compose stack (`REQ-FND-04`).
It is not a hardware product and has no physical marking. Annex I applies in
full; the CE-marking and conformity-assessment duties attached to it apply from
**11 December 2027**, while the Article 14 reporting duties are already in force
(see `compliance/cra/reporting-runbook.md`).

The obligated party is whoever places the instance on the market. The
boilerplate places nothing on the market.

## How to read a row

| Column | Meaning |
|---|---|
| Annex I ref | The subparagraph, cited as in the Regulation |
| Obligation | What the subparagraph requires, compressed, not paraphrased into vagueness |
| How this product satisfies it | The named control. If there is no control, the row says so |
| Implementing REQ IDs | `spec/requirements.md` IDs. A row with no REQ ID is a gap |
| Evidence | The artefact a market surveillance authority would be shown, and its path |
| Owner | The agent that produces the evidence, per `contracts/ownership.md` |

A row whose Evidence column names a document rather than a build output is
weaker evidence. Those rows are listed again under **Weak rows** at the end.

---

## Annex I Part I — Essential cybersecurity requirements (product properties)

### Part I (1) and (2) — the two unconditional requirements

| Annex I ref | Obligation | How this product satisfies it | Implementing REQ IDs | Evidence | Owner |
|---|---|---|---|---|---|
| I(1) | Designed, developed and produced to ensure an appropriate level of cybersecurity based on the risks | A written risk assessment drives the control set; the stack is deny-by-default at the permission layer and encrypted on every interface including inside the compose network | `REQ-SEC-01`, `REQ-SEC-02`, `REQ-RBA-02`, `REQ-FND-07` | Risk assessment section of `compliance/cra/technical-documentation.md` (Annex VII §3); independent security verdicts at `build/gates/g6/<reviewer>-security-r<round>.json` | A18, S1, S2 |
| I(2) | Made available on the market without known exploitable vulnerabilities | Every build checks every direct and transitive dependency against known-vulnerability sources and **fails the build** on a known-exploited or critical advisory; lockfile integrity is enforced; a first-party suspicious-code scan runs beyond CVE matching | `REQ-SUP-01`, `REQ-SUP-02`, `REQ-SUP-03`, `REQ-SUP-05` | `security/supply-chain/advisories/<version>.json`, `security/supply-chain/suspicious-code/<version>.json` | A19 |

### Part I (3)(a)–(l) — risk-dependent requirements

| Annex I ref | Obligation | How this product satisfies it | Implementing REQ IDs | Evidence | Owner |
|---|---|---|---|---|---|
| I(3)(a) | Secure-by-default configuration, including the possibility to reset the product to its original state | One Zod env schema validated at boot; **no silent default for any security-relevant key** — boot fails loudly instead. MFA required by default; TLS floor, `verify-full` Postgres, TLS SMTP and TLS syslog are the shipped values, not options. Reset-to-secure-state is a documented procedure, not a button | `REQ-CRA-02`, `REQ-FND-07`, `REQ-AUT-05`, `REQ-SEC-02`, `REQ-SEC-03`, `REQ-SEC-04`, `REQ-SEC-05` | `compliance/cra/secure-by-default.md`; machine-readable defaults in `packages/config/**`; generated `.env.example` | A18 (doc), A01 (schema) |
| I(3)(b) | Vulnerabilities can be addressed through security updates; notification of available updates; option to postpone | Security releases are separable from feature releases and are signed. This is server software: the operator performs the update, so "automatic installation as a default setting" does not apply — the product instead detects and announces a new version to the operator and never locks a stale shell | `REQ-CRA-07`, `REQ-PWA-05`, `REQ-REL-02`, `REQ-REL-03` | `compliance/cra/vulnerability-handling.md` §Security update channel; `CHANGELOG.md`; release signatures | A18 (doc), A22 (release) |
| I(3)(c) | Protection from unauthorised access by appropriate control mechanisms, and reporting on possible unauthorised access | Password+TOTP, passkeys and OIDC as first-class methods; MFA required by default; step-up re-auth on privileged actions; server-side revocable sessions; deny-by-default RBAC evaluated server-side; PostgreSQL RLS `FORCE`d with a non-owner app role. Reporting: a failed-auth, lockout and rate-limit-trip audit event per occurrence | `REQ-AUT-01`..`REQ-AUT-10`, `REQ-RBA-01`..`REQ-RBA-08`, `REQ-SEC-09`, `REQ-SEC-10`, `REQ-SEC-11`, `REQ-AUD-01`, `REQ-AUD-04` | Dedicated suites for tenant isolation, permission denial, MFA enforcement and audit emission under `tests/security/**` | A03, A04, A23 |
| I(3)(d) | Protect the confidentiality of stored, transmitted or processed data, e.g. by state-of-the-art encryption at rest and in transit | No cleartext ingress or egress on any interface, including inside the compose network; TLS 1.3 preferred / 1.2 AEAD floor; Postgres `sslmode=verify-full` with a pinned CA and a refusal to start against a non-TLS database; implicit-TLS or mandatory-STARTTLS SMTP; RFC 5425 TLS syslog; envelope encryption with a rotatable KEK for TOTP seeds, recovery codes, OIDC client secrets, API key material and SMTP credentials; Argon2id where verification suffices | `REQ-SEC-01`..`REQ-SEC-07`, `REQ-FND-08` | `packages/crypto/**`; KEK rotation test; egress surface at `docker/egress.md`; `build/gates/g6/**` | A01, A19, S1/S2 |
| I(3)(e) | Protect the integrity of stored, transmitted or processed data, commands, programs and configuration against unauthorised manipulation, and report on corruptions | Append-only audit tables with no `UPDATE`/`DELETE` grant to the app role, enforced by database privilege **and** trigger; a per-tenant hash chain over audit rows with a verify job that reports a break; origin-checked double-submit CSRF on every state-changing route including Server Actions; strict CSP with per-request nonces; actor columns set only by the data-access layer; reproducible builds pinned by digest | `REQ-AUD-03`, `REQ-AUD-06`, `REQ-SEC-08`, `REQ-SEC-10`, `REQ-ENT-04`, `REQ-FND-09` | Hash-chain verify job output; `tests/security/**`; reproducible-build CI comparing two image digests | A13, A01, A23 |
| I(3)(f) | Process only data adequate, relevant and limited to what is necessary (data minimisation) | Field-level redaction keeps secrets and declared PII out of the audit diff and out of the debug console by the same rule set; read-audit uses a declared sampling/aggregation policy for list reads instead of logging every row; push payloads carry a reference, never sensitive content; telemetry and phone-home are disabled build-time and run-time and asserted by test | `REQ-AUD-02`, `REQ-AUD-05`, `REQ-AUD-12`, `REQ-PWA-04`, `REQ-SUP-06` | Redaction tests and telemetry-kill assertions under `tests/**`; `security/supply-chain/` telemetry kill-list | A13, A09, A19 |
| I(3)(g) | Protect the availability of essential and basic functions, including resilience against and mitigation of denial-of-service attacks | Per-identity and per-IP rate limits with lockout backoff on auth, API-key, password-reset and export routes; the datagrid `all` option is guarded by a declared row ceiling and streams or refuses rather than hanging; server-side sort/filter/paginate above a declared threshold; a durable mail outbox with retry and dead-letter instead of sending from a request path; local syslog spooling with backpressure when the collector is down; liveness and readiness endpoints | `REQ-SEC-11`, `REQ-GRD-11`, `REQ-GRD-12`, `REQ-MAIL-04`, `REQ-AUD-07`, `REQ-FND-10` | Rate-limit trip audit events; `compliance/cer/resilience-plan.md` degraded-mode table | A03, A07, A12, A13 |
| I(3)(h) | Minimise the product's own negative impact on the availability of services provided by other devices or networks | Exactly one egress client, with an allowlist, a timeout, TLS verification and post-DNS SSRF guards; the egress surface is documented and an unexpected destination fails the security gate; outbound mail retries with backoff; remote collectors use idempotent ingest keys so a resume does not duplicate | `REQ-SEC-12`, `REQ-SUP-08`, `REQ-MAIL-04`, `REQ-OBS-05` | `docker/egress.md`; the egress test rejecting link-local, loopback and non-allowlisted hosts | A01, A19 |
| I(3)(i) | Designed to limit attack surfaces, including external interfaces | Four services and no more (`app`, `db`, `smtp-relay`, `reverse-proxy`); HTTP exists only to 308; no third-party script, font or asset loaded from a remote origin at runtime; CI fails on a route without an OpenAPI operation or an operation without a route, so there is no undocumented endpoint; one datastore, no secondary store that survives a restart | `REQ-FND-04`, `REQ-FND-05`, `REQ-SEC-02`, `REQ-SUP-07`, `REQ-API-03` | Generated OpenAPI 3.1 document; `docker/egress.md`; compose files under `docker/**` | A01, A11, A19 |
| I(3)(j) | Reduce the impact of an incident using appropriate exploitation mitigation mechanisms and techniques | CSP with per-request nonces and no `unsafe-inline`/`unsafe-eval`; RLS `FORCE`d on every tenant-scoped table with an app role that cannot bypass it, so one compromised tenant session cannot read another tenant; envelope encryption per row/column family so a single leaked DEK is not the estate; session cookies rotated on privilege change with `__Host-` prefix; step-up re-auth on privileged actions; global-tier impersonation time-boxed, reason-required and audited on entry and exit | `REQ-SEC-06`, `REQ-SEC-08`, `REQ-SEC-09`, `REQ-RBA-04`, `REQ-RBA-05`, `REQ-RBA-07`, `REQ-AUT-07` | Cross-tenant read/write test per table returning zero rows or raising; `build/gates/g6/**` | A04, A01, A23 |
| I(3)(k) | Provide security-related information by recording and monitoring relevant internal activity, including access to or modification of data, with an opt-out for the user | Full audit trail including **successful reads and detail views**; every record carries actor, tenant, on-behalf-of, permission used, target, before/after diff, correlation id, source IP, user agent and result; RFC 5424 structured syslog forwarding over TLS; an in-app SSE debug console for permitted operators. **On the opt-out:** the audit trail itself is not opt-outable — `REQ-AUD-03` and `REQ-AUD-06` depend on it and other Annex I rows use it as their evidence. What the operator can turn off is syslog forwarding and the list-read sampling rate. The manufacturer must record that reading of I(3)(k) in the Annex VII risk assessment rather than claim a full opt-out exists | `REQ-AUD-01`..`REQ-AUD-13` | `packages/audit/**` contract; read-audit emission test (`REQ-TST-08`); syslog sink status in `/api/health/ready` | A13, A23 |
| I(3)(l) | Provide for secure and easy permanent removal of all data and settings, and secure transfer where applicable | Deletion is soft by default; hard delete is a separate global-tier permission with its own audit event; per-tenant audit retention and export, with a legal-hold flag that blocks purge; every export is itself audited. **Conflict to state, not hide:** a legal hold intentionally defeats "permanent removal" for the rows it covers. The tenant-offboarding procedure that reconciles the two is `<<PLACEHOLDER: path to the tenant offboarding and data-destruction procedure, owner, and who authorises a hold release>>` | `REQ-ENT-02`, `REQ-AUD-13`, `REQ-GRD-13` | Hard-delete and export audit events; retention configuration per tenant | A13, A04 |

---

## Annex I Part II — Vulnerability handling requirements

| Annex I ref | Obligation | How this product satisfies it | Implementing REQ IDs | Evidence | Owner |
|---|---|---|---|---|---|
| II(1) | Identify and document vulnerabilities and components, including an SBOM in a commonly used machine-readable format covering at least top-level dependencies | CycloneDX SBOM produced **per build** and retained **per release**, covering direct and transitive dependencies with licence and provenance | `REQ-CRA-03`, `REQ-SUP-01` | `security/supply-chain/sbom/<version>.cdx.json` | A19 |
| II(2) | Address and remediate vulnerabilities without delay, including by providing security updates; where technically feasible, separately from functionality updates | Triage SLA and remediation targets by severity; a security-only release line that carries no feature change | `REQ-CRA-05`, `REQ-CRA-07` | `compliance/cra/vulnerability-handling.md`; `CHANGELOG.md` entries citing REQ IDs | A18, A22 |
| II(3) | Apply effective and regular tests and reviews of the security of the product | Unit, integration and e2e suites; dedicated suites for tenant isolation, permission denial, MFA enforcement and audit emission; accessibility and visual assertions; **two independent security reviewers** who state a review plan first and do not see each other's findings before submitting; no gate is self-approved | `REQ-TST-01`..`REQ-TST-08`, `REQ-GAT-02`, `REQ-GAT-03`, `REQ-GAT-04`, `REQ-GAT-07` | Per-REQ structured verdicts at `build/gates/<gate>/<reviewer>-<dimension>-r<round>.json` | A23, S1, S2 |
| II(4) | Once a security update is available, share and publicly disclose information about fixed vulnerabilities, with description, affected-product identification, impact and severity, and remediation guidance | An advisory per fixed vulnerability, published with the release, with CVE (where assigned), CVSS vector, affected and fixed versions and operator action; the justified-delay case is written down with who may invoke it | `REQ-CRA-05`, `REQ-REL-03`, `REQ-REL-05` | Advisory index at `<<PLACEHOLDER: public advisory URL for this instance>>`; `SECURITY.md` | A18, A22 |
| II(5) | Put in place and enforce a policy on coordinated vulnerability disclosure | A published CVD policy with scope, safe harbour, a single point of contact and stated timelines, plus an RFC 9116 `security.txt` | `REQ-CRA-04` | `compliance/cra/cvd-policy.md`; `SECURITY.md`; `/.well-known/security.txt` | A18, A22 |
| II(6) | Facilitate the sharing of information about potential vulnerabilities in the product and in third-party components, including a contact address for reports | The same single point of contact accepts third-party component reports; the SBOM lets a reporter identify an affected component without a source checkout; upstream reports are forwarded to the component maintainer and tracked to a fixed version | `REQ-CRA-04`, `REQ-SUP-01`, `REQ-SUP-02` | CVD intake log; `security/supply-chain/sbom/<version>.cdx.json` | A18, A19 |
| II(7) | Provide mechanisms to securely distribute updates so vulnerabilities are fixed or mitigated in a timely manner | Images pinned by digest and reproducible from a clean checkout; release artefacts signed and verifiable before deployment; `--frozen-lockfile` and a deterministic build id so the artefact the operator runs is the artefact that was reviewed | `REQ-CRA-07`, `REQ-FND-09`, `REQ-SUP-05` | Release signature and digest record; reproducible-build CI job | A22, A01 |
| II(8) | Disseminate available security updates without delay and free of charge, with advisory messages telling users what action to take | Security releases are announced on the advisory channel on publication and are not held behind a commercial gate; each advisory states the operator action explicitly | `REQ-CRA-05`, `REQ-CRA-07`, `REQ-CRA-08` | Advisory channel; support-period statement in `compliance/cra/technical-documentation.md` | A18, A22 |

---

## Obligations that are not in Annex I

Annex I is not the whole of the CRA. These sit elsewhere in the Regulation and
are covered by the files named.

| Obligation | Where in the CRA | Document |
|---|---|---|
| Cybersecurity risk assessment, kept for the support period | Art. 13(2)–(3) | `compliance/cra/technical-documentation.md` (Annex VII §3) |
| Support period determination and statement | Art. 13(8) | `compliance/cra/technical-documentation.md`, `REQ-CRA-08` |
| Information and instructions to the user | Art. 13(18), Annex II | `compliance/cra/technical-documentation.md` |
| Reporting actively exploited vulnerabilities and severe incidents | Art. 14 — **in force since 11 September 2026** | `compliance/cra/reporting-runbook.md`, `REQ-CRA-06` |
| Informing affected users of an incident and of corrective measures | Art. 14(8) | `compliance/cra/reporting-runbook.md` |
| EU declaration of conformity | Art. 28, Annex V | `compliance/cra/technical-documentation.md` |
| Technical documentation | Art. 31, Annex VII | `compliance/cra/technical-documentation.md` |

## Weak rows — evidence that is prose, not a build output

`REQ-CRA-10` requires compliance documentation to be generated from repository
state. These rows currently point at a document rather than an artefact, and are
the rows a competent authority would press hardest:

- **I(3)(a)** — the secure-default inventory is hand-maintained in
  `compliance/cra/secure-by-default.md`. It should be generated from the
  assembled env schema in `packages/config/**`. Until it is, a default can
  change in code without the document noticing.
- **I(3)(b)** and **II(7)** — signing and verification are asserted in prose. The
  signature record path is `<<PLACEHOLDER: release signature and verification
  record path>>`.
- **II(4)** and **II(8)** — the advisory channel has no URL until the
  manufacturer publishes one.
- **I(3)(l)** — no offboarding artefact exists yet.

The per-release evidence bundle that would close these is
`compliance/tools/collect-evidence.ts` writing
`compliance/generated/<version>/evidence-manifest.json`. It is **not present**
(see `compliance/README.md`).

## Sources

- [Regulation (EU) 2024/2847](https://eur-lex.europa.eu/eli/reg/2024/2847/oj) — Annex I Parts I and II, Annexes II, V, VII
- [European Commission — CRA reporting obligations](https://digital-strategy.ec.europa.eu/en/policies/cra-reporting) — applicability date 11 September 2026
