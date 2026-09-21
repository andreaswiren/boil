# Datagrid

One grid component, one declaration per grid, identical behaviour in client and
server mode, and the same declaration rendered as cards on mobile. Owned by
**A07** (`datagrid`): `packages/datagrid/**` and the table `user_grid_prefs`.
A07 publishes `grid-def`, `grid-prefs` and `query-params`; it consumes
`pagination`, `theme-tokens`, `rbac` and `i18n:grid`. TanStack Table is the
headless base (REQ-GRD-01) — it supplies the row model, nothing else. A07 owns
no route and no data source: a grid consumes `pagination` plus contract
fixtures, which is why it finishes before any endpoint exists
(`contracts/README.md` §7).

## Requirements covered

REQ-GRD-01 … REQ-GRD-15, REQ-API-11, REQ-UI-07, REQ-UI-08, REQ-UI-11,
REQ-ENT-05, REQ-AUD-01, REQ-AUD-04, REQ-I18N-02, REQ-TST-08.

## 1. Toolbar geometry — positions, not preferences

REQ-GRD-02, REQ-GRD-03 and REQ-GRD-09 are positional requirements. They are
satisfied by fixed slots in the layout, not by a configurable toolbar.

```
┌───────────────────────────────────────────────────────────────────────────┐
│ [🔍 fuzzy search        ]  ·filter chips·          [density] [⚙ columns] │  top
├───────────────────────────────────────────────────────────────────────────┤
│ [✓] │ Name ▲¹ │ Status ▼² │ Site │ Updated          ← header + filter row│
│ [✓] │ …                                                                  │
├───────────────────────────────────────────────────────────────────────────┤
│ 3 selected  [Bulk ▾] [Export]        Rows [50 ▾]   ‹ 1 2 3 … 12 ›        │  bottom
└───────────────────────────────────────────────────────────────────────────┘
```

- **Fuzzy search is top-left**, first in DOM order and first in tab order
  (REQ-GRD-02). It is the leftmost element of the toolbar row above the table.
- **The column chooser is top-right**, last in the toolbar row (REQ-GRD-03).
  Density sits immediately left of it because both are view controls.
- **Pagination is at the bottom**, right-aligned, with the page-size select to
  its left (REQ-GRD-09). Nothing paginates at the top; a second control is a
  second source of truth.
- Active filters render as removable chips between the two, so a filtered grid
  never looks empty for an unexplained reason.
- The bulk-action bar occupies the bottom-left slot and appears only with a
  selection. It replaces nothing; the row is reserved so the table does not
  shift when a checkbox is ticked.

Slots are `GridToolbarLeft`, `GridToolbarRight`, `GridFooterLeft`,
`GridFooterRight`. A grid may fill them; it may not move them. `pnpm test:visual`
asserts the search input's bounding box is left of the chooser's at all three
breakpoints, which is the only way a positional requirement stays true.

## 2. `GridDefinition` — the whole declaration

```ts
// packages/datagrid/types.ts (A07), published as `grid-def`
export type GridDefinition<TRow> = {
  /** Stable preference key. Never derived from the route (REQ-GRD-08). */
  gridKey: string;                       // "device.list", "audit.events"
  i18nNamespace: string;                 // "grid.device" (REQ-I18N-05)
  sizeClass: "small" | "large";          // page-size defaults, §7
  mode: "client" | "server" | "auto";    // "auto" resolves by serverThreshold
  serverThreshold: number;               // default 5_000 rows (REQ-GRD-12)
  allRowCeiling: number;                 // default 50_000 rows (REQ-GRD-11)
  pageSizes?: readonly PageSize[];       // overrides the size class default
  defaultSort: SortSpec[];               // [{ id: "updatedAt", dir: "desc" }]
  maxSortColumns: number;                // default 4
  rowId: (row: TRow) => string;
  columns: GridColumn<TRow>[];
  selection?: { mode: "none" | "single" | "multi" };
  bulkActions?: BulkAction<TRow>[];      // §9
  export?: { permission: PermissionString; formats: ("csv" | "ndjson")[] };
  mobile: MobileCardSpec<TRow>;          // §10 — mandatory, not a fallback
};

export type GridColumn<TRow> = {
  id: string;                            // matches the API sort/filter field
  i18nKey: string;                       // never a literal (REQ-I18N-02)
  accessor: (row: TRow) => unknown;
  filter: FilterSpec | null;             // null = not filterable, stated
  sortable: boolean;
  width: { initial: number; min: number; max?: number };
  align?: "start" | "end";               // numbers end-aligned, §4
  visibility: "default" | "hidden" | "locked";  // locked = not hideable
  pinned?: "start" | "end";
  cell?: (row: TRow) => ReactNode;       // must use semantic tokens (A06)
  permission?: PermissionString;         // column hidden without it, server-side too
};
```

`mobile` is required. A definition without a card spec fails
`pnpm test:contract`, because REQ-GRD-14 is not a progressive enhancement and a
grid whose mobile rendering was never designed ships as a horizontal scrollbar.

A column carrying `permission` is stripped **server-side** from the row payload,
not hidden in the client. Hiding a column the response still contains is a
disclosure with a CSS fix.

## 3. Sorting and multi-sort precedence (REQ-GRD-04)

A header click cycles `asc → desc → none`. `Shift`-click, or `Shift+Enter` on a
focused header, appends the column to the sort list instead of replacing it.

Precedence is visible in two places at once:

1. On the header: the direction arrow plus a superscript ordinal — `Name ▲¹`,
   `Status ▼²`. The ordinal renders only when more than one column is sorted, so
   a single-sort grid stays quiet.
2. Above the table, a chip row: `Sorted by: Name ↑ · then Status ↓ · Clear`.
   Chips are drag-reorderable and keyboard-reorderable with `Alt+←/→`, which is
   how a user changes precedence without re-clicking headers in order.

`maxSortColumns` defaults to 4. Beyond that a server-mode grid sorts on columns
with no supporting index and the query plan degrades silently; refusing the
fifth sort with `grid.sort.max_reached` is honest. The sort list is part of the
URL state (§6) and of the query grammar shared with the API
(`contracts/types/pagination.md`): `?sort=name,-status`.

## 4. Per-column filter controls (REQ-GRD-05)

The control is chosen by the column's `filter.type`. There is one control per
type and no per-grid variation, so a user learns the filter once.

| Type | Control | Operators | URL form |
|---|---|---|---|
| `text` | input with a clear button, debounced 300 ms | `contains` (default), `eq`, `startsWith` | `f.name=contains:fw-` |
| `enum` | multi-select checklist, options from the definition, with counts in client mode | `in`, `notIn` | `f.status=in:active,paused` |
| `number` | two bounded inputs, min and max, either side optional | `gte`, `lte`, `eq` | `f.port=gte:1024,lte:65535` |
| `date` | range picker with presets: today, 7d, 30d, this month, custom | `gte`, `lte` | `f.createdAt=gte:2026-09-01` |
| `boolean` | tri-state segmented control: any / yes / no | `eq` | `f.enabled=eq:true` |
| `relation` | async combobox, paged lookup, searches by label | `in` | `f.siteId=in:<uuid>,<uuid>` |

Rules that hold for every type: an empty control is not a filter and emits no
parameter; dates are sent as instants resolved in the user's timezone and stored
UTC (`spec/time.md` §3); enum labels come from the i18n namespace, never from
the raw database value; a filter on a permission-gated column is refused
server-side with 403 rather than returning zero rows, because zero rows reads as
"no such data" and that is a lie. Filters live in the header filter row on
desktop and in a filter sheet on mobile — same state object, same URL.

Fuzzy search (REQ-GRD-02) is separate from column filters: it is a ranked match
across the columns declared `fuzzy: true`, `q=` in the URL, and it composes with
filters by intersection. In server mode it maps to one `ILIKE`-based ranked
predicate; the grid does not send a regex.

## 5. Reordering and resizing, with keyboard equivalents (REQ-GRD-06, REQ-GRD-07)

Pointer: drag a header to reorder, drag its right edge to resize, double-click
the edge to auto-fit to the widest visible cell.

Keyboard, on a focused header cell — REQ-UI-11 means these are not optional:

| Keys | Effect |
|---|---|
| `Alt+←` / `Alt+→` | Move the column one position left or right |
| `Ctrl+←` / `Ctrl+→` | Resize by 16 px |
| `Ctrl+Shift+←` / `→` | Resize by 1 px |
| `Ctrl+0` | Reset the width to `width.initial` |
| `Enter` / `Space` | Open the column menu: sort, filter, hide, pin |

Every change is announced on an `aria-live="polite"` region — "Status moved to
position 3 of 7", "Status width 240 pixels" — because a silent reorder is
invisible to a screen reader and the pointer interaction is unusable for the
keyboard user REQ-UI-11 exists for. Widths clamp to `min`/`max`; a pinned column
cannot be dragged out of its pin group; a `locked` column cannot be hidden.

## 6. Preferences: what persists, where, and which source wins

**Persisted** per user per `gridKey`: column visibility, column order, column
widths, pinning, the sort list, per-column filter values, density, page size.

**Not persisted**, deliberately: the fuzzy query, the selection, the page
number. A user returning to a grid that silently reapplied last week's search
sees an empty table and reports a data-loss bug. Page number is transient for
the same reason.

```sql
user_grid_prefs (A07)                       -- tenant-scoped, RLS forced
  user_id  uuid not null,
  grid_key text not null,
  prefs    jsonb not null,                  -- versioned payload, { v: 1, ... }
  primary key (user_id, grid_key)
  -- entity-base minus `comment` (exempt, contracts/types/entity-base.md §6)
```

Writes are debounced 500 ms and applied optimistically to the local store, so
dragging a column is not a request per pixel. `prefs` carries a schema version;
an unreadable or older payload is discarded back to the definition default
rather than migrated in place, and the discard is logged at `warn`. A column id
no longer in the definition is dropped on read — a removed column must not brick
a user's grid.

**Precedence, highest first (REQ-GRD-08, REQ-GRD-15):**

1. **URL** — `?sort=…&f.*=…&cols=…&size=…&density=…`. A shared link reproduces
   the sender's view exactly.
2. **Profile** — the `user_grid_prefs` row for this user and `gridKey`.
3. **Definition default** — `defaultSort`, `visibility`, `width.initial`,
   the size class's first page size.

A visit carrying URL state **does not overwrite the profile**. The toolbar shows
`Viewing a shared view · Save as my default · Reset`, and only `Save` writes.
REQ-GRD-15 says the URL wins *for that visit*; a link that quietly rewrites the
recipient's saved layout is a side effect nobody asked for. The URL is written
with `history.replaceState` so interaction does not fill the back stack, and
`cols` is a compact ordered id list rather than a serialised object.

## 7. Size classes and page sizes (REQ-GRD-10)

Page-size ranges are **defaults per size class**, not global constants. A grid
declares its class, or overrides with `pageSizes` outright.

| `sizeClass` | Default range | Initial | Intended for |
|---|---|---|---|
| `small` | `[10, 20, 50, "all"]` | 20 | Reference lists: roles, sites, templates |
| `large` | `[20, 50, 100, 200, 500, "all"]` | 50 | Event and asset tables |

```ts
export const PAGE_SIZE_DEFAULTS = {
  small: [10, 20, 50, "all"],
  large: [20, 50, 100, 200, 500, "all"],
} as const satisfies Record<GridSizeClass, readonly PageSize[]>;
```

These constants are read only as the default for a declared class. Nothing in
the grid imports a single global page-size list — that is the shape REQ-GRD-10
forbids, because one list means every grid in the app is tuned for whichever
table someone had in mind last.

## 8. The `all` guard (REQ-GRD-11)

`all` is offered on every grid and guarded on every grid. The decision uses the
same count the pagination footer already has, so the guard costs no extra query.

| Row count | Behaviour |
|---|---|
| `≤ serverThreshold` (5 000) | Rendered directly, virtualised rows |
| `> serverThreshold`, `≤ allRowCeiling` | Streamed in 1 000-row pages with a progress indicator and a cancel button; rows appear as they land |
| `> allRowCeiling` (50 000) | Refused, with the message below and an export offer |

The refusal is a message, not a spinner and not a truncation:

```
grid.all.refused =
  "This view has {rows, number} rows. {ceiling, number} is the most this page
   can load at once. Narrow the filters, or export the full result instead."
```

Its shape is fixed: **the actual number**, **the ceiling**, **what to do
instead**. "Too many rows" tells the user nothing they did not know, and a
truncated `all` is a wrong answer presented as a complete one. The export offer
is rendered only if the caller holds the export permission; without it the
sentence ends after "Narrow the filters." The selected size falls back to the
previous value, so the grid stays usable.

## 9. Selection, bulk actions, export (REQ-GRD-13)

Selection is per row plus a header checkbox that selects the **loaded page**,
with a distinct `Select all {n} matching` affordance that carries the filter
rather than a list of ids. Selection survives pagination and clears on a filter
change, because a filter change means the selected set is no longer what the
user was looking at.

```ts
export type BulkAction<TRow> = {
  id: string;                         // "device.decommission"
  i18nKey: string;
  permission: PermissionString;       // hidden without it, checked server-side
  confirm: "none" | "dialog" | "typed";
  requiresComment: boolean;           // writes entity-base `comment`
  maxSelection?: number;              // default 500
  execute: "per-row" | "batch";
};
```

The client hides an action the caller lacks; the server checks it again per row,
because a selection is a list of ids and a list of ids is client input. A
partial failure returns per-row results and the grid marks the failed rows in
place — a bulk action that reports "3 of 40 failed" without saying which three
is unusable.

Export is audited (`spec/observability.md` §2), needs the declared export
permission plus step-up within 900 s (`spec/auth.md` §6), and emits
`<domain>.<resource>.export` carrying row count, the column set, a hash of the
filter state and the format. It runs server-side from the same query the grid
just ran — never from the rows the client happens to hold — so a permission-
gated column cannot be exported by a client that had it in memory. CSV is
UTF-8 with a BOM and `\r\n` for Excel; NDJSON is the machine format.

## 10. Mobile: the same definition, rendered as cards (REQ-GRD-14)

One definition, two renderers. Below the 834 px breakpoint the grid renders
`MobileCardSpec`, not a shrunken table.

```ts
export type MobileCardSpec<TRow> = {
  primary: (row: TRow) => ReactNode;        // one line, the identity of the row
  secondary?: (row: TRow) => ReactNode;     // one line, the disambiguator
  meta: string[];                           // up to 3 column ids, label: value
  badge?: string;                           // a column id rendered as a status badge
  action?: "sheet" | "navigate";            // default "sheet" (REQ-UI-07)
};
```

Filter and sort state is **shared, not parallel** — the same store, the same URL
parameters, the same `user_grid_prefs` row. A filter set on the phone is present
on the desktop after login. The controls differ: search stays at the top,
filters open in a bottom sheet, sort opens in a bottom sheet listing the same
precedence chips, and pagination becomes a footer with page controls at 44 px
minimum touch size (REQ-UI-07). Column order and visibility carry over as the
`meta` field order; widths are meaningless on a card and are ignored, not lost.

## 11. One client contract in both modes (REQ-GRD-12)

Every grid calls one function. The mode decides who executes it.

```ts
export type GridQuery = {                 // === contracts/types/pagination.md
  page: number; size: PageSize;
  sort: SortSpec[]; filters: FilterValue[]; q?: string;
  includeDeleted?: boolean;               // REQ-ENT-05
};
export type GridPage<TRow> = {
  rows: TRow[]; total: number; page: number; size: PageSize;
  truncated: boolean;                     // true only on a streamed `all`
};
export type GridSource<TRow> = (query: GridQuery) => Promise<GridPage<TRow>>;
```

- `mode: "server"` — the query is serialised to the URL grammar and sent.
- `mode: "client"` — the same `GridQuery` is resolved in memory by the same
  comparators and predicate functions the server uses, generated from the
  column specs.
- `mode: "auto"` — server if `total > serverThreshold`, client otherwise,
  decided once from the first response's `total`.

No component, no column spec, no URL and no preference payload differs between
the modes. Switching a grid from client to server is a one-line change in its
definition. This is the requirement's point: the identical contract is what lets
A07 build against fixtures while A11's endpoints do not yet exist, and the
interface test lives in `packages/contracts/tests/` and is run by both
(REQ-CTR-10).

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Headless base | TanStack Table | REQ-GRD-01 | No |
| Search / chooser / pagination position | Top-left / top-right / bottom, fixed slots | REQ-GRD-02, 03, 09 are positional | No |
| Toolbar configurability | Slots may be filled, not moved | A movable requirement is not a requirement | No |
| `maxSortColumns` | 4 | Beyond that server plans degrade silently | Yes |
| Filter debounce / date presets | 300 ms / today, 7d, 30d, this month | Responsive without a request per keystroke | Yes |
| Persisted keys | visibility, order, width, pin, sort, filters, density, size | REQ-GRD-08 | No |
| Not persisted | fuzzy query, selection, page number | A reapplied old search reads as data loss | No |
| Preference precedence | URL > profile > definition default | REQ-GRD-08, REQ-GRD-15 | No |
| URL state overwriting the profile | Never — explicit "Save as my default" | A link must not rewrite the recipient's layout | No |
| Page sizes | Per size class, `small` and `large` | REQ-GRD-10 forbids a global constant | Yes, per grid |
| `serverThreshold` / `allRowCeiling` | 5 000 / 50 000 rows | Largest expected table is 100k (INTAKE.md) | Yes |
| `all` above the ceiling | Refused with counts and an alternative | REQ-GRD-11 — no truncation, no hang | No |
| Bulk `maxSelection` | 500 | Bounds one request and one audit event | Yes |
| Export source | Server-side, re-running the query | Client rows may hold gated columns | No |
| Mobile rendering | Mandatory card spec per grid | REQ-GRD-14, REQ-UI-07 | No |
| Mobile state | The same store, URL and prefs row | Parallel state is state that disagrees | No |

## How this is verified

- `pnpm test:unit` — `tests/unit/datagrid/**`: every filter type maps to and
  from its URL form; the comparator set is identical in client and server mode
  against the same fixture; precedence resolution for all eight
  URL/profile/default combinations; `prefs` version discard.
- `pnpm test:integration` — `tests/integration/datagrid/**` (REQ-TST-08): the
  preference round-trip — set width, order, sort and filters, reload, new
  device, same result; a shared URL does not mutate the stored row; a dropped
  column id does not break the grid.
- `pnpm test:e2e` — `tests/e2e/grid/**` (Playwright over CDP, REQ-TST-02):
  keyboard reorder and resize with the `aria-live` announcement asserted;
  `Shift`-click multi-sort and chip reordering; `all` at each of the three row
  bands including the exact refusal text; bulk action denied without permission;
  export triggers step-up and emits the audit event.
- `pnpm test:visual` — `tests/visual/grid.spec.ts`: search left of chooser and
  pagination at the bottom at 390/834/1440, light and dark; the card renderer at
  390; axe AA on the toolbar, header row and filter sheet (REQ-TST-06); the
  surface budget for a grid page (`spec/screenspace.md` §4).
- `pnpm test:audit` — export emits `<domain>.<resource>.export` with row count,
  column set and filter hash; a bulk action emits one event per affected row.
- `pnpm test:contract` — `packages/contracts/tests/query-params.spec.ts`: the
  grid's `GridQuery` serialisation is accepted by A11's route schemas and the
  reverse, run by both agents (REQ-CTR-10); every `GridDefinition` has a
  `mobile` spec, a unique `gridKey`, and columns whose `id` matches a sortable
  API field.

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| Size class per entity grid | `large` for event and asset tables, `small` for reference lists |
| Expected largest table | 100 000 rows — sets `serverThreshold` at 5 000 |
| `allRowCeiling` | 50 000 rows |
| Export formats | CSV and NDJSON |
| Does export require step-up | Yes, 900 s |
| Default density | Comfortable on mobile, compact on desktop (REQ-UI-08) |
| Bulk actions per entity | None until a domain declares one |
