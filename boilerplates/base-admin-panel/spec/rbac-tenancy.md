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
REQ-AUD-04, REQ-SET-02, REQ-SET-05, REQ-SET-07, REQ-SET-10, REQ-CTR-08,
REQ-TST-05, REQ-TST-07.

## 1. Permission string grammar (REQ-RBA-01)

```
<domain>.<resource>.<action>        segment := [a-z][a-z0-9-]*
```

Exactly three segments, lowercase, digits and `-` only. The frozen regex,
`PermissionStringSchema` and the registry of record are
`contracts/types/rbac.md` §1 — this section is the design behind them, not a
second copy of the register.

Resources are **singular and kebab-case**: `global.deleted-record.read`,
`auth.recovery-code.regenerate`. A compound domain in the global namespace
folds into the resource so the string stays three segments —
`global.auth-policy.mfa-disable`, never four. `spec/auth.md` §5 still cites the
pre-freeze `global.auth_policy.write`; the frozen name is
`global.auth-policy.mfa-disable` and the rename table in
`contracts/types/rbac.md` §4 is the tiebreak, not this spec and not that
citation.

The action vocabulary is closed: `list`, `read`, `write`, `delete`, `restore`,
`export`, `run`, `admin` (`contracts/types/rbac.md` §2). Three consequences
worth stating, because each one gets re-litigated otherwise:

- **`write` covers create and update.** No resource in this build grants one
  without the other, and splitting them produces roles where someone can create
  a tenant role but not fix it. A domain that genuinely needs the split declares
  a domain verb and argues for it at CCR time.
- **A domain verb is declared with the permission that uses it** and appears in
  the register's verb list — `assign`, `revoke`, `rotate`, `enrol`, `purge`,
  `impersonate`, `replay`, `mint-own`, `mint-service`, and the rest. Assembly
  cannot tell `write` from `wrait`, so an unlisted verb fails review, and that
  review is the only control that keeps fifteen agents from inventing fifteen
  synonyms for "read".
- **`*` is not a permission string.** A wildcard grant means adding a permission
  silently widens every role holding the prefix — the semantic-change-under-the-
  same-name case `contracts/README.md` §5 calls the worst kind. A role lists
  strings.

One asymmetry worth naming before someone "fixes" it: the **permission** is
`<domain>.<resource>.write`, while the **audit event names** stay
`<domain>.<resource>.create` and `.update`
(`contracts/events/audit-event.md` §2). One grant covers both operations; the
trail still has to say which one happened. Aligning them in either direction
loses information — a single `write` event cannot answer "was this row created
or changed", and a `create` permission that nobody grants separately is a role
editor full of pairs that are always checked together.

Permission strings are contract members: additive only. A rename is a new
string, both granted, the old one deprecated with a removal version
(REQ-CTR-03).

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

## 3. Built-in roles and tenant-defined roles

`Role` is frozen in `contracts/types/rbac.md` §5: `key`, `nameKey`,
`descriptionKey`, `tier`, `version`, `builtIn`, `permissions`, plus the entity
envelope. What A04 decides on top of it:

| Kind | Row state | Editable | Why |
|---|---|---|---|
| Built-in tenant role | `builtIn: true`, `tenantId: null`, `tier: "tenant"` | No. Copy it and edit the copy | A tenant that can edit `tenant-admin` can escalate itself |
| Tenant role | `builtIn: false`, `tenantId` set | Yes, with `rbac.role.write` | Tenants have their own job titles |
| Global role | `tier: "global"`, `tenantId: null` | `superadmin` only | REQ-RBA-06 |

Built-in keys: `tenant-admin`, `tenant-operator`, `tenant-viewer`,
`global-operator`, `global-admin`, `superadmin`. A tenant role is created by
copying a built-in one, never from an empty grant set filled in from memory.
`nameKey` and `descriptionKey` are i18n keys in the `rbac` namespace — a role
name is never a stored English string (REQ-I18N-02).

**The ceiling**: a tenant role may hold only permissions in the tenant's
available set — those its enabled features declare, minus any the global tier
has withheld from that tenant. A grant outside it is refused at write time,
naming the offending string. A `global.*` string in a tenant role is refused
separately with `rbac.global_permission_not_grantable` (422), because the
ceiling is data and that one is a law: no union of tenant roles may ever produce
a global permission.

## 4. Three tiers (REQ-RBA-06)

```
global / MSP tier  tenantId: null  namespace global.*  step-up on every check
   │ enters a tenant → mints a NEW session (never widens the current one)
tenant             tenantId: <id>  namespace <domain>.*  RLS-scoped, holds roles
   │ role assignments
user               the identity those assignments are attached to
```

| Tier | Representative grants (frozen names) |
|---|---|
| `operator` | `global.tenant.read-any`, `global.impersonation.impersonate`, `global.audit.read-any`, `global.collector.read-any` |
| `global_admin` | the above plus `global.tenant.create` / `.suspend` / `.archive`, `global.role.write-any`, `global.auth-policy.mfa-disable`, `global.auth-session.revoke-any`, `global.deleted-record.read`, `global.rls.inspect` |
| `superadmin` | the above plus `global.record.purge`, `global.crypto-kek.rotate`, `global.audit-retention.write`, `global.user.recover`, `global.api-key.mint-service` |

Tiers are compared by index in `GLOBAL_TIER_ORDER`, never by string
(`contracts/types/identity.md` §4). Every `global.*` check requires a fresh
step-up by rule, not per row (`contracts/types/rbac.md` §3.2). Holding
`global_admin` implies **no** tenant permission: entering a tenant mints a
session and resolves that session's tenant permissions from the roles the
operator actually holds there.

The three tiers are the same three scopes the settings surface distinguishes —
personal, tenant, global (REQ-SET-02). A scope with no panel the actor may see
is not rendered at all rather than rendered empty (REQ-SET-07), which is the
presentation half of deny-by-default: an operator who cannot administer tenants
never sees a global scope to wonder about. Role editing lives on the tenant
scope, global roles and tenant administration on the global scope
(REQ-SET-05), and a role change with estate-wide blast radius —
`global.role.write-any` — demands typed confirmation naming the tenants it will
touch (REQ-SET-10).

The separate namespace is also an operational property:
`grep -rh '"global\.' packages/*/contract.declaration.ts` lists the entire
privileged surface of the build in one command.

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

The generated policy files, the role definition and the isolation suite are
frozen in `contracts/db/rls-contract.md`. This section is why the design is
shaped that way, and what would break if any part of it were dropped.

**Two independent controls, each covering the other's failure mode.**

```sql
-- db/policies/000-roles.sql (A04)
CREATE ROLE app_owner   NOINHERIT;              -- owns the schema, runs migrations
CREATE ROLE app_runtime LOGIN NOBYPASSRLS;      -- what DATABASE_URL connects as
REVOKE ALL ON SCHEMA public FROM PUBLIC;
```

*Control 1 — the app is not the owner.* `app_runtime` owns no table and holds no
`BYPASSRLS`. A table owner bypasses RLS unless it is forced, and a superuser or
`BYPASSRLS` role bypasses it even then. Connect as the owner and every policy
below is decorative. A boot-time assertion fails the app if `current_user` owns
any table or holds `rolsuper`/`rolbypassrls`.

*Control 2 — `ENABLE` **and** `FORCE` on every tenant-scoped table.*

```sql
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE  ROW LEVEL SECURITY;
```

- `ENABLE` without `FORCE`: the day the app runs under the migration
  credentials — a debug session, a data fix, a misread env var — RLS silently
  stops applying. Isolation must not depend on which DSN is in scope.
- `FORCE` without a non-owner role: one `ALTER TABLE x NO FORCE ROW LEVEL
  SECURITY`, or one new table created without both statements, and every row in
  it is readable by every tenant. That is a breach one migration away, with no
  test failing unless the isolation proof is generated per table. It is (§8).

**The tenant arrives by `SET LOCAL`, inside the transaction.**

```sql
BEGIN;
SELECT set_config('app.current_tenant', $1::text, true);  -- SET LOCAL, bindable
-- ... every statement of the request ...
COMMIT;                                                   -- the setting reverts
```

`set_config(..., true)` is the bindable spelling of the frozen
`SET LOCAL app.current_tenant`; identical semantics, and the tenant uuid is
never interpolated into SQL text. A session-wide `SET` survives the transaction
and, under transaction-level pooling (PgBouncer, or any pooler an operator puts
in front of Postgres), leaks to the next borrower of that connection —
cross-tenant disclosure with no attacker, no policy bug and nothing in a log.
`SET LOCAL` reverts at `COMMIT`/`ROLLBACK`, so a connection returns to the pool
carrying no tenant. Every request therefore runs inside a transaction; the DAL
has no non-transactional read path. One place sets it — the route kit's
transaction wrapper, from `session.tenant.id` (REQ-RBA-03).

**The policy shape**, generated per `tenantScoped: true` table:

```sql
CREATE POLICY rls_users_tenant_isolation ON users
  FOR ALL TO app_runtime
  USING      (tenant_id = current_setting('app.current_tenant', true)::uuid)
  WITH CHECK (tenant_id = current_setting('app.current_tenant', true)::uuid);
GRANT SELECT, INSERT, UPDATE, DELETE ON users TO app_runtime;
CREATE INDEX IF NOT EXISTS users_tenant_idx ON users (tenant_id);
```

- `current_setting(..., true)` is the missing-ok form: unset returns NULL, the
  comparison is NULL, the row is invisible. Unset means **zero rows**, never all
  rows. Failing closed is the default state, not a branch — a query returning
  nothing is a bug report, one returning everything is a breach.
- `USING` **and** `WITH CHECK` are both required. `USING` alone lets a caller
  move a row into another tenant.
- `FOR ALL` is one policy for four commands. Four policies are four chances to
  omit one.
- Soft delete is **not** in the policy. `deleted_at IS NULL` is the DAL's
  predicate, lifted by `global.deleted-record.read`. Isolation and visibility
  are different concerns, and mixing them makes both unprovable.

**Cross-tenant reads are a second, additive policy — not a widened predicate:**

```sql
CREATE POLICY rls_audit_events_global_read ON audit_events
  FOR SELECT TO app_runtime
  USING (current_setting('app.global_tier', true)
         IN ('operator', 'global_admin', 'superadmin'));
```

Policies for the same command are OR-ed, so this widens reads only, on the
tables that declare it (audit trail, tenant registry, collector inventory).
`app.global_tier` is set by the same `SET LOCAL` wrapper from
`session.globalTier`, and only for a session holding the relevant `global.*`
permission with a fresh step-up. A global-tier **write** has no branch at all:
it goes through the tenant policy, which means the operator entered the tenant
and the action is audited as such. `SET LOCAL ROLE` is not used to switch
tenants — one role, one setting, one predicate to reason about.

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

The suite is **generated** from the declared tenant-scoped tables
(`tests/integration/rls.generated.spec.ts`), so a new table without a test is
impossible. Four assertions per table:

```
for each table where tenantScoped === true:
  cross-tenant read  → 0 rows        (not "throws" — zero rows)
  cross-tenant write → raises        (0 rows affected also fails)
                       INSERT with another tenant_id → /row-level security/
  no tenant setting  → 0 rows        (the pooling case from §6)
  pg_class           → relrowsecurity AND relforcerowsecurity, policies > 0
```

The third assertion is the one that catches a missing transaction wrapper, which
is the realistic way this breaks in production. Two structural checks run
alongside: `app_runtime` owns no table (`pg_tables.tableowner`) and has
`rolbypassrls = false`. The suite's table count is compared against the
contract's tenant-scoped count, so it fails rather than quietly testing fewer
tables. `GET /api/v1/rbac/_selftest` reports the same four facts at runtime, with
the detailed report gated on `global.rls.inspect`.

## 9. Role changes are versioned with a diff (REQ-RBA-08)

```sql
role_versions (A04)                       -- carries the entity envelope
  role_id uuid not null,
  version int  not null,                  -- monotonic, matches Role.version
  grants  text[] not null,                -- the full set at this version
  diff    jsonb  not null,                -- { added: [...], removed: [...] }
  -- entity-base: created_at/created_by ARE `changedAt`/`changedBy`
  -- (contracts/types/rbac.md §5); `comment` carries the reason
  unique (role_id, version)
```

The contract's `RoleVersion` has `changedAt`/`changedBy`; in storage those are
the envelope's `created_at`/`created_by`, set by the DAL from the actor
(REQ-ENT-04), so the table needs no exemption and no second actor column.

Every write to a role's grants, in one transaction: insert the version row,
compute `added`/`removed` against the previous version, emit `rbac.role.write`
carrying the diff, the actor, the `comment` and both version numbers
(REQ-AUD-04). Step-up within 300 s is required. A write against a superseded
version is refused with `rbac.role_version_stale` (409) rather than
last-write-wins — two admins editing one role must not silently overwrite each
other's grants.

The grant set is reconstructible at any past version, so "who gave them that" is
one query rather than log archaeology. A user's role assignment (`user_roles`)
is insert + soft-delete, never update, and emits `rbac.role.assign` with the
resulting effective permission set. A03 rotates sessions holding an affected
role on their next request (`spec/auth.md` §8), so a revoked grant does not
survive in a live session.

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Action vocabulary | The frozen closed set of 8 + registered domain verbs | Stops synonym drift across 13 agents | No |
| Deny entries | None — grants only, deny-by-default | Evaluation order is where permission bugs live | No |
| DB roles | `app_owner` and `app_runtime`; the app role owns nothing and has no `BYPASSRLS` | REQ-RBA-04 | No |
| RLS | `ENABLE` **and** `FORCE` on every tenant-scoped table | Each covers the other's failure mode | No |
| Tenant propagation | `set_config('app.current_tenant', $1, true)` inside the transaction | Pooler-safe; a session `SET` leaks across tenants | No |
| Cross-tenant read | A second additive `SELECT` policy on `app.global_tier` | A widened predicate is one typo from "tenant = any" | No |
| Cross-tenant write | Impossible — `WITH CHECK` has no global branch | Enter the tenant instead | No |
| Tenant role ceiling | Intersection of feature-declared and non-withheld permissions | Tenants define titles, not power | No |
| Impersonation time box | 30 min default, 4 h max, not extendable | REQ-RBA-07 | Yes, lower only |
| Concurrent role writes | `rbac.role_version_stale` (409), never last-write-wins | Two admins must not overwrite each other | No |

## How this is verified

- `pnpm test:isolation` — `tests/integration/rls.generated.spec.ts` (REQ-TST-05,
  REQ-RBA-05): §8 in full, generated from the contract's tenant-scoped table
  list, plus the two structural checks.
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
- `pnpm test:audit` — `tests/audit-emission/**`: `rbac.role.write` carries the
  diff and the `comment`; impersonation enter and exit pair on every exit path.
- `pnpm test:contract` — `packages/contracts/tests/rbac.spec.ts`: no duplicate
  permission strings, every `NavEntry.permission` resolves, every operation's
  declared permission exists (REQ-CTR-10).
- `GET /api/v1/rbac/_selftest` — RLS enabled and forced on every tenant-scoped
  table, policy count equals table count, `app_runtime` owns nothing; the
  detailed report is gated on `global.rls.inspect` (REQ-CTR-08).

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
