# Time & Formatting

One module formats every instant in the product. It lives in
`packages/contracts/time` and is owned by **A02** (`contract-steward`), not by a
domain, because a domain that owns the formatter is a domain the other twelve
must import from — and the moment that is awkward, someone writes a second
formatter. `spec/agents.md` states this as a rule: time is not an agent. Every
other agent imports `time` and none of them may format a date locally.

## Requirements covered

REQ-TIM-01 … REQ-TIM-06, REQ-ENT-01, REQ-AUD-04, REQ-I18N-03, REQ-CTR-01,
REQ-CTR-10.

## 1. Why the formatter is a contract member (REQ-TIM-04)

The failure mode REQ-TIM-04 exists to prevent is not ugly code. It is two
renderings of one instant on one screen. An audit row reading `2026-09-21
14:03:07` beside a "last seen" reading `21/09/2026, 16:03` — because one went
through the module and the other through `toLocaleString()` — makes an operator
distrust the trail, and they are right to: one of the two is in the wrong zone
and nothing on screen says which.

So: one module, in the one package every domain already imports
(`contracts/README.md` §1). A domain cannot import it "from auth" and cannot
find a reason to wrap it. There is no per-component format string anywhere in
the repository, and no domain declares a date library in its `package.json`
(REQ-SUP-04).

```ts
// packages/contracts/time/index.ts — the entire public surface
export function formatInstant(iso: string, p?: Precision, o?: Opts): string;
export function formatRange(from: string, to: string, o?: Opts): string;
export function parseLocal(input: string, zone: string, mode: ParseMode): Result;
export function RelativeTime(props: { iso: string; p?: Precision }): ReactNode;
export function resolveZoneAndProfile(actor: Actor, tenant: Tenant): Resolved;
export type Precision = "date" | "minute" | "second" | "millisecond";
```

Instants are handled with `Temporal` through the TC39 polyfill (version from
`versions/manifest.json`, REQ-VER-02). It is chosen for one specific reason: its
`disambiguation` option is a first-class answer to §2, which every other
candidate library leaves to a convention.

## 2. Europe/Stockholm, CET/CEST, and the two hard hours (REQ-TIM-01)

Sweden is CET (`+01:00`) in winter and CEST (`+02:00`) in summer. Under the EU
rule both transitions happen at **01:00 UTC**, on the last Sunday in March and
the last Sunday in October. In local time both land on the same hour:

| Transition | Local effect | The hard case |
|---|---|---|
| Last Sunday in March, 01:00 UTC | 02:00 CET becomes 03:00 CEST | **02:00–02:59:59 local does not exist** |
| Last Sunday in October, 01:00 UTC | 03:00 CEST becomes 02:00 CET | **02:00–02:59:59 local happens twice** |

We do not "handle DST" by adding an hour. We decide what each case means.

**The non-existent hour (spring).** A user typing `2027-03-28 02:30`:

```ts
parseLocal("2027-03-28 02:30", "Europe/Stockholm", "reject")
// → { ok: false, kind: "nonexistent", suggestion: "2027-03-28 03:30" }
```

The field refuses with `time.parse.nonexistent`: "02:30 does not exist on
2027-03-28 in Europe/Stockholm — the clocks move from 02:00 to 03:00. Did you
mean 03:30?" Guessing silently sets an appointment an hour from where the user
looked.

A **recurring schedule** — a backup at 02:30 daily, a chain verify, a retention
purge — is the opposite case: there is no user to ask, and skipping a run is a
silent failure that surfaces as a missing backup. A schedule landing in the
non-existent hour runs at the **first instant that exists** after it, 03:00
local, once. The run's audit event records `dstShift: "forward"`.

**The ambiguous hour (autumn).** A user typing `2026-10-25 02:30` gets two real
instants, `00:30Z` (CEST) and `01:30Z` (CET):

```ts
parseLocal("2026-10-25 02:30", "Europe/Stockholm", "reject")
// → { ok: false, kind: "ambiguous",
//     options: [{ iso: "2026-10-25T00:30:00Z", label: "02:30 CEST (+02:00)" },
//               { iso: "2026-10-25T01:30:00Z", label: "02:30 CET (+01:00)"  }] }
```

The field asks which, showing both with their offsets. A recurring schedule uses
the **earlier** instant and runs **once** — never twice, because a purge or an
invoice job that runs twice is worse than one that runs an hour early. The run
records `dstShift: "ambiguous-earlier"`.

**On display**, an instant whose local time falls inside a repeated hour is
formatted **with its offset appended**: `2026-10-25 02:30:00 +02:00`. This is
the only case where the default format grows a suffix, and it is not optional: a
log read at "02:30" on that date is unreadable without it, and an operator
correlating two systems needs to know which 02:30 they are looking at.

## 3. Storage is UTC, with one deliberate exception (REQ-TIM-03)

Everything that has happened is stored as an instant: `timestamptz`, UTC, RFC
3339 with `Z` on the wire (`contracts/types/entity-base.md` §1). Never
`timestamp`, never a local string, never a separate offset column.

The exception is a **future wall-clock intention**: "the maintenance window is
09:00 local, every Tuesday", "the report runs at 06:00 in the tenant's zone".
Those are stored as `(local_time, zone_id, recurrence)` and resolved to an
instant at run time. Storing a precomputed instant for a date months away is
wrong, because Sweden's offset on that date is a matter of law, not arithmetic —
if the EU ends seasonal changes, every precomputed instant becomes an hour off
and nothing in the schema shows it. Which of the two shapes a field uses is
declared in the contract per field, not decided per caller.

## 4. The format, and when seconds appear (REQ-TIM-02, REQ-TIM-05)

Default `YYYY-MM-DD HH:mm:ss`. Variant `YYYY-MM-DD HH:mm` where seconds carry
no meaning. The choice is not made per component — the rule below is encoded as
a `Precision` on the contract field, so a timestamp is rendered the same way
everywhere it appears.

| Precision | Rendering | Applies to | Why |
|---|---|---|---|
| `second` | `2026-09-21 14:03:07` | Audit events, log records, session and step-up times, API key last-used, job runs, console lines | Machine-generated, and ordering within a minute is the question being asked |
| `minute` | `2026-09-21 14:03` | Scheduled windows, due dates, invitation expiry, notification digests, grid "created"/"updated" columns | Human-chosen or coarse; a second of precision is noise the eye has to skip |
| `date` | `2026-09-21` | Retention dates, support-period end, report ranges | The time of day is not part of the value |
| `millisecond` | `2026-09-21 14:03:07.412` | Request traces, the hash chain's ordering, debug console with timing on | Two events inside one second need an order |

`formatRange` collapses a shared prefix: `2026-09-21 14:03 – 15:40`, and
`2026-09-21 – 2026-09-24` for dates.

The format profile (REQ-TIM-05) is a user preference on `user_preferences`
(A05's table, A02's field definitions): zone, precision override, and `24h`
(default) or `12h`. **`12h` changes the time part only** — `2026-09-21 02:03:07
PM`. The date part stays `YYYY-MM-DD` in every profile and every locale. We do
not offer `MM/DD/YYYY` or `DD/MM/YYYY`: on a mixed team reading a shared
incident log, `03/04` is unresolvable, and an audit trail that cannot be read
unambiguously is not an audit trail. Swedish and English both render the ISO
date; only month and weekday **names**, where shown, come from the catalogue
(REQ-I18N-03 — and ICU date skeletons are banned there, `spec/i18n.md` §1).

## 5. Resolution: user → tenant → system

```
user preference (user_preferences.time_zone, .time_format)
  → tenant default (tenants.default_time_zone)
    → system default: Europe/Stockholm, 24h, YYYY-MM-DD HH:mm:ss
```

Resolved once per request alongside the locale (`spec/i18n.md` §4) and carried on
the `Actor` (`contracts/types/identity.md` §2). Server-rendered and
client-rendered output therefore agree, which is the second way a timestamp goes
wrong: the server formats in the system zone and the client re-formats in the
browser's, and the value changes after hydration. The browser's zone is **never**
an input. It is offered once, in the appearance settings, as "Use this device's
timezone (Europe/Stockholm detected)" — a suggestion the user accepts, not a
default that follows them onto a laptop in another country.

A global-tier operator working across tenants keeps their **own** zone
everywhere, including inside an impersonated session, so cross-tenant
correlation does not require mental arithmetic. The tenant's zone is shown
beside the timestamp on tenant-scoped detail views where it differs.

## 6. Relative time always carries the absolute (REQ-TIM-06)

There is one way to render a relative time, and it cannot forget the title:

```tsx
<RelativeTime iso={session.lastSeenAt} />
// → <time dateTime="2026-09-21T12:03:07Z" title="2026-09-21 14:03:07">
//      3 min ago
//    </time>
```

The `title` is the absolute value in the resolved zone and precision, and it is
produced inside the component — there is no prop that turns it off. Strings come
from `time.relative.*` in ICU, so Swedish pluralisation is the catalogue's
problem, not the formatter's. Beyond 7 days the component renders the absolute
value instead: "437 days ago" is a worse answer than the date. Live updating
uses one 30-second interval shared by every mounted instance, not a timer per
component, and it pauses when the tab is hidden.

Returning a bare string for a relative time is not possible: `RelativeTime` is
the only export that produces one, and it returns a node. That is deliberate —
a string API is a string somebody renders without a title.

## 7. The ban, and the lint that enforces it (REQ-TIM-04)

`pnpm lint:time` fails CI on any of the following outside
`packages/contracts/time/`:

| Banned | Because |
|---|---|
| `toLocaleString`, `toLocaleDateString`, `toLocaleTimeString` | The browser's zone and the machine's locale, neither of which is the resolved profile |
| `Intl.DateTimeFormat` constructed directly | Same, with more steps |
| `new Date(...)` in a render path, or `Date.now()` for display | A `Date` is an instant with a hidden local formatter attached |
| `.toISOString().slice(...)`, template literals assembling `${y}-${m}-${d}` | A second format string, spelled by hand |
| Importing `moment`, `dayjs`, `date-fns`, `luxon` anywhere else | A second library is a second set of DST rules (REQ-SUP-04) |
| `, date` / `, time` inside an ICU catalogue value | A third formatter, in the translations (`spec/i18n.md` §1) |
| A date library in any `package.json` other than `packages/contracts` | The dependency inventory is the earliest place to catch it (REQ-SUP-01) |

The rule has no exemption pragma. A domain that believes it needs one has found
a missing `time` export, and adding an export is an additive CCR — minutes
(`contracts/README.md` §6).

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Module location | `packages/contracts/time`, owned by A02 | A domain-owned formatter grows a rival | No |
| Library | `Temporal` via the TC39 polyfill | `disambiguation` answers §2 explicitly | No |
| Default zone | `Europe/Stockholm` | REQ-TIM-01 | Yes |
| Default format | `YYYY-MM-DD HH:mm:ss`, 24h | REQ-TIM-02, REQ-TIM-05 | Yes, 12h per user |
| Date part per locale/profile | Always `YYYY-MM-DD` | `03/04` is unresolvable on a mixed team | No |
| Seconds shown | By the field's `Precision`, per the §4 table | Decided once per field, not per component | No |
| Storage | UTC `timestamptz` for what happened | REQ-TIM-03 | No |
| Future wall-clock intentions | `(local_time, zone_id, recurrence)`, resolved at run time | The offset is a matter of law | No |
| Non-existent local hour, user input | Reject with the suggestion | Silently shifting moves the appointment | No |
| Non-existent local hour, schedule | Run at the first existing instant, once | A skipped backup is a silent failure | No |
| Ambiguous local hour, user input | Ask, showing both offsets | Only the user knows which they meant | No |
| Ambiguous local hour, schedule | Earlier instant, once | Running twice is worse than an hour early | No |
| Display inside a repeated hour | Offset appended | "02:30" twice in one night is unreadable | No |
| Browser timezone | Never an input; offered once as a suggestion | A laptop in another country is not a preference change | No |
| Operator zone under impersonation | The operator's own | Cross-tenant correlation without arithmetic | Yes |
| Relative time | A component that always sets `title`; absolute past 7 days | REQ-TIM-06, and no string API to misuse | No |

## How this is verified

- `pnpm test:unit` — `tests/unit/time/**`: both 2026 and 2027 transitions, and
  the 2025–2030 series generated from the tz database; `parseLocal` for every
  `ParseMode` at 01:59, 02:00, 02:30, 03:00 on both transition days; the
  offset suffix appears only inside a repeated hour; each `Precision` renders
  exactly the §4 string; `formatRange` prefix collapse; 12h affects only the
  time part.
- `pnpm test:integration` — `tests/integration/time/**`: resolution over the
  user/tenant/system matrix; a `timestamptz` round-trip across a transition;
  a recurring schedule at 02:30 local runs once on each transition day with the
  recorded `dstShift`.
- `pnpm lint:time` — the §7 table, repository-wide, plus the `package.json`
  dependency check.
- `pnpm test:e2e` — `tests/e2e/time/**`: a server-rendered and a
  client-rendered timestamp on the same page are byte-identical after
  hydration; `RelativeTime` exposes the absolute value in `title`; a user zone
  change re-renders every visible timestamp.
- `pnpm test:visual` — `tests/visual/time.spec.ts`: the audit grid and a detail
  header at 390/834/1440 with a repeated-hour instant present, so the offset
  suffix is checked for clipping against the surface budget.
- `pnpm test:contract` — `packages/contracts/tests/time.spec.ts`: every
  timestamp field in every declared schema has a `Precision`, and every one is
  `UtcInstantSchema` or an explicit wall-clock triple (REQ-CTR-10).

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| System timezone | `Europe/Stockholm` |
| Default format / clock | `YYYY-MM-DD HH:mm:ss`, 24h |
| May users pick their own zone and clock | Yes (REQ-TIM-05) |
| May a tenant set a tenant-wide zone | Yes; a user preference still wins |
| Relative-to-absolute cutover | 7 days |
| Week start | Monday (ISO 8601), for date pickers and week ranges |
