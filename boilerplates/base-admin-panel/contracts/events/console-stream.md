# `console-stream` — the debug console SSE protocol

**Published by:** A13. Rendered by A13's console surface at
`apps/<app>/app/(app)/console/**`.
**Requirements:** REQ-AUD-08 … REQ-AUD-12, REQ-AUD-05, REQ-RBA-02, REQ-SEC-08,
REQ-TIM-02, REQ-TIM-04.
**Consumed by:** every agent that emits a log record; A23 (REQ-TST-08).

The console shows an operator what the server is doing, live. It is the surface
most likely to become an exfiltration channel, so the redaction guarantee (§8)
is part of the protocol and not a property of the UI.

---

## 1. Transport

```
GET /api/v1/audit/console/stream?level=info&domain=auth,rbac&q=tenant
Accept: text/event-stream
```

| Property | Value |
|----------|-------|
| Protocol | SSE (`text/event-stream`), one-way, `Cache-Control: no-store`, `X-Accel-Buffering: no` |
| Permission | `audit.console.read` (§7) |
| Event type | `frame`, plus `gap` and `hello` control events |
| Heartbeat | a `: ping` comment every 15 s, so a proxy does not idle the connection out |
| Resume | `Last-Event-ID: <seq>` replays from the server ring buffer (§6) |
| Disabled | `CONSOLE_ENABLED=false` returns 503 `audit.console_disabled` |
| Connection cap | one stream per session, four per actor; the fifth is refused with `common.rate_limited` |

The filters in the query string are applied **server-side** before the frame is
serialised. A client-side filter would mean the browser received frames the
operator was not entitled to see.

## 2. The frame

```ts
// packages/logging/contract.declaration.ts
export const ConsoleLevelSchema = z.enum([
  "trace", "debug", "info", "warn", "error", "fatal",
]);

export const ConsoleFrameSchema = z.object({
  v: z.literal(1),
  /** Monotonic per stream. Sent as the SSE `id:` for Last-Event-ID resume. */
  seq: z.number().int().positive(),
  /** UTC instant, millisecond precision. */
  ts: z.string().datetime({ offset: false }),
  level: ConsoleLevelSchema,
  /** The emitting domain, from the i18n/permission domain set. */
  domain: z.enum([
    "auth", "rbac", "tenancy", "grid", "audit", "api", "mail", "notify",
    "pwa", "canonical", "collector", "help", "platform", "global",
  ]),
  /** Dot-separated event name, same grammar as an audit action. */
  event: z.string().max(80),
  /** Already-redacted, already-localised one-line message. */
  msg: z.string().max(512),
  /** Structured fields, redacted (§8). Depth 2, 20 keys, 200 chars per value. */
  fields: z.record(z.string(), z.union([z.string(), z.number(), z.boolean(), z.null()])),
  correlationId: z.string().uuid().nullable(),
  tenantId: z.string().uuid().nullable(),
  actorId: z.string().uuid().nullable(),
  /** True when `msg` contains SGR sequences the renderer must honour (§5). */
  ansi: z.boolean().default(false),
}).strict();

/** Sent when the server dropped frames for this subscriber (§6). */
export const ConsoleGapFrameSchema = z.object({
  v: z.literal(1),
  seq: z.number().int().positive(),
  ts: z.string().datetime({ offset: false }),
  kind: z.literal("gap"),
  dropped: z.number().int().positive(),
  reason: z.enum(["backpressure", "ring_overflow", "redaction_failure"]),
}).strict();
```

`ts` is a UTC `timestamptz` at the source and RFC 3339 `Z` on the wire. The
console renders `HH:mm:ss.SSS` in the operator's zone through
`packages/contracts/time` — the only formatter (REQ-TIM-02, REQ-TIM-04). A
frame never carries a preformatted local time.

A frame is not an audit event. Audit is the durable, chained, permission-gated
record (`contracts/events/audit-event.md`); the console is a live tail of the
log stream. Both carry `correlationId`, which is how an operator gets from a
console line to the audit row.

## 3. Levels and colour (REQ-AUD-10)

Colour is a theme token, never a hex literal in the console code, so both
themes stay legible and AA-contrasted (REQ-UI-11).

| Level | Token | Light | Dark | Compact tag |
|-------|-------|-------|------|-------------|
| `trace` | `--console-trace` | muted grey | dim grey | `TRC` |
| `debug` | `--console-debug` | slate | slate-light | `DBG` |
| `info` | `--console-info` | foreground | foreground | `INF` |
| `warn` | `--console-warn` | amber-700 | amber-400 | `WRN` |
| `error` | `--console-error` | red-700 | red-400 | `ERR` |
| `fatal` | `--console-fatal` | red-50 on red-700 | red-100 on red-600 | `FTL` |

Level is never encoded by colour alone: the three-letter tag carries it for a
colour-blind or monochrome reader.

## 4. Compact mode (REQ-AUD-09)

One event per line, aligned columns, metadata collapsed. Toggleable; the choice
persists in `user_preferences` (A05's table).

```
HH:mm:ss.SSS  LVL  domain........  event...................  message
12:04:31.882  INF  auth            session.login             actor=u_8fd tenant=acme amr=pwd,totp
12:04:32.104  WRN  api             key.first-use             prefix=ak_live_9f2 ip=203.0.113.7
12:04:33.550  ERR  mail            message.send              outbox=6b1 attempt=3 code=mail.smtp_tls_required
```

| Column | Width | Align | Content |
|--------|-------|-------|---------|
| time | 12 | left | `HH:mm:ss.SSS` |
| gap | 2 | — | two spaces between every column |
| level | 3 | left | the tag from §3, coloured |
| domain | 14 | left | truncated with `…` at 14 |
| event | 24 | left | truncated with `…` at 24 |
| message | rest | left | `msg`, then `fields` as `k=v` pairs, single line |

Rules: fixed pitch, no wrapping in compact mode (horizontal scroll instead — a
wrapped line destroys the column alignment the mode exists for), `…` for
truncation with the full value in the expanded row, and the expanded view is the
same frame rendered as key/value rows. Non-compact mode wraps and shows
`fields` as a block. Total line width at 14+24 columns fits 1440px at the
console font without scroll; on mobile the console drops to expanded mode,
because a 390px viewport cannot honour the widths (REQ-UI-07).

## 5. ANSI handling (REQ-AUD-10)

A collector or a child process can emit ANSI. The console renders it faithfully
and narrowly:

- Allowed: SGR (`ESC [ … m`) with codes `0`, `1`, `2`, `22`, `30`–`37`,
  `39`–`47`, `49`, `90`–`97`, `100`–`107`. Mapped to theme tokens, not to raw
  colours, so a hardcoded black-on-black stays readable.
- Stripped, always: OSC (`ESC ]`, including OSC 8 hyperlinks), cursor movement,
  erase, scroll region, DEC private modes, `ESC ( `, `ESC c`, `\r`, `\b`, `\x07`
  and every C1 control other than `ESC [`. A terminal sequence that can move a
  cursor can forge a line.
- Sequences are parsed into a span tree and rendered as elements. Nothing from
  a frame reaches `innerHTML`, `dangerouslySetInnerHTML` or a CSS
  `style` attribute; CSP forbids inline style anyway (REQ-SEC-08).
- 8-bit and 24-bit colour (`38;5;n`, `38;2;r;g;b`) is quantised to the 16-colour
  token map. Honouring arbitrary colour means honouring unreadable colour.
- Copy and download emit the **stripped** text with the sequences removed
  (REQ-AUD-11), so a pasted log cannot carry escapes into another terminal.

## 6. Ring buffer and backpressure (REQ-AUD-11)

| Buffer | Size | Policy |
|--------|------|--------|
| Server, per tenant | 2 000 frames | Drop oldest. Feeds `Last-Event-ID` resume. |
| Server, per subscriber queue | 500 frames | Slow consumer: drop oldest, count, emit one `gap` frame with `reason: "backpressure"`. |
| Client | operator-set, 500 … 20 000 | Drop oldest. The control is in the toolbar. |

- The emitter never blocks on a subscriber. A console reader that cannot keep up
  loses frames; the request it was watching still completes. The audit trail is
  the record that must not lose rows — the console is explicitly allowed to.
- Pause holds the client buffer only. The server keeps dropping into the ring;
  on resume the client replays from `Last-Event-ID` and receives a `gap` frame
  if the ring had already rotated past it. Pause is never a memory leak.
- Follow-tail is client state. When the operator scrolls up, follow disengages
  and a "N new" affordance appears; new frames still arrive and buffer.
- Download writes the client buffer, not the server's, and says how many frames
  it holds — an operator must not believe they downloaded a complete trail. For
  a complete record they export the audit trail (`audit.event.export`).

## 7. The permission gate (REQ-AUD-08, REQ-RBA-02)

- `audit.console.read` is required to open the stream. Without it: 403
  `rbac.permission_denied`. There is no anonymous or "dev only" bypass.
- A tenant operator sees frames for its own tenant plus frames with
  `tenantId: null` that name no other tenant. Cross-tenant tailing requires
  `global.audit.read-any`, which is global-tier and step-up (`rbac.md` §3).
- The filter is applied server-side after the tenant scope, never before.
- Opening the stream emits an audit event `audit.console.read` with
  `kind: "read"` — watching the system is itself an audited action.
- Frames are never persisted by the console. The durable record is
  `audit_events` and the syslog sink (REQ-AUD-07).

## 8. The redaction guarantee (REQ-AUD-12)

The console is not a secret-exfiltration channel. The guarantee is mechanical:

1. A frame is redacted **at emit**, by the same registry and the same code path
   as the audit diff (`contracts/events/audit-event.md` §4). There is no second
   implementation to drift.
2. `fields` values are scalars, capped at 200 chars, depth 1. No nested object,
   no array, no blob. A serialised request body cannot be attached to a frame.
3. Before serialisation each frame is validated against `ConsoleFrameSchema`
   (`.strict()`) and against the secret-shaped-value detector: JWT-shaped,
   `ak_live_`-prefixed, PEM blocks, 32+ char high-entropy strings, `postgres://`
   URLs. A hit **drops the frame** and emits a `gap` frame with
   `reason: "redaction_failure"` plus a `system` audit event naming the domain
   and the field. A dropped frame is a bug to fix; a leaked seed is an incident.
4. `msg` is rendered from an i18n catalogue key with parameters (REQ-I18N-02),
   so a domain cannot smuggle a value into a free-text sentence.
5. A23 asserts it (REQ-TST-08): the fixture secrets are grepped for across a
   captured stream during a full e2e run, including a deliberate handler that
   tries to log `process.env`. A hit fails the build.

## 9. Change rules after the G3 freeze

**Additive**
- A new `domain` value, a new control event kind, a new optional frame field.
- A new compact column, inserted before `message` with its width declared in
  §4. `message` consumes the rest of the line, so nothing can follow it.
- A wider client ring-buffer ceiling.

**Breaking — needs orchestrator arbitration (REQ-CTR-03)**
- A new `level`. Level is ordered and filters use `>=`; inserting one changes
  what every saved filter means. Same rule as the global tier in
  `contracts/types/identity.md` §7.
- Changing a compact column width — every operator's saved layout and every
  visual test baseline shifts.
- Allowing a non-scalar in `fields`, raising the value cap, or permitting OSC.
- Removing the permission gate for any environment, including development.
