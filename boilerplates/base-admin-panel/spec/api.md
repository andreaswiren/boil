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
REQ-CTR-08, REQ-I18N-01, REQ-SET-03, REQ-SET-04.

## 1. Zod is the source; OpenAPI is output (REQ-API-01)

The schema that validates the request at runtime is the schema the document is
generated from. There is no second description of the API in the repository, and
the document is never edited by hand.

```bash
pnpm openapi:generate   # writes packages/api-kit/generated/openapi.json
pnpm openapi:validate   # OpenAPI 3.1 structural validation, zero unresolved $ref
pnpm openapi:parity     # route ↔ operation ↔ declaration, §3
git diff --exit-code packages/api-kit/generated/openapi.json   # CI: stale fails
```

The document is committed so the diff is reviewable and the generated client is
reproducible. A shape that cannot be expressed in Zod is a shape the runtime
cannot validate, and it does not ship.

```
packages/<domain>/contract.declaration.ts   Zod in, Zod out, per operation
        │ A02 assembles at the freeze
        ▼
packages/api-kit/generated/openapi.json     generated, committed, 3.1
        ├──▶ apps/<app>/app/(app)/api-docs   in-app reference (§7)
        └──▶ packages/api-kit/client         typed client, generated at freeze time
```

The generated client exists **before any endpoint is implemented**, which is
what lets A07 and A12 build in the same wave (`contracts/README.md` §7).

## 2. The route kit — one place per operation

Permission, schemas, audit intent, step-up and declared errors live in the route
declaration, not spread across a middleware, a decorator and a comment
(`contracts/openapi/conventions.md` §2).

```ts
// apps/<app>/app/api/v1/canonical/devices/route.ts — owned by A10's subtree
export const GET = defineRoute({
  id: "canonical.listDevices",             // <domain>.<lowerCamelCase>
  method: "GET",
  path: "/api/v1/canonical/devices",       // version, domain, plural kebab resource
  summaryKey: "api.canonical.listDevices", // i18n key, never a literal
  permission: "canonical.record.read",     // null = authenticated only
  stepUp: false,
  list: true,                              // accepts PageParams verbatim (REQ-API-11)
  input: { query: PageParamsSchema },
  output: PageSchema(DeviceSchema),
  audit: { action: "canonical.device.list", kind: "view" },
  errors: ["common.validation_failed", "rbac.permission_denied"],
  rateLimit: { key: "actor+ip", limit: 120, window: 60 },
}, handler);
```

What the kit does, in order, so a handler cannot skip a step: parse and validate
input → resolve the session and the tenant → check the permission and step-up
freshness → run the handler inside the transaction that `SET LOCAL`s the tenant
(`contracts/db/rls-contract.md` §3) → validate the output → emit the declared
audit event → serialise.

| Field | Rule |
|---|---|
| `permission` | Required. `null` means authenticated-only and is reviewed at CCR time; it is not a shortcut |
| `audit` | **Mandatory on every route, including reads.** There is no `audit: null`. `kind: "view"` aggregates, `kind: "read"` does not |
| `input` | Every schema is `.strict()`; an unknown field is `common.validation_failed`, not ignored |
| `output` | Validated on the way out. A response that fails its own schema becomes `common.internal` with the same `correlationId` |
| `stepUp` | Required `true` wherever the action class demands it (`spec/auth.md` §6); `true` by rule for every `global.*` permission |
| `errors` | The problem codes this operation may produce. An undeclared code at runtime fails the parity check |
| write bodies | Merge `EntityWriteEnvelopeSchema`, so `comment` is present on every write and copied into the row and the event |

A mandatory reason — impersonation entry, MFA disable, purge, account recovery —
is the route's **own** required `reason` field with a minimum length. `comment`
stays optional; a required field is not implemented by tightening a shared
optional one.

The handler receives the resolved actor, the tenant-scoped transaction and the
parsed input. It cannot reach an unscoped client, cannot set an actor column
(`spec/entity-model.md` §4) and cannot read a tenant id from the request
(REQ-RBA-03). CSRF origin + double-submit checks are emitted by the generator as
a required header on every write operation, not written per route (REQ-SEC-10).

## 3. The parity check (REQ-API-03)

`pnpm openapi:parity` walks three sources — the filesystem route tree, the
generated document, and every `contract.declaration.ts` — and all three must
agree. Both directions are fatal:

```
route without an operation   -> ORPHAN ROUTE  apps/<app>/app/api/v1/mail/outbox/route.ts
operation without a route    -> ORPHAN OP     mail.retryMessage
declared but unrouted        -> ORPHAN DECL   A12 declared mail.retryMessage, no route file
```

An undocumented route is how an endpoint ships without a permission check; an
operation with no route is how a generated client gets a method that 404s.

Plus, in the same pass: a duplicate `id`, an `id` whose domain segment differs
from its path segment or its declaring agent, a write operation without
`comment` in its body schema, a `403` response on an operation with
`permission: null`, and a runtime problem code the operation did not declare.
Each failure names the owning agent, so a CI failure routes without triage.
`GET /api/v1/api/_selftest` reports the parity counts at runtime (REQ-CTR-08).

## 4. Errors: RFC 9457 and the code taxonomy (REQ-API-10)

Every response with a status ≥ 400 is `application/problem+json`, including the
ones a framework would otherwise answer with HTML. The envelope is frozen in
`contracts/types/errors.md` §1 and it is `.strict()`.

```jsonc
{
  "type": "https://errors.panel.example.org/rbac.permission_denied",
  "title": "Åtgärden är inte tillåten",
  "status": 403,
  "detail": "Din roll saknar behörighet för den här åtgärden.",
  "instance": "/api/v1/canonical/devices/6b1f…",
  "code": "rbac.permission_denied",
  "correlationId": "9f2a4c1e-7b33-4c10-9a55-1d0c2f4e8a71"
}
```

Decisions that follow from that shape, and are easy to get wrong:

- **The body names no permission.** `rbac.permission_denied` is the same body
  for every denial. `.strict()` also makes an extra `requiredPermission`
  property impossible — which is deliberate: the envelope is validated on the
  way out, and that validation is what stops a stack trace, a SQL fragment or an
  internal hostname from riding along in a field nobody declared.
- **`instance` is the request path with no query string**, because a query
  string holds filter values and those are data.
- **`correlationId` is a first-class field**, not encoded into `instance`. It is
  the same id on the audit row, the log record and the console frame, so a
  user's screenshot leads straight to the trail.
- `title` and `detail` are rendered from catalogue keys for the request's
  `Accept-Language` — the caller may be a script, so the locale comes from the
  request rather than from a user profile (`spec/i18n.md` §4). `type`, `code`
  and `status` are never localised.
- `errors[]` carries `{ path, rule }` pairs. **Paths and rule names, never
  values** — echoing the rejected value is how a secret ends up in a client log.

**Taxonomy shape**: `code` is `<namespace>.<snake_code>`, two segments, the
namespace being the declaring domain or `common` (A02 only). `type` is the
registry URI `https://errors.<app-domain>/<code>`, which resolves to the in-app
docs page for that code — the only human-readable explanation of it (§7). One
status per code; a code never varies its status by caller.

| Namespace | Representative codes | Status |
|---|---|---|
| `common` | `validation_failed`, `unauthenticated`, `forbidden`, `not_found`, `conflict`, `rate_limited`, `internal`, `unavailable` | 400 … 503 |
| `auth` | `credentials_invalid`, `mfa_required`, `step_up_required`, `session_expired`, `locked_out` | 401 / 403 / 429 |
| `rbac` | `permission_denied`, `global_permission_not_grantable`, `role_version_stale` | 403 / 422 / 409 |
| `tenancy` | `cross_tenant` → **404, never 403**, `tenant_suspended`, `impersonation_expired` | 404 / 403 |
| `api` | `key_expired`, `key_revoked`, `key_ip_not_allowed`, `key_scope_exceeded`, `operation_removed` | 401 / 403 / 410 |
| `grid` | `row_ceiling_exceeded`, `sort_column_unknown`, `filter_op_unsupported` | 422 / 400 |
| `audit` | `legal_hold_active`, `chain_broken`, `console_disabled` | 409 / 500 / 503 |

`spec/auth.md` §6 cites the problem type `step-up-required`; the frozen code is
`auth.step_up_required` and the registry URI is built from the code. Codes are
contract members: additive only, immutable once shipped, and a changed meaning
takes a new code (REQ-CTR-03). A 500 never includes a stack, a query or an
upstream body — only `code` and `correlationId` are meaningful, and the
specifics are in the log (REQ-AUD-05).

## 5. Pagination, filtering and sorting (REQ-API-11)

One grammar, one envelope, shared with the grid. `PageParams` and `Page<T>` in
`contracts/types/pagination.md` are what the API parses and what the grid
serialises — there is no API shape and grid shape to keep in step
(`spec/datagrid.md` §11).

```
GET /api/v1/canonical/devices
  ?page=2&pageSize=50                 # page mode; sizes are per grid (REQ-GRD-10)
  &sort=status:asc,createdAt:desc     # max 4 clauses, left is highest precedence
  &filter[status]=in:active,suspended # filter[<column>]=<op>:<value>
  &filter[createdAt]=between:2026-01-01T00:00:00Z,2026-02-01T00:00:00Z
  &q=fw-01                            # fuzzy, over declared searchable columns
  &includeDeleted=false               # REQ-ENT-05, permission-gated
  &cursor=…                           # instead of page, where the route declares it

→ { "items": [...], "page": 2, "pageSize": 50, "total": 1340,
    "nextCursor": null, "appliedSort": [...], "appliedFilters": [...],
    "truncated": false }
```

- `PageParamsSchema` is `.strict()`. A dropped filter shows the caller more rows
  than it asked to see, so an unknown param is `common.validation_failed` rather
  than a silently wider result set.
- **`appliedSort` and `appliedFilters` are the echo that makes both modes
  verifiable.** The client renders its chips from the response, so a server that
  ignored a filter is visible in the UI instead of quietly returning unfiltered
  rows.
- Page mode answers "page 7 of 240", which the grid needs. Cursor mode answers
  "the next 500 rows, consistently", which an export or a crawl needs. A route
  declares which it serves; `total` is `null` in cursor mode, because counting
  the whole set on every page is the cost cursor mode exists to avoid. A cursor
  is a keyset over `{ sortValues, id }`, opaque, valid only for the `sort`,
  `filter`, `q` and `includeDeleted` it was issued under, and it carries no
  tenant — RLS filters first.
- Sorting and filtering are accepted only on columns the operation declares;
  anything else is `grid.sort_column_unknown` or `grid.filter_op_unsupported`.
  An unindexed sort is a denial of service with a friendly URL.
- Dates are RFC 3339 `Z` on the wire, always. A bare `YYYY-MM-DD` is rejected,
  not guessed (`spec/time.md` §3).

## 6. Versioning (REQ-API-09)

Everything is under `/api/v1`. There is no unversioned path, not even a health
check, and no `latest` alias — an alias moves under a client that pinned
nothing.

Inside `/api/v1` changes are additive only: a new operation, a new optional
request field, a new response field, a widened input enum, a narrowed output
enum. Nothing else.

A breaking change to a shipped operation is served at `/api/v2`, and only after
an arbitrated CCR whose default answer is the additive alternative
(REQ-CTR-09):

- `v1` and `v2` are both routed and both documented for the deprecation window
  stated in the CCR, minimum 180 days.
- The `v2` operation **keeps the same operation id** when it is the same
  operation; the document distinguishes them by path, so the generated client
  exposes `v1.canonical.listDevices` and `v2.canonical.listDevices`. Renaming
  the id would break every caller that is not migrating.
- The `v1` operation is marked `deprecated: true` with `x-removed-in` naming the
  version that removes it, and answers with `Deprecation` and `Sunset` headers.
- After the window, `v1` returns `410 api.operation_removed`. It is never
  removed from the document silently.

## 7. Interactive documentation (REQ-API-02)

Served at `/(app)/api-docs`, behind the session, from a self-hosted viewer
bundle — no CDN, no remote font, no telemetry (REQ-SUP-06, REQ-SUP-07).

The document rendered to a caller is **filtered to that caller's permissions**,
per request, from the one generated document:

- An operation whose `permission` the caller does not hold is **hidden, not
  greyed out**, and the footer states how many are hidden. Hidden without a
  count reads as a missing feature.
- The filter is presentation only. Hiding an operation is not access control;
  the route kit's check is (REQ-RBA-02).
- Operations requiring step-up are badged, so an operator knows before the
  `403 auth.step_up_required`.
- "Try it" uses the caller's own session and adds the CSRF header — never an API
  key — so a doc request is a real request with a real audit row. It refuses to
  send a write while `API_DOCS_ENABLED=false`.
- Summaries and descriptions in the document are i18n keys from the `api`
  namespace, resolved by the renderer (REQ-I18N-01).
- Every problem `type` URI resolves to a page in the same section explaining the
  code, its status and the usual cause. That page is the code's only
  human-readable definition, so the registry cannot drift from the docs.

## 8. API keys (REQ-API-04 … REQ-API-08)

Keys are managed from two settings panels, both contributed through the registry
(REQ-SET-08): the user's own keys on the **personal** scope (REQ-SET-03) and the
tenant's keys on the **tenant** scope (REQ-SET-04), with service keys on the
global scope. A panel shows prefixes, scopes, expiry and last-used — never
material.

Keys authenticate with one header, `X-API-Key`. Not `Authorization`, so a key is
never confused with a session cookie and a bearer token cannot be replayed into
the wrong scheme (`contracts/openapi/conventions.md` §8).

Two kinds. The difference is where the permissions come from, and it matters.

| | **User key** (REQ-API-04) | **Service key** (REQ-API-05) |
|---|---|---|
| Minted with | `api.key.mint-own`, step-up | `global.api-key.mint-service`, global tier, step-up |
| Permissions | `scopes ∩ the owner's live permission set`, recomputed **per request** | An explicitly chosen set, frozen at mint |
| Ceiling | Never exceeds the owner. A role revoked at 09:00 narrows the key at 09:00 | Never exceeds the minting operator; a `global.*` scope needs `superadmin` |
| Owner of record | The user | A named user, mandatory, transferable by an audited action |
| On owner deactivation | Revoked automatically | Kept; the owner of record must be reassigned within 30 days or it is revoked |
| Scope change | Requested scopes are editable; the effective set is still the intersection | Not editable — mint a new key, because `api_key_scopes` rows are immutable |
| Read / revoke | `api.key.read-own`, `api.key.revoke-own` | `api.key.read-any`, `api.key.revoke-any` |

Recomputing a user key's effective set per request is the whole point of
REQ-API-04: a key that froze its permissions at mint time is a copy of
yesterday's authority, and a deprovisioned employee's key would keep working. A
call outside the intersection is `403 api.key_scope_exceeded`.

**Material and storage (REQ-API-06, REQ-SEC-07).**

```
token   ak_live_7Kq2Xb9t.<32 bytes, base62>   # the prefix is not secret
stored  kind, prefix ("ak_live_7Kq2Xb9t"), sha256(secret), owner, scopes, expiry
```

- Shown **exactly once**, on the creation screen, with copy and download,
  `Cache-Control: no-store`. Not re-derivable, not recoverable, not emailed.
- SHA-256 of a 256-bit random secret is the stored form — not Argon2id, because
  the input is high-entropy and the key is verified on every request
  (REQ-SEC-07).
- The prefix identifies a key in a log line, a UI list and an audit row without
  ever revealing material. It is also on the secret-shaped-value detector's list,
  so a key that reaches a console frame drops the frame
  (`spec/observability.md` §4).

**Lifecycle controls (REQ-API-07).**

| Control | Rule |
|---|---|
| Expiry | **Mandatory.** Maximum 365 days, lowerable per tenant. No "never" option exists. Past expiry: `401 api.key_expired` |
| IP allowlist | Optional CIDR list against the proxy-normalised client IP; a non-matching source is `403 api.key_ip_not_allowed` plus an audit row |
| Last used | `last_used_at`, written at most once per 60 s per key, so a hot key is not a write per request |
| Revocation | Immediate — `401 api.key_revoked`. The key row is read from Postgres per request, never cached |
| Rotation | `api.key.rotate-own`: mint the replacement, both valid for an overlap the creator sets (default 7 days), then revoke |
| Rate limit | Per key, independent of the owner's session limits (REQ-SEC-11) |
| Step-up | 300 s to mint or rotate (`spec/auth.md` §6) |

**Lifecycle audit (REQ-API-08)**: `api.key.mint`, `api.key.first-use`,
`api.key.rotate`, `api.key.revoke`, `api.key.expire`
(`contracts/events/audit-event.md` §2). `first-use` is a distinct event because
the gap between minting and first use is the signal that a key leaked before it
was ever deployed. `expire` is emitted by the sweeper, not lazily on the next
attempted use — a key nobody tries again still expires on the record. Individual
*uses* are not separate events; they are reads, and reads aggregate
(`spec/observability.md` §2).

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Schema source | Zod, OpenAPI 3.1 generated, `git diff` asserted | REQ-API-01 | No |
| Operation declaration | One `defineRoute` per method, in the domain's own file | REQ-CTR-04; no shared route table | No |
| Missing `audit` | Build failure. There is no `audit: null`, including on reads | A forgotten emission is the default failure | No |
| Unknown request fields | `400`, never ignored | Silent ignoring hides client bugs | No |
| Error envelope | RFC 9457 problem+json, always | REQ-API-10 | No |
| Code shape | `<namespace>.<snake_code>`; `type` is `https://errors.<app-domain>/<code>` | One identifier, one dereferenceable URI | No |
| Cross-tenant error | `404` with `tenancy.cross_tenant` | A 403 confirms existence | No |
| 403 body | Names no permission; the envelope is `.strict()` | Output validation is what keeps internals out of a response | No |
| Page envelope | The contract's `Page<T>`, with `appliedSort`/`appliedFilters` echoed | A silently ignored filter must be visible | No |
| Default paging | Page mode; cursor declared per operation | Grids need totals; crawls need keysets | Yes |

| Sort/filter surface | Only declared fields; anything else `400` | An unindexed sort is a DoS with a URL | No |
| Versioning | `/api/v1`, `/api/v2` only by arbitrated CCR, both served ≥ 180 days | REQ-API-09, REQ-CTR-09 | No |
| Docs viewer | Self-hosted, permission-filtered, hidden not greyed, try-it on the session | REQ-API-02, REQ-SUP-07 | Yes |
| User key permissions | Intersection with the owner's *current* permissions, per request | REQ-API-04 — never exceed, never lag | No |
| Service key permissions | Explicit, frozen; a change mints a new key | `api_key_scopes` rows are immutable | No |
| Key transport / storage | `X-API-Key` header; `sha256(secret)` + non-secret `ak_live_` prefix | Never confused with a session; REQ-SEC-07 | No |
| Key display | Once, `no-store`, never recoverable | REQ-API-06 | No |
| Expiry | Mandatory, max 365 days | REQ-API-07 — "never" is not an option | Yes, lower only |
| `last_used_at` write | At most once per 60 s | Otherwise a write per request | Yes |
| Key checks | Postgres read per request, uncached | Revocation must be immediate | No |

## How this is verified

- `pnpm openapi:parity`, `pnpm openapi:validate`, and `git diff --exit-code` on
  the generated document — §3 in all three directions, duplicate and misprefixed
  ids, writes missing `comment`, undeclared problem codes (REQ-API-01,
  REQ-API-03).
- `pnpm test:unit` — `tests/unit/api/**`: the query grammar parses and
  round-trips every operator per field type; an unsupported operator is `400`;
  problem+json validates against `ProblemSchema` for every taxonomy class, and
  a body with an extra property is rejected on the way out; token entropy and
  prefix extraction.
- `pnpm test:integration` — `tests/integration/api/**`: a user key's effective
  set narrows within one request of a role revocation; a service key cannot
  exceed its minting operator; a scope edit on a service key is refused; IP
  allowlist accept and reject; `last_used_at` coalescing; revocation effective
  on the next call; the sweeper emits `api.key.expire`.
- `pnpm test:permissions` — every operation in the document called without its
  permission returns `403`, and with a cross-tenant target returns `404`
  (REQ-TST-05).
- `pnpm test:audit` — the five key lifecycle events fire with actor, prefix and
  scope set; `first_use` fires once; a doc try-it-out request produces a normal
  audit row.
- `pnpm test:e2e` — `tests/e2e/api-docs/**`: the docs page hides operations the
  session lacks and states the hidden count; a mint flow demands step-up, shows
  the key once, and shows only the prefix on reload.
- `pnpm contracts:test --interface grid-api` —
  `packages/contracts/tests/pagination.interface.test.ts`: every `list: true`
  operation accepts the grid's serialised params and both modes agree, run by
  both A07 and A11 (REQ-CTR-10).
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
| Docs viewer | Self-hosted at `/(app)/api-docs`, `API_DOCS_ENABLED` per environment |
