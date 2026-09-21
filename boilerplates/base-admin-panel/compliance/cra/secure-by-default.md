# Secure-by-Default Configuration

Requirement: `REQ-CRA-02`. Annex I (3)(a) of [Regulation (EU) 2024/2847](https://eur-lex.europa.eu/eli/reg/2024/2847/oj).
Owner: **A18**. Enforcement point: the single env schema in `packages/config/**` (A01, `REQ-FND-07`).

Annex I (3)(a) asks two things: that the product is **made available with a
secure-by-default configuration**, and that it can be **reset to its original
state**. This file answers both, item by item, and says for each item what an
operator would have to do deliberately to make it worse.

## The rule that makes the table honest

`REQ-FND-07`: config is env-var driven, parsed and validated at boot by one Zod
schema, and **boot fails loudly on a missing or malformed value — never a silent
default for a security-relevant key**. So there are only three kinds of knob:

| Class | Meaning | How it is weakened |
|---|---|---|
| **A — welded** | The secure value is the only value the code accepts | Only by editing source and rebuilding. Not an operator action |
| **B — policy** | Changeable at runtime, global tier only, step-up authenticated, audited with a before/after diff | An explicit, attributable, logged decision (`REQ-AUT-07`, `REQ-RBA-06`, `REQ-RBA-08`) |
| **C — deployment** | Set by env var at deploy time; the schema constrains the range | Editing the environment file and restarting |

A class-A knob cannot be weakened by configuration. That is the point of it.

## Shipped defaults — transport and storage

| Item | Shipped default | Class | To weaken it, an operator must | REQ |
|---|---|---|---|---|
| Ingress TLS | TLS 1.3 preferred, TLS 1.2 floor, AEAD-only cipher list | A | Edit the reverse-proxy template in `docker/**` and rebuild. No env var exposes a lower floor | `REQ-SEC-02` |
| HTTP listener | Exists only to issue `308` to HTTPS | A | Edit the proxy config; there is no "allow plaintext" switch | `REQ-SEC-02` |
| HSTS | `max-age` at the shipped value with `includeSubDomains; preload` | A | Edit the proxy config | `REQ-SEC-02` |
| Database transport | `DATABASE_URL` **must** contain `sslmode=verify-full` and `sslrootcert=`; the app exits non-zero at boot otherwise, naming `REQ-SEC-03` | A | Remove the `.refine()` checks from `packages/config` and rebuild | `REQ-SEC-03` |
| Internal compose traffic | Encrypted, including between `app`, `db`, `smtp-relay` and `reverse-proxy` | A | Rebuild the compose stack without the dev CA wiring | `REQ-SEC-01` |
| SMTP submission | Implicit TLS on 465, or STARTTLS with certificate verification **required**. `STARTTLS optional` is not a value the enum accepts | A | Widen the enum in source | `REQ-SEC-04` |
| Syslog forwarding | RFC 5425 over TLS via `SYSLOG_TLS_URL`. Plain UDP/514 is unsupported | A | Replace the transport in `packages/syslog` | `REQ-SEC-05` |
| Column encryption | Envelope encryption on TOTP seeds, recovery codes, OIDC client secrets, API key material and SMTP credentials; `CRYPTO_KEK` is required with no default; `kek_version` stamped on every ciphertext | A | Remove the seal/open calls in the owning package | `REQ-SEC-06` |
| Password and token storage | Argon2id for passwords and recovery codes; SHA-256 of a high-entropy token for API keys | A | Change the primitive in `packages/crypto` | `REQ-SEC-07` |
| Outbound calls | One egress client; allowlist **empty by default**, so the shipped state denies every destination. Timeout, TLS verification and post-DNS SSRF guards always on | C (allowlist) / A (guards) | Add hosts to `EGRESS_ALLOWLIST`. Each added host is a documented widening of the egress surface (`docker/egress.md`) | `REQ-SEC-12`, `REQ-SUP-08` |

## Shipped defaults — identity and access

| Item | Shipped default | Class | To weaken it, an operator must | REQ |
|---|---|---|---|---|
| MFA | **Required** for every identity | B | Make a global-tier-only policy change with a typed confirmation; the change is audited. A tenant admin cannot do it | `REQ-AUT-05` |
| Auth methods enabled | Password+TOTP on, passkeys on, OIDC off until a provider is configured and validated | B | Change the global policy, then the tenant policy. A tenant cannot enable a method the global tier has disabled | `REQ-AUT-03`, `REQ-AUT-04` |
| Recovery codes | 10 single-use codes generated at first factor enrolment, displayed once, stored Argon2id-hashed | A | — | `REQ-AUT-06` |
| Step-up re-authentication | Required for role change, tenant creation, API key mint, policy change and export | A | Remove the guard from the action | `REQ-AUT-07` |
| Unlinking the last factor | Refused when it would drop the identity below policy | A | — | `REQ-AUT-09` |
| Sessions | Server-side and revocable; cookies `HttpOnly`, `Secure`, `__Host-` prefixed, `SameSite=Lax` for session and `Strict` for privileged, rotated on privilege change | A | — | `REQ-SEC-09`, `REQ-AUT-10` |
| Permission evaluation | Deny-by-default, server-side. Client-side gating is presentation only | A | — | `REQ-RBA-02` |
| Row Level Security | Enabled and `FORCE`d on every tenant-scoped table; the app connects as a non-owner role that cannot bypass RLS | A | Grant the app role ownership or `BYPASSRLS` — a database change outside the product's control, and the cross-tenant test suite fails immediately | `REQ-RBA-04`, `REQ-RBA-05` |
| Global-tier impersonation | Time-boxed, reason-required, banner-visible, audited on entry **and** exit. Default TTL `<<PLACEHOLDER: shipped impersonation TTL in minutes, as set in packages/config>>` | B (TTL) / A (rest) | Raise the TTL by global-tier policy change, audited | `REQ-RBA-07` |
| Hard delete | Soft delete is the default path; the hard-delete permission is assigned to **no** shipped role | B | Grant the permission explicitly at the global tier | `REQ-ENT-02` |
| Reads of deleted rows | Filtered out unless the caller holds the see-deleted permission | A | Grant that permission | `REQ-ENT-05` |
| Debug console access | The console permission is granted to **no** shipped role | B | Grant it explicitly. Output is redacted by the audit rules either way | `REQ-AUD-08`, `REQ-AUD-12` |
| API key expiry | Mandatory, with a shipped maximum of `<<PLACEHOLDER: maximum API key lifetime, as enforced in packages/api-kit>>` | C | Lower it only; the schema refuses a value above the maximum | `REQ-API-07` |
| Rate limits | Per-identity and per-IP limits on auth, API-key, password-reset and export routes, with lockout backoff and an audit event per trip. Shipped thresholds: `<<PLACEHOLDER: per-route-class rate limit defaults from packages/config>>` | C | Raise the thresholds. There is no value that disables the limiter | `REQ-SEC-11` |

## Shipped defaults — data handling and the browser

| Item | Shipped default | Class | To weaken it, an operator must | REQ |
|---|---|---|---|---|
| CSP | Strict, per-request nonces, no `unsafe-inline`, no `unsafe-eval`. No report-only escape hatch is shipped | A | Edit `middleware.ts` | `REQ-SEC-08` |
| Other security headers | `Referrer-Policy`, `X-Content-Type-Options`, `Permissions-Policy`, `Cross-Origin-Opener-Policy`, `Cross-Origin-Resource-Policy` all set | A | Edit `middleware.ts` | `REQ-SEC-08` |
| CSRF | Origin-checked double-submit on every state-changing route, including Server Actions | A | — | `REQ-SEC-10` |
| Remote assets | None. Fonts and assets are self-hosted; no third-party script loads at runtime | A | Add a remote origin — which fails the security gate | `REQ-SUP-07` |
| Service worker caching | Never caches an authenticated response or a tenant-scoped payload | A | — | `REQ-PWA-03` |
| Push payload content | A reference the client resolves over TLS after authenticating; no sensitive content in the payload | A | — | `REQ-PWA-04` |
| Audit trail | On, append-only, including successful reads and detail views; per-tenant hash chain with a verify job | A | Cannot be switched off. List-read **sampling rate** is class C; the trail is not | `REQ-AUD-01`..`REQ-AUD-06` |
| Redaction | Secrets and declared PII never reach an audit diff or the console in cleartext | A | — | `REQ-AUD-05`, `REQ-AUD-12` |
| Telemetry and phone-home | Disabled for every framework and tool, build-time and run-time (`NEXT_TELEMETRY_DISABLED=1`, `DO_NOT_TRACK=1`), asserted by test | A | Unset them in the image — the assertion test then fails | `REQ-SUP-06` |
| Legal hold | Off per tenant; when on, it blocks purge | B | — | `REQ-AUD-13` |

## What "reset to its original state" means here

This is server software with tenant data in it. A reset that wiped the database
would be a destructive command dressed as a compliance feature, and an operator
would never run it. So the reset is **configuration and policy only**, and it is
explicit about what it does not touch.

### Procedure — reset to secure state

Run as the operator on the host, with the stack stopped for steps 2–3.

1. **Record the reason.** Write it to the change record. The reset itself emits
   an audit event (`REQ-AUD-01`) with the actor and reason.
2. **Restore the shipped environment.** Diff the live environment against the
   generated template and revert every security-relevant key:
   ```bash
   docker compose exec app node -e "require('@app/config').printEnvTemplate()" > /tmp/env.shipped
   diff -u /tmp/env.shipped .env      # review every line before applying
   ```
   `.env.example` is generated from the assembled env declarations, never
   hand-maintained, so it is the authoritative statement of the shipped values.
3. **Boot and let the schema arbitrate.** `docker compose up -d`. If any key is
   missing or malformed the app exits non-zero and prints **every** offending
   key. A stack that boots has a valid security configuration by construction.
4. **Reset policy rows to shipped defaults.** Global tier, step-up
   authenticated:
   ```
   admin → platform → policy → Reset to shipped defaults
   ```
   This re-enables MFA enforcement, returns each auth method to its shipped
   state, returns the impersonation TTL and rate-limit thresholds to their
   shipped values, and clears the hard-delete, see-deleted and debug-console
   grants from every role. Emits one audit event per changed policy with a
   before/after diff (`REQ-RBA-08`).
5. **Revoke credentials that outlived the old configuration.** Kill all sessions
   (`REQ-AUT-10`) and revoke every API key minted under the weakened policy
   (`REQ-API-07`). Both are audited (`REQ-API-08`).
6. **Rotate the KEK** if the reset follows a suspected compromise:
   `rotateKek()` re-wraps DEKs without reading plaintext and bumps
   `kek_version` (`REQ-SEC-06`).
7. **Verify.** `curl -sf https://<host>/api/health/ready` must return 200 with DB,
   migrations, SMTP and syslog all reported healthy (`REQ-FND-10`), and the
   audit hash-chain verify job must report no break (`REQ-AUD-06`).

### What the reset deliberately does not do

- **It does not delete tenant data.** Data destruction is the offboarding
  procedure, not the reset.
- **It does not truncate the audit trail.** The trail is append-only by database
  privilege and trigger (`REQ-AUD-03`); a reset that could erase it would defeat
  Annex I (3)(e) and (3)(k).
- **It does not clear user preferences** — theme, locale, timezone, grid layout.
  None of them are security-relevant.
- **It does not re-issue the dev CA.** In production the CA is the operator's
  (`compliance/cer/applicability.md`).

### Rehearsal record

A reset procedure nobody has run is a claim, not a control.

| Field | Value |
|---|---|
| Last rehearsal date | `<<PLACEHOLDER: YYYY-MM-DD of the last reset-to-secure-state rehearsal>>` |
| Performed by | `<<PLACEHOLDER: name and role>>` |
| Result | `<<PLACEHOLDER: pass / fail, with the deviation if any>>` |
| Time to complete | `<<PLACEHOLDER: wall-clock minutes>>` |
| Next rehearsal due | `<<PLACEHOLDER: YYYY-MM-DD — at every minor release at the latest>>` |

## Known weakness of this document

It is hand-maintained, and `REQ-CRA-10` says compliance documentation should be
generated from repository state. A default can change in `packages/config`
without this table noticing. Until `compliance/tools/collect-evidence.ts` exists
and emits the default inventory from the assembled env schema, treat this table
as reviewed-at-release, and review it at every release.
