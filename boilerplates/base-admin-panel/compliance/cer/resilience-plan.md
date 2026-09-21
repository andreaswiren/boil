# Resilience Plan — Supplier Side

Requirements: `REQ-CER-03` (prevention / protection / response / recovery, RTO/RPO, backup and restore), `REQ-CER-04` (a tested restore, with date and result), `REQ-CER-05` (degraded mode per declared dependency).
Directive: [Directive (EU) 2022/2557](https://eur-lex.europa.eu/eli/dir/2022/2557/oj), Art. 13.
Owner: **A18**. Dependencies and failure modes: `compliance/cer/criticality-assessment.md`.

Art. 13 obliges the **critical entity** to hold a resilience plan. This is the
supplier-side section of that plan: what the product does, what the operator
must do, and the numbers the operator can commit to. It is not the operator's
plan, and it does not cover the operator's site, network or people.

Art. 13(1) asks the entity for measures to prevent incidents (a), protect
premises physically (b), respond and mitigate (c), recover and continue the
service (d), manage employee security (e) and raise awareness (f). (b) and the
operator's half of every other row are in `compliance/cer/applicability.md`
§The split table; (e) is `compliance/cer/incident-response.md` §Personnel
security. The four sections below are the product's half.

## Prevention and protection

- One env schema validated at boot, no silent default for a security-relevant
  key (`REQ-FND-07`): a misconfigured stack fails to start rather than run
  weakened. Build-blocking advisory and suspicious-code scans (`REQ-SUP-02`,
  `REQ-SUP-03`). Reproducible digest-pinned builds (`REQ-FND-09`).
- Encryption on every interface including the compose network (`REQ-SEC-01`),
  Postgres unreachable in cleartext by construction (`REQ-SEC-03`), sensitive
  columns sealed under a rotatable KEK (`REQ-SEC-06`).
- RLS `FORCE`d with a non-owner app role, proven per table (`REQ-RBA-04`,
  `REQ-RBA-05`), bounding the blast radius of one compromised session. Minimal
  documented egress (`REQ-SEC-12`, `REQ-SUP-08`). Append-only hash-chained audit
  so a quiet compromise does not stay quiet (`REQ-AUD-03`, `REQ-AUD-06`).
- Physical protection: the operator's, entirely (`REQ-CER-08`).

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
met them.** An RTO that has never been measured is a wish. The RPO arithmetic is
not a matter of opinion:

```
RPO ≈ archive_timeout + WAL shipping latency + archive verification lag
```

Raising `archive_timeout` raises the RPO by the same amount. Write the chosen
values down: `<<PLACEHOLDER: archive_timeout, shipping mechanism, resulting
RPO>>`.

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
survives a restart (`REQ-FND-05`). That simplifies recovery, and it is why the
database backup is the whole game.

## KEK custody relative to the backup — the part that gets this wrong

Sensitive columns — TOTP seeds, recovery codes, OIDC client secrets, API key
material, SMTP credentials — are sealed with envelope encryption under
`CRYPTO_KEK` (`REQ-SEC-06`). The ciphertext is in the database. The KEK is not.

Two failure modes pull in opposite directions. **KEK in the same backup as the
database**: the backup becomes a plaintext-equivalent copy of every secret in
the system, and whoever holds it holds the estate — `REQ-SEC-06` defeated.
**KEK not backed up at all**: a restored database has unreadable sealed columns,
and every MFA factor, OIDC client secret and API key is permanently lost — the
"no recovery" row in `criticality-assessment.md` is this one.

So the rule is: **the KEK is backed up, and it is backed up somewhere the
database backup is not.**

| Requirement | Detail |
|---|---|
| Storage | A secret manager or HSM, or a sealed offline copy under dual control — **never** the same bucket, volume, snapshot or tape as the database backup |
| Custody | At least two named holders, so one absence is not a data-loss event: `<<PLACEHOLDER: named custodians and dual-control mechanism>>` |
| Versioning | `kek_version` is stamped on every ciphertext; **every KEK version that any retained backup was written under must be retained**, not just the current one |
| Rotation and retirement | `rotateKek()` re-wraps DEKs without reading plaintext, but an old version may be destroyed only once every backup sealed under it has passed retention: `<<PLACEHOLDER: retirement check, owner, cadence>>` |
| Verified by | The restore rehearsal below. A rehearsal that does not decrypt a sealed column has not tested the restore |

## Backup and restore procedure

Postgres continuous archiving with point-in-time recovery. The operator runs
these; the product's part is to boot only against a database satisfying
`REQ-SEC-03`, and to fail loudly otherwise.

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

1. Stop the app: `docker compose stop app`. Never restore under a live writer.
2. Provision an empty data directory and restore the most recent base backup
   predating the recovery target.
3. Create `recovery.signal` and set the target:
   ```
   restore_command = '<<PLACEHOLDER: command fetching an archived WAL segment>>'
   recovery_target_time = '<<PLACEHOLDER: YYYY-MM-DD HH:mm:ss+00>>'
   recovery_target_action = 'promote'
   ```
4. Start Postgres, let WAL replay reach the target, and confirm promotion in the
   server log rather than assuming it.
5. Restore `CRYPTO_KEK` **and every `kek_version` present in the restored rows**
   from the separate custody store.
6. Bring the app up. Boot validates the env schema and TLS requirements
   (`REQ-FND-07`, `REQ-SEC-03`); a failure here is the restore telling you
   something is wrong.
7. Smoke test in this order — each step proves a different layer:
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

Cadence: at least every 6 months and after any change to the backup mechanism.
Last rehearsal `<<PLACEHOLDER: YYYY-MM-DD>>`, result
`<<PLACEHOLDER: pass/fail>>`, **next due** `<<PLACEHOLDER: YYYY-MM-DD>>`, owner
`<<PLACEHOLDER: named role>>`.

A rehearsal counts only if it restored into a **separate** environment, from a
backup nobody touched for the occasion, with step 7's smoke test passing in
full. A `pg_restore` that exited zero is not a tested restore.

## Degraded-mode behaviour per dependency (REQ-CER-05)

The rule across all of them: **fail visibly and refuse writes rather than accept
a write that cannot be audited.** An unaudited write in a panel of record is
worse than a rejected one.

### D1 Database — unreachable

Total outage. The app serves a maintenance state, login is refused outright
rather than partially succeeding, `/api/health/ready` fails the DB check, and the
console surfaces the connection error. No write is queued client-side for later
replay: a queued write is a lie about durability.

### D1 Database — read-only (disk full, replica promotion pending, deliberate)

- Reads, list views, filters and exports keep working, behind an
  application-wide read-only banner.
- Every write path returns a typed RFC 9457 error with a stable code
  (`REQ-API-10`), not a 500, so the UI can say what is happening.
- **Login is refused** where session creation requires a write (`REQ-AUT-10`);
  existing sessions continue read-only.
- **Read-audit writes fail too** (`REQ-AUD-02`). The gap is unavoidable and is
  recorded: `<<PLACEHOLDER: who records the audit-gap window, and where>>`.

### D2 Identity provider — down

- Federated login fails at the discovery or token step with a specific error,
  not a generic failure. Existing sessions survive to expiry (`REQ-AUT-10`).
- Local password+TOTP and passkey logins continue **if the tenant left them
  enabled** (`REQ-AUT-04`). A tenant that disabled them has made the IdP a
  single point of failure for login — their decision, and audited.
- Break-glass: `<<PLACEHOLDER: global-tier local account, where the credential
  lives, who may use it, and the audit expectation on use>>`.
- Recovery needs no product action; the discovery document is re-fetched.

### D3 SMTP — down or refusing TLS

- Nothing is sent from a request path, so no user-facing action fails because
  mail is down (`REQ-MAIL-04`). The durable outbox retries with backoff and
  dead-letters after `<<PLACEHOLDER: attempts and window>>`, with a delivery
  audit event per attempt.
- Flows that **depend** on mail — verification, password reset — tell the user
  mail is delayed instead of reporting success.
- Operator diagnostics show last errors and a connection probe without revealing
  credentials (`REQ-MAIL-06`). STARTTLS-optional is never a fallback
  (`REQ-SEC-04`): a relay that cannot do TLS is one we do not send to.

### D4 Syslog collector — unreachable

- The Postgres audit trail continues and remains authoritative (`REQ-AUD-03`).
  Syslog spools locally with backpressure (`REQ-AUD-07`) up to
  `<<PLACEHOLDER: spool size and behaviour at the limit>>`.
- `/api/health/ready` reports the sink as degraded and the stack stays up:
  stopping the panel over a lost log sink would turn an evidence problem into an
  availability incident.
- On recovery the spool drains in order; an overflow window is recorded at
  `<<PLACEHOLDER: where the overflow window is recorded>>`. Plain UDP is never a
  fallback (`REQ-SEC-05`).

### D5 Push service — failing

- Delivery failures are counted per subscription; a permanently failing one is
  pruned and the client re-subscribes (`REQ-PWA-02`).
- In-app and email channels continue, per category and per channel, with a
  digest option (`REQ-PWA-06`).
- No confidentiality consequence: payloads carry only a reference the client
  resolves over TLS after authenticating (`REQ-PWA-04`). The iOS/Safari path is
  already the graceful one, so this is not a new code path.

### D6 Registry unavailable, D7 certificate expired

Neither has a degraded mode, deliberately. A registry outage leaves running
stacks alone but stops every deploy, scale-out and **restore**; the mitigation
is a local digest-pinned mirror at `<<PLACEHOLDER: mirror location and refresh
cadence>>`, because a DR plan that assumes the public registry is reachable is
not a plan. An expired certificate fails hard: there is no cleartext fallback
anywhere (`REQ-SEC-01`) and a failed Postgres client verification stops the app
from starting (`REQ-SEC-03`). The control is expiry monitoring with lead time,
and it is the operator's: `<<PLACEHOLDER: expiry monitoring, alert lead time,
owner>>`.

## Plan review

Last review `<<PLACEHOLDER: YYYY-MM-DD>>`, next review
`<<PLACEHOLDER: YYYY-MM-DD — at least annually, and on the four-yearly
assessment cycle>>`, owner `<<PLACEHOLDER: named role>>`. Reviewed early on an
RTO/RPO change, a failed rehearsal, a dependency change or a Sev-1 incident.

## Sources

- [Directive (EU) 2022/2557](https://eur-lex.europa.eu/eli/dir/2022/2557/oj) — Art. 13 resilience measures
- [PostgreSQL — continuous archiving and point-in-time recovery](https://www.postgresql.org/docs/current/continuous-archiving.html)
