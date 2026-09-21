# Resilience Plan — Supplier Side

Requirements: `REQ-CER-03` (prevention / protection / response / recovery, RTO/RPO, backup and restore), `REQ-CER-04` (a tested restore, with date and result), `REQ-CER-05` (degraded mode per declared dependency).
Directive: [Directive (EU) 2022/2557](https://eur-lex.europa.eu/eli/dir/2022/2557/oj), Art. 13.
Owner: **A18**. Dependencies and failure modes: `compliance/cer/criticality-assessment.md`.

Art. 13 obliges the **critical entity** to hold a resilience plan. This is the
supplier-side section of that plan: what the product does, what the operator
must do, and the numbers the operator can commit to. It is not the operator's
plan, and it does not cover the operator's site, network or people.

## Art. 13 measures, mapped

| Art. 13(1) | Measure | Product | Operator |
|---|---|---|---|
| (a) | Prevent incidents | Secure defaults (`REQ-CRA-02`), build-blocking advisory scans (`REQ-SUP-02`), reproducible digest-pinned images (`REQ-FND-09`), two independent security reviews per change (`REQ-GAT-02`) | Patching the host, applying our security releases, capacity headroom |
| (b) | Adequate physical protection | **None** | All of it (`REQ-CER-08`, `compliance/cer/applicability.md`) |
| (c) | Respond to, resist and mitigate | Degraded modes below, rate limiting (`REQ-SEC-11`), tenant isolation limiting blast radius (`REQ-RBA-04`), one incident process (`compliance/cer/incident-response.md`) | Detection, escalation to us, its own crisis management |
| (d) | Recover, including business continuity | Backup and restore procedure below, PITR, degraded modes, provenance-based re-ingest (`REQ-DAT-05`) | Running the backups, holding the media, performing the restore |
| (e) | Employee security management | Personnel posture for manufacturer staff (`compliance/cer/incident-response.md` §Personnel security, `REQ-CER-07`) | Its own staff, including background checks under Art. 14 |
| (f) | Awareness among personnel | This document set; the runbook rehearsal record (`REQ-CRA-06`) | Its own awareness programme |

## Prevention

- One env schema, validated at boot; no silent default for a security-relevant
  key (`REQ-FND-07`). A misconfigured stack fails to start rather than running
  weakened.
- Every dependency checked against known-vulnerability sources on every build; a
  known-exploited or critical advisory blocks the build (`REQ-SUP-02`), plus a
  first-party suspicious-code scan (`REQ-SUP-03`).
- Reproducible builds from digest-pinned bases with `--frozen-lockfile`
  (`REQ-FND-09`): the artefact that runs is the artefact that was reviewed.
- Minimal, documented egress through one client with an allowlist, timeouts and
  SSRF guards (`REQ-SEC-12`, `REQ-SUP-08`).
- Append-only, hash-chained audit (`REQ-AUD-03`, `REQ-AUD-06`) so a quiet
  compromise does not stay quiet.

## Protection

- Encrypted on every interface, compose network included (`REQ-SEC-01`).
- Postgres refuses to be reached in cleartext: `sslmode=verify-full` with a
  pinned CA, enforced at boot (`REQ-SEC-03`).
- Sensitive columns sealed with envelope encryption under a rotatable KEK
  (`REQ-SEC-06`); Argon2id where verification suffices (`REQ-SEC-07`).
- RLS `FORCE`d on every tenant-scoped table, app role cannot bypass, proven by a
  cross-tenant test per table (`REQ-RBA-04`, `REQ-RBA-05`).
- Physical protection is the operator's, entirely (`REQ-CER-08`).

## Response

The incident process is `compliance/cer/incident-response.md` — one process,
with two reporting outputs: CRA Art. 14 (manufacturer to ENISA and the CSIRT)
and CER Art. 15 (operator to its competent authority). Roles, severities and
escalation live there and are not restated here.

## Recovery — RTO and RPO

Committed for the product's own components. The operator's end-to-end targets
for its essential service are larger and are its own.

| Scenario | RTO | RPO | Basis |
|---|---|---|---|
| App container failure | `<<PLACEHOLDER: minutes — typically restart time>>` | **0** | Stateless app; all state is in Postgres (`REQ-FND-05`) |
| Host failure, database intact | `<<PLACEHOLDER: minutes>>` | **0** | Redeploy digest-pinned images against the same volume |
| Database failure, restore from backup needed | `<<PLACEHOLDER: hours — must cover restore + WAL replay + smoke test>>` | `<<PLACEHOLDER: minutes — equals the WAL shipping interval>>` | Base backup plus WAL replay, below |
| Data corruption, PITR to a point before it | `<<PLACEHOLDER: hours>>` | `<<PLACEHOLDER: the recovery target is chosen, so RPO is the corruption-detection delay>>` | Hash-chain verify and referential checks bound the detection delay |
| Total site loss | `<<PLACEHOLDER: hours — operator's DR target>>` | `<<PLACEHOLDER: minutes — offsite WAL shipping lag>>` | Offsite copies; **operator's** |

**These numbers are claims until the rehearsal log below shows a restore that
met them.** An RTO that has never been measured is a wish.

The RPO arithmetic is not a matter of opinion:

```
RPO ≈ archive_timeout + WAL shipping latency + archive verification lag
```

So an `archive_timeout` of 60 s with prompt offsite shipping yields an RPO of a
few minutes. Raising `archive_timeout` raises the RPO by the same amount. Write
the chosen value down:
`<<PLACEHOLDER: archive_timeout, shipping mechanism, and the resulting RPO>>`.

## What is backed up

| Item | Contains | Backed up | Frequency | Retention |
|---|---|---|---|---|
| Postgres base backup | Everything: tenants, users, credentials, MFA factors, audit trail, canonical data | Yes | `<<PLACEHOLDER: e.g. nightly>>` | `<<PLACEHOLDER: e.g. 35 days>>` |
| WAL archive | Every committed change since the last base backup | Yes, continuously | `archive_timeout` `<<PLACEHOLDER>>` | `<<PLACEHOLDER: at least as long as the base backups it applies to>>` |
| Environment configuration (`.env`) | Connection strings, `SYSLOG_TLS_URL`, `EGRESS_ALLOWLIST`, **and `CRYPTO_KEK`** | **Separately — see KEK custody** | On change | `<<PLACEHOLDER>>` |
| TLS certificates and private keys | Ingress, Postgres, SMTP, syslog | Operator's PKI backup, not here | On issuance | `<<PLACEHOLDER>>` |
| Container images | The exact artefact, by digest | Registry plus a local mirror | Per release | Support period |
| Audit export per tenant | Portable evidence copy (`REQ-AUD-13`) | Yes, where the operator requires it | `<<PLACEHOLDER>>` | `<<PLACEHOLDER: respect legal hold — it blocks purge>>` |
| Syslog on the collector | Off-host evidence copy | Operator's collector retention | Continuous | `<<PLACEHOLDER>>` |

There is no secondary datastore to back up: Postgres is the only state that
survives a restart (`REQ-FND-05`). That is a deliberate simplification of
recovery, and it is why the database backup is the whole game.

## KEK custody relative to the backup — the part that gets this wrong

Sensitive columns — TOTP seeds, recovery codes, OIDC client secrets, API key
material, SMTP credentials — are sealed with envelope encryption under
`CRYPTO_KEK` (`REQ-SEC-06`). The ciphertext is in the database. The KEK is not.

Two failure modes, and they pull in opposite directions:

1. **KEK in the same backup as the database** → the backup is a
   plaintext-equivalent copy of every secret in the system. Whoever holds the
   backup holds the estate. This defeats `REQ-SEC-06` entirely.
2. **KEK not backed up at all** → a restored database is unreadable in its
   sealed columns. Every MFA factor, OIDC client secret and API key is lost,
   permanently. There is no recovery path; the failure mode in
   `criticality-assessment.md` marked "no recovery" is this one.

So the rule is: **the KEK is backed up, and it is backed up somewhere the
database backup is not.**

| Requirement | Detail |
|---|---|
| Storage | A secret manager or HSM, or a sealed offline copy under dual control — **never** the same bucket, volume, snapshot or tape as the database backup |
| Custody | At least two named holders so one person's absence is not a data-loss event: `<<PLACEHOLDER: named custodians and the dual-control mechanism>>` |
| Versioning | `kek_version` is stamped on every ciphertext; **every KEK version that any retained backup was written under must be retained**, not just the current one |
| Rotation | `rotateKek()` re-wraps DEKs without reading plaintext. Rotation does not let you discard the old version while a backup written under it is still in retention |
| Retirement | A KEK version may be destroyed only after every backup sealed under it has passed retention: `<<PLACEHOLDER: KEK retirement check, owner, cadence>>` |
| Verified by | The restore rehearsal below. A rehearsal that does not decrypt a sealed column has not tested the restore |

## Backup and restore procedure

Postgres continuous archiving with point-in-time recovery. Commands are the
operator's to run; the product's role is to boot only against a database that
satisfies `REQ-SEC-03` and to fail loudly otherwise.

**Configure archiving** (`<<PLACEHOLDER: postgresql.conf values as deployed>>`):

```
wal_level = replica
archive_mode = on
archive_command = '<<PLACEHOLDER: command shipping WAL offsite, e.g. to object storage>>'
archive_timeout = '<<PLACEHOLDER: seconds — this is your RPO floor>>'
```

**Base backup:**

```bash
pg_basebackup -h <<PLACEHOLDER: host>> -U <<PLACEHOLDER: backup role>> \
  -D /backup/base/$(date -u +%Y%m%dT%H%M%SZ) -Ft -z -Xs -P \
  --checkpoint=fast
# then verify the archive is readable and record its checksum
```

**Restore to a point in time:**

1. Stop the app first: `docker compose stop app`. Never restore under a live
   writer.
2. Provision an empty data directory and restore the most recent base backup
   that predates the recovery target.
3. Create `recovery.signal` and set the target:
   ```
   restore_command = '<<PLACEHOLDER: command fetching an archived WAL segment>>'
   recovery_target_time = '<<PLACEHOLDER: YYYY-MM-DD HH:mm:ss+00>>'
   recovery_target_action = 'promote'
   ```
4. Start Postgres and let WAL replay reach the target. Confirm promotion in the
   server log; do not proceed on assumption.
5. Restore `CRYPTO_KEK` **and every `kek_version` present in the restored rows**
   from the separate custody store.
6. Bring the app up. Boot validates the env schema and the TLS requirements
   (`REQ-FND-07`, `REQ-SEC-03`); a failure here is the restore telling you
   something is wrong, not an inconvenience.
7. Smoke test, in this order, because each step proves a different layer:
   - `curl -sf https://<host>/api/health/ready` → 200 with DB, migrations, SMTP
     and syslog reported (`REQ-FND-10`).
   - Log in with a local password+TOTP account: proves the KEK decrypts the TOTP
     seed (`REQ-SEC-06`, `REQ-AUT-01`).
   - Run the audit hash-chain verify job: proves the trail survived replay
     (`REQ-AUD-06`).
   - Read one row in each of two tenants as the wrong tenant and confirm zero
     rows: proves RLS came back with the data (`REQ-RBA-05`).
   - Send a test mail from the SMTP diagnostics page (`REQ-MAIL-06`).
8. Record the outcome in the rehearsal log. Then revoke sessions and API keys if
   the restore rolled back past their creation.

**How this meets the RTO.** Restore time is base-backup transfer + WAL replay +
smoke test. Measured at the last rehearsal:
`<<PLACEHOLDER: measured minutes for each of the three phases>>`. If the sum
exceeds the RTO above, the RTO is wrong or the backup strategy is — fix one, do
not round the number down.

## Restore rehearsal log (REQ-CER-04)

`REQ-CER-04` requires a **tested** restore: the date and the result, not the
procedure. An empty table here is a failed requirement, and the only honest way
to show it is to leave it visibly empty rather than to describe a rehearsal that
did not happen.

| Date | Performed by | Scenario | Target | Restore time | Data loss | Sealed column decrypted | Result | Findings |
|---|---|---|---|---|---|---|---|---|
| `<<PLACEHOLDER: YYYY-MM-DD>>` | `<<PLACEHOLDER: name, role>>` | `<<PLACEHOLDER: e.g. full loss of the database volume>>` | `<<PLACEHOLDER: recovery target time>>` | `<<PLACEHOLDER: minutes, measured>>` | `<<PLACEHOLDER: minutes of transactions lost>>` | `<<PLACEHOLDER: yes/no — TOTP login succeeded>>` | `<<PLACEHOLDER: pass/fail>>` | `<<PLACEHOLDER: what broke and what changed>>` |

| Field | Value |
|---|---|
| Rehearsal cadence | At least every 6 months, and after any change to the backup mechanism |
| Last rehearsal | `<<PLACEHOLDER: YYYY-MM-DD>>` |
| Result | `<<PLACEHOLDER: pass/fail>>` |
| **Next rehearsal due** | `<<PLACEHOLDER: YYYY-MM-DD>>` |
| Owner | `<<PLACEHOLDER: named role>>` |

A rehearsal counts only if it restored to a **separate** environment from a
backup nobody touched for the occasion, and step 7's smoke test passed in full.
A `pg_restore` that exited zero is not a tested restore.

## Degraded-mode behaviour per dependency (REQ-CER-05)

The rule across all of them: **fail visibly and refuse writes rather than accept
a write that cannot be audited.** An unaudited write in a panel of record is
worse than a rejected one.

### D1 Database — unreachable

Total outage. The app serves a maintenance state, login is refused outright
rather than partially succeeding, `/api/health/ready` reports the DB check as
failed, and the debug console surfaces the connection error. No write is queued
client-side to be replayed later: a queued write is a lie about durability.

### D1 Database — read-only (disk full, replica promotion pending, deliberate)

- Reads, list views, filters and exports keep working.
- Every write path returns a typed error in the RFC 9457 envelope with a stable
  code (`REQ-API-10`) — not a 500, so the UI can say what is actually happening.
- **Login is refused** where session creation requires a write (`REQ-AUT-10`).
  Existing sessions continue read-only.
- A read-only banner is shown application-wide.
- **Read-audit writes fail too** (`REQ-AUD-02`). The audit gap is unavoidable
  and must be recorded: `<<PLACEHOLDER: who records the audit-gap window, and
  where>>`.

### D2 Identity provider — down

- Federated login fails at the discovery or token step and reports a specific
  error, not a generic failure.
- Local password+TOTP and passkey logins continue **if the tenant left them
  enabled** (`REQ-AUT-04`). A tenant that disabled them has made the IdP a
  single point of failure for login, and that decision is theirs and audited.
- Existing sessions survive to expiry (`REQ-AUT-10`).
- Break-glass: `<<PLACEHOLDER: global-tier local account, where the credential
  lives, who may use it, and the audit expectation on use>>`.
- Recovery needs no action in the product; the discovery document is re-fetched.

### D3 SMTP — down or refusing TLS

- Nothing is sent from a request path, so no user-facing action fails because
  mail is down (`REQ-MAIL-04`).
- The durable outbox retries with backoff and dead-letters after
  `<<PLACEHOLDER: attempts and window>>`; each attempt emits a delivery audit
  event.
- Flows that **depend** on mail — email verification, password reset — tell the
  user mail is delayed instead of reporting success.
- Operator diagnostics show last errors and a connection probe without
  revealing credentials (`REQ-MAIL-06`).
- STARTTLS-optional is never a fallback (`REQ-SEC-04`): a relay that cannot do
  TLS is a relay we do not send to.

### D4 Syslog collector — unreachable

- The Postgres audit trail continues and remains authoritative (`REQ-AUD-03`).
- Syslog spools locally with backpressure (`REQ-AUD-07`) up to
  `<<PLACEHOLDER: spool size and the backpressure behaviour at the limit>>`.
- `/api/health/ready` reports the syslog sink as degraded; the stack stays up,
  because stopping the panel over a lost log sink would convert an evidence
  problem into an availability incident.
- On recovery the spool drains in order. If it overflowed, the gap window is
  recorded: `<<PLACEHOLDER: where the overflow window is recorded>>`.
- Plain UDP is never a fallback (`REQ-SEC-05`).

### D5 Push service — failing

- Per-subscription delivery failures are counted; a permanently failing
  subscription is pruned and the client re-subscribes (`REQ-PWA-02`).
- In-app and email channels continue; preferences are per-category and
  per-channel with a digest option (`REQ-PWA-06`).
- No confidentiality consequence: payloads carry a reference the client resolves
  over TLS after authenticating (`REQ-PWA-04`).
- iOS/Safari already takes the graceful path, so this is not a new code path.

### D6 Registry — unavailable

Running stacks are unaffected. Deploys, scale-outs and restores stop. Mitigation
is a local digest-pinned mirror: `<<PLACEHOLDER: mirror location and refresh
cadence>>`. A disaster recovery plan that assumes the public registry is
reachable is not a plan.

### D7 TLS certificate expiry

No degraded mode, deliberately: there is no cleartext fallback anywhere
(`REQ-SEC-01`). Postgres client verification failing means the app will not
start (`REQ-SEC-03`). The control is expiry monitoring with lead time, and it is
the operator's: `<<PLACEHOLDER: expiry monitoring, alert lead time, owner>>`.

## Plan review

| Field | Value |
|---|---|
| Last review | `<<PLACEHOLDER: YYYY-MM-DD>>` |
| Next review | `<<PLACEHOLDER: YYYY-MM-DD — at least annually, and on the four-yearly assessment cycle>>` |
| Triggers for early review | An RTO/RPO change, a failed rehearsal, a dependency change, a Sev-1 incident |
| Owner | `<<PLACEHOLDER: named role>>` |

## Sources

- [Directive (EU) 2022/2557](https://eur-lex.europa.eu/eli/dir/2022/2557/oj) — Art. 13 resilience measures
- [PostgreSQL — continuous archiving and point-in-time recovery](https://www.postgresql.org/docs/current/continuous-archiving.html)
