# `mobile-primitives` — touch primitives, thumb zones and the mobile budget

**Published by:** A27, declared once in `packages/mobile/contract.declaration.ts`,
assembled by A02: `TouchBudget`, `BottomNavSpec`, `SheetSpec`, `ActionBarSpec`,
`ThumbZone`, `SafeAreaSpec`, `KeyboardAvoidSpec`, `PullToRefreshSpec`,
`DegradationNotice`.
**Requirements:** REQ-MOB-01 … REQ-MOB-12, REQ-UI-07, REQ-UI-09, REQ-UI-10,
REQ-UI-15, REQ-MON-10, REQ-GRD-14, REQ-TST-02, REQ-TST-03.
**Consumed by:** A03, A05, A07, A09, A12, A13, A16, A21, A24, A25.

**The package carries containers and numbers, never surfaces.** A primitive owns
hit area, insets, motion, keyboard behaviour and dismissal; the content inside it
belongs to the composing domain (REQ-CTR-04). A27 owns no route file, no shell
file and no table, so a primitive cannot become a second implementation of another
agent's page. The design is `spec/mobile-ux.md`; this is the frozen shape.

---

## 1. Mobile breakpoints (REQ-MOB-11)

Three, a subset of A05's seven (`spec/screenspace.md` §2) — not a second scale.
Above `tablet` (834) nothing here applies.

```ts
export const MobileBreakpointSchema = z.enum(["phone-min", "phone", "phone-lg"]);
export const MOBILE_VIEWPORTS = {
  "phone-min": [320, 568],   // layout floor
  "phone":     [390, 844],   // the tested width (REQ-MOC-03, REQ-TST-03)
  "phone-lg":  [600, 896],
} as const;
```

Landscape is **not** a fourth breakpoint: 844×390 resolves to `tablet` by width
and would escape the mobile budget. `TouchBudget.shortViewport` handles it, keyed
off measured height (§2).

## 2. `TouchBudget` — extends `surface-budget`, does not replace it

A `TouchBudget` names the same `surface` string as A05's `SurfaceBudget` and adds
the dimension A05's four metrics cannot express: a surface satisfies `chromeV`,
`chromeH`, `contentRatio` and its payload with 28 px buttons touching each other.

```ts
export const TouchBudgetSchema = z.object({
  /** MUST equal a registered SurfaceBudget.surface (A05). Unmatched = assembly failure. */
  surface: z.string(),
  at: z.record(MobileBreakpointSchema, z.object({
    viewport: z.tuple([z.number().int(), z.number().int()]),
    minTargetPx: z.number().int().min(44),          // REQ-MOB-03
    minSpacingPx: z.number().int().min(8),          // REQ-MOB-03
    /** Fractions of usable height, measured up from the bottom safe-area edge (REQ-MOB-04). */
    reach: z.object({ easyFrac: z.number().max(0.40), okFrac: z.number().max(0.62) }),
    maxChromeV: z.number().int(),                   // fixed chrome, px; at `phone` it is A05's
    primaryActionZone: z.enum(["easy", "ok"]),      // never "hard"
    destructiveSeparationPx: z.number().int().min(96),
  })),
  /** REQ-MOB-10. Applies at any breakpoint once measured height drops below the floor. */
  shortViewport: z.object({ minUsableContentPx: z.number().int(),
    collapses: z.array(z.enum(["bottom-nav", "action-bar", "page-header", "sheet-handle"])) }),
  degradation: DegradationNoticeSchema.nullable() }).strict();   // REQ-MOB-12
```

`maxChromeV` at `phone` is **consumed, not authored**: A05 declares `chromeV` at
390 and A27 copies it. A27 authors it at `phone-min` and `phone-lg`, which A05
does not declare (budgets exist at 390/834/1440 only). A `TouchBudget` whose
`phone.maxChromeV` exceeds A05's fails assembly naming both files — the mechanical
form of "consume it, do not contradict it".

## 3. The primitives (REQ-MOB-02)

Each is a container with a props schema. None takes a domain type, a row, a field
or a data source. `PermissionString` is the 3-segment
`<domain>.<resource>.<action>` grammar (REQ-RBA-01) and belongs to the composing
agent — a primitive never decides who may see its children (REQ-RBA-02).

```ts
export const ActionRefSchema = z.object({
  id: z.string().regex(/^[a-z][a-z0-9-]*\.[a-z][a-z0-9-]*$/),
  labelKey: z.string().min(1),                       // i18n key, never a literal (REQ-I18N-02)
  weight: z.enum(["primary", "secondary", "destructive"]),
  permission: PermissionStringSchema.nullable() }).strict();   // gated server-side by the consumer

// SafeArea reads A05's --sp-safe-*; it never calls env(safe-area-inset-*) itself.
export const SafeAreaSpecSchema = z.object({
  edges: z.array(z.enum(["top", "right", "bottom", "left"])).nonempty(),
  mode: z.enum(["pad", "inset-bg"]).default("pad") }).strict();
// ThumbZone bands resolve from §2's reach fractions against measured --sp-vvh.
export const ThumbZoneSchema = z.object({ zone: z.enum(["easy", "ok", "hard"]),
  weight: z.enum(["primary", "secondary", "destructive"]) }).strict();
export const BottomNavSpecSchema = z.object({
  items: z.array(z.object({ navEntryId: z.string(), labelKey: z.string(), icon: z.string() }))
    .min(2).max(5),                                  // item 6+ goes to A05's more-sheet
  moreSheet: z.boolean().default(true),
  heightPx: z.literal(64),
  hideOnScroll: z.literal(false) }).strict();        // REQ-MOB-08: escape is always one action

export const SheetSpecSchema = z.object({
  id: z.string(),
  detents: z.array(z.enum(["peek", "half", "full"])).nonempty(),
  initialDetent: z.enum(["peek", "half", "full"]),
  dismissAffordance: z.literal("button-and-drag"),   // REQ-MOB-07: gesture + visible equivalent
  stackDepthMax: z.literal(2),                       // REQ-MOB-08
  pushesHistoryEntry: z.literal(true),               // back closes the sheet, not the app
  keyboardBehavior: z.enum(["resize", "hoist"]).default("resize") }).strict();

export const ActionBarSpecSchema = z.object({
  primary: ActionRefSchema,
  secondary: z.array(ActionRefSchema).max(2),
  destructive: ActionRefSchema.nullable(),           // overflow sheet, never inline (REQ-MOB-04)
  placement: z.literal("bottom"),
  clearsKeyboard: z.literal(true) }).strict();       // sits above --sp-kb (REQ-MOB-05)

export const KeyboardAvoidSpecSchema = z.object({
  keep: z.enum(["focused-field", "focused-field+primary"]).default("focused-field+primary"),
  strategy: z.enum(["resize", "scroll-into-view"]).default("resize"),
  extraGapPx: z.number().int().min(8).default(16) }).strict();

export const PullToRefreshSpecSchema = z.object({
  enabled: z.boolean(), triggerPx: z.number().int().min(64),
  armedOnlyAtScrollTop: z.literal(true),             // REQ-MOB-07: never mid-scroll
  equivalentActionId: z.string().min(1),             // the visible non-gesture refresh
  cooldownMs: z.number().int().min(1000) }).strict();

export const DegradationNoticeSchema = z.object({    // REQ-MOB-12, REQ-MON-10
  surface: z.string(), belowBreakpoint: z.enum(["phone-lg", "tablet"]),
  offers: z.enum(["read-only", "reduced", "link-out"]),
  reasonKey: z.string().min(1),                      // i18n `mobile.*`; states what is missing
  helpTopicId: z.string().min(1) }).strict();        // REQ-DOC-03
```

## 4. What A21 asserts, field by field (REQ-MOB-03, REQ-MOB-11)

A21 reads these fields from the assembled contract and measures the rendered box
model over CDP with touch emulation on, at all three viewports, in both themes.
| Field | How A21 uses it | REQ |
|---|---|---|
| `minTargetPx` | Every interactive element's `boundingBox()` in the surface: `w ≥ 44 && h ≥ 44` | REQ-MOB-03 |
| `minSpacingPx` | Pairwise rectangle gap for every interactive pair under 88 px centre distance | REQ-MOB-03 |
| `reach.*` + `primaryActionZone` | Bands resolved from measured `--sp-vvh` and `--sp-safe-b`; the primary action's centre must fall inside the named band | REQ-MOB-04 |
| `destructiveSeparationPx` | Distance from any destructive target to the nearest primary or frequent one | REQ-MOB-04 |
| `maxChromeV` | Sum of `data-chrome` box heights at each mobile viewport | REQ-UI-10, REQ-MOB-01 |
| `shortViewport.collapses` | Emulated 844×390 with the software keyboard open; the listed chrome must be absent | REQ-MOB-10 |
| `degradation` | Where non-null, the surface must render the notice and must not mount the heavy component | REQ-MOB-12 |

## 5. Assembly checks (A02)

A mismatch is a hard failure naming both claimants (`contracts/README.md` §3).

| Check | Fails when | Why it is fatal |
|---|---|---|
| Unmatched surface | `TouchBudget.surface` resolves to no `SurfaceBudget` | The budget would be asserted against nothing and the surface would ship unmeasured |
| Looser chrome | `at.phone.maxChromeV` > A05's `chromeV` at 390 | Two budgets for one surface; the weaker one silently wins (REQ-MOB-01) |
| Missing budget | A surface renders below 834 with no `TouchBudget` | REQ-MOB-03 is asserted per surface; an absent entry reads as a pass |
| Gesture without equivalent | `PullToRefreshSpec.enabled` and no `equivalentActionId` | REQ-MOB-07: a capability reachable only by gesture is unreachable with a screen reader or a stylus |
| Destructive in the bar | `ActionBarSpec.destructive` rendered inline beside `primary` | REQ-MOB-04: the miss distance on a phone is a thumb width (`spec/mobile-ux.md` §3) |
| Notice without help | `DegradationNotice.helpTopicId` not in A16's registry | REQ-DOC-03; "not available here" with no route onward is an apology, not a design |

## 6. Additive vs breaking

**Additive**
- A new primitive, a new optional prop, a new `detent`, a new `offers` value, a
  new `collapses` member.
- A new surface's `TouchBudget` entry, including a first `phone-min` or `phone-lg`
  entry for a surface that had only `phone`.
- A `DegradationNotice` where there was `null`: it narrows what the surface claims
  and breaks no consumer.

**Breaking**
- **Changing any budget number** — `minTargetPx`, `minSpacingPx`, `reach.*`,
  `maxChromeV`, `destructiveSeparationPx`. Every surface asserted against the
  value re-resolves on the next A21 run with no commit of its own. Raising it
  fails a dozen surfaces at once, owned by agents who changed nothing. Lowering
  it is worse: layouts that were failing start passing, the baseline is
  re-recorded, and the regression becomes the baseline. A number several owners
  are measured against is contract exactly as a type is (REQ-CTR-03).
- Renaming a primitive or a prop; making `equivalentActionId`, `helpTopicId` or
  `reasonKey` optional; reordering `ThumbZone.zone` or the detent enum (compared
  by index).
- **Redefining a number's basis while keeping its name and value.** Reading
  `easyFrac` against the layout viewport instead of the visual viewport keeps
  `0.40` on the page and moves the band by the keyboard's height. Nothing fails:
  the type is unchanged, the detector passes (REQ-CTR-07), the schema parses, and
  every assertion reports green against a band that is no longer where a thumb
  is. `contracts/README.md` §5's worst case — meaning changed under one name. A
  basis change gets a new field name, the old one deprecated with a removal
  version (REQ-CTR-03, REQ-CTR-09).

Procedure mirrors `spec/screenspace.md` §5: a critic files against the REQ ID with
the measured and proposed values, A27 edits `packages/mobile/budgets.ts`, the
commit states old, new and reason, and **a relaxation needs C1's sign-off while a
tightening does not**. Before REQ-MOC-05 approval the numbers move freely; after
it, CCR only.
