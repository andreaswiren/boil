# Screenspace & Surface Budgets

Screenspace is measured at runtime, not assumed from a breakpoint, and every
surface declares in advance how much of that space its chrome may spend. Owned
by **A05** (`ui-shell`): `packages/screenspace/**`, the shell, and
`apps/<app>/app/(app)/layout.tsx`. A05 publishes `screenspace` and
`surface-budget`; it consumes `theme-tokens`, `rbac` and `i18n:nav`. The budgets
here are asserted by A21's visual tests, so a layout that grows its header past
its budget fails a gate instead of being noticed six months later.

## Requirements covered

REQ-UI-09 (primary), REQ-UI-10 (primary), REQ-UI-07, REQ-UI-08, REQ-UI-11,
REQ-MOC-03, REQ-TST-02, REQ-TST-03, REQ-GRD-14.

## 1. What is measured (REQ-UI-09)

Five things, all live, all read from the platform rather than inferred:

| Signal | Source | Why it is not guessable |
|---|---|---|
| Viewport | `window.innerWidth/innerHeight`, `matchMedia` for orientation | The media query tells you which bucket, not how many pixels you have |
| Keyboard offset | `window.visualViewport` — `height`, `offsetTop`, `scroll` events | On iOS the layout viewport does not shrink when the keyboard opens. A fixed footer sits under the keyboard and nothing in CSS reports it |
| Safe-area insets | `env(safe-area-inset-*)`, read back through a probe element | Notch and home-indicator sizes differ per device and per orientation |
| Container size | `ResizeObserver` on each measured surface, plus CSS container queries | A pane in a two-pane layout is 600 px wide at a 1440 px viewport. Sizing it off the viewport is the bug container queries exist for |
| Available content height | Derived: viewport − chrome − keyboard − insets | This is the number a grid needs to decide how many rows fit |

The layer is one provider mounted in the `(app)` layout. It writes CSS custom
properties on `<html>` on every change, rAF-coalesced:

```css
--sp-vw, --sp-vh          /* layout viewport, px */
--sp-vvh                  /* visual viewport height (keyboard-aware) */
--sp-kb                   /* keyboard occlusion, px; 0 when closed */
--sp-safe-t/-r/-b/-l      /* resolved safe-area insets, px */
--sp-content-h            /* available content height for the current surface */
```

```ts
// packages/screenspace/index.ts — published as `screenspace`
export function useScreenspace(): {
  viewport: { w: number; h: number; orientation: "portrait" | "landscape" };
  breakpoint: BreakpointName;              // §2
  keyboard: { open: boolean; occlusion: number };
  safeArea: { top: number; right: number; bottom: number; left: number };
  content: { h: number; w: number };       // for the nearest measured surface
};
export function useContainer<T extends Element>(): {
  ref: RefObject<T>; w: number; h: number; class: ContainerClass;
};
```

Rules of use: a component reads `useContainer` for its own size and
`useScreenspace` only for viewport-level facts. Nothing reads
`window.innerHeight` directly — `pnpm lint:boundaries` fails on
`window.inner*`, `visualViewport` and `env(safe-area` outside
`packages/screenspace/`. One measurement layer, for the same reason there is one
time formatter (`spec/time.md` §1): two of them disagree, and the disagreement
surfaces as a 4-pixel gap nobody can reproduce.

`100vh` is banned in application CSS. It is wrong on mobile Safari by the height
of the browser chrome; `--sp-vvh` is right, and `100dvh` is the fallback when a
value is needed before hydration.

## 2. Named breakpoints

Three are fixed by requirement — 390, 834 and 1440 are the mockup and screenshot
viewports (REQ-MOC-03, REQ-TST-03). Four more exist because layout decisions
genuinely change there.

| Name | Min width | Reference device | What changes |
|---|---|---|---|
| `phone-min` | 320 | iPhone SE | Layout floor. Nothing may overflow here |
| `phone` | 390 | iPhone 14/15 | **Tested.** Bottom nav, single column, sheet detail |
| `phone-lg` | 600 | Large phone, phone landscape | Two-up cards, filter chips stay inline |
| `tablet` | 834 | iPad 10.9 portrait | **Tested.** Sidebar becomes an icon rail, tables become tables |
| `laptop` | 1024 | Tablet landscape, small laptop | Sidebar expands, two-pane detail becomes available |
| `desktop` | 1440 | **Tested.** | Full sidebar, multi-pane, density-first (REQ-UI-08) |
| `wide` | 1920 | Wide monitor | Content max-width caps; the extra space is margin, not stretched columns |

Budgets are declared at the three tested widths and interpolate between them.
A budget at `phone-lg` or `laptop` is added only when a critic finds a surface
that degrades there, so the budget table does not become seven columns of
numbers nobody maintains.

## 3. Surface budgets — what the concept is (REQ-UI-10)

A **surface** is a routed screen with chrome: the dashboard, a grid page, a
detail page, the login page. Every surface declares, per tested breakpoint:

- `chromeV` — vertical pixels consumed by fixed chrome above and below the
  content: app bar, page header, bottom nav, safe-area insets, a grid's toolbar
  and pagination footer.
- `chromeH` — horizontal pixels consumed by the sidebar or rail.
- `contentRatio` — content area ÷ viewport area, the single number that catches
  chrome creep on both axes at once.
- A **payload assertion** — the thing the user actually came for, counted:
  rows visible, cards visible, fields above the fold. A ratio can be satisfied
  by a large empty content area; a payload count cannot.

```ts
// packages/screenspace/budgets.ts — published as `surface-budget`
export type SurfaceBudget = {
  surface: string;                       // "grid", matches the route segment
  at: Record<"phone" | "tablet" | "desktop", {
    viewport: [number, number];
    chromeV: number;                     // maximum, px
    chromeH: number;                     // maximum, px
    contentRatio: number;                // minimum
    payload: { metric: string; min: number };
  }>;
};
```

A21 measures the real bounding boxes in a Playwright run and fails the gate when
`chromeV`, `chromeH` or `contentRatio` is exceeded or the payload count falls
short (REQ-TST-02, REQ-TST-03). Chrome is identified by `data-chrome` on the
shell elements, so measurement is not a guess about which pixels were which.

## 4. The worked budgets

Viewports: phone 390×844, tablet 834×1112, desktop 1440×900. Chrome counted:
app bar, page header, sidebar/rail, bottom nav, safe-area insets, grid toolbar,
pagination footer. **Not** counted as chrome: the table header row and the
filter row — those are the controls for the data, and calling them chrome would
push a grid toward a toolbar it cannot afford.

### Dashboard (`dashboard-01`, REQ-UI-01)

| At | chromeV ≤ | chromeH ≤ | contentRatio ≥ | Payload ≥ |
|---|---|---|---|---|
| phone 390×844 | 160 (bar 56 + nav 64 + inset 34) | 0 | 0.79 | 3 stat tiles fully visible without scroll |
| tablet 834×1112 | 120 (bar 56 + page header 64) | 72 (rail) | 0.86 | 4 tiles + 1 chart above the fold |
| desktop 1440×900 | 120 | 256 (sidebar) | 0.76 | 4 tiles + 2 charts above the fold |

### Grid page (`spec/datagrid.md`)

| At | chromeV ≤ | chromeH ≤ | contentRatio ≥ | Payload ≥ |
|---|---|---|---|---|
| phone 390×844 | 216 (bar 56 + search 48 + nav 64 + inset 34 + footer 14) | 0 | 0.74 | 5 cards fully visible |
| tablet 834×1112 | 208 (bar 56 + header 64 + toolbar 48 + footer 40) | 72 | 0.80 | 16 rows at 44 px |
| desktop 1440×900 | 224 (bar 56 + header 64 + toolbar 48 + footer 56) | 256 | 0.70 | 18 rows at 36 px compact |

### Detail page (sheet on phone, two-pane from `laptop`)

| At | chromeV ≤ | chromeH ≤ | contentRatio ≥ | Payload ≥ |
|---|---|---|---|---|
| phone 390×844 | 168 (sheet handle 24 + title 56 + action bar 54 + inset 34) | 0 | 0.78 | Title + 4 fields above the fold; the primary action is inside the bottom 40% (REQ-UI-07) |
| tablet 834×1112 | 128 | 72 | 0.85 | Title + 8 fields above the fold |
| desktop 1440×900 | 120 | 256 | 0.76 | Title + 10 fields, tabs visible, no horizontal scroll |

### Login page (`login-02`, REQ-UI-02)

No app chrome at all, so the budget is about the card and the keyboard.

| At | chromeV ≤ | chromeH ≤ | contentRatio ≥ | Payload ≥ |
|---|---|---|---|---|
| phone 390×844 | 34 (inset only) | 0 | 0.95 | With the keyboard open (`--sp-kb` ≈ 336, usable height ≈ 474): email, password and the submit button all visible, zero page scroll |
| tablet 834×1112 | 0 | 0 | 0.97 | Card ≤ 420 px wide, vertically centred, all three auth methods visible |
| desktop 1440×900 | 0 | 0 | 0.97 | Card ≤ 420 px wide; no method hidden behind a "more" affordance |

The keyboard row is the reason the measurement layer exists. A login card that
fits at 390×844 and hides its submit button under the iOS keyboard passes every
static screenshot and fails every real user.

## 5. These are starting numbers, and here is how they change

The numbers above are A05's first honest estimates from the reference layout and
the shadcn block dimensions. They are not settled. C1 will argue that a 224 px
chrome budget on a desktop grid is generous, and C1 will probably be right. A
budget's value is that it is a number someone has to argue against, not that the
first number was correct.

Revision is a controlled path, not a quiet edit:

1. A critic files a finding against `REQ-UI-10` naming the surface, the
   breakpoint, the measured value and the proposed value, with the screenshot.
2. A05 edits `packages/screenspace/budgets.ts` — the budgets are versioned data
   in one file, never prose in a component.
3. The commit states the old value, the new value and the reason. The visual
   baseline is re-recorded in the same commit.
4. **A relaxation needs C1's sign-off; a tightening does not.** A budget that
   loosens itself every time it fails is a comment, not a budget.
5. The mockup phase can move a budget freely: before REQ-MOC-05 approval there
   is no baseline to protect. After approval, steps 1–4 apply.

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Measurement layer | One provider, CSS custom properties + two hooks | REQ-UI-09; two measurers disagree | No |
| Direct `window.inner*` / `visualViewport` use | Banned outside `packages/screenspace` | Same reason as one time formatter | No |
| `100vh` | Banned; `--sp-vvh`, fallback `100dvh` | `100vh` is wrong by the browser chrome on mobile Safari | No |
| Named breakpoints | 320 / 390 / 600 / 834 / 1024 / 1440 / 1920 | 390/834/1440 are required; the rest are real layout changes | Yes, may add |
| Budgets declared at | The three tested widths, interpolated between | Seven columns of numbers rot | Yes |
| Budget metrics | `chromeV`, `chromeH`, `contentRatio`, payload count | A ratio alone passes with an empty content area | No |
| Table header + filter row | Content, not chrome | Calling them chrome starves the toolbar of an honest budget | No |
| Who may change a budget | A05 only, in `budgets.ts`, with the reason in the commit | REQ-UI-10 is a gate, not a preference | No |
| Relaxing a budget | Needs C1 sign-off | Self-loosening budgets measure nothing | No |
| Desktop sidebar | 256 px expanded, 72 px rail | Fits the nav registry's labels at `font: montserrat` | Yes |
| Content max-width at `wide` | 1600 px; the remainder is margin | Stretched columns are worse than white space | Yes |

## How this is verified

- `pnpm test:visual` — `tests/visual/budgets.spec.ts` (A21, REQ-UI-10): every
  registered surface at 390/834/1440 in light and dark; `chromeV`, `chromeH`,
  `contentRatio` and the payload count measured from real bounding boxes via
  `data-chrome`; a screenshot captured per assertion, not only on failure
  (REQ-TST-03) and presented in the reply (REQ-TST-04).
- `pnpm test:e2e` — `tests/e2e/screenspace/**` (REQ-TST-02): the login budget
  with the CDP-emulated software keyboard open; the bottom nav clear of the home
  indicator at 390 with insets emulated; a two-pane detail at 1024 measured by
  container size, not viewport; 44 px minimum touch targets on every primary
  action at `phone` (REQ-UI-07).
- `pnpm test:unit` — `tests/unit/screenspace/**`: derived content height against
  a table of viewport, chrome, keyboard and inset inputs; breakpoint resolution
  at each boundary ±1 px; rAF coalescing emits one update per frame.
- `pnpm lint:boundaries` — no `window.inner*`, `visualViewport`,
  `env(safe-area` or `100vh` outside `packages/screenspace/`.
- `GET /api/v1/shell/_selftest` — every registered surface has a budget entry at
  all three tested breakpoints, and every budget's surface resolves to a route
  (REQ-CTR-08).

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| Extra breakpoints beyond the seven | None |
| Content max-width on wide screens | 1600 px |
| Sidebar width / rail width | 256 px / 72 px |
| Two-pane detail from which breakpoint | `laptop` (1024) |
| Phone primary nav | Bottom bar (`spec/baseline.md`) |
| Budget strictness for the first build | As tabled here; the critics revise per §5 |
