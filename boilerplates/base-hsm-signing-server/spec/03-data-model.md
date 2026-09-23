# Data model

Owner: `database-architect`. Requirements: `SZ-FUN-002`, `SZ-AUD-001`,
`SZ-HSM-005`. Schema lives in `src/db/schema.ts` (Drizzle); this document is the
reasoning, and the schema is the contract.

## 1. The rule the whole model obeys

**No secret is a column.** PostgreSQL holds application state
(`spec/01-architecture.md` §3). Where something secret must be referenced, the
database holds a *handle* to it:

| Secret | What the database holds |
|--------|------------------------|
| Private signing key | Key id, label, HSM serial, mechanism, public key, certificate |
| HSM PIN | Nothing |
| DKEK share | A ceremony record and a share *fingerprint* |
| Wrapped key backup | Location, KCV, metadata — never the blob's plaintext |
| Session | An opaque id; the secret is in the cookie, not the row |
| TOTP seed | Encrypted under a key held outside the database |
| Passkey | The public credential only, which is the whole point of WebAuthn |

A reviewer should be able to check this by reading column names.

## 2. Entity groups

**Identity** — `users`, `identities` (one per authentication method, so a user
can hold a password, a passkey and an OIDC subject without three user rows),
`sessions`, `webauthn_credentials`, `totp_metadata`, `recovery_codes` (hashed),
`roles`, `capabilities`, `oidc_issuers`, `api_identities`.

*Decision:* identity is separate from user because an OIDC subject changing
tenant must not silently become a different person, and a passkey being revoked
must not delete the account.

**Authorization** — `signing_profiles`, `policies`, `policy_versions`,
`key_tags`, `user_tags`.

*Decision:* policies are **versioned and immutable**. A signing request records
the `policy_version_id` it was evaluated against, so "why was this allowed" is
answerable a year later, after the policy has changed. A mutable policy row makes
every historical decision unexplainable.

**Signing** — `signing_requests`, `request_bindings` (digest, repo, ref,
workload identity, expiry), `approvals`, `artifacts`, `signatures`.

*Decision:* the binding is its own table and is **written once**. An `UPDATE` on
a binding would be an approval laundering primitive, so the table has no update
path and the application has no code that would use one.

**Keys and devices** — `key_metadata`, `certificates`, `hsm_devices` (keyed by
**serial**, never by slot index — `SZ-HSM-005`), `key_domains`,
`dkek_ceremonies`, `wrapped_backups`.

**Operations** — `audit_events`, `audit_checkpoints`, `push_subscriptions`,
`system_config_revisions`, `backup_records`.

*Decision:* `system_config_revisions` rather than a config table with updates.
An appliance whose configuration has no history cannot answer "when did egress
get opened", which is the first question after an incident.

## 3. Audit storage (`SZ-AUD-001`)

`audit_events` is **append-only, enforced at the database**: no `UPDATE` or
`DELETE` grant for the application role, and a trigger that rejects both. The
application being compromised is the case this protects against, so application
-level discipline is not the control.

Each row carries `prev_hash` and `hash`, where the hash covers the canonical
serialisation of the event *and* `prev_hash`. `audit_checkpoints` periodically
records a signed head, so verification does not require replaying the whole chain
and a truncation is detectable rather than merely suspected.

Detail that matters: **the chain is per-appliance, not per-table**, and the
canonical serialisation is a frozen contract. A field-ordering change would
invalidate every historical hash, so the serialisation belongs in
`contracts/ownership.md` and changing it requires contract review.

## 4. Retention and deletion

Signing requests, approvals and audit events are **retained, not deleted**. A
signature is a permanent claim about the world; the record of why it exists
outlives the artefact.

Where personal data must be removable, identity rows are **pseudonymised** —
the user row is redacted, the identity link kept — so the audit chain stays
intact and still answers "a distinct person approved this" without naming them.
Deleting the row would break the hash chain and destroy the evidence for every
other signature that person approved.

## 5. Migrations

Forward-only, reviewed as contracts. A migration that would drop or retype a
column carrying audit or binding data is refused; the pattern is add, backfill,
switch, and remove in a later release once nothing reads the old column.

Restore compatibility (`spec/18-backup-restore.md` §6) means the schema version
is recorded in every backup and the migration chain runs forward from whatever a
backup contains.
