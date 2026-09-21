# API Surface, Documentation & Keys

One route declaration per operation, from which the runtime validation, the
OpenAPI document, the permission check, the rate limit and the audit intent all
derive. Owned by **A11** (`api-openapi`): `packages/api-kit/**`, the route kit
and the `/api/v1` tree under `apps/<app>/app/api/**`,
`apps/<app>/app/(app)/api-docs/**`, and the tables `api_keys`,
`api_key_scopes`. A11 publishes `openapi-document`, `api-key` and
`route-contract`; it consumes `errors`, `rbac`, `session` and `pagination`. Each
domain owns its own subtree under `/api/v1` and declares its own operations;
A11 owns the kit they declare with and assembles the document.

## Requirements covered

REQ-API-01 … REQ-API-11, REQ-SEC-06, REQ-SEC-07, REQ-SEC-10, REQ-SEC-11,
REQ-AUT-07, REQ-RBA-02, REQ-ENT-05, REQ-AUD-01, REQ-AUD-04, REQ-CTR-03,
REQ-CTR-08, REQ-I18N-01.

## 1. Zod is the source; OpenAPI is output (REQ-API-01)

The schema that validates the request at runtime is the schema the document is
generated from. There is no second description of the API anywhere in the
repository, and the document is never edited by hand.

```
packages/<domain>/contract.declaration.ts   Zod in, Zod out, per operation
        │ A02 assembles at the freeze
        ▼
packages/contracts/openapi/openapi.json     generated, committed, 3.1
        │
        ├──▶ apps/<app>/app/(app)/api-docs   in-app reference (§7)
        └──▶ packages/api-kit/client         typed client, generated at freeze time
```

`pnpm generate:openapi` regenerates the document; CI runs it and fails on a
non-empty `git diff`. A committed document that the generator would not produce
is a hand-edit, and REQ-API-01 says never.

The generated client exists **before any endpoint is implemented**, which is
what lets A07 and A12 build against it in the same wave
(`contracts/README.md` §7).

## 2. The route kit — one place per operation

```ts
// apps/<app>/app/api/v1/devices/route.ts — owned by the device domain
export const GET = defineRoute({
  operationId: "device.list",              // unique; the OpenAPI operationId
  summaryKey: "api.device.list.summary",   // i18n, never a literal
  permission: "device.device.list",        // REQ-RBA-02 — required, see below
  stepUp: null,                            // or a window in seconds (spec/auth.md §6)
  request: { query: PageQuerySchema.extend({ f: DeviceFilterSchema }) },
  responses: { 200: PageSchema(DeviceSchema), 400: Problem, 403: Problem },
  audit: { read: "list", targetType: "device" },   // REQ-AUD-02
  rateLimit: { key: "actor+ip", limit: 120, window: 60 },
  handler: async ({ query, actor, db }) => db.devices.list(query),
});
```

The kit refuses to build an operation that is missing a decision:

| Field | Rule |
|---|---|
| `permission` | Required. `public: { reason }` is the only alternative and it is reviewed at CCR time |
| `audit` | Required. `audit: { none: { reason } }` is the only alternative |
| `request` | Every schema is `.strict()`; unknown fields are `400`, not ignored |
| `responses` | Must declare every status the handler can produce, including its problem types |
| `stepUp` | Required whenever `operationId` matches a step-up action class (`spec/auth.md` §6) |
| `rateLimit` | Required on auth, key, reset and export operations (REQ-SEC-11) |

The handler receives the resolved `actor`, the tenant-scoped `db` and the parsed
input. It cannot reach an unscoped client, cannot set an actor column
(`spec/entity-model.md` §4) and cannot read a tenant id from the request
(REQ-RBA-03). CSRF origin + double-submit checks run in the kit for every
state-changing method and for Server Actions (REQ-SEC-10).

One `defineRoute` per exported method per file. The kit is also what makes the
audit intent impossible to forget: the emission happens in the kit, after the
handler resolves, with the operation's declared `action` and `targetType`.

## 3. The bidirectional check (REQ-API-03)

`pnpm check:openapi` builds two sets and fails on a non-empty difference in
either direction:

```
routes  := every exported HTTP method in apps/<app>/app/api/**/route.ts
ops     := every path+method in packages/contracts/openapi/openapi.json
routes \ ops  → "route without an operation"   (names the file)
ops \ routes  → "operation without a route"    (names the operationId)
```

Plus: duplicate `operationId`, an `operationId` whose prefix is not the declaring
agent's domain, a `403` response on an operation with no `permission`, and a
declared problem type that is not in the error taxonomy. Each failure names the
owning agent, so a CI failure routes to a person without triage.

## 4. Errors: RFC 9457 and the code taxonomy (REQ-API-10)

Every non-2xx response is `application/problem+json`. No endpoint invents a
body.

```jsonc
{
  "type": "/problems/rbac/permission-denied",   // dereferenceable, in-app doc
  "title": "Du saknar behörighet",              // localised (spec/i18n.md §5)
  "status": 403,
  "detail": "device.device.export krävs för den här åtgärden.",
  "instance": "/requests/9f2a4c1e-7b33-4c10-9a55-1d0c2f4e8a71",
  "code": "rbac.permission_denied",             // stable, never localised
  "requiredPermission": "device.device.export", // 403 to an authenticated caller
  "errors": [ { "path": "filters.createdAt", "code": "common.invalid_format" } ]
}
```

**Taxonomy shape**: `code` is `<domain>.<condition>` with a `snake_case`
condition — `common.validation_failed`, `tenancy.cross_tenant`,
`rbac.permission_denied`. `type` is the same code rendered as a URI path with
kebab-case segments — `/problems/rbac/permission-denied` — which is why
`spec/auth.md` §6 can cite the problem type `step-up-required` while the code is
`auth.step_up_required`. The slug is for humans and URLs; the code is for
machines and never changes spelling.

| Class | Codes (shape) | Status |
|---|---|---|
| Validation | `common.validation_failed`, `common.invalid_format` | 400 |
| Authentication | `auth.unauthenticated`, `auth.mfa_required`, `auth.step_up_required` | 401 / 403 |
| Authorisation | `rbac.permission_denied`, `rbac.grant_exceeds_ceiling` | 403 |
| Tenancy | `tenancy.cross_tenant` | **404**, never 403 |
| State | `common.conflict`, `common.precondition_failed` | 409 / 412 |
| Rate limit | `common.rate_limited` + `Retry-After` | 429 |
| Server | `common.internal_error` | 500 |

`code` values are contract members: additive only, never re-spelled, and a
changed meaning takes a new code (REQ-CTR-03). `instance` carries the
`correlation_id` that is on the audit row and every log line, so a user's
screenshot leads straight to the trail. A 500 never includes a stack, a query or
an upstream body — `detail` is a fixed sentence and the specifics are in the log
(REQ-AUD-05).

## 5. Pagination, filtering and sorting (REQ-API-11)

One grammar, one type, shared with the grid. `Page<T>` in
`contracts/types/pagination.md` **is** the grid's `GridPage<T>`; there is not an
API shape and a grid shape that have to be kept in step
(`spec/datagrid.md` §11).

```
GET /api/v1/devices
  ?page=2&size=50                     # offset paging; size from the grid's class
  &sort=name,-updatedAt               # precedence is left to right
  &f.status=in:active,paused          # f.<field>=<op>:<value>
  &f.createdAt=gte:2026-09-01
  &q=fw-01                            # fuzzy, over the fuzzy-declared columns
  &includeDeleted=false               # REQ-ENT-05, permission-gated
  &cursor=…                           # instead of page, where declared

→ { "rows": [ … ], "total": 1340, "page": 2, "size": 50, "truncated": false }
```

- Operators: `eq`, `ne`, `in`, `nin`, `gte`, `lte`, `gt`, `lt`, `contains`,
  `startsWith`, `isnull`. An operator a field's type does not support is `400`,
  not silently ignored.
- Offset paging is the default because grids show page numbers and a total.
  Cursor paging is declared per operation for large or streaming reads, where
  `OFFSET 200000` is a table scan.
- `total` is exact below 100 000 rows and an estimate from
  `pg_class.reltuples` above it, with `"totalIsEstimate": true` in the envelope.
  A count that takes four seconds is a worse answer than an honest estimate.
- Sorting and filtering are only accepted on fields the operation declares
  sortable or filterable; anything else is `400`. An unindexed sort is a denial
  of service with a friendly URL.

## 6. Versioning (REQ-API-09)

Everything is under `/api/v1`. There is no unversioned path and no `latest`
alias — an alias moves under a client that pinned nothing.

A new version is minted only by a breaking CCR that the orchestrator has
arbitrated (REQ-CTR-09). The rule:

- Additive change → `/api/v1`, minor contract bump, no new version.
- Breaking change → `/api/v2`, and **both are served** for the deprecation
  window declared in the CCR, minimum 180 days.
- `/api/v2` exposes the **whole** surface, not only the changed operations, so a
  client pins one version for everything. Unchanged operations are re-exported
  from the v1 handlers; they are not copied, because two copies of a handler
  diverge.
- Superseded v1 operations answer with `Deprecation` and `Sunset` headers and a
  `Link` to the v2 operation, and the OpenAPI operation carries
  `deprecated: true` with the removal version in its description.
- Removal happens after the window, as its own change, and it is the only
  removal the breaking-change detector accepts (REQ-CTR-07).

## 7. Interactive documentation (REQ-API-02)

Served at `/(app)/api-docs`, behind the session, from a self-hosted Scalar
bundle — no CDN, no remote font, no telemetry (REQ-SUP-06, REQ-SUP-07).

The document served to a caller is **filtered by that caller's permissions**:

- An operation whose `permission` the session does not hold is removed from the
  served document, and the footer states `12 operations hidden — you do not hold
  the permission`. Hidden without a count reads as a missing feature.
- Global-tier operations are absent entirely from a tenant user's document, so
  the `global.*` surface is not a map for someone who cannot use it.
- Try-it-out executes against the live API with the caller's own session and the
  CSRF token, never with an API key, so a doc request is a real request with a
  real audit row.
- Each problem `type` URI resolves to a page in the same section explaining the
  code, its status and the usual cause.

## 8. API keys (REQ-API-04 … REQ-API-08)

Two kinds. The difference is where the permissions come from, and it matters.

| | **User key** (REQ-API-04) | **Service key** (REQ-API-05) |
|---|---|---|
| Created by | The user, for themselves | An admin, with `apikey.service-key.create` |
| Permissions | The **intersection** of the requested scopes and the owner's *current* permissions, recomputed per request | An explicitly chosen set, frozen at mint |
| Ceiling | Can never exceed the owner. A role revoked at 09:00 narrows the key at 09:00 | Cannot exceed the minting admin's own permissions; `global.*` only from a `superadmin` with step-up |
| Owner of record | The user | A named user, mandatory, and transferable by an audited action |
| On owner deactivation | Revoked automatically | Kept, and the owner of record must be reassigned within 30 days or it is revoked |
| Scope change | Requested scopes are editable | Not editable — mint a new key (`api_key_scopes` is immutable) |

Recomputing a user key's permissions per request is the whole point of
REQ-API-04: a key that froze its permissions at mint time is a copy of yesterday's
authority, and a deprovisioned employee's key would keep working.

**Material and storage (REQ-API-06, REQ-SEC-07).**

```
token   pk_live_7Kq2Xb9t_<32 bytes, base62>      # prefix is not secret
stored  kind, prefix ("pk_live_7Kq2Xb9t"), sha256(secret), owner, scopes, …
```

- Shown **exactly once**, on the creation screen, with copy and download,
  `Cache-Control: no-store`. Not re-derivable, not recoverable, not emailed.
- SHA-256 of a 256-bit random secret is the stored form — no Argon2id, because
  the input is high-entropy and a key is verified on every request (REQ-SEC-07).
- The prefix identifies a key in a log, a UI list and an audit row without ever
  revealing material.

**Lifecycle controls (REQ-API-07).**

| Control | Rule |
|---|---|
| Expiry | **Mandatory.** Maximum 365 days, global ceiling lowerable per tenant. No "never" option exists |
| IP allowlist | Optional CIDR list, evaluated against the proxy-normalised client IP; a non-matching source is `403` with `apikey.ip_not_allowed` and an audit row |
| Last used | `last_used_at`, written at most once per 60 s per key, so a hot key is not a write per request |
| Revocation | Immediate. The key row is read from Postgres per request, never cached, so revocation takes effect on the next call |
| Rotation | Mint the replacement, both valid for an overlap the creator sets (default 7 days), then revoke |
| Rate limit | Per key, independent of the owner's session limits (REQ-SEC-11) |
| Step-up | 300 s to mint, rotate or change scopes (`spec/auth.md` §6) |

**Lifecycle audit (REQ-API-08)**: `apikey.key.mint`, `apikey.key.first_use`,
`apikey.key.rotate`, `apikey.key.revoke`, `apikey.key.expire`. `first_use` is a
distinct event because the gap between minting and first use is the signal that
a key leaked before it was ever deployed. `expire` is emitted by the expiry job,
not lazily on the next attempted use — a key nobody tries again still expires on
the record. Individual *uses* are not separate events; they are reads, and reads
aggregate (`spec/observability.md` §2).

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Schema source | Zod, OpenAPI 3.1 generated, `git diff` asserted | REQ-API-01 | No |
| Operation declaration | One `defineRoute` per method, in the domain's own file | REQ-CTR-04; no shared route table | No |
| Missing `permission` or `audit` | Build failure; only an explicit reasoned opt-out | A forgotten check is the default failure | No |
| Unknown request fields | `400`, never ignored | Silent ignoring hides client bugs | No |
| Error envelope | RFC 9457 problem+json, always | REQ-API-10 | No |
| Code / type spelling | `domain.snake_case` code, kebab URI slug | Machines read one, humans the other | No |
| Cross-tenant error | `404` with `tenancy.cross_tenant` | A 403 confirms existence | No |
| 403 body | Names the required permission to an authenticated caller | The permission list is already in the contract | No |
| Page envelope | `Page<T>` = the grid's `GridPage<T>` | One type cannot drift from itself | No |
| Default paging | Offset; cursor declared per operation | Grids need totals; big reads need cursors | Yes |
| `total` above 100k rows | `reltuples` estimate, flagged | A four-second count is a worse answer | Yes |
| Sort/filter surface | Only declared fields; anything else `400` | An unindexed sort is a DoS with a URL | No |
| Versioning | `/api/v1`, `/api/v2` only by arbitrated CCR, both served ≥ 180 days | REQ-API-09, REQ-CTR-09 | No |
| Docs viewer | Self-hosted Scalar, permission-filtered, try-it-out on the session | REQ-API-02, REQ-SUP-07 | Yes |
| User key permissions | Intersection with the owner's *current* permissions, per request | REQ-API-04 — never exceed, never lag | No |
| Service key permissions | Explicit, frozen; a change mints a new key | `api_key_scopes` is immutable | No |
| Key storage | `sha256(secret)` + non-secret prefix | REQ-SEC-07 | No |
| Key display | Once, `no-store`, never recoverable | REQ-API-06 | No |
| Expiry | Mandatory, max 365 days | REQ-API-07 — "never" is not an option | Yes, lower only |
| `last_used_at` write | At most once per 60 s | Otherwise a write per request | Yes |
| Key checks | Postgres read per request, uncached | Revocation must be immediate | No |

## How this is verified

- `pnpm check:openapi` — §3 both directions, duplicate and misprefixed
  `operationId`, undeclared problem types, and `git diff --exit-code` on the
  generated document (REQ-API-03).
- `pnpm test:unit` — `tests/unit/api/**`: the query grammar parses and
  round-trips every operator per field type; an unsupported operator is `400`;
  problem+json shape for each taxonomy class; token generation entropy and
  prefix extraction.
- `pnpm test:integration` — `tests/integration/api/**`: a user key's permissions
  narrow within one request of a role revocation; a service key cannot exceed
  its minting admin; scope edit on a service key is refused; IP allowlist
  accept and reject; `last_used_at` coalescing; revocation effective on the next
  call; the expiry job emits `apikey.key.expire`.
- `pnpm test:permissions` — every operation in the document called without its
  permission returns `403`, and with a cross-tenant target returns `404`
  (REQ-TST-05).
- `pnpm test:audit` — the five key lifecycle events fire with actor, prefix and
  scope set; `first_use` fires once; a doc try-it-out request produces a normal
  audit row.
- `pnpm test:e2e` — `tests/e2e/api-docs/**`: the docs page hides operations the
  session lacks and states the hidden count; a mint flow demands step-up, shows
  the key once, and shows only the prefix on reload.
- `pnpm test:contract` — `packages/contracts/tests/pagination.spec.ts`: the
  grid's serialised query is accepted by every listed operation's schema and
  `Page<T>` satisfies `GridPage<T>`, run by both A07 and A11 (REQ-CTR-10).
- `GET /api/v1/api/_selftest` — every route resolves to an operation, every
  operation to a route, every problem type to a taxonomy code (REQ-CTR-08).

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| May users mint their own keys | Yes, inheriting their own permissions |
| Maximum key lifetime | 365 days |
| Are service keys allowed to hold `global.*` | Only when minted by a `superadmin` with step-up |
| Default per-key rate limit | 120 requests / 60 s, per key |
| Cursor paging on which operations | Audit events and canonical event tables |
| Is `/api/v1` reachable from outside the reverse proxy | Yes, TLS only, same origin as the app |
| Docs viewer | Self-hosted Scalar at `/(app)/api-docs` |
