# Criticality and Dependency Assessment

Requirements: `REQ-CER-02` (criticality and dependency assessment), `REQ-CER-09` (four-yearly reassessment with a next due date).
Directive: [Directive (EU) 2022/2557](https://eur-lex.europa.eu/eli/dir/2022/2557/oj), Art. 12.
Owner: **A18**. Applicability and the product/operator split: `compliance/cer/applicability.md`.

This is a **template the operator completes**, pre-filled with the parts the
manufacturer knows: the dependency inventory and what happens when each
dependency fails. The operator supplies the essential service, the impact
thresholds and the tolerances — only they know what an hour of outage costs
their service.

## Part 1 — The essential service this panel supports

| Field | Value |
|---|---|
| Operator | `<<PLACEHOLDER: legal name>>` |
| Designated critical entity | `<<PLACEHOLDER: yes/no, notification date, competent authority>>` |
| Sector and sub-sector | `<<PLACEHOLDER: one of the eleven CER sectors>>` |
| Essential service | `<<PLACEHOLDER: name the service, not the system>>` |
| Role of this panel in that service | `<<PLACEHOLDER: e.g. holds the authoritative asset register and change history for the field estate that delivers the service>>` |
| In the control path of the service? | `<<PLACEHOLDER: yes/no — if yes, say what the panel can actuate>>` |
| Users who depend on it | `<<PLACEHOLDER: roles and headcount, tenant count>>` |
| Maximum tolerable outage of the panel | `<<PLACEHOLDER: hours — the operator's number; must be ≥ the RTO in resilience-plan.md or the plan does not meet the need>>` |
| Maximum tolerable data loss | `<<PLACEHOLDER: minutes — must be ≥ the RPO>>` |
| Assessment author and date | `<<PLACEHOLDER: name, role, YYYY-MM-DD>>` |

## Part 2 — Criticality rating of the panel

| Impact dimension | Rating | Reasoning |
|---|---|---|
| Disruption to the essential service if the panel is unavailable | `<<PLACEHOLDER: none / minor / significant / severe>>` | `<<PLACEHOLDER>>` |
| Disruption if panel data is lost | `<<PLACEHOLDER>>` | `<<PLACEHOLDER>>` |
| Disruption if panel data is corrupted but the panel is available | `<<PLACEHOLDER>>` | Worse than an outage in most estates: the record is trusted while wrong |
| Confidentiality impact of a breach | `<<PLACEHOLDER>>` | Tenant-scoped operational data, credentials, audit trail |
| Cross-border effect | `<<PLACEHOLDER: yes/no — relevant to Art. 17 notification of other Member States>>` | `<<PLACEHOLDER>>` |
| Cascading effect on other entities or sectors | `<<PLACEHOLDER>>` | Highest where the panel administers a shared estate, e.g. an MSP deployment |

## Part 3 — Dependency inventory

Every external thing the panel needs. `Shipped` means the compose stack provides
it (`REQ-FND-04`); the operator is expected to replace the shipped dev-grade
component with a production one.

| # | Dependency | What it provides | Shipped | Who runs it in production | Criticality | REQ |
|---|---|---|---|---|---|---|
| D1 | PostgreSQL | The only datastore. All state that survives a restart | Yes (`db`) | Operator | **Vital** — no panel without it | `REQ-FND-05`, `REQ-SEC-03` |
| D2 | Identity provider (OIDC: Entra ID, Authentik or Keycloak) | Federated login where enabled | No | Operator | **High**, unless local password+TOTP or passkeys remain enabled | `REQ-AUT-03`, `REQ-AUT-04` |
| D3 | SMTP relay | Verification mail, password reset, notifications | Yes (`smtp-relay`) | Operator | **Medium** — blocks onboarding and reset, not operation | `REQ-SEC-04`, `REQ-MAIL-01`..`REQ-MAIL-04` |
| D4 | Syslog collector | Off-host audit and log retention over RFC 5425 TLS | No | Operator | **High for evidence, low for function** — see note below | `REQ-AUD-07`, `REQ-SEC-05` |
| D5 | Push service (Web Push / VAPID, via the browser vendor's endpoint) | Push notifications to installed PWA clients | No | Browser vendor — **outside anyone's control** | **Low** | `REQ-PWA-02`, `REQ-PWA-04` |
| D6 | Container registry | Source of the pinned images at deploy and restore time | No | Operator or vendor | **Vital at recovery time, irrelevant while running** | `REQ-FND-09` |
| D7 | TLS certificate authority | Trust anchor for ingress, Postgres, SMTP and syslog | Dev CA only | Operator | **Vital** — expiry stops the stack, by design | `REQ-SEC-02`, `REQ-SEC-03` |

Also load-bearing, and frequently forgotten in assessments:

- **Reverse proxy** (`reverse-proxy`, shipped): TLS termination and the 308
  redirect. Fails with the host; no independent failure mode.
- **Host clock / NTP**: audit ordering, the per-tenant hash chain (`REQ-AUD-06`),
  TOTP validation (`REQ-AUT-01`) and session expiry all depend on it. Operator's
  (`compliance/cer/applicability.md` §Physical assumptions, item 5).
- **KEK custody**: not a service, but a dependency in the strict sense — without
  it the sensitive columns are unreadable even from a perfect backup
  (`REQ-SEC-06`). Treated in `compliance/cer/resilience-plan.md`.

**Note on D4.** Losing the collector does not stop the panel: the audit trail is
written to Postgres first and syslog spools locally with backpressure. What it
stops is *off-host evidence*, which is what an operator needs after an incident.
Rate it for the evidence it protects, not the uptime it affects.

## Part 4 — Failure modes

Per dependency: what fails, how far it reaches, how it is noticed, what the app
does instead, and how it comes back. Degraded-mode behaviour is specified in
full in `compliance/cer/resilience-plan.md` (`REQ-CER-05`); this table is the
assessment view.

| Dep | What fails | Blast radius | Detection | Degraded mode | Recovery |
|---|---|---|---|---|---|
| D1 | Postgres unreachable | Total outage. No login, no reads, no audit writes | `/api/health/ready` fails the DB check; connection errors in the log stream | Read-only maintenance page; login refused rather than half-working; no write is silently dropped | Restart, failover, or restore per the RTO/RPO in `resilience-plan.md` |
| D1 | Postgres read-only (disk full, failover to a replica, or deliberate) | Every write path fails: no login session creation, no audit write | Ready check reports degraded; write errors classified distinctly from outages | Explicit read-only banner; reads and exports permitted; every write returns a typed error, not a 500 (`REQ-API-10`) | Free space or promote a primary. **Audit gap is inevitable** — record its window |
| D1 | Data corruption, undetected | Worst case in the set: the record is trusted while wrong | Hash-chain verify job breaks (`REQ-AUD-06`); referential checks; operator report | None. Corruption is not degradable | Restore to a point before corruption (PITR) and replay from source systems (`REQ-DAT-05` provenance) |
| D2 | IdP unreachable | Federated users cannot log in. Existing sessions survive until expiry | Discovery-document fetch fails; login-failure rate spikes in the console | Local password+TOTP and passkey paths still work **if the tenant left them enabled** — this is the argument for not disabling them | Operator restores the IdP. Break-glass: `<<PLACEHOLDER: break-glass local account procedure and who holds it>>` |
| D2 | IdP returns valid tokens for the wrong identity, or is compromised | Authentication integrity lost for federated users | Anomalous login audit events; impersonation-style patterns | Disable the OIDC method at the global tier (audited policy change, `REQ-AUT-04`) | Operator rotates IdP trust; revoke all sessions (`REQ-AUT-10`) |
| D3 | SMTP relay unreachable or refusing TLS | No verification, reset or notification mail | Ready check's SMTP probe; outbox depth rises | Durable outbox retries with backoff; nothing is sent from a request path, so no user action fails on mail (`REQ-MAIL-04`) | Relay restored, outbox drains; dead-lettered items reviewed |
| D4 | Collector unreachable | Off-host evidence stops. App unaffected | Ready check's syslog status; spool depth | Local spooling with backpressure (`REQ-AUD-07`); the Postgres audit trail continues as the authoritative record (`REQ-AUD-03`) | Collector restored, spool drains. If the spool overflowed, record the gap window |
| D5 | Push endpoint fails or subscription expires | No push notifications | Delivery failures per subscription | In-app and email channels continue; preferences are per-channel (`REQ-PWA-06`); no payload content was at risk (`REQ-PWA-04`) | Client re-subscribes; stale subscriptions pruned |
| D6 | Registry unavailable | Cannot deploy, scale or restore. A running stack is unaffected | Deploy or restore fails | None at deploy time | Local digest-pinned image cache: `<<PLACEHOLDER: where images are mirrored so a restore does not depend on the public registry>>` |
| D7 | Certificate expiry (ingress, Postgres, SMTP or syslog) | Progressive hard failure. The Postgres case refuses to start, by design (`REQ-SEC-03`) | Expiry monitoring — **operator's**, and the most common preventable outage in this list | None. There is no cleartext fallback and that is deliberate | Reissue and reload. Monitoring and lead time are the real control |
| D7 | CA compromise | Trust anchor invalid for every internal channel | Operator's PKI monitoring | None | Reissue the chain, rotate, restart the stack |
| KEK | KEK lost | Sensitive columns permanently unreadable even with a perfect backup | Decryption failures at boot on first access | None | **No recovery.** Prevention only — see `resilience-plan.md` §KEK custody |
| KEK | KEK disclosed | Confidentiality of sealed columns lost | Detected as an incident, not by the app | Rotate: `rotateKek()` re-wraps DEKs without reading plaintext (`REQ-SEC-06`) | Rotate, then revoke every credential the sealed columns protected |
| Clock | Host clock wrong or jumps | TOTP rejects valid codes; audit ordering and the hash chain become unreliable; sessions expire early or late | TOTP failure-rate spike; chain verify anomalies | None | Operator fixes NTP. Record the affected window in the audit record |

## Part 5 — Findings

| Finding | Owner | Status |
|---|---|---|
| Postgres is a genuine single point of failure by design (`REQ-FND-05`) | Operator | Accepted. Mitigation is backup, PITR and restore speed, not a second store |
| The KEK is unrecoverable if lost, and its custody is the operator's | Operator | `<<PLACEHOLDER: custody arrangement recorded, yes/no>>` |
| Certificate expiry is the most likely cause of an unplanned outage | Operator | `<<PLACEHOLDER: expiry monitoring in place, yes/no, with lead time>>` |
| A restore depends on registry availability for pinned images | Operator | `<<PLACEHOLDER: local mirror in place, yes/no>>` |
| Disabling local auth methods makes the IdP a single point of failure for login | Operator | `<<PLACEHOLDER: decision and break-glass account, recorded>>` |
| Off-host evidence stops when the collector is down and the spool overflows | Operator | `<<PLACEHOLDER: spool sizing and alerting, recorded>>` |
| `<<PLACEHOLDER: operator-identified finding>>` | `<<PLACEHOLDER>>` | `<<PLACEHOLDER>>` |

## Part 6 — Reassessment cadence (REQ-CER-09)

Art. 12 requires a risk assessment within nine months of designation and **at
least every four years** thereafter. This assessment follows that cadence and is
additionally re-run on the events below, because a four-year clock is not a
change-detection mechanism.

| Field | Value |
|---|---|
| Last full assessment | `<<PLACEHOLDER: YYYY-MM-DD>>` |
| Performed by | `<<PLACEHOLDER: name, role>>` |
| Approved by | `<<PLACEHOLDER: name, role>>` |
| **Next full assessment due** | `<<PLACEHOLDER: YYYY-MM-DD — last date + 4 years, or earlier if the operator's competent authority requires>>` |
| Review owner | `<<PLACEHOLDER: named role accountable for not missing the date>>` |
| Reminder mechanism | `<<PLACEHOLDER: where the date is diarised — a date in a markdown file is not a reminder>>` |

Re-run early, regardless of the four-year date, on any of:

- A dependency added, removed or replaced — including replacing the shipped
  SMTP relay or database with a managed service.
- A change to the essential service the panel supports, or to its criticality.
- A major version bump of PostgreSQL, Node or the framework
  (`REQ-VER-04` requires a reviewed decision with a migration note anyway).
- An incident that reached severity `<<PLACEHOLDER: threshold, aligned with
  incident-response.md>>` or a restore rehearsal that failed.
- A change to the operator's designation, competent authority, or sector rules.
- An RTO or RPO change in `compliance/cer/resilience-plan.md`.

## Sources

- [Directive (EU) 2022/2557](https://eur-lex.europa.eu/eli/dir/2022/2557/oj) — Art. 12 (risk assessment, at least every four years), Art. 13 (resilience measures), Annex (sectors)
