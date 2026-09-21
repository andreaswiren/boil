# RBAC, Tenancy & the Global Tier

Permissions, roles, the three-tier model and the Row Level Security that makes
tenant isolation a database property rather than a code habit. Owned by **A04**
(`rbac-tenancy`): `packages/rbac/**`, `packages/tenancy/**`, `db/policies/**`,
and the tables `tenants`, `roles`, `role_versions`, `permissions`,
`role_permissions`, `user_roles`. A04 also owns the RLS policy for **every**
tenant-scoped table, including tables it does not own — one agent owning all
isolation is how REQ-RBA-04 and REQ-RBA-05 stay provable. A04 publishes `rbac`,
`tenancy`, `rls-contract`; it consumes `entity-base` and `session`. A04 writes no
audit rows (A13) and mints no sessions (A03) — it emits events and evaluates.

## Requirements covered

REQ-RBA-01 … REQ-RBA-08, REQ-ENT-02, REQ-ENT-05, REQ-AUT-07, REQ-AUD-01,
REQ-AUD-04, REQ-CTR-08, REQ-TST-05, REQ-TST-07.

## 1. Permission string grammar (REQ-RBA-01)

```
<domain>.<resource>.<action>

domain    [a-z][a-z0-9]*            the owning package's namespace, or `global`
resource  [a-z][a-z0-9-]*           kebab-case, singular
action    [a-z][a-z0-9-]*           from the closed vocabulary below
```

`PermissionStringSchema` in `packages/contracts/rbac.ts` is that regex.
Resources are **singular and kebab-case**: `global.deleted-record.read`, not
`deleted_records`. `spec/auth.md` §5 cites `global.auth_policy.write`; the
registered string is `global.auth-policy.write` — the grammar wins and A03
corrects the citation.

Closed action vocabulary — every CRUD-shaped resource uses these and no others:

| Action | Means | Notes |
|---|---|---|
| `read` | one row by id | detail views are always audited (REQ-AUD-02) |
| `list` | a paginated collection | list reads are aggregated in audit |
| `create` | insert one row | |
| `update` | partial write to one row | |
| `write` | replace a configuration document with no row identity | policies, settings |
| `delete` | soft delete — sets `deleted_at` | REQ-ENT-02 |
| `restore` | clears `deleted_at` | REQ-ENT-02 |
| `purge` | hard delete | global tier only, step-up 60 s |
| `export` | bulk extraction | audited per export (REQ-GRD-13) |
| `revoke` | invalidate a credential, session or key | |
| `approve` | a second identity authorises a pending action | |
| `impersonate` | act as another identity | REQ-RBA-07 |

A domain needing a verb outside the twelve registers it in its
`contract.declaration.ts` as a single lowercase imperative — `enrol`, `reset`,
`rotate`, `probe`, `retry`. Assembly rejects an unregistered verb, so the
vocabulary cannot grow by accident in a 13-wide wave. `*` is never a permission
string: a wildcard grant is a role, and roles are enumerated.

## 2. Evaluation is deny-by-default, in three independent layers (REQ-RBA-02)

```ts
can(actor, "device.config-backup.export") // true only if the string is in actor.permissions
```

There are no deny entries. A role is a **union of grants** and the base state is
no access, so a deny rule would only introduce evaluation order — and evaluation
order is where permission bugs live. Removing access means removing the grant.

| Layer | Enforces | Failure mode it covers |
|---|---|---|
| Route kit (A11) | the declared permission for the operation, before the handler runs | a handler that forgets to check |
| Data-access layer (A02) | `deleted_at IS NULL` unless `global.deleted-record.read` (REQ-ENT-05), actor columns (REQ-ENT-04) | a hand-written predicate |
| Postgres RLS (A04) | `tenant_id` scope, on every tenant-scoped table | a missed check anywhere above |

An operation declared without a permission fails CI (`spec/api.md` §2). The
client filters nav entries and disables buttons from `session.permissions`; that
is **presentation only** and never the enforcement point. A permission denial
returns `rbac.permission_denied` → 403; a *cross-tenant* attempt returns
`tenancy.cross_tenant` → **404**, because a 403 confirms the row exists
(`contracts/types/identity.md` §1).

## 3. System roles and tenant-defined roles

| Kind | Table state | Editable | Why |
|---|---|---|---|
| System role | `roles.system = true`, seeded by migration | Name and description no, grants no | A tenant that can edit `tenant-admin` can escalate itself |
| Tenant role | `roles.tenant_id = <tenant>`, `system = false` | Yes, by `rbac.role.update` | Tenants have their own job titles |
| Global role | `roles.tenant_id IS NULL`, `tier` set | Superadmin only, step-up | REQ-RBA-06 |

Seeded system roles: `tenant-admin`, `tenant-operator`, `tenant-viewer`,
`global-operator`, `global-admin`, `superadmin`. A tenant role is created by
cloning a system role, never from an empty grant set filled from memory.

**The ceiling**: a tenant role may hold only permissions in the tenant's
available set — the permissions its enabled features declare, minus any the
global tier has withheld from that tenant. A grant outside it is refused at
write time with `rbac.grant_exceeds_ceiling`, naming the string. No tenant role
may hold a `global.*` permission; that is a separate assertion, not a by-product
of the ceiling, because the ceiling is data and this is a law.

## 4. Three tiers (REQ-RBA-06)

```
global / MSP tier  tenantId: null  namespace global.*  step-up on every write
   │ enters a tenant → mints a NEW session (never widens the current one)
tenant             tenantId: <id>  namespace <domain>.*  RLS-scoped, holds roles
   │ role assignments
user               the identity those assignments are attached to
```

| Tier | Grants | Cross-tenant | Step-up |
|---|---|---|---|
| `operator` | `global.tenant.list`, `global.tenant.read`, `global.impersonation.impersonate`, cross-tenant read | read | every write |
| `global_admin` | tenant lifecycle, auth policy, role definitions, `global.deleted-record.read` | read + write | every write |
| `superadmin` | `global.record.purge`, KEK rotation, audit retention, break-glass recovery | read + write | every write |

Tiers are compared by index in `GLOBAL_TIER_ORDER`, never by string
(`contracts/types/identity.md` §4). Holding `global_admin` implies **no** tenant
permission: entering a tenant mints a session and resolves tenant permissions
for it. The `global.*` namespace is separate so no union of tenant roles can
produce a global permission, and so
`grep -rh '"global\.' packages/*/contract.declaration.ts` lists the entire
privileged surface in one command.

## 5. `tenant_id` comes from the session (REQ-RBA-03)

The tenant is read from the session row and nowhere else. Not `?tenantId=`, not
`X-Tenant-Id`, not a body field, not the subdomain alone. A route schema
declaring a tenant identifier fails contract assembly unless the operation is in
the `global.tenant.*` family, where the tenant is the *target resource* and not
the RLS scope, or is tenant entry, which mints a new session.

Every tenant-scoped table carries `tenant_id uuid NOT NULL REFERENCES
tenants(id)`. The DAL does not write it from an argument either: it comes from
`actor.tenantId`, the value the RLS `WITH CHECK` re-verifies.

## 6. Row Level Security, in detail (REQ-RBA-04)

Two independent controls. Each covers the other's failure mode.

```sql
-- db/policies/000-roles.sql (A04)
CREATE ROLE app_owner    NOINHERIT;              -- owns the schema, runs migrations
CREATE ROLE app_runtime  LOGIN NOINHERIT NOBYPASSRLS;  -- the tenant pool
CREATE ROLE app_global   LOGIN NOINHERIT NOBYPASSRLS;  -- the global-tier pool
REVOKE ALL ON SCHEMA public FROM PUBLIC;
```

**Control 1 — the app is not the owner.** `app_runtime` owns no table and holds
no `BYPASSRLS`. A table owner bypasses RLS unless it is forced, and
`SUPERUSER`/`BYPASSRLS` bypasses it even then. Connecting as the owner makes
every policy below decorative.

**Control 2 — `ENABLE` plus `FORCE`.**

```sql
ALTER TABLE devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE devices FORCE  ROW LEVEL SECURITY;
```

`ENABLE` applies policies to non-owners. `FORCE` applies them to the owner too.
We do both, and we do not lean on either alone:

- `ENABLE` without `FORCE`: the day the app runs under the migration
  credentials — a debug session, a data fix, a misread env var — RLS silently
  stops applying. Isolation must not depend on which DSN is in scope.
- `FORCE` without a non-owner role: one `ALTER TABLE ... NO FORCE ROW LEVEL
  SECURITY`, or one new table created without both statements, and every row in
  it is readable by every tenant. That is a breach one migration away, with no
  test failing unless the isolation proof in §8 is table-driven. It is.

**The tenant is carried by `SET LOCAL`, inside the transaction.**

```sql
BEGIN;
SELECT set_config('app.tenant_id', $1::text, true);  -- true = is_local
-- ... the request's statements ...
COMMIT;                                              -- setting reverts here
```

`set_config(..., true)` is `SET LOCAL` with a bindable parameter, so the tenant
uuid is never interpolated into SQL text. A session-wide `SET` survives the
transaction and, under transaction-level pooling (PgBouncer, or any pooler an
operator puts in front of Postgres), leaks to the next borrower of that
connection — cross-tenant disclosure caused by pool reuse, the hardest class of
bug to reproduce and the easiest to ship. `SET LOCAL` reverts at
`COMMIT`/`ROLLBACK`, so a connection returns to the pool carrying no tenant.
Every request runs in a transaction; the DAL has no non-transactional read path.

**The policy shape.**

```sql
-- db/policies/001-helpers.sql
CREATE FUNCTION app.current_tenant() RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('app.tenant_id', true), '')::uuid $$;
CREATE FUNCTION app.global_read() RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT current_setting('app.global_read', true) = 'on'
     AND current_user = 'app_global' $$;

-- db/policies/<table>.sql — generated per tenant-scoped table
CREATE POLICY devices_tenant ON devices
  FOR ALL TO app_runtime, app_global
  USING      (tenant_id = app.current_tenant() OR app.global_read())
  WITH CHECK (tenant_id = app.current_tenant());
```

- `current_setting(..., true)` is NULL when unset, so the comparison is NULL and
  the row is invisible. Unset means **zero rows**, never all rows. Fail closed
  is the default state, not a branch.
- `WITH CHECK` has no global escape: a cross-tenant *write* is impossible even
  on the global pool. A global-tier write enters the tenant first.
- Cross-tenant *reads* need two keys — the `app.global_read` GUC **and** the
  `app_global` role. That pool has its own credentials and serves only routes
  declaring a `global.*` permission, so an injected `set_config` on the tenant
  pool buys nothing.
- Policies are generated from `tenantScoped: true` in the table owner's
  declaration. Declared and no policy fails assembly; a `tenant_id` column and
  no declaration fails migration lint.

## 7. Impersonation and tenant entry (REQ-RBA-07)

The shape and the audit fields are frozen in `contracts/types/identity.md` §6.
What A04 enforces:

| Control | Value |
|---|---|
| Permission | `global.impersonation.impersonate` |
| Step-up | within 60 s (`spec/auth.md` §6) |
| Reason | mandatory, 8–500 chars, on the banner and both audit events |
| Time box | 30 min default, 4 h maximum, not extendable — exit and re-enter |
| Session | a **new** session is minted; the operator's own session is untouched |
| Banner | non-dismissible, on every page, naming subject, tenant, reason, remaining time |
| Audit | `global.impersonation.enter` **and** `global.impersonation.exit`, shared `impersonationId` |
| Write actions | permitted, and every row carries the operator's actor id (REQ-ENT-04) |

Exit is emitted on explicit exit, expiry and revocation, with
`result: "exited" | "expired" | "revoked"`. An unpaired `enter` is a defect the
verify job reports (`spec/observability.md` §6): an operator who can end a
session without an exit event can act unobserved.

## 8. Isolation is proven per table, not asserted (REQ-RBA-05)

The proof is generated from the contract, so a new table cannot escape it.

```
tests/tenant-isolation/isolation.spec.ts   (A23, suite: pnpm test:isolation)
for each table where tenantScoped === true:
  seed one row in tenant A and one in tenant B (REQ-TST-07)
  as tenant A on app_runtime:
    SELECT ...                      → exactly 1 row, A's
    SELECT ... WHERE id = <B's id>  → 0 rows
    UPDATE  ... WHERE id = <B's id> → 0 rows affected
    INSERT  ... (tenant_id = B)     → raises 42501 new row violates row-level security
    DELETE  ... WHERE id = <B's id> → 0 rows affected
  with app.tenant_id unset:         → 0 rows on every table
  as app_global with global_read on: → both rows readable, writes to B still raise
```

Plus three structural assertions that fail on the schema, not a query: every
tenant-scoped table has `relrowsecurity` **and** `relforcerowsecurity` true in
`pg_class`; `app_runtime` owns nothing (`pg_tables.tableowner`); both app roles
have `rolbypassrls = false`. The suite's table count is compared against the
contract's tenant-scoped count, so it fails rather than quietly testing fewer
tables.

## 9. Role changes are versioned with a diff (REQ-RBA-08)

```sql
role_versions (A04)
  id, role_id, version int, grants text[] NOT NULL,
  diff jsonb NOT NULL,          -- { added: [...], removed: [...] }
  reason text NOT NULL,         -- min 20 chars
  -- entity-base envelope (REQ-ENT-01)
  UNIQUE (role_id, version)
```

Every write to a role's grants inserts a `role_versions` row in the same
transaction, computes `added`/`removed` against the previous version, and emits
`rbac.role.update` with the diff, actor, reason and both version numbers
(REQ-AUD-04). Step-up within 300 s is required. The grant set is reconstructible
at any past version, so "who gave them that" is one query rather than log
archaeology. A user's role assignment (`user_roles`) is insert + soft-delete,
never update, and emits `rbac.role-assignment.create` / `.delete` with the
resulting effective permission set. A03 rotates sessions holding an affected
role on their next request (`spec/auth.md` §8), so a revoked grant does not
survive in a live session.

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Action vocabulary | Closed set of 12 + registered domain verbs | Stops synonym drift across 13 agents | No |
| Deny entries | None — grants only, deny-by-default | Evaluation order is where permission bugs live | No |
| DB roles | `app_owner` / `app_runtime` / `app_global`, none with `BYPASSRLS` | REQ-RBA-04 | No |
| RLS | `ENABLE` **and** `FORCE` on every tenant-scoped table | Each covers the other's failure mode | No |
| Tenant propagation | `set_config('app.tenant_id', $1, true)` inside the transaction | Pooler-safe; a session `SET` leaks across tenants | No |
| Cross-tenant read | Two keys: `app.global_read` GUC + `app_global` role | One key is one injection away | No |
| Cross-tenant write | Impossible — `WITH CHECK` has no global branch | Enter the tenant instead | No |
| Tenant role ceiling | Intersection of feature-declared and non-withheld permissions | Tenants define titles, not power | No |
| Impersonation time box | 30 min default, 4 h max, not extendable | REQ-RBA-07 | Yes, lower only |

## How this is verified

- `pnpm test:isolation` — `tests/tenant-isolation/**` (REQ-TST-05): §8 in full,
  table-driven from the contract, plus the three structural assertions.
- `pnpm test:permissions` — `tests/permission-denial/**` (REQ-TST-05): every
  registered operation called without its permission returns 403, or 404 for a
  cross-tenant target; a tenant role holding a `global.*` string or a grant
  outside the ceiling is refused at write time.
- `pnpm test:unit` — `tests/unit/rbac/**`: the grammar regex against a table of
  valid and invalid strings; tier comparison by index; effective-permission
  resolution for the seeded role matrix (REQ-TST-07).
- `pnpm test:integration` — `tests/integration/rbac/**`: pooler simulation, two
  sequential transactions on one connection where the second issues no
  `set_config` and must read zero rows; role diff over a 10-step history.
- `pnpm test:audit` — `tests/audit-emission/**`: `rbac.role.update` carries diff
  and reason; impersonation enter and exit pair on every exit path.
- `pnpm test:contract` — `packages/contracts/tests/rbac.spec.ts`: no duplicate
  permission strings, every `NavEntry.permission` resolves, every operation's
  declared permission exists (REQ-CTR-10).
- `GET /api/v1/rbac/_selftest` — RLS enabled and forced on every tenant-scoped
  table, `app_runtime` owns nothing, policy count equals table count
  (REQ-CTR-08).

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| Tenant model | Multi-tenant with a global tier above it |
| Global tiers used | All three: `operator`, `global_admin`, `superadmin` |
| May tenants define their own roles | Yes, within the ceiling |
| Impersonation time box / who may | 30 min, 4 h max / `operator` and above |
| Cross-tenant read for operators | Yes, read-only, audited per read |
| Seeded tenant role names | `tenant-admin`, `tenant-operator`, `tenant-viewer` |
| Withheld-permission list per tenant | Empty — the ceiling is the feature set |
