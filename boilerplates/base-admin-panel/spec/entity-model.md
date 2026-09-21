# Entity Model — the Base Envelope, Soft Delete and the Data-Access Layer

Every table in the app carries the same seven-column envelope, or it is on an
enumerated exemption list with a written reason. The envelope itself is
published by **A02** (`contract-steward`) in `packages/contracts/entity-base.ts`
and registered in `contracts/types/entity-base.md`, which is the normative
document — types, Zod, DDL fragment, exemption rows and change rules live there
and are not repeated here. This spec is the design around it: why the types are
what they are, what qualifies a table for exemption, how the data-access layer
makes actor columns unforgeable, and how CI catches the table that skipped it.
**Every table owner** — A03, A04, A07, A09, A10, A11, A12, A13, A15, A16 — is a
co-owner of this domain: A02 owns the envelope, each agent owns its compliance.

## Requirements covered

REQ-ENT-01 … REQ-ENT-05, REQ-TIM-03, REQ-AUD-01, REQ-AUD-04, REQ-RBA-03,
REQ-RBA-06, REQ-CTR-03, REQ-CTR-08, REQ-TST-01.

## 1. Why these Postgres types

The column list and the verbatim DDL block are in
`contracts/types/entity-base.md` §1 and §3. The type choices, and what each one
rules out:

| Column | Type | Ruled out | Why |
|---|---|---|---|
| `comment` | `text` | `varchar(n)` | Postgres stores them identically; a length cap belongs in one place, and that place is the schema's `CHECK` plus the Zod cap of 2000 |
| `created_at` | `timestamptz` | `timestamp` | `timestamp` has no zone, so it is a local time with the zone thrown away. UTC storage is REQ-TIM-03 and `timestamptz` is the only type that keeps the instant unambiguous across the CET/CEST transitions (`spec/time.md` §2) |
| `created_by` | `uuid` | `text`, or an FK to `users` | 16 bytes, comparable, and no parsing. **No foreign key**, deliberately — see §2 |
| `updated_at` / `updated_by` | `timestamptz` / `uuid`, nullable | `NOT NULL DEFAULT created_*` | Null means "never updated". Copying `created_at` into `updated_at` destroys that distinction and makes every row look touched |
| `deleted_at` / `deleted_by` | `timestamptz` / `uuid`, nullable | a `deleted boolean` | A boolean cannot answer when or by whom, and REQ-AUD-04 requires both |

Two additions to what the DDL fragment already states, both enforced by lint:

```sql
ALTER TABLE <table> ADD CONSTRAINT <table>_comment_len_chk
  CHECK (comment IS NULL OR length(comment) <= 2000);

-- Natural-key uniqueness is partial, or soft delete blocks re-creation.
CREATE UNIQUE INDEX <table>_<key>_uq ON <table> (tenant_id, <key>)
  WHERE deleted_at IS NULL;
```

A full unique index means a soft-deleted row keeps occupying its natural key
forever: delete `device "fw-01"`, try to create `device "fw-01"`, get a
constraint violation naming a row the user cannot see. Every unique constraint
on a soft-deletable table is partial on `deleted_at IS NULL`, and a non-partial
one fails migration lint unless the declaration marks the key as
`uniqueAcrossDeleted: true` with a reason.

`created_at` has `DEFAULT now()` as a safety net, but the DAL passes an explicit
value: one clock read per request, so every row a multi-table write touches
carries the same instant and the audit event correlates to them exactly.

## 2. No foreign key on the actor columns

An actor is a `user`, an `api_key`, a `collector` or `system`
(`contracts/types/identity.md` §2). There is no single table all four live in,
so there is no column to point a foreign key at. We do not invent a superclass
table to satisfy a constraint, and we do not narrow the actor columns to human
users — an API key writing a row is normal and must be attributable.

What replaces referential integrity:

- The DAL only ever writes `actor.id`, which came from a resolved session or a
  resolved key. A dangling value has no path in.
- A13's audit event carries an `ActorRef` **snapshot** — id, kind and label at
  the time of the write — so the row's history is readable after the actor is
  deleted, renamed or revoked.
- Migration lint fails on a foreign key declared on `created_by`, `updated_by`
  or `deleted_by`. A well-meaning `REFERENCES users(id)` breaks every
  API-key-authored insert at runtime, and it breaks it in production, not in
  the test that used a human fixture.

## 3. Exemptions, by class (REQ-ENT-01)

REQ-ENT-01 requires exemptions to be enumerated and justified. The rows are in
`contracts/types/entity-base.md` §6 — table, owner, exempt columns,
justification. This section is the rule that decides whether a new request for
an exemption is granted, so the answer is not re-argued per table.

| Class | Qualifying test | Exempt columns | Tables |
|---|---|---|---|
| **Append-only** | No `UPDATE` or `DELETE` grant exists for the app role, enforced by privilege and trigger (REQ-AUD-03) | all seven | `audit_events`, `audit_chain`, `provenance` |
| **Pure join** | Only foreign keys and no attributes of its own; the audited entity is a parent | all seven | `role_permissions`, `api_key_scopes` |
| **Machine-written** | Written by a process with no human actor — browser lifecycle, queue worker, normalization engine | the actor columns it cannot fill | `push_subscriptions`, `mail_outbox`, `quarantine` |
| **Insert/soft-delete only** | The row is created and revoked, never edited | `updated_*` | `user_roles` |
| **UI state** | Per-user presentation preference with no audit interest | `comment` | `user_grid_prefs`, `user_preferences` |
| **Migration bookkeeping** | Written by the migration runner before the app role exists | all seven | `schema_migrations` (A01) |

Class-level justifications, once, instead of per table:

- **Append-only** rows cannot carry `updated_*`/`deleted_*` that would be
  permanently null, and a soft-delete column on an audit table is an invitation
  to hide a row. The append-only guarantee is the stronger property.
- **Pure join** rows have no independent lifecycle. The diff that matters is the
  parent's (`spec/rbac-tenancy.md` §9), and duplicating it on the join row
  produces two records of one decision that can disagree.
- **Machine-written** tables keep every column they can fill. `mail_outbox`
  keeps `created_*` and `updated_*` and loses `deleted_*` because a queue row
  leaves by retention purge, not by a user's delete.
- **Migration bookkeeping** predates the DAL. `schema_migrations` is written by
  the runner as `app_owner`, before the app role exists, so a DAL-set actor
  column is impossible there. It is A01's table and it is the one class member
  with no row yet in the register — the row is filed as an additive CCR at the
  freeze, because the table is created before the register is assembled.

`ENTITY_BASE_EXEMPTIONS` in `packages/contracts/entity-base.ts` is the
machine-readable form, and `contracts/types/entity-base.md` §6 is its register.
CI asserts the two agree row for row — a table exempted in the doc but not in
the constant would pass review and fail isolation, and the reverse would exempt
a table silently. A new exemption is an additive CCR with the class named and a
non-empty justification; an empty justification is a rejected CCR.

## 4. One data-access layer sets the actor columns (REQ-ENT-04)

The write schema `EntityWriteEnvelopeSchema` contains `comment` and nothing
else. There is no argument a caller could put an actor into:

```ts
// packages/contracts/dal.ts (A02) — the only writer of the envelope
type EnvelopeColumns =
  | "createdAt" | "createdBy" | "updatedAt" | "updatedBy"
  | "deletedAt" | "deletedBy";

export function insert<T extends TableName>(
  table: T, values: Omit<Insertable<T>, EnvelopeColumns>
): Promise<Row<T>>;
```

Four layers, so forgetting one is not enough to forge an actor:

1. **Types.** `Omit<…, EnvelopeColumns>` makes the field a compile error.
2. **Ambient context.** The actor comes from an `AsyncLocalStorage` request
   context, not a parameter. There is no call signature that accepts one. A
   write outside a request context (a job) runs under the `system` actor set
   explicitly at the job boundary, and a write with no context at all throws
   rather than defaulting.
3. **Runtime strip.** Any envelope key present on the input object raises
   `common.validation_failed` instead of being dropped, so a client learns its
   payload is wrong rather than being silently ignored.
4. **API boundary.** The route kit rejects unknown fields before the handler,
   because every request schema is `.strict()` (`spec/api.md` §2).

Under impersonation the columns hold the **impersonating** operator's actor id;
the impersonated subject lives in the audit event's on-behalf-of field
(`contracts/types/identity.md` §6). The row records who acted. The trail records
on whose behalf.

`db.transaction()` propagates the same context, so a nested write cannot escape
into a different actor. A route handler that reaches Postgres through anything
other than the DAL fails `pnpm lint:boundaries`: the raw client is exported only
to `packages/contracts` and `db/`.

## 5. Migration lint (REQ-ENT-03)

`pnpm lint:migrations` runs on every commit and in CI. It parses the SQL with
the Postgres parser pinned in `versions/manifest.json` — not with regular
expressions, because a regex cannot tell a `CREATE TABLE` from the same text
inside a comment or a string literal.

| Check | Fails when |
|---|---|
| Envelope present | A `CREATE TABLE` lacks any envelope column and the table is not in `ENTITY_BASE_EXEMPTIONS` |
| Exemption justified | An exemption entry has an empty or whitespace justification |
| Doc and code agree | `ENTITY_BASE_EXEMPTIONS` and `contracts/types/entity-base.md` §6 differ |
| Pair constraints | The `*_delete_pair_chk` / `*_update_pair_chk` constraints are missing |
| Comment cap | `*_comment_len_chk` is missing on a non-exempt table |
| No actor FK | A foreign key is declared on `created_by`, `updated_by` or `deleted_by` (§2) |
| Partial uniqueness | A unique index on a soft-deletable table is not partial on `deleted_at IS NULL` and not waived (§1) |
| Live index | A tenant-scoped table lacks its `<table>_live_idx` partial index |
| Tenancy declared | A table has `tenant_id` but no `tenantScoped: true` declaration, or the reverse |
| No envelope drop | An `ALTER TABLE … DROP COLUMN` targets an envelope column |
| Ownership | A migration sits outside `db/migrations/<its own agent-id>/` (REQ-CTR-04) |

The lint reads the table list from the assembled contract, so a table that
exists in a migration but in no declaration fails too. Convention would have
caught none of these; REQ-ENT-03 exists because the envelope is worth exactly as
much as its weakest table.

## 6. Soft delete, restore, purge (REQ-ENT-02, REQ-ENT-05)

Delete is soft by default: `deleted_at`/`deleted_by` are stamped in one
statement and the row stays. Every list and detail read appends
`deleted_at IS NULL` — added by the DAL, not by the caller's predicate.

| Operation | Permission | Step-up | Audit event |
|---|---|---|---|
| Soft delete | `<domain>.<resource>.delete` | — | `<domain>.<resource>.delete` |
| Read including deleted | `global.deleted-record.read` | — | the read event, with `includeDeleted: true` |
| Restore | `<domain>.<resource>.restore` | — | `<domain>.<resource>.restore` |
| Hard delete | `global.record.purge` | 60 s | `<domain>.<resource>.purge`, `severity: critical` |

`global.record.purge` is global-tier only and held by `superadmin` alone. No
tenant role can hold it (`spec/rbac-tenancy.md` §3), because a tenant admin who
can purge can remove the evidence of what they did. Three properties of purge:

- The audit event is written **before** the delete, in the same transaction, and
  carries the full redacted row snapshot. After a purge there is no row left to
  point at, so an event holding only an id documents nothing.
- No foreign key uses `ON DELETE CASCADE`. A purge declares its dependents in
  the table's contract entry and deletes them explicitly; an undeclared
  dependent makes the purge fail on the foreign key rather than silently orphan
  or silently widen.
- `audit_events` is never purgeable. Retention and legal hold are A13's
  (REQ-AUD-13), not this permission's.

Lifting the filter is a single shared query parameter, `includeDeleted=true`
(`contracts/types/pagination.md` §2), so the grid, the API and the DAL agree on
one spelling. Without the permission the parameter is a 403, not a silent
downgrade to the filtered result — a caller that thinks it sees deleted rows and
does not is worse than a refusal.

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Envelope columns | The seven in `contracts/types/entity-base.md` | REQ-ENT-01 | No |
| Timestamps | `timestamptz`, UTC | REQ-TIM-03; `timestamp` loses the instant | No |
| Actor columns | `uuid`, no foreign key | An actor may be a key, a collector or the system | No |
| `updated_at` initial value | Null, not a copy of `created_at` | Null means never updated | No |
| Unique keys on soft-deletable tables | Partial on `deleted_at IS NULL` | A deleted row must not hold its name hostage | No |
| Exemption model | Six classes, table rows in the contract doc | REQ-ENT-01 enumerated and justified | No |
| Exemption source of truth | `ENTITY_BASE_EXEMPTIONS`, doc asserted equal in CI | Two lists drift; one list plus an equality check does not | No |
| Actor provenance | Ambient request context, four layers | REQ-ENT-04 — no parameter to forge | No |
| Delete semantics | Soft by default | REQ-ENT-02 | No |
| Purge holder | `superadmin` only, step-up 60 s | Purge removes the evidence | No |
| `ON DELETE CASCADE` | Never — declared purge plans | A cascade is an unreviewed delete | No |
| Purge audit | Full redacted snapshot, written first | Nothing survives to reference | No |
| Deleted-row visibility | `includeDeleted=true` + permission, else 403 | A silent downgrade misleads the caller | No |

## How this is verified

- `pnpm lint:migrations` — the eleven checks in §5, against every file in
  `db/migrations/**`. This is the REQ-ENT-03 test.
- `pnpm test:integration` — `tests/integration/entity/**`: an insert with
  `createdBy` in the payload returns `common.validation_failed`; the DAL fills
  the actor columns from the session; an impersonated write records the
  operator; a write with no ambient context throws; soft delete then re-create
  of the same natural key succeeds; restore round-trips.
- `pnpm test:permissions` — a list read without
  `global.deleted-record.read` never returns a `deleted_at`-stamped row, per
  table; `includeDeleted=true` without the permission is 403; purge without
  `global.record.purge` is 403 and with it demands step-up.
- `pnpm test:audit` — `tests/audit-emission/**`: delete, restore and purge each
  emit their event; the purge event contains the redacted snapshot and is
  ordered before the delete in the chain (REQ-AUD-06).
- `pnpm test:contract` — `packages/contracts/tests/entity-base.spec.ts`: every
  declared write schema is free of envelope fields; `ENTITY_BASE_EXEMPTIONS`
  matches the register; every non-exempt declared table composes
  `withEntityBase` (REQ-CTR-10).
- `GET /api/v1/<domain>/_selftest` — each owner asserts its own tables carry the
  envelope and its exemptions are listed (REQ-CTR-08).

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| Soft or hard delete as the product default | Soft, with restore exposed in the UI |
| Who may purge | `superadmin` only |
| Is purge exposed in the UI at all | Yes, on the detail view of a deleted row, behind step-up |
| Retention before automatic purge of soft-deleted rows | None — soft-deleted rows are kept until purged deliberately |
| `comment` required on destructive writes | Required on delete, restore and purge; optional elsewhere |
| Are deleted rows visible to tenant admins | No — `global.deleted-record.read` is global-tier |
