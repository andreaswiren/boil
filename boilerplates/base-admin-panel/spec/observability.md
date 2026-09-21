# Audit, Logging & the Debug Console

The audit trail, the log pipeline, syslog forwarding and the in-app debug
console. Owned by **A13** (`audit-observability`): `packages/audit/**`,
`packages/logging/**`, `packages/syslog/**`,
`apps/<app>/app/(app)/console/**`, and the tables `audit_events`,
`audit_chain`, `syslog_spool`, `log_sinks`. A13 publishes
`audit-event`, `log-record`, `console-stream` and `redaction`; it consumes
`entity-base`, `session`, `tenancy` and `theme-tokens`. Other agents **emit**;
A13 is the only writer of an audit row. That is why no domain can decide not to
be audited.

## Requirements covered

REQ-AUD-01 … REQ-AUD-13, REQ-SEC-05, REQ-FND-05, REQ-ENT-01, REQ-RBA-07,
REQ-PWA-04, REQ-UI-11, REQ-SET-04, REQ-SET-05, REQ-SET-09, REQ-TST-05,
REQ-TST-08, REQ-CTR-08.

## 1. The audit event, field by field (REQ-AUD-04)

The envelope is frozen in `contracts/events/audit-event.md` §1 —
`AuditEventSchema`, `.strict()`. This section is how it is stored and why the
shape is what it is, not a second copy of the schema.

```sql
audit_events (A13)  -- append-only (§3), tenant-scoped, RLS forced, entity-base exempt
  id               uuid        primary key,
  occurred_at      timestamptz not null,   -- UTC instant the action completed or was refused
  kind             text        not null,   -- write | read | view | auth | policy | system
  action           text        not null,   -- "rbac.role.write" — permission-shaped (§2)
  result           text        not null,   -- success | denied | failed | expired
  tenant_id        uuid,                   -- null only for a global action outside a tenant
  tenant_snapshot  jsonb,                  -- TenantRef at the time
  actor            jsonb       not null,   -- ActorRef snapshot; the SUBJECT under impersonation
  on_behalf_of     jsonb,                  -- ActorRef of the impersonating operator
  impersonation_id uuid,                   -- correlates enter, every action inside, and exit
  permission       text,                   -- the permission demanded; null if authenticated-only
  target           jsonb,                  -- { kind: "<domain>.<resource>", id, label }
  diff             jsonb,                  -- { before, after }, redacted (§4). Null for reads
  comment          text,                   -- the actor's reason, from the write envelope
  correlation_id   uuid        not null,
  ip               inet        not null,
  user_agent       text        not null,
  source           text        not null,   -- web | api | system | collector
  sampling         jsonb,                  -- §2. Null for everything that is not a view
  chain_seq        bigint      not null,   -- per-chain, gapless, from 1
  chain_prev_hash  bytea       not null,
  chain_hash       bytea       not null
```

Notes that are decisions, not descriptions:

- **`actor` is a snapshot, not a foreign key.** Id, kind and label as they were.
  The trail stays readable after the user is renamed, the key revoked or the
  collector decommissioned (`spec/entity-model.md` §2). `target.label` exists
  for the same reason: after a purge there is no row to join to.
- **`actor` is the subject and `on_behalf_of` is the operator** under
  impersonation, fixed by `contracts/types/identity.md` §6 and not restated
  differently here. Reading it the other way round makes every impersonated
  action look like the operator's own.
- **`kind` is separate from `action`** because the aggregation policy keys on it
  (§2) and because "what kind of thing happened" is the first filter an
  investigator applies.
- **`permission` records what was demanded**, which is what makes a denial
  reviewable: `result: "denied"` plus the permission the caller lacked.
- **There is no `severity` column.** Notification urgency is a property of the
  event *name*, resolved from a table A13 owns, not a field a caller can set —
  a caller-set severity is a caller-set alerting policy. `critical` names
  (`global.auth-policy.mfa-disable`, `audit.chain.verify` with
  `result: "failed"`, `global.impersonation.enter`, `*.purge`) page the global
  operators.
- **There is no `recorded_at`.** A spooled or retried emission inserts late, but
  `occurred_at` is the instant the action completed and `chain_seq` gives the
  insert order; two columns for the same question invite two answers.
- A missing `correlation_id` fails the emission. An event that cannot be tied to
  a request cannot be explained.

Every event REQ-AUD-01 lists has a name in the frozen taxonomy
(`contracts/events/audit-event.md` §2): the five write shapes, reads and lists,
export, the auth lifecycle, policy and role changes, tenant lifecycle,
impersonation entry and exit, the five API-key events, mail delivery, agent
enrolment and revocation, chain verify, and rate-limit trips. A domain that
needs a new one declares it in its own namespace — additive.

## 2. Read and view logging (REQ-AUD-02)

Reads are audited. The policy differs by read shape, and the contract splits the
two into distinct `kind` values so the difference is in the data rather than in
a convention:

| `kind` | Shape | Policy |
|---|---|---|
| `read` | A detail read of one identified resource | **Always one event. Never sampled.** This is the one that matters in an investigation: "who opened this customer's record" |
| `view` | A list, grid page or search result render | **Aggregated** per `(actor, tenant, target.kind, action, query fingerprint)` per window |
| `view` with `result: "denied"` | A refused read | Never aggregated. One row, always |

**The window is 300 s**, set by `AUDIT_VIEW_WINDOW_SECONDS`. Shorter and a normal
grid session still writes dozens of rows; longer and the trail stops showing
*when* someone was looking. At five minutes one actor browsing one resource with
one filter writes at most 12 rows an hour, so a working day of an operator's
list reads is of the order of 100 rows and a year around 25 000 — a size that
can be kept, indexed and read. `0` disables aggregation and records every view:
supported, expensive, and not the default.

The query fingerprint is a SHA-256 of the canonicalised `PageParams`
(`contracts/types/pagination.md` §2), so "same filter, same page" collapses and
"different filter" does not. A window never spans a tenant, an actor or an
impersonation session.

**How the aggregate is written, and why it is the one exception to append-only.**
The first view in a window writes the row with `sampling.aggregatedCount: 1`.
Subsequent identical views increment that counter and `sampling.windowEnd` on
the same row — an `UPDATE` of two fields, through a `SECURITY DEFINER` function
owned by `app_owner`, which is the only grant in the system that may touch an
existing audit row. Neither field is in the hash input (§5), so the counter
cannot break tamper evidence.

The alternative — a separate staging table flushed on window close — was
rejected: it needs its own retention, its own RLS, its own crash recovery, and
it puts the newest reads somewhere the audit viewer does not look. One row that
counts up is less machinery and it is queryable the moment it exists.

REQ-TST-08 names read-audit emission as one of the three easily-faked
behaviours. A23 asserts a detail read writes exactly one row and ten identical
list renders write one row with `aggregatedCount: 10`.

## 3. Append-only, twice over (REQ-AUD-03)

```sql
-- The grant is the control: the app role cannot mutate, at all.
REVOKE UPDATE, DELETE, TRUNCATE ON audit_events, audit_chain FROM app_runtime;
GRANT  SELECT, INSERT ON audit_events, audit_chain TO app_runtime;

-- The trigger catches a role that acquires the privilege later.
CREATE TRIGGER audit_events_append_only
  BEFORE UPDATE OR DELETE ON audit_events
  FOR EACH ROW EXECUTE FUNCTION audit_append_only_guard();   -- raises audit.append_only_violation
CREATE TRIGGER audit_events_no_truncate
  BEFORE TRUNCATE ON audit_events
  FOR EACH STATEMENT EXECUTE FUNCTION audit_append_only_guard();
```

Both, because each covers the other's gap. Privileges stop the application but
not the migration role, and a future `GRANT` is one line. The trigger stops the
owner too — including a migration that means well — but a trigger can be
disabled by the owner, so `pnpm lint:migrations` fails on `DISABLE TRIGGER`
against these tables and the self-test asserts `tgenabled = 'O'` on all four.

Exactly two paths may touch an existing audit row, and both are named:

1. The view-counter function of §2, `SECURITY DEFINER`, two fields only.
2. Retention purge (§8), a separate maintenance role holding `DELETE` and
   nothing else, itself audited and blocked by legal hold.

The RLS policy is insert-shaped — `FOR INSERT WITH CHECK (tenant_id = …)` plus a
`SELECT` policy, and no `UPDATE` or `DELETE` policy exists at all
(`contracts/db/rls-contract.md` §5). A missing policy and a missing grant are
two independent reasons the same statement fails.

## 4. Redaction (REQ-AUD-05, REQ-AUD-12)

Redaction happens **in the emitter, before the row exists** — not at render, not
at export, not in the console. Those all read an already-clean row, which is why
there is one implementation to review rather than five.

A domain declares its sensitive paths in its own contract declaration; A02
assembles the registry; A13 applies it. Registry, never a shared list.

```ts
redact: [
  { path: "credentials.secret", mode: "drop" },
  { path: "user.email",         mode: "hash" },
  { path: "device.serial",      mode: "mask" },
]
```

| Mode | Effect | Use when |
|---|---|---|
| `drop` | The key is removed entirely | A secret. Its presence is not informative |
| `mask` | A type-shaped placeholder: `"****"`, `0` | The shape matters, the value does not |
| `hash` | Salted SHA-256, stable per tenant | Two events must be correlatable without the value being readable |

- **The default for an undeclared field in a table that declares any sensitive
  field is `drop`.** An unknown field is not assumed safe — in a 13-agent build
  a newly added column is the likeliest leak.
- Never in a diff in any mode, regardless of declaration: password hashes, TOTP
  seeds, recovery codes, API key material, OIDC client secrets, SMTP
  credentials, VAPID private keys, session cookies, envelope ciphertext and its
  DEK (REQ-SEC-06, REQ-SEC-07).
- The diff records **that** a sensitive field changed:
  `{ before: { secret: "[redacted]" }, after: { secret: "[redacted:changed]" } }`.
  "The seed was rotated" is preserved; the seed is not.
- An event whose diff fails the redaction schema is **written with `diff: null`**
  and `result` unchanged, plus a `system` event `audit.redaction.failure` naming
  the domain and the path. A dropped diff is a bug to fix; a leaked seed is an
  incident.

Where the same registry is applied:

| Sink | Where it runs | Note |
|---|---|---|
| Audit `diff` | In `packages/audit`, before the insert | The row never exists unredacted |
| Log records | In the logger, before any transport | The message too, not only the fields |
| Console frames | At emit, before the frame enters the ring | Plus the secret-shaped detector below (REQ-AUD-12) |
| Problem bodies | In the problem serialiser | `errors[]` carries paths and rule names, never values |
| Push payloads | In `packages/notify` | Second layer: a push carries a reference, not content (REQ-PWA-04) |
| Syslog structured data | Inherited — it serialises an already-redacted log record | One implementation, not two |

Every sink's writer accepts a branded `Redacted<T>`, so passing a raw value does
not compile — stronger than a review comment and cheaper than a test. On top of
that, a console frame is checked against a **secret-shaped-value detector**
(JWT-shaped, `ak_live_`-prefixed, PEM blocks, 32+ character high-entropy
strings, `postgres://` URLs); a hit drops the frame, emits a `gap` frame with
`reason: "redaction_failure"` and a `system` audit event.

Grid exports are **not** a redaction sink: an export returns the data the caller
is permitted to read, and it is audited instead (`spec/datagrid.md` §9).

## 5. Tamper evidence: a per-tenant hash chain (REQ-AUD-06)

```
hash = sha256( prevHash || id || occurredAt || tenantId || actorId || action ||
               result || targetKind || targetId || canonicalJson(diff) ||
               correlationId || seq )
genesis prevHash = 64 zeros
```

- One chain per tenant, plus one for `tenant: null` global-tier events, so one
  tenant's volume does not serialise another's writes and an exported tenant
  chain verifies on its own.
- `chain_seq` is gapless per chain and allocated **inside the insert
  transaction** as the audited action's own transaction. An action that cannot
  be chained does not commit.
- `audit_chain` holds the current head per chain: `(tenant_id, seq, hash)`.
  Concurrency is serialised per chain with
  `pg_advisory_xact_lock(hashtext('audit_chain:' || coalesce(tenant_id::text,'global')))`,
  so two concurrent writes cannot claim one `seq`.
- Canonical JSON is key-sorted with no insignificant whitespace, timestamps as
  RFC 3339 `Z`, no exponent form. A hash over implementation-ordered JSON
  verifies on one runtime version and fails on the next.
- `sampling.aggregatedCount` and `sampling.windowEnd` are **excluded from the
  hash input**, which is what makes §2's counter increment possible. Everything
  an investigator relies on is hashed; the affordability counter is not.

The verify job — `audit.chain.verify`, incremental hourly over rows since the
last verified `seq`, full nightly — recomputes each hash and each link and
reports the first `seq` that differs. It emits `audit.chain.verify` with
`result: "success" | "failed"`, and on failure raises `audit.chain_broken`
(500), alerts every global operator, and **does not repair**: the point of
tamper evidence is that it cannot be quietly fixed. The verified head hash is
forwarded to syslog on every run (§6), which puts a copy off the box — a chain
whose heads live only where the rows live can be rewritten wholesale.

## 6. Syslog forwarding (REQ-AUD-07, REQ-SEC-05)

RFC 5424 messages over RFC 5425 TLS with octet-counted framing. Plain UDP/514 is
not a supported configuration; certificate verification is mandatory and the
connection goes through A01's egress client (REQ-SEC-12).

```
<134>1 2026-09-21T12:03:07.412Z panel.example.org admin-panel 1 9f2a4c1e
 [origin ip="10.0.2.15" software="admin-panel" swVersion="1.4.0"]
 [audit@32473 tenant="t-0a91" actor="u-7731" actorKind="user" action="rbac.role.write"
  target="role/ops-lead" result="success" kind="policy" seq="184023"
  correlationId="9f2a4c1e-…" rowHash="4b1c…"]
 role "ops-lead" updated: +device.config.write, -device.config.purge
```

- Facility `local1` for audit-derived messages, `local0` for application logs.
- Syslog severity comes from the source, because the two sources do not share a
  scale: an application log maps from its console level (`fatal→2`, `error→3`,
  `warn→4`, `info→6`, `trace`/`debug→7`), and an audit message maps from the
  event's criticality (§1) — `critical→2`, a `policy` or `auth` event→5,
  everything else→6. A `result: "denied"` or `"failed"` event raises one step,
  so a SIEM rule on severity catches refusals without knowing our taxonomy.
- `MSGID` is the `action`. `PROCID` is the process instance.
- `rowHash` is the event's `chain_hash`; it doubles as the forwarder's dedup key
  and lets a SIEM verify a chain segment it received.
- SD-IDs: standard `origin`, plus `audit@<PEN>` and `app@<PEN>`. The enterprise
  number is `SYSLOG_ENTERPRISE_ID`, default `32473` — the IANA-reserved example
  PEN — because shipping someone else's PEN is worse than shipping the
  documented placeholder, and the operator sets their own.
- The `MSG` body is the English summary. Logs are not translated
  (`spec/i18n.md` §5). Sink configuration is read with `audit.sink.read` and
  changed with `audit.sink.write`; credentials are never returned by either.

**Spooling and backpressure.** The spool is `syslog_spool`, a Postgres table,
because REQ-FND-05 permits no second durable store and a file spool in a
container is lost on the next deploy. Default bound: 1 000 000 rows or 30 days,
whichever comes first.

| Spool state | Behaviour |
|---|---|
| Collector up | Batches of 256, in-order per tenant, at-least-once with `chain_hash` as the dedup key |
| Collector down | Rows accumulate; a `warn` every 60 s with the depth; reconnect with jittered backoff, 1 s → 60 s |
| ≥ 90% of bound | Application `debug` and `info` are dropped first, counted in `syslog.dropped` by level. Audit-derived rows are never dropped |
| 100%, audit-derived only | The oldest audit-derived rows are sealed into one **gap marker** message stating the range, count and the final `chain_hash`, and forwarding continues |

The request path never blocks on syslog. Blocking a tenant's work because a SIEM
is unreachable converts someone else's outage into ours, and the durable record
is already the `audit_events` row — syslog is the forwarded copy. The gap is
therefore reported loudly and the rows remain queryable in the product.

## 7. The debug console (REQ-AUD-08 … REQ-AUD-12)

The protocol — transport, frame, levels, widths, ring sizes, ANSI rules — is
frozen in `contracts/events/console-stream.md`. This section is the surface
built on it and the reasoning behind the numbers that were A13's to choose.

**Route and gate (REQ-AUD-08).** `/(app)/console`, streaming from
`GET /api/v1/audit/console/stream`, permission `audit.console.read`. Without it:
403 `rbac.permission_denied`, with no development bypass. A tenant operator sees
its own tenant's frames plus frames naming no tenant; cross-tenant tailing needs
`global.audit.read-any`, which is global tier and therefore step-up. The filters
are applied server-side **after** the tenant scope, so the browser never
receives a frame the operator is not entitled to. `CONSOLE_ENABLED=false`
returns 503 `audit.console_disabled`. Opening the stream emits
`audit.console.read` — watching the system is itself an audited read.

**Why SSE.** One-directional, no second protocol in the CSP or the reverse
proxy, and `Last-Event-ID` gives resume for free. The controls are ordinary
requests, so a WebSocket would buy a duplex channel nothing needs. A `: ping`
comment every 15 s keeps a proxy from idling the connection out; one stream per
session and four per actor, the fifth refused with `common.rate_limited`.

**Compact mode (REQ-AUD-09).** One frame per line, fixed pitch, aligned columns,
metadata collapsed. The widths are the contract's, and changing one is a
breaking change because every operator's saved layout and every visual baseline
shifts:

```
HH:mm:ss.SSS  LVL  domain........  event...................  message
12:04:31.882  INF  auth            session.login             actor=u_8fd amr=pwd,totp
12:04:32.104  WRN  api             key.first-use             prefix=ak_live_9f2
12:04:33.550  ERR  mail            message.send              outbox=6b1 attempt=3
```

time 12 · level 3 · domain 14 · event 24 · message rest, two spaces between
columns. Compact mode **does not wrap** — a wrapped line destroys the alignment
the mode exists for, so it scrolls horizontally instead. Truncation is `…` with
the full value in the expanded row, and the expanded view is the same frame as
key/value rows. Below `tablet` the console drops to expanded mode entirely: a
390 px viewport cannot honour 53 columns of prefix, and a horizontally
scrolling log on a phone is unusable (REQ-UI-07). The compact/expanded choice
persists in `user_preferences`.

The millisecond time column is rendered by `packages/contracts/time`, which
means A13 needs a `precision` the frozen contract does not yet have — an
additive CCR adding `"milli"` (`spec/time.md` §4). The console does not format
its own timestamps, and a frame never carries a preformatted local time.

**Font (REQ-AUD-10).** JetBrains Mono, self-hosted variable woff2
(REQ-SUP-07), fallback `ui-monospace, SFMono-Regular, Menlo, monospace`. Chosen
for the disambiguated `0/O`, `1/l/I` and `;/:` — a console is where an operator
reads an id character by character — and for a genuine 400/500/700 range so
weight can carry level. `font-variant-numeric: tabular-nums` stops the time
column jittering as digits change.

**Colour (REQ-AUD-10).** Six levels, six tokens, and the three-letter tag
carries the level for a monochrome or colour-blind reader — colour is never the
only encoding:

| Level | Tag | Token |
|---|---|---|
| `trace` | `TRC` | `--console-trace` |
| `debug` | `DBG` | `--console-debug` |
| `info` | `INF` | `--console-info` |
| `warn` | `WRN` | `--console-warn` |
| `error` | `ERR` | `--console-error` |
| `fatal` | `FTL` | `--console-fatal` |

A06 owns the token values as part of the preset, A13 owns their use
(`spec/theming.md` §3); no console code names a colour. Every token is
contrast-checked against `--background` and `--card` at AA in **both** modes by
a unit test over the token pairs, not by eye (REQ-UI-11). Adding a level is a
breaking change, because the level filter is ordered and uses `>=`: inserting
one silently changes what every saved filter means.

**ANSI (REQ-AUD-10).** Frames flagged `ansi: true` carry SGR sequences from a
collector or a child process. Allowed: `0`, `1`, `2`, `22`, `30`–`37`,
`39`–`47`, `49`, `90`–`97`, `100`–`107`, mapped onto the 16 theme tokens.
8-bit and 24-bit colour (`38;5;n`, `38;2;r;g;b`) is quantised to those 16:
honouring arbitrary colour means honouring unreadable colour, and only the 16
are contrast-checked. Stripped always — OSC including OSC 8 hyperlinks, cursor
movement, erase, scroll region, DEC private modes, `\r`, `\b`, `\x07` and every
C1 control other than `ESC [`: a sequence that can move a cursor can forge a
line, and a clickable URL injected into a privileged operator's console is a
phishing primitive. Sequences are parsed into a span tree and rendered as
elements — nothing from a frame reaches `innerHTML` or a `style` attribute, and
the CSP forbids inline style anyway (REQ-SEC-08). Copy and download emit the
**stripped** text, so a pasted log cannot carry escapes into someone's terminal.

**Controls (REQ-AUD-11).**

| Control | Behaviour |
|---|---|
| Level filter | Minimum level or a multi-select, applied server-side to the subscription |
| Domain filter | Multi-select of the contract's domain set, server-side |
| Text filter | Client-side over the ring, substring by default, regex behind a toggle with an invalid-pattern hint |
| Pause / resume | Holds the **client** buffer only; the server keeps dropping into its ring. Header shows `N new`; resume replays from `Last-Event-ID` and shows a `gap` frame if the ring rotated past it. Pause is never a memory leak |
| Follow tail | On by default, disengages when the operator scrolls up, re-engages at the bottom |
| Ring size | 500 … 20 000, operator-set, with the memory cost shown |
| Copy | Selected lines or the buffer, ANSI stripped |
| Download | The **client** buffer, stating how many frames it holds — an operator must not believe they downloaded a complete trail. For that, `audit.event.export` |
| Keyboard | `/` filter, `Space` pause, `g`/`G` top/bottom, `f` follow, `c` compact |

Backpressure is explicit rather than silent: the server ring holds 2 000 frames
per tenant and each subscriber queue 500, both dropping oldest, and a slow
consumer receives one `gap` frame with `dropped` and
`reason: "backpressure"`. The emitter never blocks on a subscriber — a console
reader that cannot keep up loses frames, and the request it was watching still
completes. The audit trail is the record that must not lose rows; the console is
explicitly allowed to, and says when it did.

## 8. Retention, export and legal hold (REQ-AUD-13)

Per-tenant retention, default 400 days — over a year, so an annual review can
always look back one full cycle. Read with `audit.retention.read`, changed with
`audit.retention.write`, or across tenants with `global.audit-retention.write`.
`audit.legal-hold.write` sets and clears the hold.

Purge runs as the maintenance role of §3 and:

- Refuses while `legal_hold` is set, per tenant and per range, with
  `audit.legal_hold_active` (409). A retention change that would shorten under a
  hold is refused the same way.
- Emits `audit.retention.purge` with the range, the row count and the hash of
  the last purged row.
- Writes a **sealed-segment** row into `audit_chain` whose hash covers the
  purged range, and the first retained row's `prev_hash` points at it. The chain
  over what remains still verifies, *and* it shows where a purge happened. A
  purge that silently broke the chain would make §5 useless after the first
  retention run, which is the failure this design exists to avoid. Sealing is
  A13's design on top of the frozen contract, which requires the purge to be
  audited and hold-blocked but does not say how the chain survives it.

Retention, legal hold and the syslog sink are settings panels A13 contributes
through the registry — retention and hold at tenant scope (REQ-SET-04), the sink
and cross-tenant retention at global scope (REQ-SET-05). Each panel's own change
is audited with a before/after diff and the scope it was made at (REQ-SET-09),
and shortening retention across tenants demands typed confirmation naming what
will change and for whom (REQ-SET-10).

Export is per tenant, NDJSON plus the chain heads, permission
`audit.event.export` (step-up, 900 s), and emits `audit.event.export` — the
audit trail's own export is audited like any other.

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Actor on an event | `ActorRef` snapshot, no FK | Readable after the actor is gone | No |
| Severity | Derived from the event name by A13's table, not a field | A caller-set severity is a caller-set alerting policy | No |
| Detail reads | Always one event, never sampled | The question read logging exists for | No |
| List reads | Aggregated per actor+tenant+resource+fingerprint per 300 s | ~100 rows per operator-day instead of thousands | Yes, window only |
| Aggregate mechanics | Counter increment on the row via `SECURITY DEFINER`, two fields, unhashed | A staging table needs its own retention, RLS and crash recovery | No |
| Denied reads | Never aggregated | A refusal is never routine | No |
| Append-only | Absent grant **and** trigger; two named exceptions only | Each covers the other's gap | No |
| Sensitivity default | Undeclared field in a sensitive table = `drop` | Fail closed; a new column is the likeliest leak | No |
| Redaction point | In the emitter, before the row exists | One implementation, not five | No |
| Redaction enforcement | Branded `Redacted<T>` on every sink + the secret-shaped detector | A type error beats a review comment | No |
| Diff that fails redaction | Written with `diff: null` plus `audit.redaction.failure` | A dropped diff is a bug; a leaked seed is an incident | No |
| Chain scope | Per tenant plus one global, `seq` allocated in the action's transaction | Exportable, and unchainable means uncommitted | No |
| Chain break | Alert, never auto-repair | Evidence that can be fixed is not evidence | No |
| Chain anchoring | Verified head forwarded to syslog | An internal-only chain can be rewritten | No |
| Enterprise number | `32473` (IANA example PEN), operator-set | Shipping someone else's PEN is worse | Yes |
| Spool location / bound | `syslog_spool` table, 1 M rows or 30 days | REQ-FND-05 permits no second durable store | Yes |
| Spool full | Drop `debug`/`info` first, seal audit rows into a gap marker | Never block a request on someone else's SIEM | No |
| Console rings | 2 000 per tenant, 500 per subscriber, 500–20 000 client | A tail, not a store; the emitter never blocks | Yes, client only |
| Console on mobile | Expanded mode only | 390 px cannot honour 53 columns of prefix | No |
| Console font | JetBrains Mono, self-hosted, tabular figures | Disambiguated glyphs, real weight range | Yes |
| Console colour | Six `--console-*` tokens plus a three-letter tag, AA in both modes | Colour is never the only encoding | No |
| 8/24-bit ANSI | Quantised to the 16 contrast-checked tokens | Honouring arbitrary colour means honouring unreadable colour | No |
| OSC, cursor and C1 sequences | Stripped; OSC 8 links dropped | A sequence that moves a cursor can forge a line | No |
| Console download | The client buffer, with its frame count stated | An operator must not mistake a tail for a trail | No |
| Retention | 400 days; legal hold blocks purge and shortening | A full annual cycle | Yes |
| Retention and the chain | Sealed-segment row, chain still verifies | Otherwise §5 dies at the first purge | No |

## How this is verified

- `pnpm test:audit` — `tests/audit-emission/**` (REQ-TST-05): every event name in
  the frozen taxonomy fires once with every mandatory field populated; a denial
  records the demanded `permission`; impersonation enter and exit pair; a detail
  read writes one row and ten identical list renders write one row with
  `aggregatedCount: 10` (REQ-TST-08).
- `pnpm test:integration` — `tests/integration/audit/**`: `UPDATE`, `DELETE` and
  `TRUNCATE` on `audit_events` raise as `app_runtime` **and** as the owner; the
  view-counter function updates only its two fields and leaves `chain_hash`
  unchanged; the chain verifies over 10 000 seeded rows and a corrupted row is
  detected at the right `seq`; a retention purge leaves a verifying chain and is
  refused under legal hold.
- `pnpm test:unit` — `tests/unit/audit/**`: `redact` over a fixture per mode
  including an undeclared field in a sensitive table; canonical JSON stability
  across key insertion orders; the SGR parser over a table of sequences
  including 24-bit colour, OSC 8 and unsupported CSI; every `--console-*` token
  at AA against `--background` and `--card` in both modes.
- `pnpm test:e2e` — `tests/e2e/console/**` (REQ-TST-08): a live frame within
  2 s; 403 without `audit.console.read`; compact-mode column alignment measured
  from bounding boxes; pause holds the view while `N new` increments and resume
  reports a `gap`; download states its frame count; a secret injected into a log
  line never reaches the stream, the copy or the download, including a handler
  that deliberately logs `process.env` (REQ-AUD-12).
- `pnpm test:syslog` — `tests/integration/syslog/**`: framing and structured
  data parsed by an independent RFC 5424 parser; a TLS verification failure
  refuses to send rather than falling back; collector killed mid-stream, spool
  grows, collector returns, every message arrives once; at 90% only
  `debug`/`info` are dropped; at 100% a gap marker is emitted.
- `pnpm test:visual` — `tests/visual/console.spec.ts`: compact and expanded at
  390/834/1440 in both themes, all six levels and an ANSI-coloured line on
  screen; axe AA (REQ-TST-06); the console's surface budget
  (`spec/screenspace.md` §4).
- `GET /api/v1/audit/_selftest` — the four append-only triggers are enabled,
  `app_runtime` holds no `UPDATE`/`DELETE` on either table, every chain head
  verifies, and the spool depth and oldest unflushed window are reported
  (REQ-CTR-08).

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| List-read aggregation window | 300 s (`AUDIT_VIEW_WINDOW_SECONDS`) |
| Audit retention | 400 days; legal hold available per tenant |
| Syslog collector | None configured; the spool holds and warns until one is |
| Enterprise number for structured data | `32473` (IANA example PEN) |
| Who may open the debug console | `audit.console.read`; cross-tenant needs `global.audit.read-any` |
| Console in production | Enabled for global operators, off for tenant roles (`CONSOLE_ENABLED`) |
| Client ring buffer default | 5 000 frames, operator-changeable |
