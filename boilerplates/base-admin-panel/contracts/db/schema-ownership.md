# `schema-ownership` — tables, owners, migrations, lint

**Published by:** A02 (the map is copied from `contracts/ownership.md`, which
A02 owns; the migration lint is A02's). A04 owns every RLS policy
(`contracts/db/rls-contract.md`).
**Requirements:** REQ-CTR-04, REQ-ENT-01, REQ-ENT-03, REQ-RBA-03, REQ-RBA-04,
REQ-FND-05.
**Consumed by:** every agent that owns a table, and the migration lint in CI.

One table, one owning agent. No table without an owner. The map below is copied
from `contracts/ownership.md` — it invents no owner and it is not a second
source of truth. When the two disagree, `contracts/ownership.md` wins and this
file is corrected.

---

## 1. The table map

`tenantScoped` is the table owner's declaration in its
`contract.declaration.ts`. A04 generates the RLS policy from that flag; the flag
is the input, the policy is the output (REQ-RBA-04).

| Table | Owner | `tenantScoped` | Notes |
|-------|-------|----------------|-------|
| `tenants` | A04 | false | The tenant registry itself. Global-tier readable policy (`rls-contract.md` §5). |
| `roles` | A04 | true | Versioned (REQ-RBA-08). |
| `permissions` | A04 | false | The assembled permission registry. Read-only to the app role. |
| `role_permissions` | A04 | true | Join table. Entity-base exempt. |
| `user_roles` | A04 | true | Grant/revoke only. Partially exempt. |
| `users` | A03 | true | |
| `credentials` | A03 | true | Argon2id hashes (REQ-SEC-07). |
| `mfa_factors` | A03 | true | TOTP seeds envelope-encrypted (REQ-SEC-06). |
| `recovery_codes` | A03 | true | Argon2id hashes, single use (REQ-AUT-06). |
| `sessions` | A03 | true | Server-side and revocable (REQ-AUT-10). |
| `oidc_providers` | A03 | true | Client secrets envelope-encrypted. |
| `identity_links` | A03 | true | One identity, many methods (REQ-AUT-09). |
| `audit_events` | A13 | true | Append-only (REQ-AUD-03). Entity-base exempt. |
| `audit_chain` | A13 | true | Hash-chain heads (REQ-AUD-06). Append-only, exempt. |
| `log_sinks` | A13 | true | TLS syslog targets (REQ-AUD-07). |
| `api_keys` | A11 | true | Hash plus non-secret prefix (REQ-API-06). |
| `api_key_scopes` | A11 | true | Immutable child rows. Entity-base exempt. |
| `push_subscriptions` | A09 | true | Partially exempt; browser-driven lifecycle. |
| `notification_preferences` | A12 | true | Per category, per channel (REQ-PWA-06). |
| `notification_events` | A12 | true | Fan-out and delivery state. |
| `mail_outbox` | A12 | true | Queue row. Partially exempt. |
| `mail_templates` | A12 | true | Per-tenant overrides of the global set. |
| `canonical_*` | A10 | true | The canonical models resolved at intake (REQ-DAT-01). |
| `mapping_descriptors` | A10 | true | Versioned declarative mappings (REQ-DAT-03). |
| `quarantine` | A10 | true | Unmappable input with a reason (REQ-DAT-06). Partially exempt. |
| `provenance` | A10 | true | Immutable evidence of one run (REQ-DAT-05). Entity-base exempt. |
| `collector_agents` | A15 | true | First-class audited entity (REQ-OBS-04). Not exempt. |
| `agent_credentials` | A15 | true | Short-lived mTLS credentials (REQ-OBS-02). |
| `user_grid_prefs` | A07 | true | Per user, per grid key (REQ-GRD-08). `comment` exempt. |
| `user_preferences` | A05 | true | Theme, locale, timezone, format (REQ-TIM-05). `comment` exempt. |
| `help_topics` | A16 | false | Global content, filtered by permission at read time (REQ-DOC-04). |

`notification_events` and `notification_preferences` are A12's;
`push_subscriptions` is A09's. `contracts/ownership.md` states the split
explicitly, and it is the reason the notification contract has two publishers.

Every "exempt" note above points at `contracts/types/entity-base.md` §6, which
is the only place exemptions are enumerated and justified (REQ-ENT-01). This
column is a pointer, not a second list.

## 2. Migration namespace

```
db/migrations/<agent-id>/<timestamp>__<slug>.sql
db/migrations/A03/20261015T081200Z__create_sessions.sql
db/migrations/A11/20261015T081200Z__create_api_keys.sql
```

| Part | Rule |
|------|------|
| `<agent-id>` | `A03`, `A11`, … The owning agent, from §1. One directory per agent. |
| `<timestamp>` | `YYYYMMDDTHHMMSSZ`, UTC, generated at write time (REQ-TIM-03). |
| `<slug>` | `snake_case`, imperative: `create_api_keys`, `add_last_used_at`. |

Why the namespace exists: **two agents can never produce a conflicting
ordinal.** Thirteen agents run at the same moment in Wave 3. A single
`migrations/0042__*.sql` sequence would mean thirteen agents racing for `0043`,
and the loser's file either collides or silently reorders someone else's DDL.
With one directory per agent, two agents writing at the same second produce two
files that cannot conflict, because neither is in the other's directory.

Ordering across agents is by timestamp, then by agent id as a tiebreak, and it
is resolved by the runner — not by a filename ordinal. Rules that make that
safe:

- A migration touches only tables its agent owns (§1). The one exception is
  A04's policy migrations, which `ENABLE`/`FORCE` RLS and `CREATE POLICY` on
  tables it does not own, and touch no column (`rls-contract.md` §1).
- A migration never depends on another agent's migration having run. A foreign
  key to another agent's table is declared `NOT VALID` and validated in a later
  migration, or the reference is a plain `uuid` with the join enforced in the
  DAL. An agent that needs another agent's table to exist first has found a
  missing contract member, not an ordering problem.
- Migrations are forward-only. A mistake is corrected by a new migration.
- Every migration is idempotent-safe to re-run against a fresh database and is
  applied in a transaction. `CREATE INDEX CONCURRENTLY` is the one statement
  allowed outside a transaction, in its own file.

## 3. The `tenantScoped` declaration

```ts
// packages/audit/contract.declaration.ts
tables: [
  { name: "audit_events", tenantScoped: true, appendOnly: true },
  { name: "audit_chain",  tenantScoped: true, appendOnly: true },
  { name: "log_sinks",    tenantScoped: true },
],
```

- `tenantScoped: true` means the table carries `tenant_id uuid NOT NULL` and
  A04 generates its RLS policy. It is not optional metadata — it is the input to
  the isolation boundary (REQ-RBA-03, REQ-RBA-04).
- `tenantScoped: false` is a deliberate, reviewed statement that the table holds
  no tenant data. There are three in this build: `tenants`, `permissions`,
  `help_topics`. Adding a fourth is a CCR with a justification.
- `appendOnly: true` selects the append-only policy template
  (`rls-contract.md` §5) and asserts the app role holds no `UPDATE`/`DELETE`
  grant (REQ-AUD-03).
- The declaration is the frozen worklist A04 builds from
  (`pnpm contracts:tables --tenant-scoped`). A table that appears after G3
  arrives as an additive CCR and A04 regenerates its policies.

## 4. Migration lint rules (REQ-ENT-03)

`pnpm db:lint` walks every `db/migrations/<agent-id>/` tree and every
declaration. It fails the build; it is not advisory.

| Rule | Failure | Fix |
|------|---------|-----|
| Entity base present or exempt | `MISSING ENVELOPE  mail_templates (A12)` | Add the DDL fragment from `entity-base.md` §3, or add an exemption row with a justification to §6 (a CCR). |
| Exemption justified | `EMPTY JUSTIFICATION  quarantine` | An exemption row with an empty justification is a rejected CCR. |
| Table has an owner | `UNOWNED TABLE  widget_cache` | Declare it in the owning agent's `tables[]`, and in `contracts/ownership.md`. |
| Table is in its owner's directory | `WRONG NAMESPACE  A12 created api_keys (owner A11)` | The migration moves to the owner. Cross-agent DDL is a build defect (REQ-CTR-04). |
| `tenant_id` present when `tenantScoped` | `MISSING TENANT COLUMN  log_sinks` | Add `tenant_id uuid NOT NULL`. A04 fails its own run rather than fixing another agent's migration. |
| RLS enabled and forced | `RLS NOT FORCED  mail_outbox` | A04's policy migration is missing; A04's run is incomplete (REQ-RBA-04). |
| Append-only grants | `APPEND-ONLY VIOLATION  audit_events has UPDATE grant` | Revoke it. The trigger is a second line of defence, not the first. |
| Soft-delete index | `MISSING LIVE INDEX  users` | Add the partial index from `entity-base.md` §3 (REQ-ENT-05). |
| Timestamps are `timestamptz` | `NAIVE TIMESTAMP  users.last_seen_at is timestamp` | Every instant column is `timestamptz`, UTC (REQ-TIM-03). `timestamp` without a zone does not ship. |
| Migration filename | `BAD MIGRATION NAME  db/migrations/A07/002_prefs.sql` | Rename to `<timestamp>__<slug>.sql`. |

A deliberate violation of each rule is committed once, proven to fail, and
reverted — a lint nobody has seen fail is a lint nobody knows works.

## 5. Change rules after the G3 freeze

**Additive**
- A new table, declared by its owner, with the envelope and (if tenant-scoped)
  a generated policy. A04 regenerates; no other agent changes.
- A new nullable column on the owner's own table.
- A new index, a new check constraint that the existing data satisfies.
- A new exemption row in `entity-base.md` §6 with a justification.

**Breaking — needs orchestrator arbitration (REQ-CTR-03)**
- Moving a table between agents. The migration directory, the declaration, the
  ownership map and the route subtree all move together.
- Flipping `tenantScoped` on a shipped table. `false → true` needs a backfill of
  `tenant_id`; `true → false` is a deliberate widening of visibility and the
  default answer is no.
- Making a nullable column `NOT NULL`, narrowing a type, or renaming a column.
- Dropping a table, a column or an index. Not possible before a deprecation
  window has elapsed (`contracts/README.md` §4).
