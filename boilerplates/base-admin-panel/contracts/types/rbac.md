# `rbac` — permission strings, roles, the global tier

**Published by:** A04 (the grammar, `Role`, `PermissionSet`, the `global.*`
namespace). Assembled by A02 from every domain's declared strings.
**Requirements:** REQ-RBA-01, REQ-RBA-02, REQ-RBA-06, REQ-RBA-08, REQ-AUT-07,
REQ-ENT-02, REQ-ENT-05, REQ-I18N-05.
**Consumed by:** every agent. A domain declares its own strings; nobody else
adds to another domain's namespace.

A permission string not in the assembled registry resolves to **deny**, never to
"unknown, allow" (REQ-RBA-02). This file is the registry of record.

---

## 1. The grammar (REQ-RBA-01)

```
permission := <domain> "." <resource> "." <action>
segment    := [a-z][a-z0-9-]*
```

Exactly three segments. Lowercase, digits and `-` only. A compound word uses a
hyphen: `deleted-record`, `recovery-code`, `auth-policy`. **No underscores, no
dots inside a segment, no four-segment strings, no wildcards.** Assembly rejects
anything else:

```bash
jq -r '.declarations[].permissions[]?' build/contract-surface.json \
  | grep -vE '^[a-z0-9-]+\.[a-z0-9-]+\.[a-z0-9-]+$' && echo "MALFORMED PERMISSION STRING"
```

There is no `auth.*` wildcard. A role lists strings. A wildcard would mean that
adding a permission silently widens every role that already holds the prefix —
the exact silent semantic change REQ-CTR-03 forbids.

```ts
// packages/contracts/rbac.ts
import { z } from "zod";

export const PermissionStringSchema = z
  .string()
  .regex(/^[a-z][a-z0-9-]*\.[a-z][a-z0-9-]*\.[a-z][a-z0-9-]*$/)
  .brand<"PermissionString">();

export type PermissionString = z.infer<typeof PermissionStringSchema>;
```

## 2. Action vocabulary

The core verbs are closed. A domain verb is declared with the permission and
appears in this table; a verb that is not here fails review, not assembly —
assembly cannot tell `write` from `wrait`.

| Action | Means |
|--------|-------|
| `list` | Read a collection. Only where listing is separable from reading a row. |
| `read` | Read one resource or the collection when they are gated together. |
| `write` | Create **and** update. We do not split them; no resource in this build grants one without the other. |
| `delete` | Soft delete (REQ-ENT-02). |
| `restore` | Clear the soft-delete marker. |
| `export` | Produce a file. Always audited (REQ-GRD-13). |
| `run` | Execute a bounded operation (export job, diagnostic, self-test). |
| `admin` | Administer the resource's own configuration, not its rows. |

Declared domain verbs: `assign`, `revoke`, `revoke-tenant`, `revoke-any`,
`rotate`, `mint-own`, `read-own`, `revoke-own`, `read-any`, `enrol`, `reset`,
`regenerate`, `link`, `unlink`, `replay`, `retry`, `verify`, `dismiss`, `send`,
`impersonate`, `purge`, `inspect`, `suspend`, `archive`, `create`, `recover`,
`mfa-disable`, `mint-service`, `write-any`.

## 3. The global tier namespace (REQ-RBA-06)

```
global-permission := "global" "." <resource> "." <action>
```

`global` is a reserved domain, not a modifier. A cross-tenant override of a
domain permission compounds the domain into the resource segment, so the string
stays three segments: `global.auth-policy.mfa-disable`, not
`global.auth-policy.mfa-disable`.

Three rules, no exceptions:

1. A `global.*` permission is **never grantable to a tenant role**. Assembly
   fails a tenant role that lists one; `can()` returns false for a
   `tier: "tenant"` actor holding one by data corruption.
2. Every `global.*` check requires step-up on the current session
   (REQ-AUT-07). No global permission is satisfied by a session whose
   `steppedUpAt` is null or stale.
3. A global-tier actor has `tenantId: null` until it enters a tenant
   (`contracts/types/identity.md` §4). Holding `global_admin` implies no tenant
   permission.

## 4. Frozen names that supersede draft declarations

Pre-freeze declarations in `.claude/agents/` used underscores and four
segments. The grammar in §1 is the frozen shape; these are the names that ship.
This table exists so an agent reading its own prompt does not declare a string
assembly will reject.

| Draft string | Declared in | Frozen name | Why it changed |
|--------------|-------------|-------------|----------------|
| `global.impersonation.start` | A04 | `global.impersonation.impersonate` (`identity.md` §1) | The action names what is done, not when it begins. `start` has no matching `stop` — exit is the same permission's lifecycle, audited separately (REQ-RBA-07). |
| `platform.deleted.read` | A02 | `global.deleted-record.read` (`entity-base.md` §5) | There is no `platform` tier. The global tier's namespace is `global.*` (REQ-RBA-06), and the resource is a deleted record, not "deleted". |
| `global.record.hard_delete` | A04 | `global.record.purge` (`entity-base.md` §5) | `hard_delete` describes the implementation; `purge` describes the capability. The distinction matters because soft delete is the default and this is the separate permission that bypasses it (REQ-ENT-02). |
| `global.auth.policy.disable_mfa` | A03 | `global.auth-policy.mfa-disable` | Four segments. The grammar in §1 is exactly three, so the compound resource is hyphenated. |
| `global.auth.session.revoke_any` | A03 | `global.auth-session.revoke-any` | Four segments, same reason. |
| `global.api.key.mint_service` | A11 | `global.api-key.mint-service` | Four segments, same reason. |
| `global.mail.sender_identity.write` | A12 | `global.mail-sender.write` | Four segments, same reason. |

Underscores in an action or resource segment (`read_own`, `revoke_any`,
`recovery_code`, `oidc_provider`, `write_own`) were normalised to hyphens across
the fleet rather than recorded here, because the grammar in §1 admits only
`[a-z][a-z0-9-]*` and a purely mechanical substitution is not a design decision
worth a table row. The rows above are the ones where the *name* changed, not the
punctuation.

## 5. `Role` and `PermissionSet`

```ts
import { withEntityBase } from "./entity-base";
import { GlobalTierSchema } from "./identity";

/** A resolved, flattened grant set. What `can()` evaluates against. */
export const PermissionSetSchema = z.object({
  tier: z.enum(["tenant", "global"]),
  /** Exact strings. Deduplicated at assembly. Evaluation is exact match. */
  granted: z.array(PermissionStringSchema).readonly(),
});

export const RoleSchema = withEntityBase({
  id: z.string().uuid(),
  /** Null for a global-tier role. Tenant roles are tenant-scoped rows. */
  tenantId: z.string().uuid().nullable(),
  key: z.string().regex(/^[a-z][a-z0-9-]{1,62}$/),
  /** i18n keys under `rbac.*` (REQ-I18N-05). Never a literal. */
  nameKey: z.string(),
  descriptionKey: z.string(),
  tier: z.enum(["tenant", "global"]),
  /** Monotonic. A change writes a new version row (REQ-RBA-08). */
  version: z.number().int().positive(),
  /** Built-in roles are not editable; a copy is. */
  builtIn: z.boolean(),
  permissions: z.array(PermissionStringSchema).readonly(),
});

export const RoleVersionSchema = z.object({
  roleId: z.string().uuid(),
  version: z.number().int().positive(),
  /** Redacted per `contracts/events/audit-event.md` §4 before it is stored. */
  diff: z.object({
    added: z.array(PermissionStringSchema).readonly(),
    removed: z.array(PermissionStringSchema).readonly(),
  }),
  changedAt: z.string().datetime({ offset: false }),
  changedBy: z.string().uuid(),
});

export type Role = z.infer<typeof RoleSchema>;
export type PermissionSet = z.infer<typeof PermissionSetSchema>;
```

`changedAt` is UTC `timestamptz` in storage and RFC 3339 `Z` on the wire, like
every timestamp in the contract. It is formatted only at the edge, only by
`packages/contracts/time` (REQ-TIM-04).

A role write emits `rbac.role.write` with the before/after diff (REQ-RBA-08,
`contracts/events/audit-event.md` §2) and requires step-up (REQ-AUT-07).

## 6. The initial permission catalogue

Every string below is in the frozen registry. `Step-up` means the check fails
without a fresh step-up on the session (REQ-AUT-07). Every `global.*` row is
step-up by rule §3.2 and is not repeated per row.

### auth — A03

| Permission | Step-up | Allows |
|------------|---------|--------|
| `auth.session.read` | no | Read own active sessions (REQ-AUT-10). |
| `auth.session.revoke` | no | Revoke own session, including the current one. |
| `auth.session.revoke-tenant` | yes | Revoke any session in the caller's tenant. |
| `auth.mfa.enrol` | no | Enrol an MFA factor for self (REQ-AUT-06). |
| `auth.mfa.reset` | yes | Reset another user's factor in the tenant. |
| `auth.recovery-code.regenerate` | yes | Regenerate own 10 recovery codes. |
| `auth.policy.read` | no | Read the effective tenant auth policy. |
| `auth.policy.write` | yes | Change tenant auth policy, never wider than global (REQ-AUT-04). |
| `auth.oidc-provider.read` | no | Read tenant OIDC provider config, secrets excluded. |
| `auth.oidc-provider.write` | yes | Configure a tenant OIDC provider (REQ-AUT-03). |
| `auth.identity.link` | no | Link a method to own identity (REQ-AUT-09). |
| `auth.identity.unlink` | no | Unlink a redundant method from own identity. |

### rbac — A04

| Permission | Step-up | Allows |
|------------|---------|--------|
| `rbac.role.read` | no | Read tenant roles and their permission sets. |
| `rbac.role.write` | yes | Create or change a tenant role; writes a version row. |
| `rbac.role.assign` | yes | Assign or revoke a role for a tenant user. |
| `rbac.permission.read` | no | Read the permission registry for the role editor. |

### tenancy — A04

| Permission | Step-up | Allows |
|------------|---------|--------|
| `tenancy.tenant.read` | no | Read own tenant's profile and settings. |
| `tenancy.tenant.write` | yes | Change own tenant's profile, locale, timezone, sender identity. |
| `tenancy.member.read` | no | List tenant members. |
| `tenancy.member.invite` | no | Invite a user into the tenant. |
| `tenancy.member.remove` | yes | Remove a member from the tenant (soft delete). |

### grid — A07

| Permission | Step-up | Allows |
|------------|---------|--------|
| `grid.prefs.read` | no | Read own per-grid preferences (REQ-GRD-08). |
| `grid.prefs.write` | no | Persist own per-grid preferences. |
| `grid.export.run` | yes | Run a grid export. Audited with row count, filters, columns (REQ-GRD-13). |

### audit — A13

| Permission | Step-up | Allows |
|------------|---------|--------|
| `audit.event.read` | no | Read the tenant's audit trail. |
| `audit.event.export` | yes | Export the tenant's audit trail (REQ-AUD-13). |
| `audit.chain.verify` | no | Run the hash-chain verify job for the tenant (REQ-AUD-06). |
| `audit.console.read` | no | Open the debug console SSE stream (REQ-AUD-08). |
| `audit.retention.read` | no | Read the tenant's retention settings. |
| `audit.retention.write` | yes | Change retention; cannot shorten under legal hold (REQ-AUD-13). |
| `audit.legal-hold.write` | yes | Set or clear the legal-hold flag. |
| `audit.sink.read` | no | Read syslog sink configuration, credentials excluded (REQ-AUD-07). |
| `audit.sink.write` | yes | Configure a TLS syslog sink. |

### api — A11

| Permission | Step-up | Allows |
|------------|---------|--------|
| `api.docs.read` | no | Open the in-app API docs, filtered to own permissions (REQ-API-02). |
| `api.key.mint-own` | yes | Mint a key bound to self, never exceeding own permissions (REQ-API-04). |
| `api.key.read-own` | no | List own keys by prefix and metadata, never material. |
| `api.key.rotate-own` | yes | Rotate own key; new material shown once (REQ-API-06). |
| `api.key.revoke-own` | no | Revoke own key immediately. |
| `api.key.read-any` | no | List any key in the tenant. |
| `api.key.revoke-any` | yes | Revoke any key in the tenant. |

### mail — A12

| Permission | Step-up | Allows |
|------------|---------|--------|
| `mail.template.read` | no | Read tenant mail templates (REQ-MAIL-03). |
| `mail.template.write` | yes | Edit a tenant mail template. |
| `mail.outbox.read` | no | Read outbox rows and delivery state, addresses masked (REQ-MAIL-04). |
| `mail.outbox.retry` | no | Requeue a dead-lettered message. |
| `mail.sender.write` | yes | Change the tenant sender identity (REQ-MAIL-01). |
| `mail.diagnostic.run` | yes | Test send and connection probe, credentials never returned (REQ-MAIL-06). |

### notify — A12

| Permission | Step-up | Allows |
|------------|---------|--------|
| `notify.category.read` | no | Read the notification category registry, filtered by permission. |
| `notify.preference.read` | no | Read own per-category, per-channel preferences (REQ-PWA-06). |
| `notify.preference.write` | no | Change own preferences and digest option. |
| `notify.notification.read` | no | Read own in-app notifications. |
| `notify.notification.dismiss` | no | Dismiss own in-app notification. |
| `notify.broadcast.send` | yes | Send a tenant-wide operator broadcast. |

### pwa — A09

| Permission | Step-up | Allows |
|------------|---------|--------|
| `pwa.subscription.read` | no | Read own push subscriptions (REQ-PWA-02). |
| `pwa.subscription.write` | no | Register or update own push subscription. |
| `pwa.subscription.revoke` | no | Remove own push subscription. |

### canonical — A10

| Permission | Step-up | Allows |
|------------|---------|--------|
| `canonical.record.read` | no | Read canonical records (REQ-DAT-01). |
| `canonical.descriptor.read` | no | Read mapping descriptors (REQ-DAT-03). |
| `canonical.descriptor.write` | yes | Publish a new descriptor version. |
| `canonical.quarantine.read` | no | Read quarantined input with its reason (REQ-DAT-06). |
| `canonical.quarantine.replay` | no | Replay a quarantined record through the engine. |
| `canonical.provenance.read` | no | Read provenance for a normalised record (REQ-DAT-05). |

### collector — A15

| Permission | Step-up | Allows |
|------------|---------|--------|
| `collector.agent.read` | no | Read agent inventory, heartbeat and version (REQ-OBS-04). |
| `collector.agent.enrol` | yes | Issue an enrolment token for a new agent (REQ-OBS-02). |
| `collector.agent.write` | no | Change an agent's declared, least-privilege config (REQ-OBS-03). |
| `collector.agent.revoke` | yes | Revoke an agent identity immediately. |
| `collector.credential.rotate` | yes | Rotate an agent's short-lived credential. |
| `collector.ingest.write` | n/a | Held only by an actor of kind `collector`. Never grantable to a human role. |

### help — A16

| Permission | Step-up | Allows |
|------------|---------|--------|
| `help.topic.read` | no | Read tenant-visible help topics (REQ-DOC-01). |
| `help.topic.read-global` | no | Read global-tier topics (REQ-DOC-04). |
| `help.topic.admin` | yes | Publish or retire a help topic. |
| `help.architecture.read` | no | Read the architecture chart set (REQ-DOC-05). |

### platform — A02

| Permission | Step-up | Allows |
|------------|---------|--------|
| `platform.contract.read` | no | Read the assembled contract surface index. |
| `platform.selftest.run` | no | Call any domain's `_selftest` route (REQ-CTR-08). |

### global — A04 assembles; every row is step-up and tier `global`

| Permission | Allows |
|------------|--------|
| `global.tenant.create` | Create a tenant (REQ-RBA-06). |
| `global.tenant.suspend` | Suspend a tenant. |
| `global.tenant.archive` | Archive a tenant. |
| `global.tenant.read-any` | Read any tenant's profile across the estate. |
| `global.impersonation.impersonate` | Enter a tenant as a subject: time-boxed, reason-required, audited on entry and exit (REQ-RBA-07). |
| `global.role.write-any` | Write a role in any tenant. |
| `global.deleted-record.read` | See soft-deleted rows via `includeDeleted=true` (REQ-ENT-05). |
| `global.record.purge` | Hard delete. Emits `<domain>.<resource>.purge` (REQ-ENT-02). |
| `global.rls.inspect` | Read RLS state for every declared tenant-scoped table (REQ-RBA-04). |
| `global.auth-policy.mfa-disable` | Disable MFA for a tenant: typed confirmation, audited (REQ-AUT-05). |
| `global.auth-session.revoke-any` | Revoke any session in the estate (REQ-AUT-10). |
| `global.api-key.mint-service` | Mint a service key with an explicit permission set and an owner of record (REQ-API-05). |
| `global.audit.read-any` | Read any tenant's audit trail and console stream. |
| `global.audit-retention.write` | Change retention across tenants; legal hold still blocks purge (REQ-AUD-13). |
| `global.user.recover` | Recover a locked-out account, reason-required and audited. |
| `global.crypto-kek.rotate` | Rotate the KEK for envelope encryption (REQ-SEC-06). |
| `global.collector.read-any` | Read collector inventory across tenants (REQ-OBS-04). |

## 7. Evaluation

- `can(actor, permission, target?)` is deny-by-default and server-side
  (REQ-RBA-02). The client helper is `useVisible(permission)`: it hides UI and
  enforces nothing.
- An API key's effective set is `key.scopes ∩ owner's live permission set`
  (REQ-API-04). A permission the owner has since lost is not held by the key.
- Under impersonation the check runs against the **subject's** set. The
  operator's own set gates only entry (`contracts/types/identity.md` §6).
- A denied check emits an audit event with `result: "denied"` and the
  permission that was demanded, and returns `rbac.permission_denied` — or
  `tenancy.cross_tenant` at 404 when answering would confirm another tenant's
  row (`contracts/types/errors.md` §4).

## 8. Change rules after the G3 freeze

**Additive**
- A new permission string in a domain's own namespace, declared by that domain.
- A new `global.*` permission (A04 declares it; step-up applies by rule).
- A new role, a new role version, a new optional field on `Role`.
- A new declared domain verb, listed in §2 with the permission that uses it.

**Breaking — needs orchestrator arbitration (REQ-CTR-03)**
- Renaming a permission string. Add the new one, grant both, deprecate the old
  with a removal version.
- Widening what a shipped string allows. That is the silent semantic change
  REQ-CTR-03 names as the worst case: new meaning, new string.
- Introducing wildcards, a fourth segment, or underscores into the grammar.
- Moving a permission between the tenant and global tiers.
- Splitting `write` into `create` + `update` for a shipped resource.
