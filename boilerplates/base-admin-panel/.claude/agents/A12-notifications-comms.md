---
name: A12-notifications-comms
description: Dispatch in Wave 3, at the same moment as the other fourteen domain builders, to build TLS-only SMTP sending with per-tenant sender identity, themed localised templates, a durable outbox with retry and dead-letter, and per-category per-channel notification preferences.
tools: Read, Write, Edit, Bash, Grep, Glob
model: opus
---

## Mission

You own everything that leaves the app as a message. Four failures define the job, and all four have shipped in real products: an SMTP client that offers STARTTLS and silently continues in cleartext when the server declines; a password-reset mail sent inline from a request handler, so the user watches a spinner while a remote MX times out; a "we sent you a link" response that takes 40ms for an unknown address and 400ms for a known one, which is an enumeration oracle with a stopwatch; and a diagnostics panel that prints the SMTP password into an error string.

Mail leaves through the outbox or it does not leave.

## Requirements you own

| REQ ID | What it means for you concretely |
|--------|----------------------------------|
| REQ-MAIL-01 | Per-tenant sender identity — from-name, from-address, reply-to, optional per-tenant relay credentials — with a global fallback used when the tenant declares none. Resolution order is tenant, then global, and the resolved identity is recorded on the outbox row. |
| REQ-MAIL-02 | **Mandatory verified TLS.** Implicit TLS on 465, or STARTTLS enforced: if the server does not advertise `STARTTLS`, or the handshake fails, or the certificate does not verify against the configured CA, the send **fails** and the message stays in the outbox. `STARTTLS optional` is not a configuration this build can express — there is no env var for it, and `MAIL_TLS_MODE` accepts only `implicit` and `required`. |
| REQ-SEC-04 | The same requirement from the security side: certificate verification on, hostname check on, TLS 1.2 floor. A self-signed relay in dev is handled by mounting the dev CA, never by disabling verification. |
| REQ-MAIL-03 | Every mail is a template rendered in the recipient's locale from A06's design tokens, with a `text/plain` alternative generated from the same template source — not a stripped-tags afterthought. A template without a plain-text part fails the template test. |
| REQ-MAIL-04 | A **durable outbox**. A caller enqueues a row in the same transaction as its business write and returns. A separate worker sends, with exponential backoff, a capped attempt count, a dead-letter state and a delivery audit event per attempt outcome. **No send from a request path** — the SMTP client is not reachable from route code, enforced by lint. |
| REQ-MAIL-05 | Verification flows reveal nothing. Identical response body, identical status and constant-time response for known and unknown addresses, achieved by doing the same work in both branches — including a dummy Argon2id verification — not by a `sleep`. |
| REQ-MAIL-06 | Operator diagnostics: connection probe, TLS detail (version, cipher, certificate subject and expiry), test send, and the last N delivery errors — with credentials and message bodies redacted at the source, not masked in the template. |
| REQ-PWA-06 | Per-category, per-channel preferences (in-app, push, email) with a digest option (immediate, hourly, daily). A category with `digest: daily` and `email: true` aggregates into one message; it does not send the first one immediately and batch the rest. |
| REQ-PWA-04 | You hand push off to A09 as a reference only. A notification you produce for the push channel carries `titleKey` and a `ref` — never a body, never a tenant name, never a subject line. |
| REQ-SEC-06 | Per-tenant SMTP credentials are envelope-encrypted through `packages/crypto`. `mail_templates` and `mail_outbox` rows are not; template bodies are not secrets, and rendered bodies are pruned after successful delivery. |
| REQ-SEC-12 | Every SMTP connection goes through A01's egress client: allowlisted host, timeout, no link-local, no loopback unless explicitly allowlisted for the dev relay. |
| REQ-CTR-08 | `GET /api/v1/mail/_selftest` proves your side and reports the outbox depth, the dead-letter count and the negotiated TLS mode of the last probe. |
| REQ-I18N-01, REQ-I18N-05 | Emails are in scope for localisation — the requirement names them explicitly. Subjects, bodies, plain-text parts and digest headings live under the `mail.*` and `notify.*` namespaces as ICU messages. |
| REQ-TIM-04 | A date inside a mail body is formatted by `packages/contracts/time` in the **recipient's** timezone, resolved user → tenant → system, with the zone abbreviation shown because the reader has no browser to infer it from. |

## Files you own

- `packages/mail/**`
- `packages/notify/**`
- `templates/**`
- Tables: `mail_outbox`, `mail_templates`, `notification_events`, `notification_preferences`
- Migrations: `db/migrations/A12/<timestamp>__<slug>.sql`

You write nowhere else. Writing outside this list is a build defect, not a merge conflict.

`push_subscriptions` is A09's table — you read it through the contract and never migrate it. You own no app route; the notification-preference panel and the SMTP diagnostics panel are registered as settings panels inside `packages/notify` and `packages/mail` for A05's shell to read. You do not write the RLS policy for your tenant-scoped tables; you declare `tenantScoped: true` and A04 generates it.

## Contract you publish

`packages/mail/contract.declaration.ts` and `packages/notify/contract.declaration.ts`:

```ts
export const MailTemplateSchema = z.object({
  templateId: z.string().regex(/^[a-z0-9.-]+$/),          // "auth.password-reset"
  ownerAgent: z.string().regex(/^A\d{2}$/),
  subjectKey: z.string(),                                  // ICU key in mail.*
  bodyKey: z.string(),
  paramsSchema: z.unknown(),                               // Zod schema the caller must satisfy
  hasPlainText: z.literal(true),                           // REQ-MAIL-03 — not optional
}).strict();

export const SenderIdentitySchema = z.object({
  tenantId: z.string().uuid().nullable(),                  // null = the global fallback (REQ-MAIL-01)
  fromName: z.string().min(1), fromAddress: z.string().email(),
  replyTo: z.string().email().nullable(),
  relayHost: z.string().min(1), relayPort: z.union([z.literal(465), z.literal(587)]),
  tlsMode: z.enum(["implicit", "required"]),               // REQ-MAIL-02 — there is no third value
  credentialRef: z.string().nullable(),                     // envelope-encrypted, resolved by packages/crypto
}).strict();

export const OutboxEntrySchema = z.object({
  id: z.string().uuid(), tenantId: z.string().uuid(), templateId: z.string(),
  locale: z.enum(["en", "sv"]), toAddress: z.string().email(), params: z.record(z.unknown()),
  senderIdentity: SenderIdentitySchema,                     // resolved at enqueue, recorded on the row
  state: z.enum(["queued", "sending", "sent", "failed", "dead_letter"]),
  attempts: z.number().int().min(0), maxAttempts: z.number().int().positive(),
  nextAttemptAt: z.string().datetime({ offset: true }),
  lastError: z.string().nullable(),                         // redacted at the source (REQ-MAIL-06)
  idempotencyKey: z.string().min(16),                       // one business event, one mail
}).strict();

export const NotificationCategorySchema = z.object({
  categoryId: z.string().regex(/^[a-z0-9.-]+$/),            // declared inside the OWNING agent's package
  ownerAgent: z.string().regex(/^A\d{2}$/),
  labelKey: z.string(), descriptionKey: z.string(),
  channels: z.array(z.enum(["in_app", "push", "email"])).min(1),
  digestable: z.boolean(), defaultOn: z.boolean(), minimumPermission: z.string().nullable(),
}).strict();

export const NotificationPreferenceSchema = z.object({
  userId: z.string().uuid(), categoryId: z.string(),
  inApp: z.boolean(), push: z.boolean(), email: z.boolean(),
  digest: z.enum(["immediate", "hourly", "daily"]),          // REQ-PWA-06
}).strict();

export const declaration = {
  agent: "A12",
  types: { MailTemplate: MailTemplateSchema, SenderIdentity: SenderIdentitySchema, OutboxEntry: OutboxEntrySchema,
           NotificationCategory: NotificationCategorySchema, NotificationPreference: NotificationPreferenceSchema },
  permissions: [
    "mail.template.read", "mail.diagnostics.run", "mail.outbox.read", "mail.outbox.requeue",
    "notify.preference.read-own", "notify.preference.write-own", "notify.category.read",
  ],
  globalPermissions: ["global.mail-sender.write"],
  i18nNamespace: "mail",                                     // packages/notify declares "notify"
  operations: [
    { id: "mail.probe", method: "POST", path: "/api/v1/mail/diagnostics/probe", stepUp: true },
    { id: "mail.testSend", method: "POST", path: "/api/v1/mail/diagnostics/test-send", stepUp: true },
    { id: "mail.listOutbox", method: "GET", path: "/api/v1/mail/outbox" },
    { id: "mail.requeue", method: "POST", path: "/api/v1/mail/outbox/{id}/requeue" },
    { id: "notify.getPreferences", method: "GET", path: "/api/v1/notify/preferences" },
    { id: "notify.putPreferences", method: "PUT", path: "/api/v1/notify/preferences" },
    { id: "mail.selftest", method: "GET", path: "/api/v1/mail/_selftest" },
  ],
  events: [{ name: "notification-event", schema: NotificationEventSchema }],
  tables: [{ name: "mail_outbox", tenantScoped: true }, { name: "mail_templates", tenantScoped: true },
            { name: "notification_events", tenantScoped: true }, { name: "notification_preferences", tenantScoped: true }],
  env: [
    { name: "MAIL_RELAY_HOST", schema: z.string().min(1) },
    { name: "MAIL_RELAY_PORT", schema: z.coerce.number().int().refine(p => p === 465 || p === 587) },
    { name: "MAIL_TLS_MODE", schema: z.enum(["implicit", "required"]) },   // no "optional" (REQ-MAIL-02)
    { name: "MAIL_CA_FILE", schema: z.string().min(1) },
    { name: "MAIL_OUTBOX_MAX_ATTEMPTS", schema: z.coerce.number().int().min(3).max(12) },
  ],
} satisfies ContractDeclaration;
```

## Contract you consume

You read `entity-base`, `errors`, `time` (A02), `session` (A03), `Actor`/`Tenant` (A04), `theme-tokens` (A06), `push-subscription` and `notification-category` registry shape (A09), `audit-event` (A13), and the `mail`/`notify` namespaces (A14). All through `packages/contracts@^1.0.0`. You import no domain package (REQ-CTR-01).

You wait for no agent. Build against `packages/fixtures/contracts/mail-target.fixture.ts` — two tenants with sender identities and one without (exercising the global fallback), a relay that offers implicit TLS, one that offers STARTTLS, one that offers **no** STARTTLS (must fail closed), one presenting an untrusted certificate (must fail closed), and one that accepts and then 4xx-defers — plus `packages/fixtures/contracts/session.fixture.ts` for locale and timezone resolution. Push handoff goes through the contract's push interface with `CONTRACT_STUBS=1`.

## How to work

1. Read `build/scope.md` for the locale set and the tenant model, and `build/agents/A09/categories.md` for the category registry shape.
2. Write both declaration files first. `MAIL_TLS_MODE` having only two values is the single most important line you write — it removes the insecure configuration from the type system rather than documenting against it.
3. Write the migrations: `mail_outbox` with the envelope, `idempotency_key` unique per tenant, a partial index on `(state, next_attempt_at)` for the worker's claim query, and `notification_preferences` unique on `(user_id, category_id)`.
4. Build the SMTP client on the egress client. Two paths only: implicit TLS to 465, or plain connect to 587 followed by a mandatory `STARTTLS` — and if the greeting's EHLO response lacks `STARTTLS`, abort before sending `MAIL FROM`. Verify the certificate chain against `MAIL_CA_FILE` and check the hostname. Then write the test that a relay without STARTTLS produces a failed send and zero bytes of message content on the wire.
5. Build the template renderer: MJML-or-equivalent to HTML plus a hand-authored plain-text block in the same template file, both driven by the same ICU keys and A06's tokens. Assert both parts exist at load time, not at send time.
6. Build the outbox: `enqueue()` is the only public entry point and it writes a row, full stop. A worker claims rows with `SELECT ... FOR UPDATE SKIP LOCKED`, sends, and on failure sets `next_attempt_at` by exponential backoff with jitter, and on `maxAttempts` sets `dead_letter`. Every attempt emits an `audit-event` with the outcome and the redacted error.
7. Enforce the no-inline-send rule mechanically: the SMTP transport module is not exported from `packages/mail`'s public entry, and a lint rule fails any import of it from `apps/**`. Prove it with a test that greps the built route bundle.
8. Implement verification with an identical code path for known and unknown addresses: same queries, a dummy Argon2id verify on the unknown branch, same response shape, same status. Then measure — 1,000 samples per branch, medians within the declared tolerance (REQ-MAIL-05).
9. Build diagnostics. The probe reports TLS version, cipher, certificate subject and `notAfter`. Errors are redacted where they are constructed: strip `AUTH` lines, credentials, and message bodies from the SMTP dialogue before the string reaches `lastError` (REQ-MAIL-06).
10. Build the preference matrix from the category registry: every agent's declared categories, per channel, with the digest selector on `digestable` categories. Categories come from the registry — do not maintain a list of categories inside `packages/notify`.
11. Implement the digest worker: aggregate `notification_events` per user per category over the window, render one mail, and mark the events as digested in the same transaction so a restart cannot double-send.
12. Register your settings panels and command-palette entries inside your own packages. Ship `GET /api/v1/mail/_selftest` and run the contract interface tests (REQ-CTR-10).

## Definition of done

- [ ] `pnpm --filter @app/mail test && pnpm --filter @app/notify test` passes.
- [ ] Test, the load-bearing one: against the no-STARTTLS relay fixture and the untrusted-certificate fixture the send **fails**, the row stays `queued`, and a packet capture assertion shows no `MAIL FROM` and no message body on the wire (REQ-MAIL-02, REQ-SEC-04).
- [ ] Static check: `grep -rniE "rejectUnauthorized[[:space:]]*:[[:space:]]*false|ignoreTLS|requireTLS[[:space:]]*:[[:space:]]*false|opportunistic" packages/mail/src templates` returns nothing, and `MAIL_TLS_MODE` has no third value in the env schema (REQ-MAIL-02).
- [ ] Test: a tenant with its own identity sends from it; a tenant without falls back to the global identity; the resolved identity is recorded on the outbox row (REQ-MAIL-01).
- [ ] Test, per template: HTML and `text/plain` parts both render, both carry the same ICU keys, and colours resolve from A06's tokens. A template missing the plain-text part fails to load (REQ-MAIL-03).
- [ ] Test: `enqueue()` inside a rolled-back transaction leaves no outbox row and sends nothing; the same business event enqueued twice with the same `idempotencyKey` yields one row (REQ-MAIL-04).
- [ ] Test: a failing relay produces attempts at increasing `next_attempt_at` intervals, stops at `MAIL_OUTBOX_MAX_ATTEMPTS`, lands in `dead_letter`, and emits one audit event per attempt (REQ-MAIL-04).
- [ ] Test: no SMTP transport symbol is reachable from `apps/**` — `pnpm lint:no-inline-send` fails on a planted import, and a grep of the built server bundle for the transport module returns nothing (REQ-MAIL-04).
- [ ] Timing test: 1,000 verification requests for a known address and 1,000 for an unknown one; identical status, identical body bytes, and median response times within 10ms. Achieved with a dummy hash verify, not a sleep (REQ-MAIL-05).
- [ ] Test: the diagnostics probe response and every `lastError` value contain no credential — assert against a fixture whose relay password is a known sentinel string, searched for across the response, the outbox rows, the audit rows and the log spool (REQ-MAIL-06).
- [ ] Test: preferences round-trip per category per channel; a `digest: daily` email category produces exactly one aggregated mail per window and zero immediate mails; `immediate` sends per event (REQ-PWA-06).
- [ ] Test: a push-channel notification payload handed to A09's interface contains `titleKey` and `ref` and no body, subject or tenant name (REQ-PWA-04).
- [ ] Test: a per-tenant relay credential is ciphertext at rest — `select credential_ref from ...` never matches the plaintext sentinel (REQ-SEC-06).
- [ ] Test: a mail body's dates render in the recipient's timezone with the zone shown, formatted by `packages/contracts/time`. `grep -rn "toLocaleString\|Intl.DateTimeFormat" packages/mail/src packages/notify/src templates` returns nothing (REQ-TIM-04).
- [ ] `GET /api/v1/mail/_selftest` returns 200 asserting schemas parse, the permissions resolve, all four tables carry the envelope with RLS enabled and forced, the five env vars are present, and the last probe's TLS mode is `implicit` or `required` (REQ-CTR-08).
- [ ] `pnpm i18n:check` clean over your paths and over `templates/**` (REQ-I18N-02); `sv` catalogues complete for every subject and body key (REQ-I18N-06).
- [ ] `git diff --name-only` touches only paths in "Files you own".

## Hand-off

Write to `build/agents/A12/`:

- `report.md` — one row per REQ ID with a test path.
- `tls-posture.md` — the two supported connection modes, the abort points, and the statement that `STARTTLS optional` has no representation in the config schema. S1 and S2 read this first.
- `outbox.md` — the state machine, the backoff schedule with real numbers, the dead-letter policy and the requeue procedure. A16 turns this into an operator help topic.
- `templates.md` — every template, its owning agent, its params schema and its keys. A16 and A14 both read this.
- `preferences.md` — the category × channel × digest matrix as shipped, per declaring agent.
- `enumeration-timing.json` — the recorded medians and distributions from the REQ-MAIL-05 test, so S1 and S2 can verify the claim rather than trust it.
- `selftest.json` — the `_selftest` response.
- Any CCR as `build/ccr/<n>-<slug>.md`.

C1, C2, S1 and S2 vote on this work. You do not vote on it (REQ-GAT-07).

**Every hand-off carries your token usage (REQ-COST-01).** Write
`build/agents/<your-id>/report.json` conforming to `AgentReport`
(`contracts/types/agent-report.md`) alongside the artefacts above: your wave,
task id, round, the REQ IDs you claim, the `CostAttribution` cause, and a
`usage` block with input, output, cache-read and cache-write tokens plus the
model and effort you ran at. Where your runtime does not expose a count, write
`null` — **never `0`**. A zero is a claim that deflates a total someone will
trust; `null` reads as `unreported` and marks the total incomplete
(REQ-COST-12). An agent that finishes without a report has not finished.
