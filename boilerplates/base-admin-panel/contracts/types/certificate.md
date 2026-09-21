# `certificate` — ACME accounts, certificates, orders, renewal policy

**Published by:** A25 (`AcmeAccount`, `Certificate`, `CertOrder`,
`ChallengeType`, `RenewalPolicy`, `DnsProviderDescriptor`, `RenewalLogEntry`).
Assembled by A02.
**Requirements:** REQ-ACME-01 … REQ-ACME-18, REQ-SEC-06, REQ-SEC-12,
REQ-AUD-05, REQ-RBA-06, REQ-TIM-04.
**Consumed by:** A05 (settings panel), A07 (inventory grid), A12, A13 (audit and
the debug stream), A18, A23, A24.

---

## 1. The rules that outrank the schemas

> Private key material exists in exactly two places: an envelope-encrypted
> column, and the memory of the process using it.

**No route, at any permission, returns a private key.**
`acme_accounts.private_key_enc`, `certificates.private_key_enc` and
`dns_providers.credentials_enc` appear in no read model here — not
`.optional()`, not masked, not length-hinted (REQ-ACME-12). A schema that could
carry them is one someone will eventually fill.

Everything here is **server-derived** except the three inputs named in §10.
Every table is `tenantScoped: false`, because `packages/tls` materialises a
certificate row before any session exists and there is no tenant to scope by
(`spec/acme-tls.md` §12); access control is the `global.*` set plus step-up
(REQ-RBA-06), never RLS. Every instant is UTC `timestamptz` in storage,
RFC 3339 `Z` on the wire, formatted only at the edge (REQ-TIM-04).

## 2. `ChallengeType` (REQ-ACME-01, REQ-ACME-15)

```ts
// packages/contracts/certificate.ts
import { z } from "zod";

/** Unordered. Nothing compares these by index — see §11. */
export const ChallengeTypeSchema = z.enum(["http-01", "dns-01", "tls-alpn-01", "dns-persist-01"]);
export const TerminationModeSchema = z.enum(["self", "behind-proxy", "delegated"]);

/** Contract data, not UI data: the picker (REQ-ACME-02) AND the server-side
 *  order validator read it; two copies drift into a failed order at the CA. */
export const CHALLENGE_CAPABILITIES = {
  "http-01":        { wildcard: false, modes: ["self"] },                   // RFC 8555 §8.3
  "dns-01":         { wildcard: true,  modes: ["self","behind-proxy","delegated"] }, // RFC 8555 §8.4
  "tls-alpn-01":    { wildcard: false, modes: ["self"] },                   // RFC 8737
  "dns-persist-01": { wildcard: true,  modes: ["self","behind-proxy","delegated"] }, // acme-dns-persist
} as const;
```

## 3. `AcmeAccount` (REQ-ACME-05, REQ-ACME-14)

```ts
export const AcmeAccountSchema = z.object({
  id: z.string().uuid(),
  directoryUrl: z.string().url(),   // staging vs production derives from it
  accountUri: z.string().url(),     // what a dns-persist-01 record binds to (§11)
  /** RFC 7638 thumbprint, shown to the operator: the only handle on the key, and
   *  what makes a restored-from-backup account visible. */
  keyThumbprint: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
  contactEmail: z.string().email(),
  status: z.enum(["valid", "deactivated", "revoked"]),
  offeredChallenges: z.array(ChallengeTypeSchema).readonly(),  // probed, never assumed
  renewalInfoUrl: z.string().url().nullable(),                 // null ⇒ no ARI (REQ-ACME-07)
  offeredProfiles: z.array(z.string()).readonly(),             // e.g. classic, shortlived
  registeredAt: UtcInstantSchema, keyRotatedAt: UtcInstantSchema.nullable(),
}).strict();
```

## 4. `Certificate` (REQ-ACME-15, REQ-ACME-16)

```ts
export const CertificateStatusSchema = z.enum([
  "pending", "active", "renewing",
  "install_failed",  // issued but rejected by validation; the old leaf still serves
  "expired", "revoked",
  "observed",        // not ours: read from an upstream's handshake (REQ-ACME-03)
]);

export const CertificateSchema = z.object({
  id: z.string().uuid(), accountId: z.string().uuid().nullable(),  // null: observed, internal
  names: z.array(z.string().min(1)).nonempty().readonly(),  // a `*.` entry forces §2's wildcard set
  challengeType: ChallengeTypeSchema,
  issuerKind: z.enum(["acme", "internal"]),   // `internal` = the HAProxy↔app hop leaf
  issuerCn: z.string().max(200), profile: z.string(),
  staging: z.boolean(),                       // a staging leaf is never committed to the edge
  status: CertificateStatusSchema, serial: z.string().regex(/^[0-9a-f]+$/),
  spkiSha256: z.string().regex(/^[A-Za-z0-9_-]{43}$/),   // the termination-detection pin
  notBefore: UtcInstantSchema, notAfter: UtcInstantSchema,
  ariWindowStart: UtcInstantSchema.nullable(), ariWindowEnd: UtcInstantSchema.nullable(),
  ariExplanationUrl: z.string().url().nullable(),   // ARI suggestedWindow, verbatim
  nextAttemptAt: UtcInstantSchema.nullable(),      // an INSTANT, never a duration (§11)
  nextCheckAt: UtcInstantSchema.nullable(), lastRenewalAt: UtcInstantSchema.nullable(),
  lastRenewalResult: z.enum(["success", "failed", "skipped"]).nullable(),
  consecutiveFailures: z.number().int().min(0),   // drives the alert ladder (REQ-ACME-11)
  /** Non-null only for dns-persist-01; `needs_republish` is written by an account
   *  key change (REQ-ACME-05). */
  persistState: z.enum(["absent", "published", "needs_republish", "expired"]).nullable(),
  persistUntil: UtcInstantSchema.nullable(),
  edgeStorePath: z.string().max(400).nullable(),   // HAProxy store; null when delegated
  installedAt: UtcInstantSchema.nullable(),        // null while `install_failed` (REQ-ACME-13)
  chainPem: z.string(), leafPem: z.string(),       // public material
}).merge(EntityBaseSchema).strict();
```

`nextAttemptAt` is an instant, not "hours before expiry": a duration must be
re-interpreted by every reader, and two readers differing is how a 160-hour
certificate expires while both believe they are early.

## 5. `CertOrder` (REQ-ACME-14, REQ-ACME-17)

```ts
export const CertOrderSchema = z.object({
  id: z.string().uuid(), certificateId: z.string().uuid(), accountId: z.string().uuid(),
  orderUrl: z.string().url(),                   // so a stuck order is inspectable
  names: z.array(z.string()).nonempty().readonly(), challengeType: ChallengeTypeSchema,
  staging: z.boolean(),
  replaces: z.string().nullable(),              // RFC 9773 certID; null on first issuance
  status: z.enum(["pending", "ready", "processing", "valid", "invalid", "expired"]),
  /** Per-name, so a partial failure names the name. */
  authorizations: z.array(z.object({
    identifier: z.string(),
    status: z.enum(["pending", "valid", "invalid", "revoked", "deactivated"]),
    errorType: z.string().nullable(),           // ACME problem URN, e.g. …:error:dns
    errorDetail: z.string().max(1000).nullable(),
  })).readonly(),
  rateLimitOverridden: z.boolean(),             // audited when true (REQ-ACME-14)
  startedAt: UtcInstantSchema, finishedAt: UtcInstantSchema.nullable(),
}).strict();
```

A production order requires a `valid` staging order over the same `names`
(REQ-ACME-14) — a query over this table, not a flag a caller can set.

## 6. `RenewalPolicy` (REQ-ACME-06, REQ-ACME-08, REQ-ACME-09)

```ts
export const RenewalPolicySchema = z.object({
  /** Down to 1 h per REQ-ACME-08; 1440 is the ceiling, above which REQ-ACME-09's
   *  "ARI checks at least daily" cannot hold. */
  checkIntervalMinutes: z.number().int().min(60).max(1440).default(360),
  /** Subtracted from the ARI window's END, not from notAfter (§11). Must be >=
   *  checkIntervalMinutes, enforced at boot (REQ-FND-07). */
  safetyMarginHours: z.number().int().min(1).max(720).default(8),
  /** Used ONLY when renewalInfo is unavailable. Not a schedule (§11). 0.5 is
   *  correct at both 160 h and 90 d. */
  fallbackLifetimeFraction: z.number().min(0.1).max(0.9).default(0.5),
  profile: z.string().default("classic"),
  /** Floor after a CA *validation* failure: the budget refills at 1 per 12 min
   *  per identifier. A network error uses 2 min instead. */
  validationRetryFloorMinutes: z.number().int().min(12).default(15),
}).strict();
```

Five knobs; only the first two are expected to be touched (REQ-ACME-08).

## 7. `DnsProviderDescriptor` (REQ-ACME-18) — adding a provider is data

```ts
export const DnsCredentialFieldSchema = z.object({
  key: z.string().regex(/^[a-z][a-zA-Z0-9]*$/),
  labelKey: z.string(), hintKey: z.string(),   // i18n keys; the hint states the minimum scope
  secret: z.boolean(),                         // true ⇒ encrypted, write-only, rule GENERATED (§10)
  pattern: z.string().nullable(),              // shape check only, never trust-bearing
}).strict();

export const DnsProviderDescriptorSchema = z.object({
  id: z.string().regex(/^[a-z][a-z0-9-]*$/), label: z.string().max(80),
  apiBase: z.string().url().startsWith("https://"),  // IS the egress allowlist entry (REQ-SEC-12)
  minimumScope: z.string().max(200),                 // shown in the form (REQ-ACME-18)
  credentials: z.array(DnsCredentialFieldSchema).readonly(),
  operations: z.object({ findZone: DnsOperationSchema, listTxt: DnsOperationSchema,
                         createTxt: DnsOperationSchema, deleteTxt: DnsOperationSchema }),
  propagationHintSeconds: z.number().int().min(0).max(3600),  // hint only; REQ-ACME-04's
  supportsWildcard: z.boolean(),                              // authoritative check decides
  adapter: z.string().nullable(),   // bounded escape hatch; a descriptor is still required
}).strict();
```

A `manual` descriptor is always present with `credentials: []`: DNS-01 must work
for a zone hosted at a registrar with no API.

## 8. `RenewalLogEntry` (REQ-ACME-10)

```ts
export const RenewalLogEntrySchema = z.object({
  id: z.string().uuid(),
  certificateId: z.string().uuid().nullable(), orderId: z.string().uuid().nullable(),
  at: z.string().datetime({ offset: false }),  // UTC, millisecond precision
  level: ConsoleLevelSchema,                   // reused from console-stream
  event: z.string().max(80),                   // audit-action grammar: "dns.authoritative-check"
  msg: z.string().max(512),
  /** Scalars only, 200 chars each. A PEM or a response body cannot fit. */
  fields: z.record(z.string(), z.union([z.string(), z.number(), z.boolean(), z.null()])),
  correlationId: z.string().uuid(),
}).strict();
```

This row projects 1:1 onto `ConsoleFrameSchema` with `domain: "acme"` — the
additive CCR in `spec/acme-tls.md` §6. **No second stream protocol and no second
redactor:** the durable row and the live frame come from the same redacted value.

## 9. Table shapes

All five are `tenantScoped: false` (§1). Migrations:
`db/migrations/A25/<timestamp>__<slug>.sql`. Every `*_enc` column is envelope
ciphertext and appears in no read model (§1).

```sql
acme_accounts (A25)
  id uuid pk, directory_url text, account_uri text, key_thumbprint text,
  contact_email text, status text, offered_challenges text[], renewal_info_url text,
  offered_profiles text[], registered_at timestamptz, key_rotated_at timestamptz,
  private_key_enc bytea not null, unique (directory_url, account_uri)

certificates (A25)  -- entity-base envelope applies
  id uuid pk, account_id uuid -> acme_accounts, names text[], challenge_type text,
  issuer_kind text, issuer_cn text, profile text, staging boolean, status text,
  serial text, spki_sha256 text, not_before timestamptz, not_after timestamptz,
  ari_window_start timestamptz, ari_window_end timestamptz, ari_explanation_url text,
  next_attempt_at timestamptz, next_check_at timestamptz, last_renewal_at timestamptz,
  last_renewal_result text, consecutive_failures int, persist_state text,
  persist_until timestamptz, edge_store_path text, installed_at timestamptz,
  chain_pem text, leaf_pem text, private_key_enc bytea not null,
  check (status <> 'active' or installed_at is not null),
  check (persist_state is null or challenge_type = 'dns-persist-01')

cert_orders (A25)
  id uuid pk, certificate_id uuid, account_id uuid, order_url text, names text[],
  challenge_type text, staging boolean, replaces text, status text,
  authorizations jsonb, rate_limit_overridden boolean default false,
  started_at timestamptz, finished_at timestamptz

cert_renewal_log (A25)  -- append-only, entity-base exempt
  id uuid pk, certificate_id uuid, order_id uuid, at timestamptz, level text,
  event text, msg text, fields jsonb, correlation_id uuid not null

dns_providers (A25)
  id uuid pk, descriptor_id text, label text, zone text, credentials_enc bytea not null,
  created_at timestamptz, last_used_at timestamptz, unique (descriptor_id, zone)
```

`cert_renewal_log` takes the same `entity-base` exemption as `audit_events` —
`updated_*` columns on an append-only table are a contradiction. A25 writes the
justification; A02 records it.

## 10. Server-derived only, and the redaction declarations

**A caller may supply exactly three things:** `names`, `challengeType` and
`profile` on an order; `RenewalPolicy` values; a `DnsProvider`'s `zone` and its
credential values. **Every other field in this file is server-derived and
rejected from a request** — the CA-reported ones (`serial`, `notBefore`,
`notAfter`, `ariWindow*`, `orderUrl`, `authorizations`, `accountUri`,
`keyThumbprint`, `offered*`, `renewalInfoUrl`), the scheduler-computed ones
(`nextAttemptAt`, `nextCheckAt`, `lastRenewal*`, `consecutiveFailures`,
`replaces`), and the installer-owned ones (`status`, `installedAt`,
`edgeStorePath`, `spkiSha256`, `chainPem`, `leafPem`, `persistState`).

| Field | Mode | Why |
|---|---|---|
| `acme_accounts.private_key_enc` | `drop` | In no read model; a rotation reads as `[redacted] → [redacted:changed]` |
| `certificates.private_key_enc` | `drop` | Same |
| `dns_providers.credentials_enc` | `drop` | Generated from every `secret: true` descriptor field (§7) |
| JWS `signature`, `payload`, `jwk` | `drop` | Scrubbed, never dumped (REQ-ACME-12, REQ-AUD-05) |
| HAProxy Runtime API payload | `drop` | The payload is a PEM containing the private key |
| `RenewalLogEntry.fields.*` | scalar, 200 chars | A PEM cannot be attached to a frame |
| `acme_accounts.contact_email` | `hash` | Declared PII; events stay correlatable without the address |
| `certificates.names` | none | A SAN list is in the public certificate; redacting it breaks the inventory |

**The credential `drop` rules are generated, not hand-written.** Every
`secret: true` descriptor field produces its declaration at assembly, so a new
provider cannot ship an unredacted credential. A25's test plants such a
descriptor and asserts assembly fails.

## 11. Additive vs breaking

**Additive**
- **A new `ChallengeType`**, with its `CHALLENGE_CAPABILITIES` row. Nothing
  compares challenge types by index and no filter is ordered over them, so a new
  member widens the input without changing what an existing value means. This is
  the expected path for the next validation method.
- A new `CertificateStatus`, `offeredProfiles` string, `DnsProviderDescriptor`,
  `RenewalLogEntry.event` name, or appended `TerminationMode`; a new optional
  field on any schema here; a new `RenewalPolicy` knob **with a default**, since
  an absent value must keep meaning what it meant.

**Breaking — orchestrator arbitration (REQ-CTR-03)**
- **Changing the renewal-timing semantics under the same field name. This is the
  worst break in this contract and it is called out here for that reason.**
  `nextAttemptAt` means "the instant the next attempt runs"; redefining it as a
  deadline, a window start or a duration keeps every type check passing, keeps
  the breaking-change detector silent, and produces a fleet that renews at the
  wrong time. The same applies to `safetyMarginHours` (subtracted from the
  window's **end**, not from `notAfter`) and to `fallbackLifetimeFraction` (used
  **only** when ARI is unavailable — treating it as the schedule reintroduces
  the fixed-fraction bug REQ-ACME-07 exists to remove). A timing semantic change
  gets a new field name and a deprecation window, always.
- Making `ChallengeType` ordered, or comparing it by index anywhere.
- Adding a private-key field to any read model, in any form, including masked.
- Making `staging` optional, or defaulting it to `false`.
- Declaring any table here `tenantScoped: true`: the RLS shape would change for
  a path that runs before a session exists. A per-tenant custom domain gets a
  new `tenant_domains` table instead.
- Removing the `persist_state`/`challenge_type` check constraint, which is what
  keeps a `needs_republish` flag meaningful (REQ-ACME-05).
