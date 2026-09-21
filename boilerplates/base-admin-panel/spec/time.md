# Time & Formatting

One module formats every instant in the product. It lives in
`packages/contracts/time` and is owned by **A02** (`contract-steward`), not by a
domain, because a domain that owns the formatter is a domain the other fourteen
must import from — and the moment that is awkward, someone writes a second
formatter. `spec/agents.md` states this as a rule: time is not an agent. Every
other agent imports `time` and none of them may format a date locally.

## Requirements covered

REQ-TIM-01 … REQ-TIM-06, REQ-ENT-01, REQ-AUD-04, REQ-I18N-03, REQ-SET-03,
REQ-SET-11, REQ-CTR-01, REQ-CTR-10.

## 1. Why the formatter is a contract member (REQ-TIM-04)

The failure REQ-TIM-04 prevents is not ugly code. It is two renderings of one
instant on one screen. An audit row reading `2026-09-21 14:03:07` beside a "last
seen" reading `21/09/2026, 16:03` — one through the module, one through
`toLocaleString()` — makes an operator distrust the trail, and they are right
to: one of the two is in the wrong zone and nothing on screen says which.

So: one module, in the one package every domain already imports
(`contracts/README.md` §1). A domain cannot import it "from auth" and cannot
find a reason to wrap it. There is no per-component format string in the
repository, and no domain declares a date library in its `package.json`
(REQ-SUP-04).

The public surface is frozen in `contracts/types/time.md` §2 —
`DEFAULT_TIMEZONE`, `DEFAULT_FORMAT`, `FormatProfileSchema`, `formatInstant`,
`formatRelative`, `parseLocal`, `resolveProfile`. This spec is the reasoning and
the enforcement around it, not a second copy of the signatures.

Two additions A02 owns on top of that surface, both additive (REQ-CTR-03):

- `formatRange(from, to, profile)` — collapses a shared prefix:
  `2026-09-21 14:03 – 15:40`, `2026-09-21 – 2026-09-24`. Without it every caller
  that renders a window builds the dash and the collapse rule itself, which is a
  second formatter with extra steps.
- `precision: "milli"` — the debug console renders `HH:mm:ss.SSS`
  (`contracts/events/console-stream.md` §4) and must do it through this module.
  A new `precision` value is explicitly additive in the frozen change rules.

Instants are handled with `Temporal` through the TC39 polyfill (version from
`versions/manifest.json`, REQ-VER-02), chosen for one specific reason: its
disambiguation behaviour makes §2 expressible instead of conventional.

## 2. Europe/Stockholm, CET/CEST, and the two hard hours (REQ-TIM-01)

Sweden is CET (`+01:00`) in winter and CEST (`+02:00`) in summer. Under the EU
rule both transitions happen at **01:00 UTC**, on the last Sunday in March and
the last Sunday in October, and in local time both land on the same hour:

| Transition | Local effect | The hard case |
|---|---|---|
| Last Sunday in March, 01:00 UTC | 02:00 CET becomes 03:00 CEST | **02:00–02:59:59 local does not exist** |
| Last Sunday in October, 01:00 UTC | 03:00 CEST becomes 02:00 CET | **02:00–02:59:59 local happens twice** |

*Rendering* is never ambiguous: the stored value is a UTC instant and maps to
exactly one local wall time. Only *parsing* a human-entered local time is, and
`parseLocal` **refuses both cases**:

```ts
parseLocal("2027-03-28 02:30", { profile })
// → { ok: false, reason: { kind: "nonexistent", gapStart, gapEnd } }
parseLocal("2026-10-25 02:30", { profile })
// → { ok: false, reason: { kind: "ambiguous", candidates: [00:30Z, 01:30Z] } }
```

- **Non-existent**: the field rejects and says why — "02:30 does not exist on
  2027-03-28 in Europe/Stockholm; the clocks move from 02:00 to 03:00." It does
  **not** shift to 03:30. Silently moving a user's input by an hour is how a job
  fires at the wrong time once a year and stays unreproducible for twelve
  months.
- **Ambiguous**: the field asks which, showing both with their offsets —
  `02:30 CEST (+02:00)` and `02:30 CET (+01:00)`. It does not default to the
  earlier one.

**A recurring schedule is the case the contract's rule does not answer**, and it
needs its own, because at 02:30 on a transition night there is nobody to ask:

1. The schedule's local time is validated **at creation**, through `parseLocal`,
   where a human is present to resolve it. A schedule whose local time is
   unresolvable is refused then, not silently every year.
2. At **run** time, the resolution is deterministic and recorded, never silent:
   a non-existent local hour runs at the first instant that exists after it —
   03:00, once — and an ambiguous local hour runs at the **earlier** instant,
   once. The run's audit event carries `dstShift: "forward" | "earlier"`.
3. Once, not twice, and never skipped. A retention purge or an invoice job that
   runs twice is worse than one that runs an hour early; a backup that is
   skipped is a silent failure nobody sees until they need the backup.

**On display**, an instant whose local time falls inside a repeated hour is
rendered with its offset appended: `2026-10-25 02:30:00 +02:00`. It is the only
case where the default format grows a suffix, and it is not optional — a log
read at "02:30" on that date is unreadable without it, and an operator
correlating two systems needs to know which 02:30 they are looking at.

## 3. Storage is UTC (REQ-TIM-03)

Everything that has happened is an instant: `timestamptz`, UTC, RFC 3339 with
`Z` on the wire (`contracts/types/time.md` §1). Never `timestamp`, never a local
string, never an offset other than `Z`, and **never a timezone name stored
alongside a naive timestamp**.

A future wall-clock intention — "the maintenance window is 09:00 local, every
Tuesday" — is therefore not stored as a timestamp at all. It is a schedule: an
RRULE string plus an IANA zone name, resolved to an instant at run time by §2's
rules. Precomputing an instant months ahead is wrong for a reason the schema
cannot show: Sweden's offset on that date is a matter of law, and if the EU ends
seasonal changes every precomputed value becomes an hour off with nothing
flagging it. A schedule is a specification; a timestamp is a fact. The two are
different columns with different types, and which one a field uses is declared
in the contract per field, not decided per caller.

## 4. The format, and when seconds appear (REQ-TIM-02, REQ-TIM-05)

`DEFAULT_FORMAT` is `YYYY-MM-DD HH:mm:ss`, `24h`, `showSeconds:
"when-meaningful"`. "When meaningful" is resolved from the caller's `precision`,
not from taste, and the precision is declared on the contract field — so a
timestamp renders identically everywhere it appears:

| Precision | Renders | Applies to | Why |
|---|---|---|---|
| `second` | `2026-09-21 14:03:07` | Audit events, log lines, console frames, session and step-up times, API key last-used, job runs | Machine-generated, and ordering within a minute is the question being asked |
| `minute` | `2026-09-21 14:03` | Grid created/updated columns, detail headers, emails, scheduled windows, invitation expiry | Human-chosen or coarse; a second of precision is noise the eye must skip |
| `day` | `2026-09-21` | Retention boundaries, support-period end, report ranges | The time of day is not part of the value |
| `milli` (additive) | `14:03:07.412` | The debug console's time column | Two frames inside one second need an order |

A caller that passes no precision gets `second`. Being explicit is cheap;
guessing produces a grid where two columns disagree.

The profile (REQ-TIM-05) is a user preference on `user_preferences` — A05's
table, A02's field definitions — carrying `timezone`, `clock` and
`showSeconds`. **`12h` changes the time part only**: `2026-09-21 02:03:07 PM`.
The date part stays `YYYY-MM-DD` in every profile and every locale. We do not
offer `MM/DD/YYYY` or `DD/MM/YYYY`: on a mixed team reading one incident log
`03/04` is unresolvable, and a trail that cannot be read unambiguously is not a
trail. Month and weekday **names**, where shown, come from the catalogue —
and ICU date skeletons are banned there, so the catalogue cannot become a second
formatter (`spec/i18n.md` §1).

## 5. Resolution: user → tenant → system

```
user preference (user_preferences.timezone, .clock, .showSeconds)
  → tenant default (tenants.default_time_zone)
    → system default: Europe/Stockholm, 24h, when-meaningful
```

`resolveProfile` merges the levels, and each level may set any subset — a tenant
that fixes the zone does not thereby fix the clock. An actor with no preference
and no tenant default renders in `Europe/Stockholm`, not UTC: a UTC display
default is how an operator reads an audit trail an hour off and does not notice.

Resolved once per request alongside the locale (`spec/i18n.md` §4) and carried
on the `Actor`. Server-rendered and client-rendered output therefore agree,
which is the second way a timestamp goes wrong: the server formats in the system
zone, the client re-formats in the browser's, and the value changes after
hydration.

The personal panel that sets the profile is contributed to A05's settings shell
(REQ-SET-03) and shows the **effective** value with its source — "Europe/
Stockholm — your tenant's default" — because a resolution chain the user cannot
see is a chain they will argue with (REQ-SET-11).

The browser's zone is **never** an input. It is offered once, in the appearance
settings, as "Use this device's timezone (Europe/Stockholm detected)" — a
suggestion the user accepts, not a default that follows them onto a laptop in
another country.

A global-tier operator keeps their **own** profile everywhere, including inside
an impersonated session, so cross-tenant correlation needs no mental arithmetic.
Where a tenant's zone differs, it is shown beside the timestamp on that tenant's
detail views.

## 6. Relative time always carries the absolute (REQ-TIM-06)

`formatRelative` returns both halves, and the type is why the title cannot be
forgotten:

```ts
const { label, title } = formatRelative(session.lastSeenAt, { profile });
// label "3 min ago"   title "2026-09-21 14:03:07"
```

There is no variant that returns only a label. A05 ships the one component that
renders the pair, and it binds both:

```tsx
<RelativeTime iso={session.lastSeenAt} />
// → <time dateTime="2026-09-21T12:03:07Z" title="2026-09-21 14:03:07">3 min ago</time>
```

`title` is the absolute value in the resolved zone and precision. Labels come
from `common.relative.*` in ICU, so Swedish pluralisation is the catalogue's
problem rather than the formatter's. Beyond 7 days the component renders the
absolute value instead — "437 days ago" is a worse answer than the date. Live
updating uses one 30-second interval shared by every mounted instance, not a
timer per component, and it pauses when the tab is hidden.

## 7. The ban, and the lint that enforces it (REQ-TIM-04)

The frozen rule is two `no-restricted-syntax` selectors
(`contracts/types/time.md` §6). `pnpm lint:time` runs them plus five checks of
A02's own, all outside `packages/contracts/time/`:

| Banned | Because |
|---|---|
| `toLocaleString`, `toLocaleDateString`, `toLocaleTimeString` | The browser's zone and the machine's locale, neither of which is the resolved profile |
| `new Intl.DateTimeFormat` | The same, with more steps |
| `new Date(...)` in a render path, or `Date.now()` for display | A `Date` is an instant with a hidden local formatter attached |
| `.toISOString().slice(...)`, `${y}-${m}-${d}` template literals | A second format string, spelled by hand |
| Importing `moment`, `dayjs`, `date-fns`, `luxon` anywhere else | A second library is a second set of DST rules (REQ-SUP-04) |
| `, date` / `, time` in an ICU catalogue value | A third formatter, in the translations |
| A date library in any `package.json` other than `packages/contracts` | The dependency inventory is the earliest place to catch it (REQ-SUP-01) |

The rule has no exemption pragma. A domain that believes it needs one has found
a missing `time` export, and adding an export is an additive CCR — minutes
(`contracts/README.md` §6).

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Module location | `packages/contracts/time`, owned by A02 | A domain-owned formatter grows a rival | No |
| Library | `Temporal` via the TC39 polyfill | Makes §2 expressible rather than conventional | No |
| Default zone | `Europe/Stockholm` | REQ-TIM-01 | Yes |
| Default format | `YYYY-MM-DD HH:mm:ss`, 24h | REQ-TIM-02, REQ-TIM-05 | Yes, 12h per user |
| Date part per locale/profile | Always `YYYY-MM-DD` | `03/04` is unresolvable on a mixed team | No |
| Seconds shown | `when-meaningful`, resolved from the field's `precision` | Decided once per field, not per component | No |
| Storage | UTC `timestamptz` for what happened | REQ-TIM-03 | No |
| Future wall-clock intentions | An RRULE plus an IANA zone, resolved at run time | The offset is a matter of law, and no naive timestamp is stored | No |
| Non-existent local hour, user input | Refuse and explain | Silently shifting moves the appointment | No |
| Non-existent local hour, schedule | Validated at creation; at run time the first existing instant, once, audited | A skipped backup is a silent failure | No |
| Ambiguous local hour, user input | Ask, showing both offsets | Only the user knows which they meant | No |
| Ambiguous local hour, schedule | Earlier instant, once, audited with `dstShift` | Running twice is worse than an hour early | No |
| Display inside a repeated hour | Offset appended | "02:30" twice in one night is unreadable | No |
| Browser timezone | Never an input; offered once as a suggestion | A laptop in another country is not a preference change | No |
| Operator zone under impersonation | The operator's own | Cross-tenant correlation without arithmetic | Yes |
| Relative time | `formatRelative` returns label **and** title; the component binds both; absolute past 7 days | REQ-TIM-06, and no label-only API to misuse | No |

## How this is verified

- `pnpm test:unit` — `tests/unit/time/**`: both 2026 and 2027 transitions, and
  the 2025–2030 series generated from the tz database; `parseLocal` at 01:59,
  02:00, 02:30 and 03:00 on both transition days returns `ok: false` with the
  right `reason` and candidates; the offset suffix appears only inside a
  repeated hour; each precision renders exactly the §4 string; `formatRange`
  prefix collapse; `12h` affects only the time part. A build that cannot
  demonstrate the 2027 transitions has not satisfied REQ-TIM-01.
- `pnpm test:integration` — `tests/integration/time/**`: resolution over the
  user/tenant/system matrix; a `timestamptz` round-trip across a transition;
  a recurring schedule at 02:30 local is refused at creation with an
  unresolvable local time, and an accepted one runs exactly once on each
  transition day with the recorded `dstShift`.
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
  timestamp field in every declared schema is `Timestamp` and declares a
  precision; no schema stores a zone name beside a naive timestamp (REQ-CTR-10).

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| System timezone | `Europe/Stockholm` |
| Default format / clock | `YYYY-MM-DD HH:mm:ss`, `24h`, `when-meaningful` |
| May users pick their own zone and clock | Yes (REQ-TIM-05) |
| May a tenant set a tenant-wide zone | Yes; a user preference still wins |
| Relative-to-absolute cutover | 7 days |
| Week start | Monday (ISO 8601), for date pickers and week ranges |
