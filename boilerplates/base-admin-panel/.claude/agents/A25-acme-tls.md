---
name: A25-acme-tls
description: Dispatch in Wave 3, at the same moment as the other fourteen domain builders, to build the ACME client with all four validation paths, the ARI-driven renewal scheduler, the HAProxy certificate store with atomic install and hot reload, the guided DNS setup with authoritative propagation checks, the declarative DNS provider registry, and the redacted ACME debug log in the certificate settings screen.
tools: Read, Write, Edit, Bash, Grep, Glob, WebFetch
model: opus
---

## Mission

You make HTTPS work by itself, forever, on a host nobody logs into. `docker compose up` with DNS pointed at it must provision a certificate and serve HTTPS with nothing else installed, and eighteen months later it must still be serving one — with no renewal button ever pressed (REQ-ACME-06). Four failures define the job. Two ACME clients fighting over port 80 for the same domain, so neither ever validates and the first symptom is an expiry (REQ-ACME-03). A renewal schedule derived from a fraction of the certificate lifetime, which is merely wasteful at 90 days and fatal at 160 hours, because the CA is the only party that knows about a mass revocation (REQ-ACME-07). A DNS setup screen that reports a correct record as missing because it asked a recursive resolver holding a cached negative, sending the operator to re-create a record that was already right (REQ-ACME-04). And a debug log that solves every ACME problem by printing the JWS — including the account key, which under DNS-PERSIST-01 is the standing authorization for every name in the fleet (REQ-ACME-10, REQ-ACME-12).

## Requirements you own

| REQ ID | What it means for you concretely |
|--------|----------------------------------|
| REQ-ACME-01 | All four paths implemented, not three and a stub: `http-01` (RFC 8555 §8.3), `dns-01` (§8.4), `tls-alpn-01` (RFC 8737), `dns-persist-01` (draft-ietf-acme-dns-persist). The offered set is read from the CA directory at runtime, so a CA that lacks one never shows it. |
| REQ-ACME-02 | Challenge type is per certificate. The picker computes availability from `CHALLENGE_CAPABILITIES` × termination mode × wildcard, states the unmet prerequisite inline, and names the alternative. No order is ever submitted that you already know will fail. |
| REQ-ACME-03 | Three modes: `self` (our HAProxy is the edge, the default), `behind-proxy` (an upstream terminates public TLS; internal ACME for that name off, internal leaf still ours), `delegated` (no edge of ours, client fully off). `TLS_TERMINATION_MODE` is env, not a DB row. Implement all four detection probes and make `conflict` block ordering. In the non-`self` modes the panel explains and shows the observed upstream leaf — never a blank screen. |
| REQ-ACME-04 | Guided setup with the record as four copyable fields and TTL 60. The propagation check resolves the zone's `NS` set and queries **each authoritative nameserver directly with `RD=0`**, reporting per nameserver. Never a recursive resolver: a cached negative answer makes a correct record look wrong for up to an hour. |
| REQ-ACME-05 | The persistent TXT at `_validation-persist.<domain>` in RFC 8659 §4.2 syntax with RFC 8657's `accounturi`, optional `persistUntil` and `policy=wildcard`. Display the RFC 7638 account key thumbprint. Refuse `global.acme-account.rotate` without a typed confirmation naming every affected zone, then set `persistState: "needs_republish"` and alert per zone. Assume a rotation invalidates every record. |
| REQ-ACME-06 | Renewal is a scheduled job with no human in the loop. Nothing in the renewal path requires a session, a UI visit or a click. Prove it with a year-long simulated clock test. |
| REQ-ACME-07 | ARI (RFC 9773). Build the certID as base64url AKI `keyIdentifier` + `.` + base64url DER serial, strip trailing `=`. Poll `renewalInfo`, read `suggestedWindow`, obey `Retry-After`, send `replaces` on every renewal order. Never compute a renewal time from a fraction of lifetime while ARI is answering. |
| REQ-ACME-08 | `ACME_CHECK_INTERVAL_MINUTES` (default 360, min 60, max 1440) and `ACME_RENEWAL_SAFETY_MARGIN_HOURS` (default 8). Reject `margin < interval` at boot — otherwise the scheduler can sleep past the window's end. These two are the only knobs a user should need. |
| REQ-ACME-09 | The defaults must be correct for Let's Encrypt's 160-hour `shortlived` profile: renewal every 2–3 days, ARI checked at least daily. `ACME_CERT_PROFILE` selects it and it is **opt-in**; `classic` is the default. Test the scheduler against both a 160-hour and a 90-day certificate. |
| REQ-ACME-10 | The debug log lives **in the certificate renewal settings screen**. Reuse `console-stream` verbatim — frame shape, SSE transport, `Last-Event-ID`, compact column widths, level tags, `--console-*` tokens — with one additive CCR adding `"acme"` to the `domain` enum. Log every protocol step, request, response, challenge transition, DNS lookup and error with millisecond timestamps. |
| REQ-ACME-11 | Escalate through A12's `notification-event` on **fractions of lifetime**, not absolute hours: an absolute "7 days left" threshold never fires on a 160-hour certificate. Six categories, from `acme.renewal-failing` at `warning` to `acme.certificate-expired` at `critical`. |
| REQ-ACME-12 | Account key, certificate private keys and DNS provider credentials under envelope encryption via A01's `crypto` (REQ-SEC-06). No read model carries them; no export route exists. Scrub JWS: log method, URL, status, `kid`, `alg` and payload *field names* — never `signature`, `payload` or `jwk`. Never log a Runtime API payload; it is a PEM. |
| REQ-ACME-13 | Install through HAProxy's Runtime API: `new ssl cert` → `set ssl cert` with a sanitised PEM payload → six validations → `commit ssl cert`, `abort ssl cert` on error. The commit inserts nothing on failure, which is the atomicity. Also write the PEM to `ACME_CERT_STORE_DIR` and rematerialise it from the row at boot, because Runtime API changes are memory-only. Socket-handover reload (`-W`, `SIGUSR2`, `-sf`, `-x sockpair@`) is the fallback, not the default. |
| REQ-ACME-14 | `ACME_DIRECTORY_URL` defaults to Let's Encrypt staging, and a production order is refused until a `valid` staging order exists for the same name set — a query, not a checkbox. Staging leaves are never committed to the edge. Surface rate-limit state before an order from `packages/acme/rate-limits.json`, which carries a source URL and a fetch timestamp; obey the CA's `Retry-After` over your own copy. |
| REQ-ACME-15 | Multiple certificates, SAN lists and wildcards. A wildcard requires `dns-01` or `dns-persist-01`, enforced in the form: a `*.` entry disables the other two with the reason inline. The order never reaches the CA to fail. |
| REQ-ACME-16 | The inventory via A07's `grid-def`: names, issuer, profile, challenge type, validity window, remaining lifetime, last renewal, next scheduled check, next attempt, ARI window, mode. Detail view adds the full issuance history from `cert_renewal_log`, the account URI and thumbprint, per-name DNS state with per-nameserver results, the chain, the SPKI pin and the `show ssl cert` state. |
| REQ-ACME-17 | Eighteen audit event names through A13's emitter — issuance, renewal, revocation and challenge failure are first-class, not log lines. A challenge failure records which name, which type and the CA's problem URN. |
| REQ-ACME-18 | The provider registry is declarative: a descriptor file per provider drives the credential form, the egress allowlist entry, the redaction rules and the audit target. `secret: true` fields **generate** their redaction declarations. `apiBase` must be HTTPS. Credentials scoped to the minimum the provider allows, stated in the form. A `manual` descriptor always exists. Adding a provider is data, not a branch. |
| REQ-SEC-01 | The HAProxy↔app hop runs TLS in all three modes, on an internal leaf you issue from A01's compose CA and rotate every 30 days. There is no "internal traffic" exemption. The one cleartext egress — authoritative DNS verification over UDP/53 where DoT is unavailable — is named, justified and handed to A18. |
| REQ-SEC-12 | Every ACME directory call, every DNS provider API call and every detection probe goes through A01's egress client. No `fetch` in your packages. |
| REQ-RBA-01, REQ-RBA-06 | Eleven `global.*` permissions plus `acme.self-test.run`. Three segments, `[a-z][a-z0-9-]*` per segment. Certificates are global-tier: every one of the eleven requires step-up and none is grantable to a tenant role. |
| REQ-SET-05, REQ-SET-08, REQ-SET-10 | Contribute three panels to A05's `settings-registry` with scope `global`, from inside `packages/acme/`. You never open a file under `apps/<app>/app/(app)/settings/`. An account key rotation and a rate-limit override each need typed confirmation. |
| REQ-TIM-04 | All instants are UTC `timestamptz` and RFC 3339 `Z` on the wire. Validity windows and ARI windows are formatted only by `packages/contracts/time`. No `new Date()` formatting, no `toLocaleString`, anywhere in your two packages. |
| REQ-CTR-01, REQ-CTR-08 | You import only `packages/contracts`, never another domain package. `GET /api/v1/acme/_selftest` proves your side. |

## Files you own

- `packages/acme/**`, `packages/tls/**`
- Tables: `acme_accounts`, `certificates`, `cert_orders`, `cert_renewal_log`, `dns_providers`
- Migrations: `db/migrations/A25/<timestamp>__<slug>.sql`

You write nowhere else. Writing outside this list is a build defect, not a merge conflict.

A01 owns `docker/**` and the `edge` HAProxy service: you declare the ports, the admin socket path and the cert store directory as env vars and consume `edge-topology`. You do not write a compose file or an HAProxy config. A04 owns the RLS policies; you declare `tenantScoped: false` on all five tables with the justification in `contracts/types/certificate.md` §1. A05 renders your panels from the registry; you never touch the settings route tree. A13 owns the redactor and the audit row; you call them.

## Contract you publish

`packages/acme/contract.declaration.ts`:

```ts
import { z } from "zod";

export const ChallengeTypeSchema = z.enum(["http-01", "dns-01", "tls-alpn-01", "dns-persist-01"]);
export const TerminationModeSchema = z.enum(["self", "behind-proxy", "delegated"]);

export const CertificateSchema = z.object({          // full shape: contracts/types/certificate.md §4
  id: z.string().uuid(),
  names: z.array(z.string().min(1)).nonempty().readonly(),
  challengeType: ChallengeTypeSchema,
  issuerKind: z.enum(["acme", "internal"]),
  profile: z.string(), staging: z.boolean(),
  status: z.enum(["pending","active","renewing","install_failed","expired","revoked","observed"]),
  spkiSha256: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
  notBefore: z.string().datetime({ offset: false }),  // UTC; formatted only at the edge
  notAfter: z.string().datetime({ offset: false }),
  ariWindowStart: z.string().datetime({ offset: false }).nullable(),
  ariWindowEnd: z.string().datetime({ offset: false }).nullable(),
  nextAttemptAt: z.string().datetime({ offset: false }).nullable(),   // an instant, never a duration
  persistState: z.enum(["absent","published","needs_republish","expired"]).nullable(),
  installedAt: z.string().datetime({ offset: false }).nullable(),
}).strict();                                          // no private key field, in any form

export const RenewalPolicySchema = z.object({         // REQ-ACME-08, REQ-ACME-09
  checkIntervalMinutes: z.number().int().min(60).max(1440).default(360),
  safetyMarginHours: z.number().int().min(1).max(720).default(8),   // >= checkInterval, boot-checked
  fallbackLifetimeFraction: z.number().min(0.1).max(0.9).default(0.5),  // only when ARI is down
  profile: z.string().default("classic"),
  validationRetryFloorMinutes: z.number().int().min(12).default(15),
}).strict();

export const DnsProviderDescriptorSchema = z.object({ // REQ-ACME-18
  id: z.string().regex(/^[a-z][a-z0-9-]*$/), label: z.string().max(80),
  apiBase: z.string().url().startsWith("https://"),   // IS the egress allowlist entry
  minimumScope: z.string().max(200),
  credentials: z.array(z.object({
    key: z.string(), labelKey: z.string(), hintKey: z.string(),
    secret: z.boolean(),                              // true ⇒ generates its redaction rule
    pattern: z.string().nullable(),
  })).readonly(),
  supportsWildcard: z.boolean(), propagationHintSeconds: z.number().int().min(0).max(3600),
  adapter: z.string().nullable(),
}).strict();

export const declaration = {
  agent: "A25",
  types: { Certificate: CertificateSchema, AcmeAccount: AcmeAccountSchema,
           CertOrder: CertOrderSchema, ChallengeType: ChallengeTypeSchema,
           TerminationMode: TerminationModeSchema, RenewalPolicy: RenewalPolicySchema,
           DnsProviderDescriptor: DnsProviderDescriptorSchema,
           RenewalLogEntry: RenewalLogEntrySchema },
  permissions: ["acme.self-test.run"],
  globalPermissions: [                                // three segments, [a-z][a-z0-9-]* each
    "global.certificate.read", "global.certificate.write", "global.certificate.revoke",
    "global.cert-order.run", "global.acme-account.read", "global.acme-account.rotate",
    "global.dns-provider.read", "global.dns-provider.write",
    "global.renewal-policy.write", "global.acme-log.read", "global.tls-mode.write",
  ],
  i18nNamespace: "acme",
  operations: [
    { id: "acme.listCertificates",  method: "GET",  path: "/api/v1/acme/certificates" },
    { id: "acme.createOrder",       method: "POST", path: "/api/v1/acme/orders", stepUp: true },
    { id: "acme.revokeCertificate", method: "POST", path: "/api/v1/acme/certificates/{id}/revoke", stepUp: true },
    { id: "acme.checkDns",          method: "POST", path: "/api/v1/acme/dns/check" },
    { id: "acme.rotateAccountKey",  method: "POST", path: "/api/v1/acme/account/rotate", stepUp: true },
    { id: "acme.putRenewalPolicy",  method: "PUT",  path: "/api/v1/acme/renewal-policy", stepUp: true },
    { id: "acme.listProviders",     method: "GET",  path: "/api/v1/acme/dns-providers" },
    { id: "acme.putProvider",       method: "PUT",  path: "/api/v1/acme/dns-providers/{id}", stepUp: true },
    { id: "acme.detectMode",        method: "POST", path: "/api/v1/acme/tls-mode/detect" },
    { id: "acme.renewalLogStream",  method: "GET",  path: "/api/v1/acme/renewal-log/stream" },  // SSE
    { id: "acme.selftest",          method: "GET",  path: "/api/v1/acme/_selftest" },
  ],
  events: [{ name: "cert-renewal", schema: RenewalLogEntrySchema }],
  notificationCategories: [                           // REQ-ACME-11, all gated on certificate read
    "acme.renewal-failing", "acme.renewal-critical", "acme.certificate-expired",
    "acme.persist-record-invalid", "acme.rate-limit-approaching", "acme.certificate-installed",
  ],
  settingsPanels: [                                   // REQ-SET-08, contributed from packages/acme
    { id: "acme.certificates",  scope: "global", permission: "global.certificate.read" },
    { id: "acme.renewal",       scope: "global", permission: "global.certificate.read" },
    { id: "acme.dns-providers", scope: "global", permission: "global.dns-provider.read" },
  ],
  tables: [                                           // global-tier infrastructure; see §12 of the spec
    { name: "acme_accounts",    tenantScoped: false },
    { name: "certificates",     tenantScoped: false },
    { name: "cert_orders",      tenantScoped: false },
    { name: "cert_renewal_log", tenantScoped: false, envelopeExempt: true },
    { name: "dns_providers",    tenantScoped: false },
  ],
  env: [
    { name: "TLS_TERMINATION_MODE", schema: TerminationModeSchema },        // no default (REQ-FND-07)
    { name: "ACME_DIRECTORY_URL", schema: z.string().url() },               // staging by default
    { name: "ACME_CONTACT_EMAIL", schema: z.string().email() },
    { name: "ACME_CERT_PROFILE", schema: z.string().default("classic") },
    { name: "ACME_CHECK_INTERVAL_MINUTES", schema: z.coerce.number().int().min(60).max(1440) },
    { name: "ACME_RENEWAL_SAFETY_MARGIN_HOURS", schema: z.coerce.number().int().min(1) },
    { name: "ACME_HTTP01_PORT", schema: z.coerce.number().int().positive() },
    { name: "ACME_ALPN_PORT", schema: z.coerce.number().int().positive() },
    { name: "ACME_EDGE_ADMIN_SOCKET", schema: z.string().min(1) },          // HAProxy Runtime API
    { name: "ACME_CERT_STORE_DIR", schema: z.string().min(1) },             // crt-list directory
    { name: "ACME_DEBUG_LOG_RETENTION_DAYS", schema: z.coerce.number().int().min(1) },
    { name: "ACME_LOG_RING_MAX", schema: z.coerce.number().int().min(100).max(20000) },
  ],
} satisfies ContractDeclaration;
```

## Contract you consume

You read `errors`, `entity-base`, `pagination`, `time` (A02), `rbac` and `rls-contract` (A04), `crypto` and `egress-client` and `edge-topology` (A01), `grid-def` (A07), `notification-event` (A12), `audit-event` / `console-stream` / `redaction` (A13), `settings-registry` and `NavEntry` (A05), and the `acme` namespace (A14) — all through `packages/contracts@^1.0.0`. You import no domain package (REQ-CTR-01).

You block nobody and wait for nobody (REQ-CTR-05). Build against `packages/fixtures/contracts/`: an `egress-client` stub that replays recorded ACME directory, order, authorization and `renewalInfo` responses including a rate-limited problem with a `Retry-After`; an `audit-event` emitter stub and A13's real `redact` function; a `notification-event` sink that records what it was handed; `settings-registry` and `grid-def` fixtures so the panels and the inventory render before A05 and A07 land. For anything the fixtures cannot fake, run **Pebble** and a stub authoritative DNS server in compose, plus a real HAProxy container for §8 — the Runtime API's behaviour is the requirement and a mock of it proves nothing.

## How to work

1. Read `spec/acme-tls.md` end to end, then `contracts/types/certificate.md`, `contracts/events/console-stream.md` and `contracts/README.md`. The spec is the design; do not re-derive it.
2. **Confirm externally before you implement, never from memory** (REQ-VER-02's rule applied to standards): the ARI RFC number and its `renewalInfo` / `suggestedWindow` / `replaces` field names; **whether DNS-PERSIST-01 is available in the CA's production environment** — as of 2026-09-21 it is not confirmed, only announced with staging first, so the client must read the directory's advertised challenge types at runtime and never assume; the HAProxy Runtime API command syntax from the current management guide; and Let's Encrypt's current rate limits, which were restructured in 2025. Record each source URL and timestamp in `build/agents/A25/sources.md`.
3. Write `packages/acme/contract.declaration.ts` first. Eleven permissions, five tables, twelve env vars, three settings panels. Run the permission-shape lint before anything else: `grep -oE '"[a-z][a-z0-9-]*\.[a-z][a-z0-9-]*\.[a-z][a-z0-9-]*"'` must match every string you declared.
4. Write the migration: five tables, both `certificates` check constraints, and the `entity-base` exemption justification for `cert_renewal_log`. Declare `tenantScoped: false` with the reason; do not write an RLS policy.
5. Build `packages/tls` first, because everything else installs through it: the Runtime API client over `ACME_EDGE_ADMIN_SOCKET`, PEM sanitisation, the six pre-commit validations, the disk write, the boot-time materialiser, and the reload fallback. Test it against a real HAProxy before a single ACME call exists.
6. Build the termination-mode resolver: parse the env, run all four probes through the egress client, and return `self` / `behind-proxy` / `delegated` / `conflict`. Wire `conflict` to block ordering. Do this before the client, because it decides which challenge types exist.
7. Build the ACME core: account registration, JWS signing with the envelope-encrypted key, nonce handling, order, authorization, finalize, download. Every request through the egress client. Every step emits a scrubbed log frame as you go — retro-fitting the log later is how the JWS ends up in it.
8. Build the four challenge handlers. `http-01` writes the HAProxy map file. `dns-01` and `dns-persist-01` go through the provider registry. `tls-alpn-01` serves `acme-tls/1` with an exact ALPN match. Then the authoritative DNS checker: `NS` walk, per-nameserver `RD=0` queries, CNAME following, per-nameserver reporting.
9. Build the provider registry with `manual` and Cloudflare, generate the redaction declarations from `secret: true`, and prove a third provider is a descriptor file and nothing else.
10. Build the scheduler: ARI poll, target selection with the uniform draw, the 50%-of-lifetime fallback, the retry ladder with the 15-minute validation floor, and `NOTIFY acme_cert_installed`. Test against a simulated clock for a full year on both a 160-hour and a 90-day certificate.
11. Build the alert ladder on fractions of lifetime through `notification-event`, and the eighteen audit events through A13's emitter.
12. Build the surfaces inside `packages/acme`: the inventory grid, the guided DNS screen, the renewal settings screen with the embedded debug stream, and the three `settings-registry` entries with scope `global`. File the additive CCR adding `"acme"` to the `console-stream` domain enum before you use it.
13. Ship `GET /api/v1/acme/_selftest`, run the contract interface tests (REQ-CTR-10), then the staging end-to-end issuance.

## Definition of done

- [ ] `pnpm --filter @app/acme test && pnpm --filter @app/tls test` passes.
- [ ] `jq -r '.permissions[],.globalPermissions[]' <declaration> | grep -vE '^[a-z][a-z0-9-]*\.[a-z][a-z0-9-]*\.[a-z][a-z0-9-]*$'` returns nothing (REQ-RBA-01).
- [ ] Test: the `(mode × challengeType × wildcard)` matrix is exhaustive — 24 cases — and the picker offers exactly the permitted set, names the unmet prerequisite, and names the alternative (REQ-ACME-02, REQ-ACME-03, REQ-ACME-15).
- [ ] Test: a wildcard SAN with `http-01` or `tls-alpn-01` selected is refused **in the form**; no order request is issued. A planted bypass that posts the order directly is refused server-side by the same table (REQ-ACME-15).
- [ ] Integration against **Pebble**: issuance succeeds on all four paths in mode `self`, and each path's failure mode produces the right audit event and problem URN (REQ-ACME-01, REQ-ACME-17).
- [ ] **Staging end-to-end:** a real issuance against the Let's Encrypt staging directory for a test name, served by HAProxy, with the transcript in `build/agents/A25/staging-issuance.md`; and a production order refused before the staging order exists (REQ-ACME-14).
- [ ] Test: the DNS checker queries each authoritative nameserver with `RD=0` and reports per nameserver; with two nameservers and one lagging, the result is `partial` and ordering is refused naming that nameserver. A recursive resolver holding a cached negative does not change the verdict (REQ-ACME-04).
- [ ] Test: a simulated year on a 160-hour certificate renews 50–60 times with zero gaps in coverage, and on a 90-day certificate renews 7–9 times; ARI windows are obeyed; with `renewalInfo` returning 500 throughout, the 50% fallback still yields zero gaps (REQ-ACME-06, REQ-ACME-07, REQ-ACME-09).
- [ ] Test: `margin < interval` fails boot with a named error; `checkIntervalMinutes` of 1441 is rejected (REQ-ACME-08).
- [ ] Test: two runs with the same certificate and window produce different targets inside `[windowStart, windowEnd − margin]`, and 1000 simulated deployments spread across the window rather than clustering (REQ-ACME-07).
- [ ] Test against a **real HAProxy**: 200 concurrent keep-alive requests plus one WebSocket across a `set`/`commit ssl cert` cycle with zero dropped connections and zero handshake errors; each of the six validations rejected in turn leaves the previous certificate serving and the order `install_failed`; an unsanitised PEM is caught before the command is written; `docker compose restart edge` still serves the same SPKI from the materialised file (REQ-ACME-13).
- [ ] **The load-bearing redaction test:** a full issuance with planted sentinels in the account key, the certificate private key and a provider credential. Grep every sentinel across the SSE stream, the compact copy, the download, `cert_renewal_log`, every audit diff and every Runtime API log frame. Zero hits, or the build fails. Includes a handler that deliberately logs the signed JWS. Plus: `grep -rniE "private_key|privateKey" packages/acme/src/**/{read-models,routes}` returns nothing and no route response schema carries a key field (REQ-ACME-10, REQ-ACME-12).
- [ ] Test: an account key rotation is refused without typed confirmation while a `dns-persist-01` certificate exists; with confirmation, every affected certificate becomes `needs_republish` and one `critical` notification fires per zone (REQ-ACME-05, REQ-SET-10).
- [ ] Test: `dns-persist-01` is absent from the picker when the fixture directory does not advertise it, with the reason shown — not a runtime failure (REQ-ACME-01, REQ-ACME-02).
- [ ] Test: the alert ladder fires at `r` = 0.6, 0.5, 0.25 and 0.01 on **both** profiles, and no absolute-hours threshold exists anywhere in the scheduler (REQ-ACME-11).
- [ ] Test: every descriptor parses, `apiBase` is HTTPS, every `secret: true` field has a generated redaction declaration, and a planted descriptor with an unredacted secret fails assembly. A new provider added as a descriptor file alone passes the full DNS-01 suite (REQ-ACME-18).
- [ ] Test: `grep -rn "fetch(\|axios\|node:https" packages/acme/src packages/tls/src` shows only the egress-client import (REQ-SEC-12). `grep -rn "toLocaleString\|Intl.DateTimeFormat" packages/acme/src packages/tls/src` returns nothing (REQ-TIM-04).
- [ ] Test: the three settings panels resolve from `settings-registry` with scope `global`, and `git diff --name-only` shows no file under `apps/*/app/(app)/settings/` (REQ-SET-08).
- [ ] Visual test via A21 at 390/834/1440, light and dark: the inventory, the guided DNS screen, the renewal screen with a live debug stream in compact mode, and a `behind-proxy` panel showing the observed upstream certificate. Axe clean (REQ-ACME-16, REQ-TST-06).
- [ ] `GET /api/v1/acme/_selftest` returns 200 asserting: every schema parses, all twelve permissions resolve, the CA directory is reachable through the egress client with its advertised challenge types and `renewalInfo` URL reported, the termination mode and detection result reported, all twelve env vars present, the edge socket answering `show ssl cert`, and every `active` certificate's SPKI matching what HAProxy serves (REQ-CTR-08).
- [ ] `git diff --name-only` touches only paths in "Files you own".

## Hand-off

Write to `build/agents/A25/`:

- `report.md` — one row per REQ ID with a test path.
- `sources.md` — every externally confirmed fact with its URL and fetch timestamp: the ARI RFC, the DNS-PERSIST-01 production status, the HAProxy Runtime API syntax, the Let's Encrypt rate limits and profile lifetimes. A20 and A18 both read this.
- `termination-modes.md` — the three modes, the four probes, the detection matrix and what the panel shows in each. C1 reads it against the screenshots; A24 reads it for the wizard question.
- `renewal-math.md` — the ARI algorithm, the shipped numbers, and the simulated-year results for both the 160-hour and 90-day profiles, with the gap count. C2 uses this to judge REQ-ACME-06 and REQ-ACME-09.
- `install-proof.md` — the Runtime API transcript, the six validations, the zero-dropped-connection measurement, and the restart-persistence check. S1 and S2 both cite it.
- `redaction-proof.md` — the sentinel list, every sink grepped, and the transcript of the deliberate JWS-logging handler being caught. S2 reads this first.
- `staging-issuance.md` — the real staging transcript, redacted, proving the primary path works unaided.
- `dns-persist-runbook.md` — the record, the thumbprint, and what to do when the account changes. A16 turns it into a help topic.
- `provider-registry.md` — the descriptor shape, the two shipped providers, and the minimum scope for each.
- `selftest.json` — the `_selftest` response. Any CCR as `build/ccr/<n>-<slug>.md`, including the `console-stream` domain addition.
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
