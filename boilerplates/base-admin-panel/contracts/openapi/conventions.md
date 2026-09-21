# `openapi` — how the document is produced

**Published by:** A11 (the document, the route kit, the in-app docs). Each
domain declares its own operations; A11 assembles.
**Requirements:** REQ-API-01, REQ-API-02, REQ-API-03, REQ-API-09, REQ-API-10,
REQ-API-11, REQ-CTR-03, REQ-CTR-09, REQ-AUT-07, REQ-AUD-04, REQ-ENT-01.
**Consumed by:** every agent that owns a route subtree; A23 (generated client
and fixtures).

`contracts/openapi/skeleton.yaml` is the shape the generator emits. This file is
the rules it emits by.

---

## 1. Generated, never hand-maintained (REQ-API-01)

The document is emitted from the **same Zod schemas the runtime validates
with**. There is one schema per payload and it has two consumers: the request
validator and the OpenAPI generator.

```bash
pnpm openapi:generate                                    # writes packages/api-kit/generated/openapi.json
git diff --exit-code packages/api-kit/generated/openapi.json   # CI: a stale document fails the build
pnpm openapi:validate                                    # 3.1 structural validation, zero unresolved $ref
```

Hand-editing the generated document is a build defect. A shape that cannot be
expressed in Zod is a shape the runtime cannot validate, and it does not ship.
The document is committed so the diff is reviewable and the generated client is
reproducible.

## 2. A route declares everything in one place

Permission, schemas, audit intent and step-up live in the route declaration —
not spread across a middleware, a decorator and a comment. One object is the
single source for the router, the validator, the OpenAPI operation, the
permission check and the audit emission.

```ts
// apps/<app>/app/api/v1/tenancy/tenants/route.ts
export const GET = defineRoute({
  id: "tenancy.listTenants",              // §3
  method: "GET",
  path: "/api/v1/tenancy/tenants",        // §4
  summaryKey: "api.tenancy.list_tenants", // i18n key, never a literal (REQ-I18N-02)
  permission: "tenancy.tenant.read",      // null = authenticated only (REQ-RBA-02)
  stepUp: false,                          // REQ-AUT-07
  list: true,                             // accepts PageParams verbatim (REQ-API-11)
  input: { query: PageParamsSchema },
  output: PageSchema(TenantSchema),
  audit: { action: "tenancy.tenant.list", kind: "view" },   // REQ-AUD-02
  errors: ["common.validation_failed", "rbac.permission_denied"],
}, handler);
```

What the kit does with it, in order: parse and validate input → resolve the
session and the tenant (`identity.md` §1) → check the permission and the step-up
freshness → run the handler inside the transaction that sets the tenant
(`contracts/db/rls-contract.md` §3) → validate the output → emit the declared
audit event → serialise. A handler that skips a step cannot: the steps are the
kit, not the handler.

`audit` is mandatory on every route, including reads. `kind: "view"` gets
aggregation, `kind: "read"` does not (`contracts/events/audit-event.md` §3).
There is no `audit: null`.

## 3. Operation ids

```
operationId := <domain> "." <lowerCamelCase verb phrase>
```

Matching A11's `RouteContractSchema`: `/^[a-z][a-zA-Z0-9]*\.[a-zA-Z0-9]+$/`.
`tenancy.listTenants`, `api.mintKey`, `grid.getPrefs`, `rbac.startImpersonation`.

- The domain segment equals the route's `/api/v1/<domain>/` segment and the
  declaring agent's domain. A duplicate operation id is a hard assembly failure
  naming both claimants.
- The id is the generated client's method name, so it is stable forever. A
  renamed operation is a new operation (§7).
- `<domain>.selftest` is reserved for REQ-CTR-08.

## 4. Path grammar

```
/api/v{1|2}/<domain>/<resource>[/{id}[/<sub-resource>[/{subId}]]]
```

| Rule | Detail |
|------|--------|
| Version first | `/api/v1/...` always (REQ-API-09). No unversioned path exists, not even a health check. |
| Domain second | The owning agent's domain. A11 owns the tree; each domain owns its subtree (`contracts/ownership.md`). |
| Resource plural, kebab-case | `tenants`, `api-keys`, `mapping-descriptors`. |
| Path params camelCase | `{tenantId}`, `{gridKey}`. The name matches the Zod key. |
| No tenant in the path | **Ever.** The tenant comes from the session (REQ-RBA-03). `/api/v1/tenancy/tenants/{tenantId}` is the global-tier exception of `identity.md` §1: the tenant is the target resource, not the scope. |
| No verbs in paths | The method is the verb. The exceptions are bounded operations: `.../{id}/rotate`, `.../{id}/replay`, `.../_selftest`. |
| Collections are paginated | Every collection GET accepts `PageParams` verbatim (`contracts/types/pagination.md` §2). |

## 5. The audited comment on every write (REQ-ENT-01, REQ-AUD-04)

Every `POST`, `PUT`, `PATCH` and `DELETE` body carries the entity write
envelope's `comment` field — optional, max 2000 chars, free text:

```ts
input: { body: TenantUpdateSchema.merge(EntityWriteEnvelopeSchema) }
```

This is the document `contracts/types/entity-base.md` §1 points at. Rules:

- `comment` is the **only** envelope member a caller may send. A body declaring
  `createdBy`, `updatedAt` or any other actor/timestamp column is rejected by
  the generator at build time and by the validator at runtime with
  `common.validation_failed`.
- The kit copies `comment` into the row and into the audit event. A handler
  never reads it for logic.
- Where a reason is mandatory — impersonation entry, MFA disable, account
  recovery, purge — the route declares its own required `reason` field with a
  minimum length. `comment` stays optional; a required field is not implemented
  by tightening a shared optional one.
- The generator emits `comment` into the request schema of every write
  operation. An operation missing it fails the parity check (§6).

## 6. Route ↔ operation parity in CI (REQ-API-03)

Bidirectional, both directions fatal:

```bash
pnpm openapi:parity
# route without an operation  -> ORPHAN ROUTE   apps/<app>/app/api/v1/mail/outbox/route.ts
# operation without a route   -> ORPHAN OP      mail.retryMessage
# declared but unrouted       -> ORPHAN DECL    A12 declared mail.retryMessage, no route file
```

The check walks the filesystem route tree, the generated document and every
`contract.declaration.ts`, and all three must agree. An undocumented route is
how an endpoint ships without a permission check; an operation with no route is
how a generated client gets a method that 404s. `GET /api/v1/api/_selftest`
reports the parity count so an integration failure names one owner
(REQ-CTR-08).

## 7. Versioning and breaking changes (REQ-API-09, REQ-CTR-03, REQ-CTR-09)

Inside `/api/v1`, changes are additive only: a new operation, a new optional
request field, a new response field, a widened input enum, a narrowed output
enum. Nothing else.

A breaking change to a shipped operation is served at `/api/v2`:

- `v1` and `v2` are both routed and both documented for the deprecation window
  stated in the CCR. The `v1` operation is marked `deprecated: true` with
  `x-removed-in` naming the version that removes it.
- The `v2` operation keeps the same operation id when it is the same operation
  (the document distinguishes them by path), so the generated client exposes
  `v1.tenancy.listTenants` and `v2.tenancy.listTenants`.
- After the window, `v1` returns 410 `api.operation_removed`
  (`contracts/types/errors.md` §3). It is never removed from the document
  silently.
- A breaking CCR is arbitrated by the orchestrator, and the default answer is
  the additive alternative (`contracts/README.md` §6).

## 8. Security schemes

```yaml
securitySchemes:
  sessionCookie: { type: apiKey, in: cookie, name: __Host-session }
  apiKeyHeader:  { type: apiKey, in: header, name: X-API-Key }
```

- Both are declared at the document root as alternatives (`security` is a list
  of single-scheme requirements, so either satisfies an operation).
- The session cookie is opaque: `HttpOnly`, `Secure`, `SameSite`, `__Host-`
  prefix (REQ-SEC-09). It carries no claims, no tenant, no permissions
  (`identity.md` §5).
- API keys are `Authorization`-free by design: one header, `X-API-Key`, so a
  bearer token is never confused with a session. The key's effective permissions
  are `scopes ∩ owner's live set` (REQ-API-04).
- Cookie-authenticated mutations additionally require the double-submit CSRF
  header (REQ-SEC-10). It is declared as a required header parameter on every
  write operation, emitted by the generator, not written per route.
- An operation with `security: []` does not exist in this build. The login and
  the OIDC callback are the only unauthenticated routes and they are declared
  with their own scheme-free operations plus rate limits (REQ-SEC-11).

## 9. The in-app docs reflect the caller's permissions (REQ-API-02)

`/api-docs` is served in-app, behind auth, and renders the document **filtered
to the caller**:

- An operation whose `permission` the caller does not hold is hidden, not shown
  greyed out. A hidden operation is still in the document served to a caller who
  holds it; the filter is per-request, not a second document.
- The filter is presentation only. Hiding an operation is not an access control;
  the route kit's check is (REQ-RBA-02).
- Operations requiring step-up are badged, so an operator knows before the 403
  `auth.step_up_required`.
- The "try it" console uses the caller's own session, adds the CSRF header, and
  refuses to send a write while `API_DOCS_ENABLED=false`.
- The docs are localised from the `api.*` namespace. Summaries and descriptions
  in the document are i18n keys; the renderer resolves them (REQ-I18N-01).

## 10. Change rules after the G3 freeze

**Additive**
- A new operation in a domain's own subtree.
- A new optional request field, a new response field, a new declared error code
  on an operation.
- A new security scheme, offered alongside the existing ones.
- A new `x-` extension carrying no semantics the client must honour.

**Breaking — needs orchestrator arbitration (REQ-CTR-03, REQ-CTR-09)**
- Changing an operation id, a path, or a method. The generated client's method
  names and every integration break at once.
- Removing a response field, making a request field required, narrowing an
  input enum, or changing a status code (`errors.md` §7).
- Moving a route between domains — it changes the path, the operation id and the
  owner.
- Serving an operation without a declared permission or without an audit
  declaration.
