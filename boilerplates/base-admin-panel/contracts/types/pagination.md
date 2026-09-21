# `pagination` — page, cursor, sort, filter, envelope

**Published by:** A02. The grammar is the one A07's grid serialises and A11's
API parses — one grammar, two consumers.
**Requirements:** REQ-API-11, REQ-GRD-04, REQ-GRD-05, REQ-GRD-09, REQ-GRD-10,
REQ-GRD-11, REQ-GRD-12, REQ-GRD-15, REQ-ENT-05, REQ-CTR-10, REQ-TIM-03.
**Consumed by:** A07, A11, A04, A10, A13, A16, A23.

The grid renders 40 rows client-side and 12,000 rows server-side from the same
`GridDef`. That is only true if both modes speak this file exactly (REQ-GRD-12).

---

## 1. Two modes, one wire shape

| | Client mode | Server mode |
|---|---|---|
| Selected by | declared row count under `serverThreshold` | at or over `serverThreshold` |
| Sort, filter, paginate run | in the TanStack row model | in SQL |
| Params | applied locally, still written to the URL (REQ-GRD-15) | serialised to the query string |
| Response | `Page<T>` built locally | `Page<T>` from the API |

The consumer never branches on the mode. Both modes produce and consume
`PageParams` and `Page<T>`; client mode resolves them against rows already in
memory. A component that reads `mode` is a defect.

## 2. Query parameters

| Param | Shape | Default | Notes |
|-------|-------|---------|-------|
| `page` | integer ≥ 1 | `1` | Page mode. Mutually exclusive with `cursor`. |
| `pageSize` | integer 1…500, or `all` | `50` | Ranges are per grid (REQ-GRD-10). `all` is guarded (§6). |
| `cursor` | opaque base64url string | — | Cursor mode (§5). Mutually exclusive with `page`. |
| `sort` | sort expression | per grid | §3. |
| `filter[<column>]` | filter expression | — | §4. Repeatable, one key per column. |
| `q` | string, max 200 | — | Fuzzy search across the grid's declared searchable columns (REQ-GRD-02). |
| `includeDeleted` | `true` \| `false` | `false` | Lifts the `deleted_at IS NULL` predicate. Requires `global.deleted-record.read` (REQ-ENT-05, `contracts/types/entity-base.md` §5). Without the permission the param is rejected, not ignored. |

```ts
// packages/contracts/pagination.ts
import { z } from "zod";

export const PAGE_SIZE_MAX = 500;

export const PageParamsSchema = z
  .object({
    page: z.coerce.number().int().min(1).default(1),
    pageSize: z
      .union([z.coerce.number().int().min(1).max(PAGE_SIZE_MAX), z.literal("all")])
      .default(50),
    cursor: z.string().regex(/^[A-Za-z0-9_-]{16,512}$/).optional(),
    sort: z.string().max(200).optional(),
    q: z.string().max(200).optional(),
    filter: z.record(z.string(), z.string().max(400)).optional(),
    includeDeleted: z.coerce.boolean().default(false),
  })
  .strict()
  .refine((p) => !(p.cursor && p.page > 1), {
    message: "page and cursor are mutually exclusive",
  });

export type PageParams = z.infer<typeof PageParamsSchema>;
```

A param outside this object fails with `common.validation_failed`
(`contracts/types/errors.md` §3). `.strict()` is the guard: a dropped filter
shows the caller more rows than it asked to see.

## 3. Sort grammar (REQ-GRD-04)

```
sort      := clause ("," clause){0,3}
clause    := <column> ":" ("asc" | "desc")
```

Left to right is highest to lowest precedence. `sort=status:asc,createdAt:desc`
sorts by status, then by newest within each status. The grid renders the
precedence ordinal in the header from the position in this list — the indicator
is the parse, not a second piece of state.

- Maximum four clauses; a fifth is `common.validation_failed`.
- A column not declared `sortable` in the `GridDef` is rejected with
  `grid.sort_column_unknown`. Server mode never interpolates a column name into
  SQL — the name is resolved against the declared column list first.
- Every sort is stabilised by appending `id:asc` server-side. Without it, keyset
  pagination over a non-unique sort key skips and repeats rows.
- Null ordering is `NULLS LAST` for `asc`, `NULLS FIRST` for `desc`, in both
  modes. The §8 interface test asserts the comparator matches the SQL.

```ts
export const ColumnNameSchema = z.string().regex(/^[a-zA-Z][a-zA-Z0-9_]{0,62}$/);
export const SortSpecSchema = z
  .array(z.object({ column: ColumnNameSchema, direction: z.enum(["asc", "desc"]) }))
  .max(4);

export const parseSort = (raw: string | undefined) =>
  SortSpecSchema.parse(
    (raw ?? "").split(",").filter(Boolean).map((c) => {
      const [column, direction = "asc"] = c.split(":");
      return { column, direction };
    }),
  );
export const serialiseSort = (s: z.infer<typeof SortSpecSchema>) =>
  s.map((c) => `${c.column}:${c.direction}`).join(",");
```

## 4. Filter grammar (REQ-GRD-05)

```
filter[<column>] := <op> ":" <value>
value            := scalar | scalar ("," scalar)*     // for list and range ops
```

The operator set is type-aware. The column's declared type decides which
operators are legal; a mismatch is `grid.filter_op_unsupported`.

| Column type | Operators | Example |
|-------------|-----------|---------|
| `text` | `eq`, `neq`, `contains`, `starts`, `ends`, `empty` | `filter[name]=contains:nordlo` |
| `enum` | `eq`, `in`, `nin` | `filter[status]=in:active,suspended` |
| `number` | `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `between` | `filter[seats]=between:10,50` |
| `date` | `on`, `before`, `after`, `between`, `empty` | `filter[createdAt]=between:2026-01-01T00:00:00Z,2026-02-01T00:00:00Z` |
| `boolean` | `is` | `filter[mfaRequired]=is:true` |

Encoding rules, because a filter that parses differently on the two sides is a
data leak in one direction and a missing row in the other:

- Values are percent-encoded. A literal comma inside a scalar is `%2C`; the
  split happens after decoding the pair and before decoding the scalars.
- `between` takes exactly two scalars, inclusive on both ends. `empty` takes no
  value: `filter[note]=empty:`.
- **Date values are RFC 3339 with a `Z` offset on the wire, always** — never a
  local date, never a bare `YYYY-MM-DD`. Storage is UTC `timestamptz`
  (REQ-TIM-03). The grid's date-range control resolves the operator's timezone
  through `packages/contracts/time` and sends UTC instants (REQ-TIM-04). A
  `YYYY-MM-DD` value is rejected, not guessed, because "2026-01-01" means two
  different instants in `Europe/Stockholm` and UTC.
- `q` is not a filter. It is the grid's fuzzy search and it is applied as an
  `OR` across declared searchable columns, after the filters are applied as
  `AND`.

```ts
export const FilterOpSchema = z.enum([
  "eq", "neq", "contains", "starts", "ends", "empty",
  "in", "nin", "gt", "gte", "lt", "lte", "between",
  "on", "before", "after", "is",
]);

export const FilterSpecSchema = z.array(
  z.object({ column: ColumnNameSchema, op: FilterOpSchema, values: z.array(z.string()).max(50) }),
);
```

## 5. Cursor mode

Page mode answers "page 7 of 240" and the grid needs that (REQ-GRD-09). Cursor
mode answers "the next 500 rows, consistently" and an export or an API crawl
needs that. Both are in this contract; a route declares which it serves.

- The cursor is opaque base64url over `{ sortValues, id }` — a keyset, not an
  offset. It carries no tenant: a cursor from another tenant resolves to zero
  rows because RLS filters first (`contracts/db/rls-contract.md` §4).
- A cursor is valid only for the same `sort`, `filter`, `q` and `includeDeleted`
  it was issued under. A mismatch is `common.validation_failed`, never a
  silently different result set.
- `total` is `null` in cursor mode. Counting the whole set on every page is the
  cost cursor mode exists to avoid.

## 6. Response envelope

```ts
export const PageSchema = <T extends z.ZodTypeAny>(item: T) =>
  z.object({
    items: z.array(item),
    page: z.number().int().min(1),
    pageSize: z.union([z.number().int().min(1), z.literal("all")]),
    /** Total matching rows. Null in cursor mode, and when `all` streamed. */
    total: z.number().int().min(0).nullable(),
    /** Present in cursor mode. Null on the last page. */
    nextCursor: z.string().nullable(),
    /** Echo of what the server actually applied. The grid renders from this. */
    appliedSort: SortSpecSchema,
    appliedFilters: FilterSpecSchema,
    /** True when a guard cut the result short (REQ-GRD-11). */
    truncated: z.boolean().default(false),
  });
```

`appliedSort` and `appliedFilters` are the echo that makes the two modes
verifiable: the grid renders its chips and precedence ordinals from the
response, not from its own request. A server that quietly ignored a filter is
then visible in the UI instead of silently showing unfiltered rows.

`pageSize: "all"` is guarded (REQ-GRD-10, REQ-GRD-11): the server counts first,
and above the grid's declared `allRowCeiling` it either streams in chunks with
`truncated: true`, or refuses with `grid.row_ceiling_exceeded` whose `detail`
parameters carry the count and the ceiling. It never hangs the tab.

## 7. Timestamps

Every timestamp in a filter value, an item or a cursor is UTC `timestamptz` in
storage and RFC 3339 `Z` on the wire. Display formatting happens only at the
edge, only in `packages/contracts/time` — `Europe/Stockholm`,
`YYYY-MM-DD HH:mm:ss` (REQ-TIM-01, REQ-TIM-02, REQ-TIM-04).

## 8. The interface test both sides run (REQ-CTR-10)

`packages/contracts/tests/pagination.interface.test.ts`. It belongs to the
contract, not to A07 or A11, and both run it (`pnpm contracts:test --interface
grid-api`). When it fails the contract is ambiguous, and the fix is a clarifying
CCR — not a patch on whichever side was looked at first.

```ts
import { describe, expect, it } from "vitest";
import { PageParamsSchema, parseSort, serialiseSort } from "@app/contracts";
import { applyClientMode } from "@app/datagrid/row-model";      // A07's side
import { toSqlPlan } from "@app/api-kit/list-plan";             // A11's side
import { gridRows } from "@app/fixtures/contracts/grid-rows.fixture";

const CASES = [
  "?page=2&pageSize=20&sort=status:asc,createdAt:desc",
  "?pageSize=50&filter[status]=in:active,suspended&filter[seats]=between:10,50",
  "?filter[createdAt]=between:2026-01-01T00:00:00Z,2026-02-01T00:00:00Z&q=nordlo",
];

describe("pagination grammar", () => {
  it.each(CASES)("both modes return the same rows and order for %s", (qs) => {
    const params = PageParamsSchema.parse(Object.fromEntries(new URLSearchParams(qs)));
    const client = applyClientMode(gridRows, params);
    const server = toSqlPlan(gridRows, params).execute();
    expect(server.items.map((r) => r.id)).toEqual(client.items.map((r) => r.id));
    expect(server.total).toBe(client.total);
    expect(server.appliedFilters).toEqual(client.appliedFilters);
    expect(serialiseSort(parseSort(params.sort))).toBe(params.sort ?? "");
  });

  it("rejects a bare date, a fifth sort clause, and page+cursor together", () => {
    expect(() => PageParamsSchema.parse({ filter: { createdAt: "on:2026-01-01" } })).toThrow();
    expect(() => parseSort("a:asc,b:asc,c:asc,d:asc,e:asc")).toThrow();
    expect(() => PageParamsSchema.parse({ page: "2", cursor: "Y3Vyc29yLXZhbHVlLTAwMQ" })).toThrow();
  });
});
```

## 9. Change rules after the G3 freeze

**Additive**
- A new filter operator, added to §4 with the column types that accept it.
- A new optional `PageParams` field, defaulted so an existing caller's meaning
  does not change.
- A new field on the `Page` envelope.
- A route gaining cursor mode alongside page mode.

**Breaking — needs orchestrator arbitration (REQ-CTR-03)**
- Changing a default (`pageSize`, `includeDeleted`, null ordering): every
  existing caller's result set changes with no change on their side.
- Changing an operator's meaning — `between` becoming exclusive is the textbook
  silent semantic change.
- Raising `PAGE_SIZE_MAX`: additive for callers, breaking for every server that
  sized its query plan against it. It goes through a CCR.
- Accepting a bare `YYYY-MM-DD` value, or removing `appliedSort` /
  `appliedFilters` from the envelope.
