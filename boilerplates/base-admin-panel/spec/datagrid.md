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
REQ-ENT-05, REQ-AUD-01, REQ-AUD-04, REQ-I18N-02, REQ-SET-04, REQ-SET-11,
REQ-TST-08.

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
  selection. The row is reserved, so ticking a checkbox shifts nothing.

Slots are `GridToolbarLeft`, `GridToolbarRight`, `GridFooterLeft`,
`GridFooterRight`. A grid may fill them; it may not move them. `pnpm test:visual`
asserts the search input's bounding box is left of the chooser's at all three
breakpoints — the only way a positional requirement stays true.

## 2. `GridDefinition` — the whole declaration

```ts
// packages/datagrid/types.ts (A07), published as `grid-def`
export type GridDefinition<TRow> = {
  /** Stable preference key. Never derived from the route (REQ-GRD-08). */
  gridKey: string;                       // "canonical.device", "audit.events"
  i18nNamespace: string;                 // "grid" (contracts/types/i18n-namespaces.md §1)
  sizeClass: "small" | "large";          // page-size defaults, §7
  mode: "client" | "server" | "auto";    // resolved once by serverThreshold
  serverThreshold: number;               // default 5_000 rows (REQ-GRD-12)
  allRowCeiling: number;                 // default 50_000 rows (REQ-GRD-11)
  pageSizes?: readonly PageSize[];       // overrides the size class default
  defaultSort: SortSpec;                 // [{ column: "updatedAt", direction: "desc" }]
  paging: "page" | "cursor";             // page mode by default (pagination.md §5)
  rowId: (row: TRow) => string;
  columns: GridColumn<TRow>[];
  selection?: { mode: "none" | "single" | "multi" };
  bulkActions?: BulkAction<TRow>[];      // §9
  export?: { permission: PermissionString; formats: ("csv" | "ndjson")[] };
  mobile: MobileCardSpec<TRow>;          // §10 — mandatory, not a fallback
};

export type GridColumn<TRow> = {
  /** Matches the API's column name: /^[a-zA-Z][a-zA-Z0-9_]{0,62}$/ */
  id: string;
  i18nKey: string;                       // "grid.device.columnSerial" — never a literal
  accessor: (row: TRow) => unknown;
  type: "text" | "enum" | "number" | "date" | "boolean";  // decides the operators
  filterable: boolean;                   // false = no filter control, stated
  searchable?: boolean;                  // included in `q` (REQ-GRD-02)
  sortable: boolean;
  width: { initial: number; min: number; max?: number };
  align?: "start" | "end";               // numbers end-aligned
  visibility: "default" | "hidden" | "locked";  // locked = not hideable
  pinned?: "start" | "end";
  cell?: (row: TRow) => ReactNode;       // semantic tokens only (spec/theming.md §3)
  permission?: PermissionString;         // stripped server-side without it
};
```

The column's `type` is what makes the filter control and the legal operator set
derivable rather than declared twice (`contracts/types/pagination.md` §4). The
column `id` obeys the contract's `ColumnNameSchema`, because in server mode the
name is resolved against the declared column list before it reaches SQL and is
never interpolated.

`mobile` is required. A definition without a card spec fails
`pnpm test:contract`: REQ-GRD-14 is not a progressive enhancement, and a grid
whose mobile rendering was never designed ships as a horizontal scrollbar.

A column carrying `permission` is stripped **server-side** from the row payload,
not hidden in the client. Hiding a column the response still contains is a
disclosure with a CSS fix.

## 3. Sorting and multi-sort precedence (REQ-GRD-04)

The wire form is the contract's: `sort=status:asc,createdAt:desc`, left to right
is highest to lowest precedence, maximum four clauses
(`contracts/types/pagination.md` §3).

A header click cycles `asc → desc → none`. `Shift`-click, or `Shift+Enter` on a
focused header, appends the column instead of replacing the list.

Precedence is visible in two places at once:

1. On the header: the direction arrow plus a superscript ordinal — `Name ▲¹`,
   `Status ▼²`. The ordinal renders only when more than one column is sorted, so
   a single-sort grid stays quiet.
2. Above the table, a chip row: `Sorted by: Name ↑ · then Status ↓ · Clear`.
   Chips are drag- and keyboard-reorderable with `Alt+←/→`, which is how a user
   changes precedence without re-clicking headers in order.

Both render from the response's `appliedSort`, not from the request the grid
sent (§11). A server that silently ignored a sort is then visible in the UI
instead of looking like a bug in the data.

A fifth clause is refused client-side with the same message the server returns —
`common.validation_failed` — because beyond four clauses a server-mode grid
sorts on columns with no supporting index and the plan degrades silently. A sort
on a column not declared `sortable` is `grid.sort_column_unknown`. Every sort is
stabilised server-side by appending `id:asc`; without it, keyset pagination over
a non-unique key skips and repeats rows.

## 4. Per-column filter controls (REQ-GRD-05)

The control follows the column's declared `type`, and the legal operators are
the contract's (`contracts/types/pagination.md` §4). One control per type, no
per-grid variation, so a user learns the filter once.

| Type | Control | Operators | URL form |
|---|---|---|---|
| `text` | input with a clear button, debounced 300 ms | `eq`, `neq`, `contains`, `starts`, `ends`, `empty` | `filter[name]=contains:nordlo` |
| `enum` | multi-select checklist, options from the definition, counts in client mode | `eq`, `in`, `nin` | `filter[status]=in:active,suspended` |
| `number` | two bounded inputs, either side optional | `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `between` | `filter[seats]=between:10,50` |
| `date` | range picker with presets: today, 7d, 30d, this month, custom | `on`, `before`, `after`, `between`, `empty` | `filter[createdAt]=between:2026-01-01T00:00:00Z,2026-02-01T00:00:00Z` |
| `boolean` | tri-state segmented control: any / yes / no | `is` | `filter[mfaRequired]=is:true` |

Rules that hold for every type:

- An empty control is not a filter and emits no parameter.
- **A date filter is sent as RFC 3339 with a `Z` offset, never as
  `YYYY-MM-DD`.** The picker resolves the operator's timezone through
  `packages/contracts/time` and sends instants, because "2026-01-01" is two
  different moments in `Europe/Stockholm` and UTC and the server must not have
  to guess which one the user meant (`spec/time.md` §3).
- A literal comma inside a scalar is `%2C`; the split happens after decoding the
  pair and before decoding the scalars.
- Enum labels come from the i18n namespace, never from the raw database value.
- An operator the column's type does not allow is `grid.filter_op_unsupported` —
  refused, not ignored.
- A filter on a permission-gated column is refused with 403 rather than
  returning zero rows, because zero rows reads as "no such data" and that is a
  lie.

Chips render from `appliedFilters` in the response (§11), for the same reason
the sort chips do. Filters live in the header filter row on desktop and in a
filter sheet on mobile — same state object, same URL.

Fuzzy search (REQ-GRD-02) is separate from column filters: `q=`, a ranked match
across the columns declared `searchable`, `OR`-ed among themselves and `AND`-ed
with the filters. In server mode it is one ranked `ILIKE`-based predicate; the
grid never sends a regex.

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
position 3 of 7", "Status width 240 pixels". A silent reorder is invisible to a
screen reader, and the pointer interaction is unusable for exactly the user
REQ-UI-11 exists for. Widths clamp to `min`/`max`; a pinned column cannot leave
its pin group; a `locked` column cannot be hidden.

## 6. Preferences: what persists, where, and which source wins

**Persisted** per user per `gridKey`: column visibility, column order, column
widths, pinning, the sort list, per-column filter values, density, page size.

**Not persisted**, deliberately: the fuzzy query, the selection, the page
number. A user returning to a grid that silently reapplied last week's search
sees an empty table and reports a data-loss bug. The page number is transient
for the same reason.

```sql
user_grid_prefs (A07)                       -- tenantScoped: true, RLS forced
  tenant_id uuid not null references tenants(id),
  user_id   uuid not null,
  grid_key  text not null,
  prefs     jsonb not null,                 -- versioned payload, { v: 1, ... }
  primary key (tenant_id, user_id, grid_key)
  -- entity-base minus `comment` (exempt, contracts/types/entity-base.md §6)
```

Read with `grid.prefs.read`, written with `grid.prefs.write` — own rows only;
there is no permission to read another user's layout. Writes are debounced
500 ms and applied optimistically, so dragging a column is not a request per
pixel. `prefs` carries a schema version; an unreadable or older payload is
discarded back to the definition default rather than migrated in place, and the
discard logs at `warn`. A column id no longer in the definition is dropped on
read — a removed column must not brick a user's grid.

**Precedence, highest first (REQ-GRD-08, REQ-GRD-15, REQ-SET-11):**

1. **URL** — `?page=…&pageSize=…&sort=…&filter[…]=…&q=…&cols=…&density=…`, the
   contract's `PageParams` plus the two view-only params A07 owns. A shared link
   reproduces the sender's view exactly.
2. **Profile** — the `user_grid_prefs` row for this user and `gridKey`.
3. **Tenant grid defaults** — density and page size set on the tenant settings
   panel (REQ-SET-04). A tenant that runs on 14-inch laptops sets `compact`
   once instead of asking 200 people to.
4. **Definition default** — `defaultSort`, `visibility`, `width.initial`, and
   the size class's initial page size.

The grid's preference panel shows the effective value and its source — "Page
size 50, from your tenant's default" — because an unexplained default is a
support ticket (REQ-SET-11).

A visit carrying URL state **does not overwrite the profile**. The toolbar shows
`Viewing a shared view · Save as my default · Reset`, and only `Save` writes.
REQ-GRD-15 says the URL wins *for that visit*; a link that rewrites the
recipient's saved layout is a side effect nobody asked for. The URL is written
with `history.replaceState`, and `cols` is a compact ordered id list.

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

These are read only as the default for a declared class. Nothing imports a
single global page-size list — the shape REQ-GRD-10 forbids, because one list
means every grid is tuned for whichever table someone had in mind last.

## 8. The `all` guard (REQ-GRD-11)

`pageSize=all` is offered on every grid and guarded on every grid. The server
counts first, so the guard costs no extra query beyond the count the footer
already needs.

| Row count | Behaviour |
|---|---|
| `≤ serverThreshold` (5 000) | Rendered directly, virtualised rows |
| `> serverThreshold`, `≤ allRowCeiling` | Streamed in 1 000-row chunks with progress and a cancel button, `truncated: true` in the envelope; rows appear as they land |
| `> allRowCeiling` (50 000) | Refused with `grid.row_ceiling_exceeded` (422), whose `detail` parameters carry the count and the ceiling |

The refusal is a message, not a spinner and not a truncation. The `detail` is
rendered from the error's catalogue key with those two parameters:

```
errors.grid.rowCeilingExceeded =
  "This view has {rows, number} rows. {ceiling, number} is the most this page
   can load at once. Narrow the filters, or export the full result instead."
```

Its shape is fixed: **the actual number**, **the ceiling**, **what to do
instead**. "Too many rows" tells the user nothing they did not know, and a
truncated `all` is a wrong answer presented as a complete one. The export clause
appears only if the caller holds `grid.export.run`. The selected size falls back
to the previous value, so the grid stays usable. `total` is `null` while a
streamed `all` is in flight — the envelope never reports a total it did not
count.

## 9. Selection, bulk actions, export (REQ-GRD-13)

Selection is per row plus a header checkbox that selects the **loaded page**,
with a distinct `Select all {n} matching` affordance that carries the filter
rather than a list of ids. Selection survives pagination and clears on a filter
change, because a filter change means the selected set is no longer what the
user was looking at.

```ts
export type BulkAction<TRow> = {
  id: string;                         // "tenancy.member.remove"
  i18nKey: string;
  permission: PermissionString;       // hidden without it, checked server-side
  confirm: "none" | "dialog" | "typed";
  requiresComment: boolean;           // writes the entity envelope's `comment`
  maxSelection?: number;              // default 500
  execute: "per-row" | "batch";
};
```

The client hides an action the caller lacks; the server checks it again per row,
because a selection is a list of ids and a list of ids is client input. A
partial failure returns per-row results and marks the failed rows in place — a
bulk action reporting "3 of 40 failed" without saying which three is unusable.
Each affected row gets its own audit event, and `requiresComment` fills the
envelope `comment` that the event copies (`contracts/openapi/conventions.md` §5).

Export needs `grid.export.run` — step-up by rule
(`contracts/types/rbac.md` §6), 900 s (`spec/auth.md` §6) — and emits
`<domain>.<resource>.export` with row count, the applied filters and the column
set (`contracts/events/audit-event.md` §2). It runs server-side from the same
query the grid just ran, never from the rows the client holds, so a
permission-gated column cannot be exported by a client that had it in memory.
CSV is UTF-8 with a BOM and `\r\n` for Excel; NDJSON is the machine format.

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

Filter and sort state is **shared, not parallel** — one store, one set of URL
parameters, one `user_grid_prefs` row. A filter set on the phone is there on the
desktop after login. Controls differ: search stays at the top, filters and sort
open in bottom sheets carrying the same precedence chips, pagination becomes a
footer at 44 px minimum touch size (REQ-UI-07). Column order and visibility
carry over as the `meta` order; widths are meaningless on a card and are
ignored, not lost.

## 11. One client contract in both modes (REQ-GRD-12)

Both modes produce and consume the contract's `PageParams` and `Page<T>`
(`contracts/types/pagination.md` §2, §6). The grid holds no second shape.

```ts
export type GridSource<TRow> =
  (params: PageParams) => Promise<Page<TRow>>;

// Page<T> = { items, page, pageSize, total | null, nextCursor | null,
//             appliedSort, appliedFilters, truncated }
```

- `mode: "server"` — the params are serialised to the query string and sent.
- `mode: "client"` — the same params are resolved in memory by comparators and
  predicates generated from the column specs, with the contract's null ordering
  (`NULLS LAST` ascending, `NULLS FIRST` descending) so the two modes agree.
- `mode: "auto"` — server if the first response's `total` exceeds
  `serverThreshold`, client otherwise, decided once.

**No component reads `mode`.** A component that branches on it is a defect: the
mode changes who executes the query, never what the grid renders. The toolbar,
the chips and the footer render from the response's `appliedSort`,
`appliedFilters` and `total`, which is what makes "the server ignored a filter"
visible rather than silent.

This identical contract is what lets A07 finish while A11's endpoints do not
exist yet — the grid consumes `pagination` plus fixtures, never `api-kit`. The
interface test is the contract's
(`packages/contracts/tests/pagination.interface.test.ts`), and A07 and A11 both
run it (REQ-CTR-10).

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Search / chooser / pagination position | Top-left / top-right / bottom, fixed slots | REQ-GRD-02, 03, 09 are positional | No |
| Toolbar configurability | Slots may be filled, not moved | A movable requirement is not a requirement | No |
| Sort clause limit | 4, from the contract | Beyond that server plans degrade silently | No |
| Persisted keys | visibility, order, width, pin, sort, filters, density, page size | REQ-GRD-08 | No |
| Not persisted | fuzzy query, selection, page number | A reapplied old search reads as data loss | No |
| Preference precedence | URL > profile > definition default | REQ-GRD-08, REQ-GRD-15 | No |
| URL state overwriting the profile | Never — explicit "Save as my default" | A link must not rewrite the recipient's layout | No |
| Page sizes | Per size class, `small` and `large` | REQ-GRD-10 forbids a global constant | Yes, per grid |
| `serverThreshold` / `allRowCeiling` | 5 000 / 50 000 rows | Largest expected table is 100k (INTAKE.md) | Yes |
| `all` above the ceiling | Refused with counts and an alternative | REQ-GRD-11 — no truncation, no hang | No |
| Export source | Server-side, re-running the query, `grid.export.run` | Client rows may hold gated columns | No |
| Mobile rendering | Mandatory card spec per grid | REQ-GRD-14, REQ-UI-07 | No |

## How this is verified

- `pnpm test:unit` — `tests/unit/datagrid/**`: every column type maps to and
  from its URL form for every legal operator, and refuses the illegal ones;
  comparators match the contract's null ordering; precedence resolution for all
  eight URL/profile/default combinations; `prefs` version discard.
- `pnpm test:integration` — `tests/integration/datagrid/**` (REQ-TST-08): the
  preference round-trip — set width, order, sort and filters, reload, new
  device, same result; a shared URL does not mutate the stored row; a dropped
  column id does not break the grid.
- `pnpm test:e2e` — `tests/e2e/grid/**` (Playwright over CDP, REQ-TST-02):
  keyboard reorder and resize with the `aria-live` announcement asserted;
  `Shift`-click multi-sort and chip reordering; `all` in each of the three row
  bands including the exact refusal text; a bulk action denied without
  permission; export triggering step-up.
- `pnpm test:visual` — `tests/visual/grid.spec.ts`: search left of chooser,
  pagination at the bottom, at 390/834/1440 in both themes; the card renderer at
  390; axe AA on toolbar, header row and filter sheet (REQ-TST-06); the grid
  page's surface budget (`spec/screenspace.md` §4).
- `pnpm test:audit` — export emits `<domain>.<resource>.export` with row count,
  column set and filter hash; a bulk action emits one event per affected row.
- `pnpm contracts:test --interface grid-api` —
  `packages/contracts/tests/pagination.interface.test.ts`: client mode and
  server mode return the same rows in the same order for every case, run by both
  A07 and A11 (REQ-CTR-10). Plus `packages/contracts/tests/grid-def.spec.ts`:
  every definition has a `mobile` spec, a unique `gridKey`, and column ids that
  satisfy `ColumnNameSchema`.

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
