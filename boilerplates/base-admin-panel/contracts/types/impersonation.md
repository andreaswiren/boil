# Contract: `impersonation`

**Published by:** A04 (the session model, the effective-permission rule, the
refusal taxonomy), A03 (`ImpersonationContext`, already in
[`identity.md`](identity.md) §4 — this file extends it and does not redefine it).
Assembled by A02.
**Requirements:** REQ-IMP-01 … REQ-IMP-12, REQ-RBA-06, REQ-RBA-07, REQ-AUT-07,
REQ-AUD-04, REQ-TIM-03.
**Consumed by:** A03, A05, A11, A13, A23.

Everything here is **server-derived**. No field is ever read from a request
body, query string, header or cookie other than the opaque session cookie —
`identity.md` §1's rule applies without exception, and applies harder here,
because the one thing a client must never be able to assert is *whose session
this is*.

---

## 1. The rule that outranks the schemas (REQ-IMP-02)

> During impersonation the effective permission set is the **target's,
> exactly**. Not the operator's. **Never the union.**

The union is not a hypothetical. It is what a context-merging middleware
produces by default, and it is invisible in testing: the operator can do
everything, so no test fails. What it produces in the audit trail is worse than
the escalation — every record from that session becomes a false statement about
what was possible, so a later investigation cannot tell an action the target
could have taken from one only the operator could.

```ts
/**
 * The ONLY permitted resolution during impersonation.
 * There is no `operator` term on the right-hand side. That absence is the
 * contract; adding one is a security regression, not a feature (§6).
 */
export function resolveEffectivePermissions(
  session: ImpersonationSession,
): PermissionSet {
  return permissionsOf(session.target);   // never union(operator, target)
}
```

Enforced server-side at the same evaluation point as every other permission
decision (REQ-RBA-02). A client-side variant of this rule is presentation, not
enforcement.

## 2. `ImpersonationSession`

A **distinct session object**. It does not mutate the operator's session
(REQ-IMP-09) — mutation in place is the design that makes exit unreliable,
revocation impossible, and "which session am I revoking" unanswerable.

```ts
export const ImpersonationSessionSchema = z.object({
  id: z.string().uuid(),
  /** The operator. Remains the `actor` on every audit event (REQ-AUD-04). */
  operator: ActorRefSchema,
  /** The impersonated user. Becomes `onBehalfOf` on every audit event. */
  target: ActorRefSchema,
  /** The target's tenant. The operator's own tenant context does not apply. */
  tenant: TenantRefSchema,
  /** The operator's own session, held intact alongside — never replaced. */
  operatorSessionId: z.string().uuid(),
  /** Typed at entry, free text, audited verbatim, minimum length enforced. */
  reason: z.string().min(12).max(500),
  startedAt: Timestamp,                       // UTC (REQ-TIM-03)
  /** startedAt + the configured box, never extended in place (REQ-IMP-04). */
  expiresAt: Timestamp,
  endedAt: Timestamp.nullable(),
  endedBy: z.enum(["operator-exit", "expiry", "revoked", "target-logout"]).nullable(),
  /** Set when another global operator killed it mid-flight (REQ-IMP-09). */
  revokedBy: ActorRefSchema.nullable(),
}).strict();
```

`expiresAt` is absolute and set once. An implementation that slides it on
activity has removed the time box while appearing to have one, which is worse
than no box because it is reported as a control.

## 3. Entry

```ts
export const ImpersonationEntrySchema = z.object({
  targetUserId: z.string().uuid(),
  reason: z.string().min(12).max(500),
  /** Requested box; clamped server-side to the configured maximum. */
  requestedMinutes: z.number().int().positive().max(240),
}).strict();
```

Preconditions, all server-side: impersonation is enabled for this deployment
(REQ-IMP-11); the operator holds `global.impersonation.impersonate`
(`rbac.md` §6); step-up re-authentication is fresh (REQ-AUT-07); the target is
not a global-tier operator unless peer impersonation is enabled and a second
approval exists (REQ-IMP-08).

## 4. The refusal taxonomy (REQ-IMP-07)

Refusals are **explicit, with a reason** — never a silent no-op and never a
disabled control with no explanation. A silent refusal reads as a bug and
teaches operators to retry; a stated one teaches them the boundary.

Codes follow `errors.md`'s `<namespace>.<snake_code>` convention and all return
`403`:

| Code | Refused action | The escalation it prevents |
|------|----------------|---------------------------|
| `impersonation.credential_change` | Change the target's password or email | Permanent account takeover — the operator keeps access after the box expires |
| `impersonation.mfa_change` | Enrol, remove or reset the target's MFA factors | Defeats REQ-AUT-05 for that account, silently and permanently |
| `impersonation.recovery_codes` | Generate or view recovery codes | A durable credential that outlives the session and leaves no further trace |
| `impersonation.api_key_mint` | Mint an API key as the target | A credential that acts as the target with no impersonation banner and no expiry link to the session |
| `impersonation.role_change` | Change the target's roles or grants | The operator grants the target powers, then uses them — laundering through an account they control |
| `impersonation.nested` | Start a second impersonation from inside one | Breaks `onBehalfOf` into an ambiguous chain; the audit trail can no longer name one responsible actor |
| `impersonation.peer` | Impersonate another global-tier operator | Removes the last separation of duties in the tier (REQ-IMP-08) |
| `impersonation.self_target` | Impersonate yourself | Produces a session whose `actor` and `onBehalfOf` are equal, defeating every query that distinguishes them |

```ts
export const ImpersonationRefusalSchema = z.enum([
  "credential_change", "mfa_change", "recovery_codes", "api_key_mint",
  "role_change", "nested", "peer", "self_target",
]);
```

The list is enforced at the permission layer, not in the UI. A refused action
that is merely hidden is a refused action that returns the moment someone calls
the endpoint directly.

## 5. `TenantSwitch`

Published by A04, consumed by A05's chooser (`spec/tenant-switching.md`).

```ts
export const TenantSwitchSchema = z.object({
  /** The ONE place a tenant id is accepted from a client (REQ-RBA-09). */
  tenantId: z.string().uuid(),
}).strict();

export const TenantSwitchResultSchema = z.object({
  previous: TenantRefSchema.nullable(),   // null on first selection after login
  current: TenantRefSchema,
  sessionRotated: z.literal(true),        // always; a switch without rotation is not a switch
}).strict();
```

`previous` is non-optional in the audit record for the reason
`spec/tenant-switching.md` §6 gives: "switched to Acme" cannot answer what the
actor could see a moment earlier.

While impersonating, the accessible-tenant list is the **target's**
(REQ-IMP-02). An operator who could reach a tenant the target cannot must not
reach it through the target's session.

## 6. Additive vs breaking

**Additive** — a new refusal code (the surface gets *more* restrictive, and
existing callers already handle `403`); a new optional field on
`ImpersonationSession`; a new `endedBy` variant that clients treat as "ended".

**Breaking, and ordinary arbitration does not cover it** — removing a refusal
code, widening `resolveEffectivePermissions` to include any operator term, or
making `expiresAt` slidable. Each of these is a **security regression** rather
than an interface change: it passes the breaking-change detector's shape check
while changing what the system permits.

So they require **S1 and S2 sign-off**, not the orchestrator's CCR arbitration
(`contracts/README.md` §6). The orchestrator may not approve a change to this
file that narrows a refusal or touches the effective-permission rule. That is
the one place in this structure where the arbitration default is overridden, and
it is overridden because the cost of being wrong here is an authorized account
takeover that looks correct in every test.
