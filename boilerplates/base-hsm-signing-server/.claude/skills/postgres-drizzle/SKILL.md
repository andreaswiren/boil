---
name: postgres-drizzle
description: PostgreSQL and Drizzle schemas, migrations, indexes, transactions, row locking and retention for the appliance. Load for any persistence change.
---

# Postgres and Drizzle

Design: `spec/03-data-model.md`.

## The rule a reviewer can check by reading column names

**No secret is a column.** The database holds application state; where something
secret must be referenced, it holds a *handle* — key id and HSM serial, not a
key; a ceremony record and a share fingerprint, not a share; a public credential,
not a passkey.

## Append-only means the database enforces it

`audit_events` has **no `UPDATE` or `DELETE` grant** for the application role,
plus a trigger rejecting both. The application being compromised is the case this
defends against, so application discipline is not the control
(`SZ-AUD-001`).

## Immutability where it is load-bearing

- **Policies are versioned and immutable.** A request records the
  `policy_version_id` it was evaluated against, so decisions stay explainable
  after the policy changes.
- **Request bindings are written once.** No update path, and no application code
  that would use one — an `UPDATE` on a binding is an approval-laundering
  primitive.
- **Config is revisions, not a mutable row.** "When did egress get opened" is the
  first question after an incident.

## Transactions and locking

A signing request transitioning state takes a row lock; two approvals arriving
together must not both succeed into a single-approval profile. Use explicit
locking rather than optimistic retry in the signing path — a retry that succeeds
twice is a second signature.

## Migrations

Forward-only, reviewed as contracts. Never drop or retype a column carrying audit
or binding data: add, backfill, switch, remove in a later release.

Restore compatibility means every backup records its schema version and the
migration chain runs forward from whatever it finds
(`spec/18-backup-restore.md` §6).

## Retention

Signing requests, approvals and audit events are **retained, not deleted**. For
personal-data removal, **pseudonymise** the identity — deleting rows breaks the
audit hash chain and destroys evidence for every other signature that person
approved.

## Definition of done

- [ ] No secret-bearing column; verified by reading the schema.
- [ ] `UPDATE`/`DELETE` on audit events fails at the database.
- [ ] Concurrent approvals cannot over-approve a profile.
- [ ] A migration dropping binding or audit data is refused in review.
