# `identity` — Actor, Session, Tenant, global tier

**Published by:** A03 (`Actor`, `ActorRef`, `Session`, `ImpersonationContext`),
A04 (`Tenant`, `TenantRef`, `GlobalTier`). Assembled by A02.
**Requirements:** REQ-RBA-03, REQ-RBA-06, REQ-RBA-07, REQ-AUT-07, REQ-AUT-10,
REQ-TIM-03.
**Consumed by:** A04, A05, A07, A09, A11, A12, A13, A15, A23.

Everything in this file is **server-derived**. No member of it is ever read
from a request body, query string, header or cookie other than the opaque
session cookie itself.

---

## 1. The rule that outranks the schemas (REQ-RBA-03)

> The tenant comes from the session. Never from a parameter.

| Value | Source | Never from |
|-------|--------|-----------|
| `session.actor.id` | server session store, keyed by the cookie | body, header |
| `session.tenant` | the session row | `?tenantId=`, `X-Tenant-Id`, body, subdomain alone |
| `session.globalTier` | the actor's global-tier grant | anything client-supplied |
| `session.permissions` | resolved server-side from roles at session load | client cache |
| `session.impersonation` | the impersonation grant (REQ-RBA-07) | anything client-supplied |

A route that accepts a tenant identifier is a defect, with two exceptions, both
global-tier and both audited:

1. `global.tenant.*` operations, where the tenant is the *target resource* and
   the caller holds a global-tier permission. The tenant is still not the RLS
   scope — see §5.
2. Tenant entry / impersonation (`global.impersonation.impersonate`), which
   mints a **new session** with the new tenant inside it. The parameter selects
   a session to create; it never widens the current one.

A caller's attempt to read another tenant's resource returns
`tenancy.cross_tenant` mapped to **404**, not 403 — an error body never
confirms that another tenant's row exists
(`contracts/types/errors.md` §4).

## 2. `ActorRef` and `Actor`

```ts
// packages/contracts/identity.ts
import { z } from "zod";

export const ActorKindSchema = z.enum([
  "user",      // a human identity
  "api_key",   // REQ-API-04 / REQ-API-05, acts as its owner or its scope set
  "collector", // REQ-OBS-02, mTLS agent identity
  "system",    // scheduled jobs, outbox worker, chain verifier
]);

/** The minimal, embeddable reference. Safe to denormalise into events. */
export const ActorRefSchema = z.object({
  id: z.string().uuid(),
  kind: ActorKindSchema,
  /** Display label at the time of reference. Snapshot, not a live join. */
  label: z.string().max(200),
});

/** The full request-scoped actor. Never serialised to a client. */
export const ActorSchema = ActorRefSchema.extend({
  tenantId: z.string().uuid().nullable(),        // null only for system/global
  globalTier: GlobalTierSchema.nullable(),
  /** Resolved permission strings. Deny-by-default (REQ-RBA-02). */
  permissions: z.array(PermissionStringSchema).readonly(),
  locale: z.string().min(2).max(10),             // REQ-I18N-04
  timeZone: z.string().default("Europe/Stockholm"), // REQ-TIM-01
});

export type ActorRef = z.infer<typeof ActorRefSchema>;
export type Actor = z.infer<typeof ActorSchema>;
```

`PermissionStringSchema` and `GlobalTierSchema` come from
`contracts/types/rbac.md`. `Actor` is the value the data-access layer reads to
fill `created_by` / `updated_by` / `deleted_by` (REQ-ENT-04).

## 3. `Tenant`, `TenantRef`

```ts
export const TenantStatusSchema = z.enum(["active", "suspended", "archived"]);

export const TenantRefSchema = z.object({
  id: z.string().uuid(),
  slug: z.string().regex(/^[a-z0-9][a-z0-9-]{1,62}$/),
  name: z.string().max(200),
});

export const TenantSchema = TenantRefSchema.extend({
  status: TenantStatusSchema,
  /** Presentation defaults; a user preference wins (REQ-TIM-03, REQ-I18N-04). */
  defaultLocale: z.string().min(2).max(10),
  defaultTimeZone: z.string().default("Europe/Stockholm"),
  /** Auth methods this tenant enables, never wider than global (REQ-AUT-04). */
  authMethods: z.array(z.enum(["password_totp", "passkey", "oidc"])),
}).merge(EntityBaseSchema);
```

`TenantRef` is what goes into a session, an audit event and a notification.
`TenantSchema` is the admin read model and carries the entity envelope.

## 4. `GlobalTier` (REQ-RBA-06)

```ts
/** Ordered, least to most. Comparison is by index, never by string. */
export const GlobalTierSchema = z.enum([
  "operator",     // MSP operator: cross-tenant read, support actions
  "global_admin", // system administration, tenant lifecycle, policy
  "superadmin",   // purge, KEK rotation, audit retention, break-glass
]);
export const GLOBAL_TIER_ORDER = ["operator", "global_admin", "superadmin"] as const;
```

A global-tier actor has `tenantId: null` until it enters a tenant. Its
permissions live in the `global.*` namespace and every one of them requires
step-up (REQ-AUT-07, REQ-RBA-06). Holding `global_admin` does **not** imply a
tenant permission: entering a tenant mints a session and the tenant-scoped
permissions are resolved for that session.

## 5. `Session` (REQ-AUT-10)

```ts
export const AmrSchema = z.enum([
  "pwd", "totp", "webauthn", "oidc", "recovery_code",
]);

export const SessionSchema = z.object({
  id: z.string().uuid(),
  actor: ActorRefSchema,
  /** Null for a global-tier session that has not entered a tenant. */
  tenant: TenantRefSchema.nullable(),
  globalTier: GlobalTierSchema.nullable(),
  permissions: z.array(PermissionStringSchema).readonly(),
  /** Methods actually satisfied on this session. Drives REQ-AUT-05/07. */
  amr: z.array(AmrSchema).nonempty(),
  mfaSatisfied: z.boolean(),
  /** Last successful step-up. Null means no step-up in this session. */
  steppedUpAt: UtcInstantSchema.nullable(),
  createdAt: UtcInstantSchema,
  lastSeenAt: UtcInstantSchema,
  expiresAt: UtcInstantSchema,
  /** Present only while operating on behalf of someone else (REQ-RBA-07). */
  impersonation: ImpersonationContextSchema.optional(),
  /** Presentation only. Server-derived; a client cannot set it. */
  ip: z.string().ip(),
  userAgent: z.string().max(512),
});
```

Session state is server-side and revocable (REQ-AUT-10). The cookie carries an
opaque id and nothing else — no claims, no tenant, no permissions. A client
that wants to know its own permissions calls the session read route; that
answer is presentation gating only and is never the enforcement point
(REQ-RBA-02).

All five timestamps are UTC `timestamptz` in `sessions` and RFC 3339 `Z` on the
wire. `packages/contracts/time` formats them at the edge (REQ-TIM-04).

## 6. `ImpersonationContext` — the on-behalf-of shape (REQ-RBA-07)

```ts
export const ImpersonationContextSchema = z.object({
  /** The operator doing the acting. This is the on-behalf-of value. */
  impersonatedBy: ActorRefSchema,
  /** The identity being acted as. Equals session.actor. */
  subject: ActorRefSchema,
  /** Mandatory, free-text, audited, shown in the operator's banner. */
  reason: z.string().min(8).max(500),
  /** Optional external ticket reference. */
  ticket: z.string().max(120).optional(),
  startedAt: UtcInstantSchema,
  /** Mandatory time box. The session dies here, not at the normal TTL. */
  expiresAt: UtcInstantSchema,
  /** Correlates the enter and exit audit events. */
  impersonationId: z.string().uuid(),
});
```

What the audit trail depends on, exactly (`contracts/events/audit-event.md`):

| Audit field | Value under impersonation | Value normally |
|-------------|---------------------------|----------------|
| `actor` | `session.actor` (the subject) | `session.actor` |
| `onBehalfOf` | `session.impersonation.impersonatedBy` | `null` |
| `tenant` | the entered tenant | `session.tenant` |
| `impersonationId` | `session.impersonation.impersonationId` | `null` |

Entry emits `global.impersonation.enter` and exit emits
`global.impersonation.exit`, both carrying `reason`, `expiresAt` and the shared
`impersonationId`. An expiry without an explicit exit still emits
`global.impersonation.exit` with `result: "expired"` — a time box that lapses
silently would break the pairing the trail is read by.

`contracts/README.md` §6 illustrates CCR-007 as `Session.impersonatedBy?:
ActorRef`. The frozen shape nests it inside `impersonation` so the actor, the
reason and the time box cannot exist without one another. Read the
on-behalf-of actor as `session.impersonation?.impersonatedBy`.

## 7. Change rules after the G3 freeze

**Additive**
- A new `ActorKind` (a new kind of caller), a new `Amr` value, a new
  `TenantStatus` — all are *input-widening* on read models.
- A new optional field on `Session`, `Tenant` or `ImpersonationContext`.
- A new global tier appended to `GLOBAL_TIER_ORDER` **above** `superadmin`.

**Breaking**
- Inserting a global tier in the middle of the order: every `>=` comparison
  silently changes meaning. New name, new tier, deprecate the old.
- Making `impersonation.reason` optional, or removing `expiresAt`.
- Adding a tenant identifier to any request schema.
- Putting permissions or the tenant into the cookie.
