# `entity-base` — the base envelope

**Published by:** A02. **Requirements:** REQ-ENT-01 … REQ-ENT-05, REQ-TIM-03.
**Consumed by:** every agent that owns a table.

This file is the document REQ-ENT-01 points at: the exemption list is
enumerated and justified here, and nowhere else. A table that is neither
compliant nor listed below fails migration lint (REQ-ENT-03).

---

## 1. The envelope

| Column | Type | Null | Set by | Meaning |
|--------|------|------|--------|---------|
| `comment` | `text` | yes | caller | Free-text reason for the last write. Copied into the audit event. |
| `created_at` | `timestamptz` | no | DAL | UTC instant of insert. |
| `created_by` | `uuid` | no | DAL | Actor id from the request context. |
| `updated_at` | `timestamptz` | yes | DAL | UTC instant of last update. Null until first update. |
| `updated_by` | `uuid` | yes | DAL | Actor id of last update. |
| `deleted_at` | `timestamptz` | yes | DAL | Soft-delete marker (REQ-ENT-02). Null means live. |
| `deleted_by` | `uuid` | yes | DAL | Actor id that soft-deleted. |

`comment` is the only member a caller may write. It is the audited-comment
field carried by every write operation in the OpenAPI document
(`contracts/openapi/conventions.md` §5).

All four timestamps are UTC `timestamptz` in storage and RFC 3339 with a `Z`
offset on the wire. They are never formatted by a domain package. Rendering
goes through `packages/contracts/time` only — `Europe/Stockholm` default,
`YYYY-MM-DD HH:mm:ss` (REQ-TIM-01, REQ-TIM-02, REQ-TIM-04).

## 2. Zod

```ts
// packages/contracts/entity-base.ts
import { z } from "zod";

export const ActorIdSchema = z.string().uuid();
export const UtcInstantSchema = z.string().datetime({ offset: false });

/** What a reader gets back. Every field is server-derived except `comment`. */
export const EntityBaseSchema = z.object({
  comment: z.string().max(2000).nullable(),
  createdAt: UtcInstantSchema,
  createdBy: ActorIdSchema,
  updatedAt: UtcInstantSchema.nullable(),
  updatedBy: ActorIdSchema.nullable(),
  deletedAt: UtcInstantSchema.nullable(),
  deletedBy: ActorIdSchema.nullable(),
});

/** What a writer may send. Actor and timestamp columns are absent by design. */
export const EntityWriteEnvelopeSchema = z.object({
  comment: z.string().max(2000).optional(),
});

/** Compose an entity read model. */
export const withEntityBase = <T extends z.ZodRawShape>(shape: T) =>
  z.object(shape).merge(EntityBaseSchema);

export type EntityBase = z.infer<typeof EntityBaseSchema>;
export type EntityWriteEnvelope = z.infer<typeof EntityWriteEnvelopeSchema>;
```

A write schema that declares `createdBy`, `updatedBy`, `deletedBy`,
`createdAt`, `updatedAt` or `deletedAt` as an input is a contract violation and
the assembly step rejects the declaration.

## 3. Postgres DDL fragment

Every owned table ends with this block verbatim. Lint matches on it.

```sql
-- entity-base (REQ-ENT-01). Do not reorder, do not rename.
  comment      text,
  created_at   timestamptz  NOT NULL DEFAULT now(),
  created_by   uuid         NOT NULL,
  updated_at   timestamptz,
  updated_by   uuid,
  deleted_at   timestamptz,
  deleted_by   uuid
);

-- Soft-delete read path (REQ-ENT-05): one partial index per table.
CREATE INDEX <table>_live_idx ON <table> (tenant_id) WHERE deleted_at IS NULL;

-- Consistency: a delete marker is never half-written.
ALTER TABLE <table> ADD CONSTRAINT <table>_delete_pair_chk
  CHECK ((deleted_at IS NULL) = (deleted_by IS NULL));
ALTER TABLE <table> ADD CONSTRAINT <table>_update_pair_chk
  CHECK ((updated_at IS NULL) = (updated_by IS NULL));
```

## 4. Actor columns come from the data-access layer (REQ-ENT-04)

One rule, no exceptions:

- `created_by` / `updated_by` / `deleted_by` are written by
  `packages/contracts`-typed DAL helpers from the request's `Actor`, resolved
  from the session (`contracts/types/identity.md`).
- The DAL takes the actor from an ambient request context, not from an
  argument, so a caller has no place to put a forged value.
- Under impersonation the columns hold the **impersonating** operator's actor
  id. The impersonated subject is preserved in the audit event's on-behalf-of
  field, not in the row (`contracts/events/audit-event.md` §1).
- A route handler that sets an actor column directly fails the
  import-boundary + DAL lint. The API rejects the field before that with
  `common.validation_failed` (`contracts/types/errors.md`).

## 5. Soft delete and reads (REQ-ENT-02, REQ-ENT-05)

- Every list and detail read appends `deleted_at IS NULL`. The DAL adds it; a
  hand-written predicate does not opt out.
- Including deleted rows requires `global.deleted-record.read` and is expressed
  as the shared query param `includeDeleted=true`
  (`contracts/types/pagination.md` §2).
- Hard delete is `global.record.purge`, global-tier only, step-up required, and
  emits its own audit event `<domain>.<resource>.purge`.
- Restore is `<domain>.<resource>.restore`; it clears `deleted_at`/`deleted_by`
  and emits `<domain>.<resource>.restore`.

## 6. Enumerated exemptions (REQ-ENT-01)

A table appears here or it carries the envelope. Nothing else is accepted.

| Table | Owner | Exempt columns | Justification |
|-------|-------|----------------|---------------|
| `audit_events` | A13 | all seven | Append-only (REQ-AUD-03). No `UPDATE`/`DELETE` grant exists, so `updated_*`/`deleted_*` would be permanently null and `comment` is already a first-class envelope field. The event carries its own actor and timestamp. |
| `audit_chain` | A13 | all seven | Hash-chain heads (REQ-AUD-06). Machine-derived, append-only, no actor. |
| `role_permissions` | A04 | all seven | Pure join table. The audited entity is `roles`; the diff lives on the role version (REQ-RBA-08). |
| `user_roles` | A04 | `comment`, `updated_*` | Grant/revoke is insert/soft-delete, never update. `comment` is carried on the assignment audit event instead. Keeps `created_*` and `deleted_*`. |
| `api_key_scopes` | A11 | all seven | Immutable child rows of `api_keys`. A scope change mints a new key (REQ-API-06). |
| `push_subscriptions` | A09 | `comment`, `updated_by` | Written by the browser's subscription lifecycle, not by an operator. `updated_at` is kept for expiry pruning. |
| `mail_outbox` | A12 | `comment`, `deleted_*` | Queue row. Terminal states are `sent`/`dead`; rows leave by retention purge, not soft delete. |
| `provenance` | A10 | all seven | Immutable evidence of one normalisation run (REQ-DAT-05). Mutating it would destroy the thing it proves. |
| `quarantine` | A10 | `updated_by`, `deleted_by` | Written by the engine, which has no human actor. Retains timestamps for retry and retention. |
| `user_grid_prefs` | A07 | `comment` | Per-user UI state (REQ-GRD-08). A reason-for-change note on a column width is noise in the audit trail. |
| `user_preferences` | A05 | `comment` | Same reason. |
| `collector_agents` | A15 | — | **Not exempt.** Listed to make the answer explicit: agent lifecycle is audited as a first-class entity (REQ-OBS-04). |

Adding a row to this table is an additive CCR and requires the justification
column to be filled. An empty justification is a rejected CCR.

## 7. Change rules after the G3 freeze

**Additive**
- A new exemption row with a justification.
- A new *nullable* column on top of the envelope for one table (owner's own
  migration, not a change to this envelope).
- A widened `comment` length cap.

**Breaking — needs orchestrator arbitration (REQ-CTR-03)**
- Adding an eighth envelope column: every table's DDL and every read schema
  changes at once.
- Making `comment` `NOT NULL`, or narrowing its cap.
- Removing an exemption row (the table's owner must migrate first; the removal
  is the second step, after the deprecation window).
- Turning soft delete into hard delete for any table.
