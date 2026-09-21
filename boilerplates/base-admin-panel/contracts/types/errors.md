# `errors` — RFC 9457 problems and the code taxonomy

**Published by:** A02. Enforced at the HTTP boundary by A11's route kit.
**Requirements:** REQ-API-10, REQ-RBA-02, REQ-RBA-03, REQ-AUT-07, REQ-FND-08,
REQ-I18N-01, REQ-I18N-02.
**Consumed by:** every agent that can fail a request, which is all of them.

One envelope, one code taxonomy, one mapping to HTTP status. A domain that
invents its own error shape breaks the generated client for every consumer.

---

## 1. The envelope

`Content-Type: application/problem+json` on **every** response with a status
≥ 400, including the ones a framework would otherwise answer with HTML.

```ts
// packages/contracts/errors.ts
import { z } from "zod";

export const ErrorCodeSchema = z
  .string()
  .regex(/^[a-z][a-z0-9]*\.[a-z][a-z0-9_]*$/)   // "<namespace>.<snake_code>"
  .brand<"ErrorCode">();

export const ProblemSchema = z
  .object({
    /** Registry URI. Resolves to the in-app docs page for the code (§2). */
    type: z.string().url(),
    /** i18n catalogue key, resolved for the caller's locale (REQ-I18N-01). */
    title: z.string(),
    status: z.number().int().min(400).max(599),
    /** Rendered from a catalogue key plus parameters. Never a raw message. */
    detail: z.string().optional(),
    /** The request path that produced it. No query string — it can hold data. */
    instance: z.string(),
    code: ErrorCodeSchema,
    /** Joins to the audit record and the console frame (REQ-AUD-04). */
    correlationId: z.string().uuid(),
    /** Field-level validation only. Paths, never values. */
    errors: z
      .array(z.object({ path: z.string(), rule: z.string() }))
      .optional(),
  })
  .strict();

export type Problem = z.infer<typeof ProblemSchema>;
```

`.strict()` is deliberate. An extra property is how a stack trace, a SQL
fragment or an internal hostname ends up in a client response; the schema is
validated on the way **out**, and a failing problem body is replaced by
`common.internal` with the same `correlationId`.

A11's pre-freeze draft used `code: z.string().regex(/^[A-Z]+_[A-Z0-9_]+$/)` and
A02's used `E_VALIDATION`-style constants. The frozen taxonomy is the lowercase
dotted form in §3, which is what `contracts/types/entity-base.md` §4
(`common.validation_failed`) and `contracts/types/identity.md` §1
(`tenancy.cross_tenant`) already cite.

## 2. The problem type registry

```
type := "https://errors." <app-domain> "/" <code>
```

`https://errors.example.com/tenancy.cross_tenant`. The URI is an identifier
first and a document second, but it does resolve: the in-app docs render one
page per registered code from this registry, and the page is the only
human-readable explanation of the code (REQ-API-02).

The registry is assembled from declarations. A domain declares its codes in
`packages/<domain>/contract.declaration.ts` under `errorCodes`, A02 assembles,
and a duplicate code is a hard assembly failure naming both claimants.

| Registry field | Source | Rule |
|----------------|--------|------|
| `code` | the declaring domain | Unique across the app. Immutable once shipped. |
| `namespace` | the code's first segment | Equals the declaring domain, or `common` (A02 only). |
| `status` | this file, §4 | One status per code. A code does not vary its status by caller. |
| `titleKey` / `detailKey` | the domain's i18n namespace | `<domain>.errors.<code-tail>` (REQ-I18N-05). |
| `retryable` | the declaring domain | Whether a client may retry unchanged. |

## 3. The initial code taxonomy

Namespaces are the domain names from `contracts/types/rbac.md` §6, plus
`common`, which only A02 may declare in.

| Code | Status | Meaning |
|------|--------|---------|
| `common.validation_failed` | 400 | Input failed a Zod schema. `errors[]` carries paths and rule names, never values. |
| `common.unauthenticated` | 401 | No session, no valid API key. |
| `common.forbidden` | 403 | Authenticated, not permitted, and saying so leaks nothing. |
| `common.not_found` | 404 | The resource does not exist in the caller's scope. |
| `common.conflict` | 409 | Concurrent write, stale version, or uniqueness violation. |
| `common.precondition_failed` | 412 | `If-Match` / version precondition failed. |
| `common.payload_too_large` | 413 | Body over the route's declared cap. |
| `common.unsupported_media_type` | 415 | Body content type is not the declared one. |
| `common.rate_limited` | 429 | Per-identity or per-IP limit tripped (REQ-SEC-11). Carries `Retry-After`. |
| `common.internal` | 500 | Unhandled. Nothing but `code` and `correlationId` is meaningful. |
| `common.unavailable` | 503 | A declared dependency is down (REQ-CER-05). |
| `common.timeout` | 504 | Upstream or database timeout. |
| `auth.credentials_invalid` | 401 | Password, TOTP or assertion rejected. Identical body and timing for unknown and known users (REQ-MAIL-05). |
| `auth.mfa_required` | 401 | Policy requires a second factor that this session has not satisfied (REQ-AUT-05). |
| `auth.step_up_required` | 403 | Permission held, step-up missing or stale (REQ-AUT-07). |
| `auth.session_expired` | 401 | Server-side session gone or revoked (REQ-AUT-10). |
| `auth.locked_out` | 429 | Lockout backoff active (REQ-SEC-11). |
| `auth.policy_forbidden_by_global` | 403 | Tenant tried to enable a globally disabled method (REQ-AUT-04). |
| `auth.identity_last_factor` | 409 | Unlinking would leave the identity below policy (REQ-AUT-09). |
| `auth.recovery_code_consumed` | 409 | Single-use code already spent (REQ-AUT-06). |
| `auth.passkey_counter_regression` | 401 | WebAuthn signature counter went backwards (REQ-AUT-02). |
| `rbac.permission_denied` | 403 | Deny-by-default check failed (REQ-RBA-02). Names no permission. |
| `rbac.global_permission_not_grantable` | 422 | A tenant role listed a `global.*` string (REQ-RBA-06). |
| `rbac.role_version_stale` | 409 | Role write against a superseded version (REQ-RBA-08). |
| `tenancy.cross_tenant` | **404** | Reference to another tenant's resource. Never 403 (§4). |
| `tenancy.tenant_suspended` | 403 | Tenant status is `suspended` or `archived`. |
| `tenancy.impersonation_expired` | 403 | Time box lapsed (REQ-RBA-07). |
| `tenancy.impersonation_reason_missing` | 400 | Entry attempted without the mandatory reason. |
| `api.key_expired` | 401 | Key past its mandatory expiry (REQ-API-07). |
| `api.key_revoked` | 401 | Key revoked. |
| `api.key_ip_not_allowed` | 403 | Source IP outside the key's allowlist. |
| `api.key_scope_exceeded` | 403 | Scope ∩ owner's live permissions does not cover the operation (REQ-API-04). |
| `api.operation_removed` | 410 | `/api/v1` operation past its deprecation window (REQ-API-09). |
| `grid.row_ceiling_exceeded` | 422 | `pageSize=all` over the grid's ceiling (REQ-GRD-11). Parameters: count, ceiling. |
| `grid.sort_column_unknown` | 400 | Sort names a column the grid did not declare sortable. |
| `grid.filter_op_unsupported` | 400 | Operator illegal for the column's declared type (REQ-GRD-05). |
| `audit.legal_hold_active` | 409 | Purge or retention change blocked by legal hold (REQ-AUD-13). |
| `audit.chain_broken` | 500 | Hash-chain verification failed (REQ-AUD-06). Operator-facing, always alerted. |
| `audit.console_disabled` | 503 | Debug console disabled by config in this environment (REQ-AUD-08). |
| `mail.address_unverified` | 403 | Send refused to an unverified address (REQ-MAIL-05). |
| `mail.smtp_tls_required` | 502 | Relay would not negotiate TLS. Never falls back to cleartext (REQ-SEC-04). |
| `mail.template_render_failed` | 500 | Template or locale catalogue failure (REQ-MAIL-03). |
| `notify.category_unknown` | 400 | Category not in the registry (REQ-PWA-06). |
| `notify.channel_unavailable` | 503 | Push or SMTP dependency down; the in-app channel still records it. |
| `canonical.descriptor_invalid` | 422 | Descriptor would write an unknown canonical field (REQ-DAT-07). |
| `canonical.unmappable_input` | 422 | Input quarantined with a reason, never coerced (REQ-DAT-06). |
| `collector.enrolment_token_invalid` | 401 | Enrolment token unknown, used or expired (REQ-OBS-02). |
| `collector.agent_revoked` | 403 | Agent identity revoked (REQ-OBS-04). |
| `collector.ingest_duplicate` | 409 | Idempotency key already ingested (REQ-OBS-05). Safe for the agent to drop. |

## 4. Error class to HTTP status

| Class | Status | Codes | Rule |
|-------|--------|-------|------|
| Validation | 400 / 413 / 415 / 422 | `common.validation_failed`, `grid.*`, `canonical.*` | 400 for a malformed request, 422 for a well-formed request the domain refuses. |
| Authentication | 401 | `common.unauthenticated`, `auth.credentials_invalid`, `auth.mfa_required`, `auth.session_expired`, `api.key_*` | Answer is identical for an unknown and a known identity. |
| Authorization | 403 | `common.forbidden`, `rbac.permission_denied`, `tenancy.tenant_suspended` | Says the caller may not. Never which permission would work. |
| Step-up | 403 | `auth.step_up_required` | The one 403 a client may act on: it re-authenticates and retries (REQ-AUT-07). |
| Isolation | **404** | `tenancy.cross_tenant` | See below. |
| Conflict | 409 / 412 | `common.conflict`, `rbac.role_version_stale`, `audit.legal_hold_active` | State, not input. |
| Gone | 410 | `api.operation_removed` | Deprecation window elapsed. |
| Rate limit | 429 | `common.rate_limited`, `auth.locked_out` | Always with `Retry-After`. |
| Dependency | 502 / 503 / 504 | `common.unavailable`, `mail.smtp_tls_required`, `notify.channel_unavailable` | Degraded-mode behaviour is declared per dependency (REQ-CER-05). |
| Internal | 500 | `common.internal`, `audit.chain_broken` | `correlationId` is the whole payload of value. |

**The 404 rule (REQ-RBA-03, REQ-API-10).** A reference to a resource in another
tenant returns `tenancy.cross_tenant` at **404**, with the same body, the same
timing and the same headers as a genuinely missing row. A 403 would confirm that
the row exists, which is a cross-tenant information leak — the answer that makes
the difference invisible is the only correct one. This holds under RLS too: the
query returns zero rows (`contracts/db/rls-contract.md` §4) and the route maps
zero rows to 404 without a second lookup.

## 5. What an error body never carries (REQ-API-10, REQ-FND-08)

Never, in any field, in any environment, including development:

- A secret, a token, an API key prefix, a password hash, a TOTP seed, a
  connection string, an env var value.
- A stack trace, an exception class, a file path, a SQL statement, a driver
  message, an internal hostname or container name.
- Any evidence that another tenant's resource exists — an id, a count, a name,
  a differing message, or a measurably different response time.
- The permission the caller lacks, the role that would grant it, or another
  user's identity.
- Echoed input values. `errors[]` carries `path` and `rule`; the rejected value
  stays out, because the value is often the secret.

What the operator gets instead: `correlationId`. It joins the problem body to
the audit record (REQ-AUD-04) and to the console frame
(`contracts/events/console-stream.md` §2), both of which are permission-gated
and redacted. The detail lives where access to it is checked.

Enforcement: the route kit validates every outgoing problem against
`ProblemSchema` and A23 runs a test that walks every declared error path and
greps the serialised body for the fixture's secret values. A hit fails the
build.

## 6. Localisation

`title` and `detail` are rendered from catalogue keys plus parameters
(REQ-I18N-01, REQ-I18N-02). `detail` is never an interpolated sentence built in
a handler. `common.*` keys live in the `errors` namespace (A02's); a domain's
codes live in that domain's namespace. An untranslated key falls back to the
base locale in production and visibly in development (REQ-I18N-07) — a missing
translation never turns into an empty `title`.

## 7. Change rules after the G3 freeze

**Additive**
- A new code in a domain's own namespace, with its status, title key and
  registry page.
- A new optional field on `Problem` that carries no caller-supplied data.
- A new entry in `errors[]` for an existing validation failure.

**Breaking — needs orchestrator arbitration (REQ-CTR-03)**
- Changing a shipped code's HTTP status. Clients branch on status; this changes
  behaviour with no visible diff on their side.
- Renaming a code, or reusing a retired one for a different meaning.
- Moving `tenancy.cross_tenant` off 404 — that one is a security regression, not
  a contract change, and the answer is no.
- Adding a required field to `Problem`, or loosening `.strict()`.
