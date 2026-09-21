# `rls-contract` — Row Level Security, forced and proven

**Published by:** A04. A04 owns the policy for **every** tenant-scoped table,
including the tables it does not own. One agent owning all isolation is how
REQ-RBA-04 and REQ-RBA-05 stay provable.
**Requirements:** REQ-RBA-03, REQ-RBA-04, REQ-RBA-05, REQ-AUD-03, REQ-FND-05,
REQ-SEC-03, REQ-TST-05.
**Consumed by:** every agent that declares `tenantScoped: true`; A23 (the
generated isolation suite).

Fourteen agents writing "their own" tenant filter means fourteen correct filters and
one leak. There is one filter, it is in the database, and it is forced.

---

## 1. What A04 writes, and only that

A04 generates one file per tenant-scoped table from the frozen declarations
(`contracts/db/schema-ownership.md` §3):

```
db/policies/<table>.sql
db/migrations/A04/<timestamp>__rls_<table>.sql
```

Each file contains `ENABLE`, `FORCE`, `CREATE POLICY` and `GRANT` — nothing
else. A04 never adds, alters or drops a column on another agent's table. If a
declared tenant-scoped table is missing `tenant_id`, A04 fails its own run and
names the owning agent; it does not fix the owner's migration.

The files are generated and committed. A hand-edited policy file fails the
generator's diff check, because a hand edit is how one table quietly loses
`FORCE`.

## 2. Enable, and force (REQ-RBA-04)

```sql
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE  ROW LEVEL SECURITY;
```

Both statements, on every tenant-scoped table. `ENABLE` alone exempts the table
owner; `FORCE` removes that exemption.

**The app role must not be the table owner.** This is the part that is easy to
get wrong and fatal to get wrong:

- A table's owner bypasses RLS unless the table is `FORCE`d, so `FORCE` appears
  to make ownership irrelevant. It does not: `FORCE` is per-table state that any
  future migration can drop — one `ALTER TABLE x NO FORCE ROW LEVEL SECURITY`,
  or one new table created by the app role with no policy migration, and the
  owner-bypass is back. Relying on `FORCE` alone is one migration away from a
  breach, with no attacker involved.
- A superuser and a `BYPASSRLS` role bypass RLS regardless of `FORCE`.

Defence in depth, all of it asserted:

```sql
-- One-time, in A04's first migration. Owner and app role are different roles.
CREATE ROLE app_owner NOLOGIN;                  -- owns the schema and every table
CREATE ROLE app_runtime LOGIN NOBYPASSRLS;      -- what DATABASE_URL connects as
GRANT USAGE ON SCHEMA public TO app_runtime;

-- Boot assertion (REQ-FND-07): fail loudly, never a silent default.
DO $$
BEGIN
  IF (SELECT rolsuper OR rolbypassrls FROM pg_roles WHERE rolname = current_user) THEN
    RAISE EXCEPTION 'app role % is superuser or BYPASSRLS — refusing to boot', current_user;
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_tables t
    WHERE t.schemaname = 'public' AND t.tableowner = current_user
  ) THEN
    RAISE EXCEPTION 'app role % owns tables — RLS would be bypassable', current_user;
  END IF;
END $$;
```

The app role holds `SELECT/INSERT/UPDATE/DELETE` where it needs them and nothing
more: no `CREATE`, no `TRUNCATE`, no ownership, no `BYPASSRLS`. A `DATABASE_URL`
pointing at a superuser fails boot, and connections are `sslmode=verify-full`
against a pinned CA (REQ-SEC-03).

## 3. The tenant arrives as `SET LOCAL`, inside the transaction

```sql
BEGIN;
SET LOCAL app.current_tenant = '8f1c39aa-...';   -- from the session, never a parameter
SELECT ... ;                                      -- every statement of the request
COMMIT;
```

One place sets it: the route kit's transaction wrapper, from
`session.tenant.id` (REQ-RBA-03, `contracts/types/identity.md` §1). No other
code path calls it, and a lint rule fails any route that reads `tenantId` from
params or body.

**Why `SET LOCAL` and not `SET`.** The app runs behind a connection pool. A
session-wide `SET` outlives the request: the connection returns to the pool
still carrying tenant A's id, and the next request that forgets to set its own
tenant reads tenant A's rows as tenant B — a cross-tenant read with no
attacker, no policy bug and nothing in a log. `SET LOCAL` is scoped to the
transaction and rolled back on commit or abort, so the leak is impossible
rather than unlikely.

Consequences that follow, and are not optional:

- Every query runs **inside** that transaction. Outside it there is no setting,
  `current_setting('app.current_tenant', true)` is null, the predicate is false
  and the query reads zero rows. Failing closed is designed: a query returning
  nothing is a bug report, one returning everything is a breach.
- The setting name is `app.current_tenant`, matching the literal in A04's
  `RlsContractSchema` (`sessionSetting: z.literal("app.current_tenant")`). Some
  drafts call it `app.current_tenant`; the declaration's literal is the tiebreak.
- The global tier does not widen the setting. Entering a tenant mints a new
  session with that tenant in it (`identity.md` §1); a cross-tenant read uses
  §5's global-readable policy branch, never "tenant = any".
- `SET LOCAL ROLE` is not used to switch tenants. One role, one setting.

## 4. The tenant-scoped policy template

```sql
-- db/policies/users.sql — GENERATED by A04 from tables[].tenantScoped. Do not hand-edit.
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE  ROW LEVEL SECURITY;

CREATE POLICY rls_users_tenant_isolation ON users
  FOR ALL
  TO app_runtime
  USING      (tenant_id = current_setting('app.current_tenant', true)::uuid)
  WITH CHECK (tenant_id = current_setting('app.current_tenant', true)::uuid);

GRANT SELECT, INSERT, UPDATE, DELETE ON users TO app_runtime;
CREATE INDEX IF NOT EXISTS users_tenant_idx ON users (tenant_id);
```

- `USING` filters reads and the rows an update or delete may see. `WITH CHECK`
  filters what a write may produce. Both are required: `USING` alone lets a
  caller move a row into another tenant.
- `current_setting(..., true)` is the missing-ok form. It returns null instead of
  raising, and `tenant_id = null` is false, so no setting means no rows.
- `FOR ALL` covers all four commands in one policy. Four separate policies are
  four chances to omit one.
- The `tenant_id` index is not an optimisation: every query carries the
  predicate, so its absence is a sequential scan on every read.
- Soft delete is **not** in the policy. `deleted_at IS NULL` is the DAL's
  predicate, lifted by `global.deleted-record.read` (REQ-ENT-05). Isolation and
  visibility are different concerns and mixing them makes both unprovable.

## 5. Two more templates

**Global-tier readable** — a tenant-scoped table an operator may read across
tenants (audit trails, tenant registry, collector inventory). The cross-tenant
branch is a second policy, not a widened predicate:

```sql
CREATE POLICY rls_audit_events_tenant_isolation ON audit_events
  FOR ALL TO app_runtime
  USING      (tenant_id = current_setting('app.current_tenant', true)::uuid)
  WITH CHECK (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- Additive: policies are OR-ed for the same command, so this widens reads only.
CREATE POLICY rls_audit_events_global_read ON audit_events
  FOR SELECT TO app_runtime
  USING (current_setting('app.global_tier', true) IN ('operator', 'global_admin', 'superadmin'));
```

`app.global_tier` is set by the same `SET LOCAL` wrapper from
`session.globalTier`, and only for a session holding the relevant `global.*`
permission with a fresh step-up (`contracts/types/rbac.md` §3). It grants
`SELECT` only: a global-tier write still goes through the tenant branch, so it
happens inside an entered tenant and is audited as such.

**Append-only** — `audit_events`, `audit_chain` (REQ-AUD-03):

```sql
ALTER TABLE audit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_events FORCE  ROW LEVEL SECURITY;

CREATE POLICY rls_audit_events_insert ON audit_events
  FOR INSERT TO app_runtime
  WITH CHECK (tenant_id = current_setting('app.current_tenant', true)::uuid);

-- No UPDATE or DELETE policy exists, and no grant does either.
REVOKE UPDATE, DELETE, TRUNCATE ON audit_events FROM app_runtime;
GRANT SELECT, INSERT ON audit_events TO app_runtime;

CREATE TRIGGER audit_events_append_only
  BEFORE UPDATE OR DELETE ON audit_events
  FOR EACH ROW EXECUTE FUNCTION audit_append_only_guard();
```

The absent grant is the control; the trigger catches a role that acquires the
privilege later. The view-counter path (`contracts/events/audit-event.md` §3)
runs as a `SECURITY DEFINER` function owned by `app_owner` and may touch only
the two sampling fields.

## 6. The isolation proof (REQ-RBA-05, REQ-TST-05)

Isolation is proven by test, per table, not by inspection. The suite is
**generated** from the declared tenant-scoped tables, so a new table without a
test is impossible:

```ts
// tests/integration/rls.generated.spec.ts — generated from contracts.tables
import { tenantScopedTables } from "@app/contracts/tables";
import { asTenant } from "./helpers/db";           // opens a tx and SET LOCALs the tenant

describe.each(tenantScopedTables)("RLS: %s", (table) => {
  it("cross-tenant read returns zero rows", async () => {
    const seeded = await asTenant("tenant-a", (tx) => tx.insertFixtureRow(table));
    const rows = await asTenant("tenant-b", (tx) => tx.selectById(table, seeded.id));
    expect(rows).toHaveLength(0);                   // not "throws" — zero rows
  });

  it("cross-tenant write raises", async () => {
    const seeded = await asTenant("tenant-a", (tx) => tx.insertFixtureRow(table));
    await expect(
      asTenant("tenant-b", (tx) => tx.updateById(table, seeded.id, { comment: "moved" })),
    ).rejects.toThrow();                            // 0 rows affected is also a failure
    await expect(
      asTenant("tenant-b", (tx) => tx.insertFixtureRow(table, { tenantId: "tenant-a" })),
    ).rejects.toThrow(/row-level security/);        // WITH CHECK violation
  });

  it("no tenant setting returns zero rows", async () => {
    expect(await withoutTenant((tx) => tx.selectAll(table))).toHaveLength(0);
  });

  it("is enabled, forced and has a policy", async () => {
    const [meta] = await asOwner((tx) => tx.rlsState(table));
    expect(meta).toMatchObject({ relrowsecurity: true, relforcerowsecurity: true });
    expect(meta.policies).toBeGreaterThan(0);
  });
});
```

Four assertions per table: cross-tenant read returns zero rows, cross-tenant
write raises, no-setting returns zero rows, and the table is enabled and forced.
The third is the pooling case from §3 and it is what catches a missing
transaction wrapper. `GET /api/v1/rbac/_selftest` reports the same four facts
for every declared tenant-scoped table at runtime, so production drift names one
owner (REQ-CTR-08); `global.rls.inspect` gates the detailed report. The two
seeded tenants and the global operator come from A23's fixtures (REQ-TST-07).

## 7. Change rules after the G3 freeze

**Additive**
- A new tenant-scoped table: A04 regenerates its policy file and the isolation
  suite grows by four assertions. No other agent changes.
- A new global-readable policy on a table that already has the tenant branch,
  `SELECT` only.
- A tightening: an extra `WITH CHECK` predicate that current data satisfies.

**Breaking — needs orchestrator arbitration (REQ-CTR-03)**
- Renaming `app.current_tenant`, or changing the tenant column from
  `tenant_id`. Every policy, every declaration literal and the route kit change
  at once.
- Any widening of a `USING` predicate. It is a cross-tenant read by definition
  and the default answer is no.
- Dropping `FORCE`, granting `BYPASSRLS`, or making the app role a table owner.
  These are not contract changes; they are security regressions and the answer
  is no in every case.
- Moving the tenant into a request parameter (REQ-RBA-03). Same answer.
