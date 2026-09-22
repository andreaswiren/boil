# Mobile UX — primitives, budgets and the touch contract

Mobile is built from published primitives and asserted numbers, not from a media
query at the end of a desktop layout. Owned by **A27** (`mobile-ux`):
`packages/mobile/**` and nothing else. A27 publishes `mobile-primitives` and
`touch-budget` (`contracts/types/mobile-primitives.md`); it consumes
`theme-tokens` (A06), `screenspace`, `surface-budget` and `nav-registry` (A05)
and `i18n:mobile` (A14). A05 owns screenspace measurement and the surface budgets;
this document owns the mobile half of them and measures nothing A05 already
measures (`spec/screenspace.md` §1, §3).

## Requirements covered

REQ-MOB-01 … REQ-MOB-12 (primary), REQ-UI-07, REQ-UI-09, REQ-UI-10, REQ-UI-11,
REQ-UI-15, REQ-GRD-14, REQ-MON-07, REQ-MON-10, REQ-PWA-01, REQ-WIZ-14,
REQ-TST-02, REQ-TST-03.

## 1. The boundary: A27 publishes, the surface owner composes (REQ-MOB-01, REQ-MOB-02)

A05 owns the shell. A07 owns the datagrid. Both render on a phone. A27 owns
neither: owning either would rebuild the merge point this structure exists to
avoid — two agents writing one surface, a shared file, a queue. The split is the
one the repo uses everywhere, **registry, never a shared list**, applied to pixels
instead of nav entries:

| Question | Answered by | Owner |
|---|---|---|
| What a grid row looks like, and which file renders it | `MobileCardSpec` (`spec/datagrid.md` §10) in `packages/datagrid/src/mobile/card-list.tsx` | A07 |
| How tall the filter sheet opens and that dragging it down also has a visible Close | `<Sheet>` from `@app/mobile` | A27 |
| Whether the export button is 44 px and far enough from Delete | `TouchBudget` for surface `grid` | A27 declares, A21 asserts, A07 fixes |

**A27 ships no `MobileGrid`, no mobile route and no mobile shell.** With a grid
renderer here, every grid change would need two agents and one would be waiting
(REQ-CTR-05).

### Worked example — A07's mobile grid (REQ-GRD-14)

```tsx
// packages/datagrid/src/mobile/card-list.tsx — A07's file, A07's fix if it fails
import { SafeArea, Sheet, ActionBar, PullToRefresh, useTouchBudget } from "@app/mobile";

export function GridCardList<TRow>({ def, state, rows }: GridRenderProps<TRow>) {
  useTouchBudget("grid");                              // A27's numbers, A05's measurements
  return (
    <SafeArea edges={["bottom"]}>
      <PullToRefresh enabled triggerPx={64} equivalentActionId="grid.refresh">
        {rows.map((r) => <GridCard key={def.rowId(r)} row={r} spec={def.mobile} />)}
      </PullToRefresh>
      <Sheet id="grid.filters" detents={["half", "full"]} initialDetent="half">
        <GridFilters state={state} />                  {/* same reducer, same URL params */}
      </Sheet>
      <ActionBar primary={{ id: "grid.export", ... }} destructive={{ id: "grid.bulk-delete", ... }} />
    </SafeArea>);
}
```

A07 writes every line of that file; A27 wrote the four primitives and the `grid`
entry in `TouchBudget`. Nobody edits anybody's file, and `ActionBar` keeps
`grid.bulk-delete` out of the thumb zone beside Export without A07 knowing §3's
arithmetic.

## 2. Touch targets (REQ-MOB-03)

44×44 CSS px minimum hit box, 8 px minimum gap between adjacent targets, at every
mobile breakpoint. The hit box is the box model, not the glyph: a 20 px icon with
12 px padding passes; a 44 px `min-height` on a flex child that shrank to 31 px does
not. A21 asserts it computationally, never visually (REQ-MOB-11):

Collect every interactive element (`button, a[href], input, select, textarea,
[role="button"], [tabindex]:not([tabindex="-1"])`), read `boundingBox()` per element
over CDP with touch emulation on, and fail when `w < 44 || h < 44`, naming selector,
measured size and viewport. Then, for every pair whose centres are under 88 px
apart, compute the rectangle gap on the axis of nearest approach and fail under
`minSpacingPx`.

O(n²) over roughly 40 elements per surface is under a millisecond, and it catches
what a screenshot diff cannot: two 40 px buttons look correct and are not.
Screenshots stay evidence for a human (REQ-TST-04); they are not the assertion.
## 3. Thumb reach (REQ-MOB-04)

Bands are fractions of **usable height** — `--sp-vvh` minus the bottom safe-area
inset — resolved at runtime, never hardcoded, because the keyboard changes them
(§4). Resolved values at the declared viewports:

| Viewport | Usable height | `easy` (bottom 40%) | `ok` (40–62%) | `hard` |
|---|---|---|---|---|
| 320×568, inset 0 | 568 | y 341–568 | y 216–341 | y 0–216 |
| 390×844, inset 34 | 810 | y 486–810 | y 308–486 | y 0–308 |
| 600×896, inset 34 | 862 | y 517–862 | y 328–517 | y 0–328 |
| 844×390 landscape, inset 21 | 369 | y 221–369 | y 140–221 | y 0–140 |

Rules:

- The primary action sits in `easy`. `ok` takes secondary actions; `hard` is for
  content and headers, never a repeated action.
- A destructive action is **never within 96 px** of a primary or frequent one. 390
  CSS px across a 71.5 mm display is 0.183 mm per px, so a 17.5 mm thumb contact
  patch is 96 CSS px: the miss distance on a phone is a thumb width. The 8 px of §2
  proves two targets are distinct, not that the wrong one is hard to hit. So
  destructive actions live in `ActionBarSpec.destructive`, in the overflow sheet
  behind one deliberate tap, not inline beside Save.
- The tenant chooser keeps its meaning without its geometry (REQ-UI-15): the current
  tenant stays legible in the header, and switching opens a `<Sheet>` from a control
  in `easy`. A chooser two menus deep answers "whose data am I about to change" too
  late.

## 4. The keyboard is a layout event (REQ-MOB-05)

A27 reads `--sp-kb` and `--sp-vvh` from A05's screenspace layer and calls
`visualViewport` nowhere — `pnpm lint:boundaries` fails on it outside
`packages/screenspace/` (`spec/screenspace.md` §1). One measurer, one truth.

With the keyboard open three things stay visible: the focused field, its label and
inline error, and the primary action. `<KeyboardAvoidingContainer>` pads the scroll
container by `var(--sp-kb)`, scrolls the focused field into the remaining band with
a 16 px gap, and lifts `<ActionBar>` to `calc(var(--sp-kb) + var(--sp-safe-b))`.
The failure this prevents: a footer at `position: fixed; bottom: 0` on iOS at
390×844. The keyboard takes 336 px and the **layout** viewport does not shrink, so
the footer keeps `bottom: 0` — 336 px under the keyboard. The Save button is not
merely off-screen; no scroll position reveals it, because the page believes it is
844 px tall and fully visible, and nothing in CSS reports otherwise. The login
budget already accounts for it: 474 px usable with the keyboard open
(`spec/screenspace.md` §4). Every `position: fixed` element in a mobile surface is
an `<ActionBar>` or sits in a `<KeyboardAvoidingContainer>`; `pnpm lint:mobile`,
shipped from `packages/mobile`, fails on any other.

## 5. Input affordances (REQ-MOB-06)

The cheapest quality win on a phone and the one most often skipped. Every field
declares all four attributes. A numeric field that opens QWERTY is a defect.

| Field kind | `type` | `inputmode` | `enterkeyhint` | `autocomplete` |
|---|---|---|---|---|
| Email | `email` | `email` | `next` | `username` at sign-in, `email` elsewhere |
| Password (sign-in) | `password` | — | `go` | `current-password` |
| Password (set or change) | `password` | — | `next` | `new-password` |
| TOTP code / recovery code | `text` | `numeric` / `text` | `go` | `one-time-code` |
| Search (grid, palette) | `search` | `search` | `search` | `off` |
| Integer count, port, page size | `text` | `numeric` | `done` | `off` |
| Decimal, amount, timeout | `text` | `decimal` | `done` | `off` |
| Phone | `tel` | `tel` | `next` | `tel` |
| URL, hostname, ACME directory | `url` | `url` | `next` | `url` |
| IPv4 / CIDR / DNS name, secret paste | `text` | `text` | `next` | `off` |
| Date, time | `date` / `time` | — | `next` | `off` |
| Person name / organisation | `text` | `text` | `next` | `name` / `organization` |
| Multiline (`comment`, REQ-ENT-01) | `textarea` | `text` | `enter` | `off` |

Five rules go with the table:

- **`type="number"` is banned**: spinner, scroll-wheel mutation, dropped leading
  zeros, refused paste. `text` + `inputmode="numeric"` + `pattern="[0-9]*"`
  replaces it everywhere.
- `autocomplete="off"` on a password field is ignored by every major browser and
  breaks password managers; `new-password` is how you mean it.
- Where case or spelling matters — recovery codes, secrets, hostnames, permission
  strings — also set `autocapitalize`, `autocorrect` off and `spellcheck="false"`.
- Input font size is **16 px minimum**: below it iOS Safari zooms on focus, the
  layout viewport shifts, and the user is panning a page they were typing into.
- A secret paste field is `text` with a reveal toggle, never `password`: masking a
  value the operator must verify against the console they copied it from produces a
  support ticket, not security. Redaction still applies (REQ-AUD-05).

## 6. Gestures (REQ-MOB-07)

Every gesture is an accelerator, and the capability it accelerates is always
reachable by a visible control — that is what keeps the surface usable with a
screen reader, a stylus and a mounted tablet.

| Gesture | Rule | Visible equivalent |
|---|---|---|
| Horizontal swipe | Ignored within **24 px** of either viewport edge; carriers set `touch-action: pan-y` | The control the swipe would have hit |
| Swipe a card for actions | Allowed, max one action per direction | The card's overflow button |
| Pull to refresh | Armed **only** at `scrollTop === 0` on pointerdown; 64 px trigger, 1500 ms cooldown, disabled while a fetch is in flight | `equivalentActionId`: a refresh control in the toolbar |
| Sheet drag-down | Always paired with a Close button (`dismissAffordance: "button-and-drag"`) | Close |

iOS and Android both read an edge swipe as Back; a carousel that captures it either
eats the user's Back or loses mid-animation, and 24 px of margin is the whole fix.
Scroll containers set `overscroll-behavior-y: contain` so the browser's own
pull-to-refresh cannot fire on top of ours — two refreshes, one of which reloads the
document and discards unsaved state.

## 7. Navigation depth (REQ-MOB-08)

- **Depth is bounded at 3** below a bottom-nav root: list → detail → sub-detail.
  A fourth level is a design finding for C1, not a deeper stack.
- Every screen states where it is: the header carries the surface title, the bottom
  nav keeps the active root highlighted, and `hideOnScroll` is `false` — a nav that
  hides costs a scroll gesture before an escape is offered.
- **One action out, from any depth.** Tapping a bottom-nav root returns to that
  root, not one step back. Sheets stack at most 2 deep, and each one pushes a
  history entry so the platform back gesture closes the sheet instead of leaving
  the app. That last detail is exactly why no domain rolls its own sheet.
- A phone has no breadcrumb bar: where desktop uses breadcrumbs, mobile uses the
  title plus a back control in the top-left labelled with the parent's name.

## 8. Connectivity and long-running actions (REQ-MOB-09)

Mobile networks fail mid-request and mobile tabs get backgrounded by a phone call.
Both are designed for, not defaulted.

- **Double-submit is prevented by an idempotency key minted when the form
  renders** and sent on every attempt (REQ-PWA-01). Disabling the button is
  presentation; the key is the guarantee. A retry after a timeout carries the same
  key and resolves to the same record. A submit enters an explicit `pending` state,
  recorded so a tab returning through `visibilitychange` reconciles by re-reading the
  resource instead of re-posting it.
- **Optimistic UI only when all four hold**: reversible locally, emits no audit
  event, expected under 1 s, failure fully undone by a re-render. Filter, sort,
  column visibility and theme qualify.
- **Never optimistic**: anything audited (REQ-AUD-01), destructive, permission- or
  role-changing, an export, a certificate operation, or a setting with blast radius
  (REQ-SET-10). An optimistic tick on a role change that failed is a lie about
  authority.
- Offline is A09's service worker (REQ-PWA-03 — no authenticated response cached);
  mobile surfaces render its offline state through A27's primitives and never invent
  a second one.

## 9. Orientation and short viewports (REQ-MOB-10)

Orientation is never locked. The worst case is a landscape phone with the keyboard
open: 844×390, keyboard ≈ 200 px, home indicator 21 px, page header 56 px, action
bar 54 px — **59 px of content left**. That is a sliver, not a layout.

The rule is keyed off measured height, not width: below
`shortViewport.minUsableContentPx = 240`, chrome collapses in order — `bottom-nav`,
`page-header`, `sheet-handle`. `action-bar` collapses last and instead unsticks,
rendering inline beneath the focused field so the submit stays with what is being
submitted; the same case then has 190 px for field, error and button. Sheets open at
`full` in a short viewport whatever `initialDetent` says.

## 10. Honest degradation (REQ-MOB-12, REQ-MON-10)

Where a surface does not belong on a phone, the mobile build says so and offers the
useful subset, rather than shipping the desktop rendering and calling it responsive.
The worked case is the editor: `packages/editor/**` is A05's, and below `tablet` 834
Monaco is **not loaded at all** — a code-split boundary, so the phone never pays its
bytes either (REQ-MON-07). A05 declares

`{ surface: "editor.document", belowBreakpoint: "tablet", offers: "reduced",
reasonKey: "mobile.editor.reduced", helpTopicId: "editor-on-mobile" }` and composes
the fallback from `<SafeArea>` + `<KeyboardAvoidingContainer>` +
`<ActionBar>`. The reduced editor offers, stated rather than implied:
syntax-highlighted read-only rendering, the same schema validation with errors listed
by line (REQ-MON-05), search, copy, and editing of single scalar values where the
descriptor allows. Not offered: multi-cursor, folding, format-on-type, the diff view.
The notice names what is missing and where to get it — "Full editing needs a wider
screen", plus a help link — because "not supported on mobile" with no route onward is
an apology, not a design. A wide comparison view takes the same pattern: stack the
diff per hunk, or declare `offers: "link-out"`. A27 owns the primitive and the notice
shape; A05 owns the editor file, the reason key and the decision — the §1 boundary.

## 11. The mobile column of every surface budget

`maxChromeV` at `phone` is A05's `chromeV` for that surface, copied
(`spec/screenspace.md` §4). A27 authors `phone-min` and `phone-lg`, which A05 does
not declare, plus the touch columns at all three. A21 asserts every number
(REQ-UI-10, REQ-MOB-03, REQ-MOB-11).

| Surface | `maxChromeV` 320 / 390 / 600 | Target / spacing | Primary | Payload ≥ (320 / 390 / 600) |
|---|---|---|---|---|
| Dashboard | 152 / **160** / 160 | 44 / 8 | `easy` | 2 / 3 / 4 stat tiles whole, 2-up at 600 |
| Grid page | 200 / **216** / 216 | 44 / 8 | `easy` | 3 / 5 / 7 cards whole |
| Detail page | 160 / **168** / 168 | 44 / 8 | `easy` | title + 2 / 4 / 6 fields above the fold |
| Login | 0 / **34** / 34 | 48 / 12 | `ok` | email, password and submit visible with the keyboard open, zero page scroll |
| Setup wizard | 144 / 152 / 152 | 44 / 8 | `easy` | 1 / 3 fields + Continue; 10 recovery codes at 390×664 with no truncation (REQ-WIZ-14) |

Bold is A05's `chromeV` at 390, copied not authored. `setup.wizard` has no A05
number yet: A27's 152 is the proposal, and A05's declaration wins on conflict.

Login runs 48/12 rather than the 44/8 floor: it is the one surface a user meets
before learning the app, often one-handed, and a mistyped credential there costs a
rate-limit trip (REQ-SEC-11). Its primary action is `ok`, not `easy`, because the
card is vertically centred and the keyboard owns the bottom 336 px.

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Mobile ownership model | A27 publishes primitives and budgets; surface owners compose | REQ-MOB-01; a second implementer is a merge point | No |
| Landscape | `shortViewport`, keyed off measured height | 844×390 is `tablet` by width and would escape the budget | No |
| Touch floor | 44×44 px, 8 px spacing; 48/12 on login; 96 px to a destructive target | REQ-MOB-03, REQ-MOB-04 | No |
| Optimistic UI | Reversible, unaudited, sub-second actions only; Monaco is not loaded below 834 | A tick on a failed role change is a lie; REQ-MON-10 | No |
| `type="number"` | Banned; `text` + `inputmode="numeric"` | Spinner, scroll mutation, leading-zero loss | No |
| Bottom nav | ≤ 5 items, 64 px, never hides on scroll; depth 3, sheets stack 2 | A 6th item is 53 px wide at 320; REQ-MOB-08 | Yes, item set |
| A27's self-test | `mobileSelftest()` exported from the package, embedded in A05's `/api/v1/shell/_selftest` | A27 owns no route (REQ-CTR-08) | No |

## How this is verified

- `pnpm test:visual` — `tests/visual/touch.spec.ts` (A21, REQ-MOB-11): every
  registered surface at 320/390/600 and 844×390, touch emulation on, both themes;
  `minTargetPx`, `minSpacingPx`, thumb band, `destructiveSeparationPx` and
  `maxChromeV` from real bounding boxes; a screenshot per assertion (REQ-TST-03),
  presented in the reply (REQ-TST-04).
- `pnpm test:e2e` — `tests/e2e/mobile/**` (REQ-TST-02): login at 390×844 with the CDP
  software keyboard open, submit reachable, no page scroll (REQ-MOB-05);
  pull-to-refresh refusing to arm at `scrollTop > 0` (REQ-MOB-07); a sheet closed by
  the platform back gesture (REQ-MOB-08); a double submit resolving to one record on
  a 3G profile with the first response dropped (REQ-MOB-09); the editor at 390
  rendering the notice and loading no Monaco chunk (REQ-MON-10).
- `pnpm test:unit` — `tests/unit/mobile/**`: band resolution against a table of
  viewport, inset and keyboard inputs, including the landscape collapse order
  (REQ-MOB-10); every field kind in §5 emitting all four attributes (REQ-MOB-06).
- `pnpm lint:mobile` — no `position: fixed` outside `<ActionBar>` /
  `<KeyboardAvoidingContainer>`, no `type="number"`, and no `visualViewport`,
  `window.inner*` or `100vh` in `packages/mobile`.
- `mobileSelftest()` — every surface with a `SurfaceBudget` has a `TouchBudget` at
  all three breakpoints, every `phone.maxChromeV` matches A05's, every gesture spec
  carries an `equivalentActionId` (REQ-CTR-08).

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| Phone primary navigation | Bottom bar, ≤ 5 items plus a more-sheet |
| Pull-to-refresh surfaces | Grid pages and the notification list only |
| Extra mobile breakpoints, card swipe actions | None beyond 320/390/600; swipe off |
| Reduced editor on phones | Editable for scalar values, read-only for documents |
| Short-viewport floor | 240 px usable content |
