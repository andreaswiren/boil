# Contract: `time`

**Published by:** A02. **Consumed by:** every agent.
**Requirements:** REQ-TIM-01, REQ-TIM-02, REQ-TIM-03, REQ-TIM-04, REQ-TIM-05, REQ-TIM-06.

This is the only date and time formatter in the application. It lives in the
contract package rather than in a domain because a second formatter is the exact
failure this requirement exists to prevent (REQ-TIM-04) — and a second formatter
is what you get when fifteen agents each need to render a timestamp and none of
them owns the answer.

## 1. Storage is UTC, always

Every timestamp column is `timestamptz` and every value written is UTC
(REQ-TIM-03). No column stores a local time, an offset, or a timezone name
alongside a naive timestamp.

```sql
created_at  timestamptz NOT NULL DEFAULT now()
```

On the wire — JSON bodies, event envelopes, the OpenAPI document — a timestamp is
an RFC 3339 string in UTC with a `Z` suffix. Never a local string, never an epoch
number, never an offset other than `Z`.

```ts
export const Timestamp = z.string().datetime({ offset: false });  // "2026-09-21T19:26:03Z"
```

A timezone is a *presentation* concern. It is applied once, at the edge, by this
module. Nothing else applies it.

## 2. The exports

```ts
export const DEFAULT_TIMEZONE = "Europe/Stockholm";           // REQ-TIM-01
export const DEFAULT_FORMAT   = "YYYY-MM-DD HH:mm:ss";        // REQ-TIM-02

export const FormatProfileSchema = z.object({
  timezone: z.string().refine(isIanaZone, "must be an IANA zone name"),
  clock: z.enum(["24h", "12h"]).default("24h"),
  showSeconds: z.enum(["always", "when-meaningful", "never"]).default("when-meaningful"),
});
export type FormatProfile = z.infer<typeof FormatProfileSchema>;

/** The only way to render an instant for a human. */
export function formatInstant(
  value: Date | string,
  opts: { profile: FormatProfile; precision?: "milli" | "second" | "minute" | "day" },
): string;

/** Relative label plus the absolute value it must always carry (REQ-TIM-06). */
export function formatRelative(
  value: Date | string,
  opts: { profile: FormatProfile; now?: Date },
): { label: string; title: string };

/** Parse a user-entered local time in the profile's zone into a UTC instant. */
export function parseLocal(
  input: string,
  opts: { profile: FormatProfile },
): { ok: true; utc: Date } | { ok: false; reason: AmbiguityReason };

/** Resolve the profile for a request: user -> tenant -> system (REQ-TIM-05). */
export function resolveProfile(ctx: {
  user?: Partial<FormatProfile>;
  tenant?: Partial<FormatProfile>;
}): FormatProfile;
```

## 3. Seconds are shown only when they mean something

REQ-TIM-02 gives `YYYY-MM-DD HH:mm:ss` as the default and
`YYYY-MM-DD HH:mm` where seconds carry no meaning. `showSeconds:
"when-meaningful"` resolves that from the caller's `precision`, not from taste:

| Context | Precision | Renders |
|---------|-----------|---------|
| Audit event, log line, API key last-used | `second` | `2026-09-21 19:26:03` |
| Debug console stream, ACME protocol log | `milli` | `2026-09-21 19:26:03.418` — the console interleaves events inside one second, so second precision loses their order. Without this, A13 and A25 would format locally and break REQ-TIM-04. |
| Created/updated column in a grid, detail header, email | `minute` | `2026-09-21 19:26` |
| Date-only field (a birth date, a retention boundary) | `day` | `2026-09-21` |

A caller that passes no `precision` gets `second`. Being explicit is cheap;
guessing produces a grid where two columns disagree.

## 4. Europe/Stockholm, and the two hours that break naive code

Stockholm is CET (UTC+1) in winter and CEST (UTC+2) in summer (REQ-TIM-01). The
transitions produce one local hour that happens twice and one that never happens
at all. Both must be handled deliberately, because the default behaviour of most
date libraries is to silently pick one answer.

**The ambiguous hour (autumn, last Sunday in October).** Local `02:30` occurs
twice — once at UTC `00:30` and again at UTC `01:30`.

- *Rendering* is never ambiguous: the stored instant is UTC, so it maps to
  exactly one local wall time. Nothing to resolve.
- *Parsing* a user-entered `02:30` on that date is ambiguous. `parseLocal`
  returns `{ ok: false, reason: "ambiguous" }` with both candidate instants. The
  UI asks which one. It does not guess, and it does not default to the earlier
  offset.

**The non-existent hour (spring, last Sunday in March).** Local `02:30` does not
occur; the clock jumps 02:00 → 03:00.

- `parseLocal` returns `{ ok: false, reason: "nonexistent" }`. The UI rejects the
  input and says why.
- It does **not** shift the value forward to 03:30. Silently moving a user's
  input by an hour is the behaviour that makes a scheduled job fire at the wrong
  time once a year and be unreproducible for twelve months.

```ts
export type AmbiguityReason =
  | { kind: "ambiguous";   candidates: [Date, Date] }
  | { kind: "nonexistent"; gapStart: Date; gapEnd: Date }
  | { kind: "unparseable" };
```

Tests for both dates are mandatory and named in `spec/time.md`. A build that
cannot demonstrate correct behaviour on the 2027 transition dates has not
satisfied REQ-TIM-01.

## 5. Resolution order

User preference → tenant default → system default (REQ-TIM-05). Each level may
set any subset of the profile; `resolveProfile` merges them in that order. The
system default is `Europe/Stockholm`, `24h`, `when-meaningful`.

An actor with no user preference and no tenant default renders in
Europe/Stockholm. That is the requirement, not a fallback to UTC — a UTC display
default is how an operator reads an audit trail an hour off and does not notice.

## 6. What is banned, and how it is enforced

No agent calls `toLocaleString`, `toLocaleDateString`, `toLocaleTimeString`,
`Intl.DateTimeFormat`, or a date library's own formatter in application code
(REQ-TIM-04). No agent writes a format string.

Enforced by lint, not by convention:

```
no-restricted-syntax:
  - selector: CallExpression[callee.property.name=/^toLocale(Date|Time)?String$/]
    message: "Use formatInstant from @contracts/time (REQ-TIM-04)."
  - selector: NewExpression[callee.object.name="Intl"][callee.property.name="DateTimeFormat"]
    message: "Use formatInstant from @contracts/time (REQ-TIM-04)."
```

`packages/contracts/time` is the one place the rule is disabled, because it is
the one place the formatting happens.

## 7. Additive vs breaking

**Additive** — a new `precision` value; a new optional field on
`FormatProfile`; a new named format for a new surface; a new
`AmbiguityReason` variant that callers already handle through the discriminated
union's default branch.

**Breaking** — changing `DEFAULT_FORMAT` or `DEFAULT_TIMEZONE`; changing what
`when-meaningful` resolves to for an existing precision; making
`parseLocal` resolve an ambiguous time instead of refusing; changing the wire
representation away from UTC RFC 3339. Each of these silently changes what every
existing surface displays, which is the semantic-change-under-the-same-name case
that `contracts/README.md` §5 calls the worst kind.
