# Audit, Logging & the Debug Console

The audit trail, the log pipeline, syslog forwarding and the in-app debug
console. Owned by **A13** (`audit-observability`): `packages/audit/**`,
`packages/logging/**`, `packages/syslog/**`,
`apps/<app>/app/(app)/console/**`, and the tables `audit_events`,
`audit_chain`, `audit_read_buffer`, `syslog_spool`, `log_sinks`. A13 publishes
`audit-event`, `log-record`, `console-stream` and `redaction`; it consumes
`entity-base`, `session`, `tenancy` and `theme-tokens`. Other agents **emit**;
A13 is the only writer of an audit row. That is why no domain can decide not to
be audited.

## Requirements covered

REQ-AUD-01 … REQ-AUD-13, REQ-SEC-05, REQ-FND-05, REQ-ENT-01, REQ-RBA-07,
REQ-PWA-04, REQ-UI-11, REQ-TST-05, REQ-TST-08, REQ-CTR-08.

## 1. The audit event, field by field (REQ-AUD-04)

```sql
audit_events (A13) -- append-only (§3), tenant-scoped, RLS forced
  id               uuid        primary key,
  tenant_seq       bigint      not null,  -- per-tenant, gapless, chain order
  occurred_at      timestamptz not null,  -- UTC instant of the action
  recorded_at      timestamptz not null,  -- UTC instant of the insert
  tenant_id        uuid,                  -- null only for a pre-tenant global action
  actor            jsonb       not null,  -- ActorRef snapshot: id, kind, label
  on_behalf_of     jsonb,                 -- ActorRef of the impersonating operator
  impersonation_id uuid,                  -- pairs enter/exit (REQ-RBA-07)
  action           text        not null,  -- "rbac.role.update" — permission-shaped
  permission_used  text,                  -- the string actually checked, null if none
  target_type      text        not null,  -- "role", "device", "session"
  target_id        text,                  -- uuid or natural key; null for a list read
  target_label     text,                  -- snapshot label, readable after deletion
  before           jsonb,                 -- redacted, writes only
  after            jsonb,                 -- redacted, writes only
  diff_paths       text[],                -- changed JSON paths, for indexing
  result           text        not null,  -- success | denied | failed | expired
  error_code       text,                  -- taxonomy code on a failure (spec/api.md §4)
  severity         text        not null,  -- info | notice | warning | critical
  correlation_id   uuid        not null,  -- the request id, on every log line too
  source_ip        inet        not null,
  user_agent       text,
  comment          text,                  -- the actor's reason (entity-base §1)
  read_agg         jsonb,                 -- §2, list reads only
  schema_version   int         not null,
  prev_hash        bytea       not null,  -- §5
  row_hash         bytea       not null
```

Notes that are decisions, not descriptions:

- **`actor` is a snapshot, not a foreign key.** Id, kind and label as they were
  at the time. The trail stays readable after the user is renamed, the key is
  revoked or the collector is decommissioned (`spec/entity-model.md` §2).
- **`action` uses the permission grammar** (`spec/rbac-tenancy.md` §1), so the
  event name, the permission and the i18n key for the human summary are the same
  string in three places and cannot drift.
- **`occurred_at` and `recorded_at` are both kept**: a spooled or retried
  emission inserts late, and one column cannot answer both questions.
- **`permission_used` records what was checked**, which is what makes a denial
  reviewable: `result: "denied"` plus the permission the caller lacked.
- **`target_label`** exists because after a purge there is no row to join to.
- **`severity`** drives notification, not colour alone: `critical` pages the
  global operators (MFA disabled, chain break, impersonation entry, purge).
- A missing `correlation_id` fails the emission. An event that cannot be tied to
  a request cannot be explained.

Events covered (REQ-AUD-01): create, update, delete, restore, purge, login,
logout, failed auth, rate-limit trip, policy change, permission and role change,
impersonation enter and exit, export, API key mint/first-use/rotate/revoke/
expire, agent enrolment and revocation, mail delivery, chain verify, retention
purge — plus reads (§2).

## 2. Read and view logging (REQ-AUD-02)

Reads are audited. Unaggregated, that is millions of rows a day and nobody reads
any of them, so the policy is explicit and different per read shape.

| Read shape | Policy | Why |
|---|---|---|
| Detail view (`*.read`, one row) | **Always one event.** No sampling. | "Who looked at this customer's record" is the question read logging exists to answer |
| List / grid read (`*.list`) | **Aggregated** per `(actor, tenant, target_type, 5-minute window)` | One operator sorting and paging a grid produces 30 requests and one intention |
| Export | Always one event, with row count and filter hash | It is a bulk read (REQ-GRD-13) |
| Report / PDF render | Always one event | Same |
| Console stream open/close | Always one event each | A privileged read channel |
| `_selftest`, health, static assets | Not audited | No tenant data crosses them |

**The window is 5 minutes.** Shorter and a normal grid session still writes
dozens of rows; longer and the trail stops showing *when* someone was looking.
At 5 minutes one actor browsing one resource writes at most 12 rows an hour, so
a full working day of one operator's list reads is about 100 rows and a year is
of the order of 25 000 — a size that can be kept, indexed and read.

```jsonc
// read_agg on an aggregated list event
{ "count": 27, "firstAt": "2026-09-21T12:00:04Z", "lastAt": "2026-09-21T12:04:51Z",
  "rowsReturned": 1340, "filterHashes": ["9f2a…", "c41b…"], "includeDeleted": false }
```

The open window lives in `audit_read_buffer`, a Postgres table — not in process
memory. REQ-FND-05 allows no second durable store, and an in-memory buffer loses
the trail on every deploy, which is exactly when someone is looking. The buffer
carries the entity envelope, so it needs no exemption (REQ-ENT-01). A window is
flushed into `audit_events` when it closes, when the session ends, or on a clean
shutdown; a crash leaves the row in the buffer and the next flush picks it up.
`filterHashes` is capped at 10 distinct values, after which the aggregate sets
`"filtersTruncated": true` rather than growing unboundedly.

## 3. Append-only, twice over (REQ-AUD-03)

```sql
-- Privileges: the app role cannot mutate, at all.
REVOKE UPDATE, DELETE, TRUNCATE ON audit_events, audit_chain
  FROM app_runtime, app_global;
GRANT  INSERT, SELECT ON audit_events, audit_chain TO app_runtime, app_global;

-- Trigger: the owner cannot either, and a migration cannot quietly try.
CREATE FUNCTION app.deny_audit_mutation() RETURNS trigger
  LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'audit_events is append-only (REQ-AUD-03)'
    USING ERRCODE = 'restrict_violation';
END $$;

CREATE TRIGGER audit_events_no_update BEFORE UPDATE OR DELETE ON audit_events
  FOR EACH ROW EXECUTE FUNCTION app.deny_audit_mutation();
CREATE TRIGGER audit_events_no_truncate BEFORE TRUNCATE ON audit_events
  FOR EACH STATEMENT EXECUTE FUNCTION app.deny_audit_mutation();
```

Both, because each covers the other's gap. Privileges stop the application but
not the migration role, and a future `GRANT` is one line. The trigger stops the
owner too — including a migration that means well — but a trigger can be
disabled by the owner, so `pnpm lint:migrations` fails on `DISABLE TRIGGER`
against these tables and the self-test asserts `tgenabled = 'O'` on all four.
Retention purge (§8) runs as a separate maintenance role that holds `DELETE` and
nothing else, and it is the only path that removes an audit row.

## 4. Redaction (REQ-AUD-05, REQ-AUD-12)

Sensitivity is declared on the contract field, once, by the field's owner:

```ts
sensitivity: "secret" | "pii" | "public"
```

| Class | Treatment | Example output |
|---|---|---|
| `secret` | Never emitted in any form. The diff records that it changed, not what it changed to | `"totpSeed": "[redacted:secret]"`, `diff_paths: ["totpSeed"]` |
| `pii` | Masked by type: email keeps first char and domain, phone keeps last 4, name keeps initials, free text is replaced by length | `"a***@example.com"`, `"***-**-1234"`, `"[text:412 chars]"` |
| `pii` where correlation is needed | Hashed with a per-tenant salt so the same value matches itself without being readable | `"pii:sha256:7c4e2a91b0d3"` |
| `public` | Emitted as-is | |
| **undeclared** | Treated as `pii` and masked | fail closed |

Undeclared means masked. A field added without a sensitivity is the likeliest
leak in a 13-agent build, so the default must be the safe one — and
`pnpm test:contract` fails on an undeclared field anyway, which makes it two
independent controls.

One function, five sinks, and forgetting it is a **type error**:

```ts
declare const brand: unique symbol;
export type Redacted<T> = T & { readonly [brand]: true };
export function redact<T>(value: T, schema: ZodType<T>): Redacted<T>;
```

| Sink | Where redaction runs | Note |
|---|---|---|
| Audit `before`/`after` | Before the insert, in `packages/audit` | The row is never written unredacted |
| Log records | In the logger, before any transport | Includes the message, not only the fields |
| Console SSE stream | Server-side, before the event enters the ring buffer | The ring never holds a secret (REQ-AUD-12) |
| Error responses | In the problem+json serialiser | A validation error never echoes the rejected secret |
| Push payloads | In `packages/notify` | Second layer: a push carries a reference, not content (REQ-PWA-04) |
| Syslog structured data | Inherited — it serialises an already-redacted log record | One redaction, not two implementations |

Every sink's writer accepts `Redacted<T>` only. A caller that passes a raw value
does not compile, which is stronger than a review comment and cheaper than a
test. Grid exports are **not** a redaction sink: an export returns the data the
caller is permitted to read, and it is audited instead (`spec/datagrid.md` §9).

## 5. Tamper evidence: a per-tenant hash chain (REQ-AUD-06)

```
row_hash = sha256( canonical_json(immutable fields) || prev_hash )
genesis:   prev_hash = sha256("audit-chain-genesis:" || tenant_id)
```

- The chain is **per tenant**, so one tenant's volume does not serialise
  another's writes and an exported tenant chain is verifiable on its own.
- `tenant_seq` is gapless per tenant. The insert takes
  `pg_advisory_xact_lock(hashtext('audit_chain:' || tenant_id))`, reads the head
  from `audit_chain`, writes the event and the new head in the **same
  transaction** as the audited action. An action that cannot be chained does not
  commit.
- Genesis includes the tenant id, so two tenants' chains cannot be swapped and a
  chain cannot be replayed into a different tenant.
- Canonical JSON means sorted keys, no insignificant whitespace, `timestamptz`
  as RFC 3339 `Z`, numbers without exponent form. A hash over
  implementation-ordered JSON verifies on one library version and fails on the
  next.

The verify job: incremental every hour over rows since the last verified
`tenant_seq`, full every night. It re-computes each `row_hash` and each link,
and emits `audit.chain.verify` with `{ tenant, from, to, result }`. A break emits
`severity: critical`, notifies every global operator, and **does not repair** —
the point of tamper evidence is that it cannot be quietly fixed. The verified
head hash is forwarded to syslog at each run (§6), which puts a copy off the box:
a chain whose heads live only where the rows live can be rewritten wholesale.

## 6. Syslog forwarding (REQ-AUD-07, REQ-SEC-05)

RFC 5424 messages over RFC 5425 TLS with octet-counted framing. Plain UDP/514 is
not a supported configuration; certificate verification is mandatory and the
connection goes through A01's egress client (REQ-SEC-12).

```
<134>1 2026-09-21T12:03:07.412Z panel.example.org admin-panel 1 9f2a4c1e
 [origin ip="10.0.2.15" software="admin-panel" swVersion="1.4.0"]
 [audit@32473 tenant="t-0a91" actor="u-7731" actorKind="user" action="rbac.role.update"
  target="role/ops-lead" result="success" severity="notice" seq="184023"
  correlationId="9f2a4c1e-…" rowHash="4b1c…"]
 role "ops-lead" updated: +device.config.write, -device.config.purge
```

- Facility `local1` for audit-derived messages, `local0` for application logs.
  Severity maps `critical→2`, `warning→4`, `notice→5`, `info→6`, `debug→7`.
- `MSGID` is the `action`. `PROCID` is the process instance.
- SD-IDs: standard `origin`, plus `audit@<PEN>` and `app@<PEN>`. The enterprise
  number is `SYSLOG_ENTERPRISE_ID`, default `32473` — the IANA-reserved example
  PEN — because shipping someone else's PEN is worse than shipping the
  documented placeholder, and the operator sets their own.
- The `MSG` body is the localised-to-`en` summary. Logs are not translated
  (`spec/i18n.md` §5).

**Spooling and backpressure.** The spool is `syslog_spool`, a Postgres table,
because REQ-FND-05 permits no second durable store and a file spool in a
container is lost on the next deploy. Default bound: 1 000 000 rows or 30 days,
whichever comes first.

| Spool state | Behaviour |
|---|---|
| Collector up | Batches of 256, in-order per tenant, at-least-once with the `row_hash` as the dedup key |
| Collector down | Rows accumulate; a `warn` every 60 s with the depth; reconnect with jittered backoff, 1 s → 60 s |
| ≥ 90% of bound | Application `debug` and `info` are dropped first, counted in `syslog.dropped` by level. Audit-derived rows are never dropped |
| 100%, audit-derived only | The oldest audit-derived rows are sealed into one **gap marker** message stating the range, count and the final `row_hash`, and forwarding continues |

The request path never blocks on syslog. Blocking a tenant's work because a SIEM
is unreachable converts someone else's outage into ours, and the durable record
is already the `audit_events` row — syslog is the forwarded copy. The gap is
therefore reported loudly and the rows remain queryable in the product.

## 7. The debug console (REQ-AUD-08 … REQ-AUD-12)

`/(app)/console`, permission `audit.console.read` for the tenant scope and
`global.console.read` for the cross-tenant scope, the latter with step-up within
300 s because it streams other tenants' activity. Disabled by default in
production for non-global roles (`CONSOLE_ENABLED`, REQ-FND-07). Opening and
closing a stream are each audited (§2).

**Transport.** SSE — `text/event-stream`, one stream per tab, a comment
heartbeat every 15 s, `Last-Event-ID` resume from the server ring, two
concurrent streams per user. Not WebSockets: the stream is one-directional, the
controls are ordinary requests, and SSE needs no second protocol in the CSP or
the reverse proxy. The server ring holds 5 000 events per tenant in memory and
is deliberately ephemeral — it is a tail, not a store; the record is Postgres.

**Compact mode (REQ-AUD-09).** One event per line, fixed columns, metadata
collapsed. Widths are fixed so the eye scans a column rather than re-finding it:

| Column | Width | Content |
|---|---|---|
| time | 19 | `2026-09-21 14:03:07`, 23 with `.mmm` when timing is on |
| level | 5 | `WARN `, right-padded |
| domain | 12 | `rbac`, `auth`, `normalizer` |
| actor | 16 | label, truncated with `…` |
| event | 28 | the `action` string |
| message | rest | single line, ellipsised, never wrapped |

96 columns before the message, which fits 1440 px at the console font size with
the sidebar expanded. Expanded mode renders the same event as pretty-printed
JSON under the line; `›`/`⌄` toggles one event, the toolbar toggles all. Below
`tablet` the actor and domain columns drop out and the message moves to a second
line — a horizontally scrolling log on a phone is unusable.

**Font (REQ-AUD-10).** JetBrains Mono, self-hosted variable woff2 (REQ-SUP-07),
fallback `ui-monospace, SFMono-Regular, Menlo, monospace`. Chosen for the
disambiguated `0/O`, `1/l/I` and `;/:` — a console is where an operator reads an
id character by character — and for a real 400/500/700 range, so level weight
carries meaning without colour. `font-variant-numeric: tabular-nums` keeps the
time column from jittering as digits change.

**Colour (REQ-AUD-10).** Console colours are tokens in `theme-tokens`; A06 owns
the values, A13 owns their use, and A13 filed the additive CCR for them at the
freeze. No component names a colour (`spec/theming.md` §3).

| Level | Token | Light | Dark |
|---|---|---|---|
| `trace` / `debug` | `--console-debug` | muted, ≥ 4.5:1 | muted, ≥ 4.5:1 |
| `info` | `--console-info` | foreground | foreground |
| `notice` | `--console-notice` | primary | primary |
| `warning` | `--console-warn` | amber ramp | amber ramp |
| `error` | `--console-error` | destructive | destructive |
| `critical` | `--console-critical` | destructive on tinted row | same, plus weight 700 |

Every level token is contrast-checked against `--background` and
`--card` at AA (4.5:1) in **both** modes by a unit test over the token pairs, not
by eye. Level is also encoded in the text (`WARN`) and the weight, so the console
is readable in monochrome and to a colour-blind operator (REQ-UI-11).

**ANSI fidelity (REQ-AUD-10).** Event text may arrive carrying SGR sequences —
a collector's output, a subprocess. The console parses SGR (`0`, `1`, `2`, `3`,
`4`, `7`, `22`–`27`, `30`–`37`, `39`, `40`–`47`, `49`, `90`–`97`, `100`–`107`)
into spans mapped onto `--ansi-0 … --ansi-15`. 256-colour and 24-bit sequences
are mapped to the nearest of the 16 rather than honoured: an arbitrary RGB from
an upstream process is invisible in one theme and blinding in the other, and the
16 slots are the ones contrast-checked. Unsupported CSI, OSC and cursor
sequences are stripped, never rendered as literal escape text; OSC 8 hyperlinks
are dropped rather than linked, because a clickable URL injected into a
privileged operator's console is a phishing primitive.

**Controls (REQ-AUD-11).**

| Control | Behaviour |
|---|---|
| Level filter | Multi-select, or a minimum level. Applied server-side to the subscription so filtered events are not streamed at all |
| Domain filter | Multi-select of registered domains, server-side |
| Text filter | Client-side over the ring, substring by default, regex behind a toggle with an invalid-pattern hint |
| Pause / resume | The ring keeps filling; the header shows `N new`. Resume jumps to tail |
| Follow tail | On by default, turns itself off when the operator scrolls up, back on at the bottom |
| Ring size | `500 / 2 000 / 5 000 / 20 000`, with the memory cost shown |
| Copy | Selected lines or the whole buffer, as text or JSON |
| Download | NDJSON of the current buffer; audited as `audit.console.export` |
| Keyboard | `/` filter, `Space` pause, `g`/`G` top/bottom, `f` follow, `c` compact |

Everything the console shows, copies and downloads is already redacted
server-side (§4). The console is a view of the stream, not a second, more
generous one (REQ-AUD-12).

## 8. Retention, export and legal hold (REQ-AUD-13)

Per-tenant retention, default 400 days — over a year, so an annual review can
always look back one full cycle. Purge runs as the maintenance role (§3) and:

- Refuses on a tenant with `legal_hold = true`, per tenant and per date range.
- Emits `audit.retention.purge` with the range, the row count and the
  `row_hash` of the last purged row.
- Writes a **sealed-segment** row into `audit_chain` whose hash covers the
  purged range, and the first retained row's `prev_hash` points at it. The
  chain over what remains still verifies; it verifies *and* shows where a
  purge happened. A purge that silently breaks the chain would make §5
  unusable after the first retention run.

Export is per tenant, NDJSON plus the chain heads, permission
`audit.export.create`, step-up 900 s, and itself audited.

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Detail reads | Always one event | The question read logging exists for | No |
| List reads | Aggregated per actor+tenant+resource per 5 min | ~100 rows per operator-day instead of thousands | Yes, window only |
| Aggregation buffer | A Postgres table | REQ-FND-05; memory loses the trail on deploy | No |
| Append-only | Privileges **and** trigger | Each covers the other's gap | No |
| Sensitivity default | Undeclared = `pii` = masked | Fail closed | No |
| Redaction enforcement | `Redacted<T>` branded type on every sink | A type error beats a review comment | No |
| Hash chain scope | Per tenant, in the action's transaction | Exportable, and unchainable means uncommitted | No |
| Chain break | Alert, never auto-repair | Evidence that can be fixed is not evidence | No |
| Chain anchoring | Verified head forwarded to syslog | An internal-only chain can be rewritten | No |
| Enterprise number | `32473` (IANA example), operator-set | Shipping someone else's PEN is worse | Yes |
| Spool location / bound | `syslog_spool` table, 1 M rows or 30 days | REQ-FND-05 | Yes |
| Spool full | Drop `debug`/`info` first, seal audit rows into a gap marker | Never block a request on someone else's SIEM | No |
| Console ring | 5 000 events per tenant, in memory, ephemeral | It is a tail, not a store | Yes |
| Console font | JetBrains Mono, self-hosted, tabular figures | Disambiguated glyphs, weight range | Yes |
| Console colour | `theme-tokens`, AA-checked in both modes, plus text and weight | REQ-AUD-10, REQ-UI-11 | No |
| Truecolor ANSI | Mapped to the 16 contrast-checked slots | Arbitrary RGB is unreadable in one theme | No |
| OSC 8 hyperlinks | Dropped | A link in a privileged console is a phishing primitive | No |
| Retention and the chain | Sealed-segment row, chain still verifies | Otherwise §5 dies at the first purge | No |

## How this is verified

- `pnpm test:audit` — `tests/audit-emission/**` (REQ-TST-05): every REQ-AUD-01
  event type fires exactly once with every mandatory field populated; a denial
  records `permission_used`; impersonation enter/exit pair; a detail read emits
  one event and 30 list requests inside one window emit one aggregate with
  `count: 30`.
- `pnpm test:integration` — `tests/integration/audit/**` (REQ-TST-08): `UPDATE`,
  `DELETE` and `TRUNCATE` on `audit_events` raise as `app_runtime` **and** as
  the owner; the chain verifies over 10 000 seeded rows and a corrupted row is
  detected at the right `tenant_seq`; a retention purge leaves a verifying
  chain; a crash mid-window leaves the buffer row for the next flush.
- `pnpm test:unit` — `tests/unit/audit/**`: `redact` over a fixture per
  sensitivity class including an undeclared field; canonical JSON stability
  across key insertion orders; the SGR parser over a table of sequences
  including truecolor, unsupported CSI and OSC 8; every console level token at
  AA against `--background` and `--card` in both modes.
- `pnpm test:e2e` — `tests/e2e/console/**` (REQ-TST-08): a live event within
  2 s; 403 without `audit.console.read`; compact-mode column alignment from
  bounding boxes; pause holds the view while `N new` increments; download emits
  `audit.console.export`; a secret injected into a log line never reaches the
  stream, the copy or the download (REQ-AUD-12).
- `pnpm test:syslog` — `tests/integration/syslog/**`: framing and structured
  data parsed by an independent RFC 5424 parser; a TLS verification failure
  refuses to send rather than falling back; collector killed mid-stream, spool
  grows, collector returns, every message arrives once; at 90% only
  `debug`/`info` are dropped; at 100% a gap marker is emitted.
- `pnpm test:visual` — `tests/visual/console.spec.ts`: compact and expanded at
  390/834/1440 in both themes, all six levels and an ANSI-coloured line on
  screen; axe AA (REQ-TST-06); the console's surface budget
  (`spec/screenspace.md` §4).
- `GET /api/v1/audit/_selftest` — the four triggers are enabled, `app_runtime`
  holds no `UPDATE`/`DELETE` on either table, every tenant's chain head
  verifies, the spool depth and the oldest unflushed window are reported
  (REQ-CTR-08).

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| List-read aggregation window | 5 minutes |
| Audit retention | 400 days; legal hold available per tenant |
| Syslog collector | None configured; the spool holds and warns until one is |
| Enterprise number for structured data | `32473` (IANA example PEN) |
| Who may open the debug console | `audit.console.read` for a tenant; global scope needs step-up |
| Console in production | Enabled for global operators, off for tenant roles |
| Ring buffer default | 5 000 events |
