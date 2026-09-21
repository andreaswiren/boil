# `notification-event` — categories, channels, and a push payload with no content

**Published by:** A12 (`NotificationEvent`, `NotificationPreference`, the
digest). A09 publishes `NotificationCategory` and `PushEnvelope`
(`packages/pwa`), because the subscription lifecycle is A09's.
**Requirements:** REQ-PWA-02, REQ-PWA-04, REQ-PWA-06, REQ-MAIL-04, REQ-MAIL-03,
REQ-SEC-01, REQ-I18N-01, REQ-TIM-03.
**Consumed by:** every domain that notifies a human — A03, A04, A10, A11, A13,
A15, A16.

A domain does not send. It emits a `NotificationEvent` with a category, and A12
resolves preferences, fans out to channels, and records delivery. One fan-out
path is what makes "why did I not get that email" answerable.

---

## 1. The envelope

```ts
// packages/notify/contract.declaration.ts
import { z } from "zod";
import { ActorRefSchema, TenantRefSchema } from "@app/contracts/identity";

export const NotificationEventSchema = z.object({
  id: z.string().uuid(),
  /** Registry id, e.g. "auth.new-device" (§2). Unknown → notify.category_unknown. */
  category: z.string().regex(/^[a-z0-9.-]+$/),
  tenant: TenantRefSchema.nullable(),
  /** Who it is for. Resolved to users before fan-out; a role fans out to its holders. */
  audience: z.discriminatedUnion("kind", [
    z.object({ kind: z.literal("user"), userId: z.string().uuid() }),
    z.object({ kind: z.literal("role"), roleId: z.string().uuid() }),
    z.object({ kind: z.literal("tenant") }),
    z.object({ kind: z.literal("global_tier") }),
  ]),
  /** Who or what caused it. Null for a system event. */
  actor: ActorRefSchema.nullable(),
  severity: z.enum(["info", "warning", "critical"]),
  /** i18n keys plus scalar params. Never a rendered sentence (REQ-I18N-02). */
  titleKey: z.string(),
  bodyKey: z.string(),
  params: z.record(z.string(), z.union([z.string(), z.number(), z.boolean()])),
  /** The in-app deep link. A path, never an absolute URL with a token in it. */
  href: z.string().regex(/^\/(?!\/)/).max(300),
  /** What it is about. The push payload carries only this reference (§4). */
  ref: z.string().uuid(),
  target: z.object({ kind: z.string(), id: z.string() }).nullable(),
  /** Set by the emitter; identical events collapse in a digest (§3). */
  dedupeKey: z.string().max(200),
  occurredAt: z.string().datetime({ offset: false }),
  correlationId: z.string().uuid(),
}).strict();

export type NotificationEvent = z.infer<typeof NotificationEventSchema>;
```

`occurredAt` is UTC `timestamptz` in storage and RFC 3339 `Z` on the wire. Every
rendering — the in-app list, the email, the digest header — formats it through
`packages/contracts/time`, `Europe/Stockholm` and `YYYY-MM-DD HH:mm:ss` by
default (REQ-TIM-03, REQ-TIM-04). An email template that formats a date itself
fails the formatter lint.

`params` are scalars only, and they are redacted by the audit registry before
storage (`contracts/events/audit-event.md` §4). A notification row is readable
by anyone who can read that user's notifications; it is not a place for a
secret.

## 2. Categories (REQ-PWA-06)

A category is declared by its owning agent in its contract declaration and
assembled by A02. Registry, never a shared list — two agents adding a category
in the same minute do not touch the same file. The shape is A09's
`NotificationCategorySchema`: `id`, `agent`, `titleKey`, `descriptionKey`,
`channels`, `defaultOn`, `digestable`, `permission`.

| Category | Owner | Default channels | Default on | Digestable | Permission gate |
|----------|-------|------------------|------------|------------|-----------------|
| `auth.new-device` | A03 | in_app, push, email | yes | no | — |
| `auth.mfa-changed` | A03 | in_app, email | yes | no | — |
| `auth.recovery-codes-low` | A03 | in_app, email | yes | yes | — |
| `auth.login-failed-burst` | A03 | in_app, push | yes | no | `auth.session.revoke-tenant` |
| `rbac.role-changed` | A04 | in_app, email | yes | yes | `rbac.role.read` |
| `tenancy.member-joined` | A04 | in_app | yes | yes | `tenancy.member.read` |
| `global.impersonation-started` | A04 | in_app, push, email | yes | no | `global.audit.read-any` |
| `api.key-expiring` | A11 | in_app, email | yes | yes | `api.key.read-own` |
| `api.key-revoked` | A11 | in_app, email | yes | no | `api.key.read-own` |
| `grid.export-ready` | A07 | in_app, push | yes | no | `grid.export.run` |
| `audit.chain-broken` | A13 | in_app, push, email | yes | no | `audit.chain.verify` |
| `audit.retention-purge-blocked` | A13 | in_app, email | yes | yes | `audit.retention.read` |
| `mail.delivery-failed` | A12 | in_app, email | yes | yes | `mail.outbox.read` |
| `canonical.quarantine-added` | A10 | in_app | yes | yes | `canonical.quarantine.read` |
| `collector.agent-offline` | A15 | in_app, push, email | yes | yes | `collector.agent.read` |
| `collector.agent-revoked` | A15 | in_app, email | yes | no | `collector.agent.read` |
| `help.topic-published` | A16 | in_app | no | yes | `help.topic.read` |

A category whose `permission` the user does not hold is invisible in the
preference UI and never delivered. Permission is checked at fan-out time, not at
emit time: a user who lost the permission between emit and send gets nothing.

## 3. Channels, preferences and the digest

Channels are `in_app`, `push`, `email` — A09's enum, used verbatim.

```ts
export const NotificationPreferenceSchema = z.object({
  userId: z.string().uuid(),
  tenantId: z.string().uuid(),
  category: z.string(),
  channels: z.object({
    in_app: z.boolean(),
    push: z.boolean(),
    email: z.boolean(),
  }),
  /** Email only. `immediate` bypasses the digest. */
  digest: z.enum(["immediate", "hourly", "daily", "weekly"]).default("immediate"),
  /** Local clock for the daily/weekly send, in the user's zone (REQ-TIM-05). */
  digestAtLocal: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/).default("08:00"),
}).strict();
```

Resolution order, per event and per channel: the user's preference → the
category's `defaultOn` → off. There is no tenant-level override that can turn a
user's channel back on.

Digest rules:

- Only `email` digests. `in_app` is always immediate — it is a list the user
  pulls. `push` is never digested; a batched push is a push with stale content.
- `digestable: false` on the category wins over any user preference. An MFA
  change is not held for a day.
- `severity: "critical"` bypasses the digest on every channel, whatever the
  preference says. Rate-limiting critical safety notifications is not a feature.
- Collapse inside a digest is by `dedupeKey`: one line with a count, not twelve
  identical lines.
- `digestAtLocal` is resolved in the user's timezone through
  `packages/contracts/time`, which handles the DST-ambiguous and non-existent
  local hours (REQ-TIM-01). A digest at 02:30 on a spring-forward night sends
  once, not zero times and not twice.

Email leaves through the outbox only: retry, backoff, dead-letter, and one
`mail.message.send` audit event per attempt (REQ-MAIL-04). No send happens on a
request path.

## 4. The push payload carries no content (REQ-PWA-04)

A push payload passes through a third-party push service (FCM, WNS, APNs via
Safari). It is encrypted to the subscription key, but the endpoint, the timing
and the size are visible to that service, and the payload is decrypted by the
service worker before the user has authenticated anything. Treat it as
published.

**Unsafe — never ship this:**

```json
{
  "title": "Invoice 4471 overdue — Acme Industries AB",
  "body": "Karin Öberg (karin@acme.example) disabled MFA for tenant acme. Reason: audit request from Nordlo.",
  "data": { "tenantId": "8f1c…", "userEmail": "karin@acme.example", "sessionToken": "eyJhbGci…" }
}
```

Three failures in nine lines: a tenant's identity and a customer's name on a
third-party wire; personal data in a notification tray on a lock screen; a
credential in `data`.

**Safe — the whole payload that crosses the push service:**

```json
{ "v": 1, "category": "auth.mfa-changed", "ref": "3f6b0a5c-9e11-4f0a-bd2e-7c5a2f0d1b84", "titleKey": "notify.auth.mfa_changed.title", "locale": "sv", "count": 1 }
```

This is A09's `PushEnvelopeSchema`, and it is `.strict()` — an extra field fails
validation before the push is sent, which is the guard that keeps content out.
Rules:

- `titleKey` is a catalogue key, resolved by the service worker from the
  precached locale bundle. Not a sentence, and never interpolated with `params`.
- `ref` is an opaque uuid. It is not a database id, it is not guessable, it
  expires (default 7 days), and it resolves to one notification for one user.
- The service worker shows a generic, localised title and body from the
  catalogue. Nothing tenant-specific, nothing personal.
- On click, the client calls `GET /api/v1/pwa/refs/{ref}` over TLS **with the
  session cookie**, and only then does it have the title, the body, the tenant
  and the `href` (REQ-SEC-01). An unauthenticated or wrong-user request gets
  `common.not_found` — never `common.forbidden`, which would confirm the ref
  exists.
- The resolved response is `no-store`. The service worker never caches it
  (REQ-PWA-03).
- `count` is the only number allowed: a badge count for the user's own unread
  total. It leaks nothing about which tenant or which resource.

A category with `channels: ["push"]` and content the user must see in the tray
does not exist in this build. If the content matters, the channel is in_app or
email.

## 5. Delivery record

Fan-out writes one row per `(event, user, channel)` in `notification_events`
(A12's table, tenant-scoped, entity-base carrying), with `state` in
`pending | sent | failed | suppressed` and a `suppressedReason` of
`preference_off | permission_missing | no_subscription | digest_held |
channel_unavailable`. "I did not get it" is then a query, not an investigation.

Email delivery emits `mail.message.send` and push delivery emits
`notify.push.send`, both audit events (`contracts/events/audit-event.md` §2). A
push that the service rejects with a 404/410 subscription status marks the
subscription expired (A09's `expiredAt`) and suppresses further sends — it does
not retry forever.

## 6. Change rules after the G3 freeze

**Additive**
- A new category in an agent's own namespace, with its owner, default channels
  and digestable flag.
- A new optional field on `NotificationEvent` or `NotificationPreference`.
- A new digest interval appended to the enum.
- A new `suppressedReason` value.

**Breaking — needs orchestrator arbitration (REQ-CTR-03)**
- A new channel. Every stored preference row is missing the key, and defaulting
  it either surprises the user or silently drops notifications. It goes through
  a CCR with a stated default and a migration.
- Changing a shipped category's `defaultOn`, `digestable` or `permission` — the
  same event now reaches a different set of people.
- Adding any content field to `PushEnvelope`, or removing its `.strict()`.
  That is a privacy regression and the default answer is no.
- Making `ref` resolvable without authentication.
