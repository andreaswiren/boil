# Authentication, MFA & Federation

Three method families — password+TOTP, passkeys, OIDC — one identity, one
server-side session. Owned by **A03** (`auth-identity`): `packages/auth/**`,
`apps/<app>/app/(auth)/**`, and the tables `users`, `credentials`,
`mfa_factors`, `recovery_codes`, `sessions`, `oidc_providers`, `identity_links`.
A03 publishes `session`, `auth-policy`, `mfa`; it consumes `entity-base`,
`rbac`, `audit-event`, `theme-tokens`, `i18n:auth`. A03 defines no permissions
(A04) and writes no audit rows (A13) — it emits events.

## Requirements covered

REQ-AUT-01 … REQ-AUT-10, REQ-SEC-06, REQ-SEC-07, REQ-SEC-09, REQ-SEC-11,
REQ-UI-02, REQ-AUD-01, REQ-AUD-04, REQ-MAIL-05, REQ-TST-05.

## 1. Identity keying

An identity is keyed on **`(issuer, subject)`**, never on email.

```sql
identity_links (A03)
  issuer  text not null,  -- "https://login.microsoftonline.com/<tid>/v2.0" | "local"
  subject text not null,  -- provider oid/sub | local user uuid
  user_id uuid not null references users(id),
  unique (issuer, subject)
```

Email is mutable, re-assignable and provider-controlled; keying on it is an
account-takeover primitive. Email is a contact attribute, verified separately
(REQ-MAIL-05), never a join key. A login presenting a known email with an
unknown `(issuer, subject)` is a linking request, not a match, and linking
requires an already-authenticated session (§9).

## 2. Password + TOTP (REQ-AUT-01)

```
anonymous ──POST /auth/password──┬─ invalid → AWAIT_CREDENTIAL (uniform body + timing)
                                 └─ valid   → PENDING_MFA (partial session, 5 min, 0 perms)
PENDING_MFA ──/auth/totp     → AUTHENTICATED
            ──/auth/recovery → AUTHENTICATED + force_enrol
            ──5 failures or timeout → LOCKED_OUT (REQ-SEC-11)
PENDING_ENROL (policy requires MFA, no factor) ── enrol → recovery codes once → AUTHENTICATED
```

Argon2id for passwords, parameters in `packages/crypto` (A01), not here
(REQ-SEC-07). TOTP is RFC 6238, SHA-1, 6 digits, 30 s step, ±1 step drift.
Seeds are envelope-encrypted (REQ-SEC-06), never returned by any read after
enrolment. The last accepted step counter is stored and a code at or below it is
rejected, so a valid code is single-use. The partial session uses its own cookie
name, carries zero permissions, and is upgradable only by the MFA routes. Wrong
email and wrong password return an identical body and status in the same latency
band (REQ-MAIL-05).

## 3. Passkeys (REQ-AUT-02)

WebAuthn Level 2. `residentKey: "required"`, `userVerification: "required"`,
`attestation: "none"`, challenges single-use with a 60 s TTL bound to the cookie.

- A passkey asserting `uv: true` **satisfies MFA on its own** — one ceremony
  proves possession and verification. `uv: false` is refused outright.
- RP ID comes from validated config; a mismatch fails boot, not first login.
- Sign-count regression, where the authenticator reports counters, emits
  `auth.passkey.counter_regression` and refuses the assertion.
- Backup flags (`be`/`bs`) are stored and surfaced, so a synced passkey is
  distinguishable from a hardware-bound one in the session list.

## 4. OIDC federation (REQ-AUT-03)

Authorization Code + PKCE (`S256`), `state` and `nonce` mandatory, every
endpoint read from the discovery document. We never hand-configure a URL.

| Provider | Discovery URL shape |
|---|---|
| Entra ID | `https://login.microsoftonline.com/{tenantId}/v2.0/.well-known/openid-configuration` |
| Authentik | `https://{host}/application/o/{app-slug}/.well-known/openid-configuration` |
| Keycloak | `https://{host}/realms/{realm}/.well-known/openid-configuration` |

| Concern | Entra ID | Authentik | Keycloak |
|---|---|---|---|
| Stable subject | `oid` + `tid` — `sub` is **pairwise per app registration** | `sub` | `sub` |
| Groups | `groups`, only if the app registration requests it; **replaced by `_claim_names`/`_claim_sources` on overage** | `groups`, names, per scope | `groups`, or `realm_access.roles` / `resource_access.*.roles` by mapper |
| Email | optional; `preferred_username` is often a UPN | with `email` scope | with `email` scope |

Decisions that follow:

- **Entra is keyed on `oid`+`tid`.** `oidc_providers.subject_claim` defaults
  to `sub`, set to `oid` for the Entra adapter.
- **A group-claim overage refuses the login** (`oidc-group-overage`), audited.
  Treating an overage as "no groups" silently strips a user's roles.
- `iss` is compared string-equal to the discovery document's `issuer`. Entra's
  `common` authority is not supported — each tenant is explicit.
- Group-to-role mapping is declarative per provider (`group_mappings jsonb`);
  edits are audited as permission changes (REQ-RBA-08).
- Discovery and JWKS cached per `Cache-Control`, min 5 min, max 24 h, refetched
  on an unknown `kid`, always via A01's egress client (REQ-SEC-12). Client
  secrets are envelope-encrypted (REQ-SEC-06).
- OIDC satisfies MFA **only when the provider asserts it**: `amr` contains
  `mfa`/`hwk`/`otp`, or `acr` matches `oidc_providers.mfa_assertion`. Otherwise
  the user lands in `PENDING_MFA` for a local second factor.

## 5. Policy matrix (REQ-AUT-04, REQ-AUT-05)

Effective policy is the intersection. A tenant may only narrow.

| Setting | Global | Tenant | Effective |
|---|---|---|---|
| `password_totp_enabled` | set | set | `global AND tenant` |
| `passkey_enabled` | set | set | `global AND tenant` |
| `oidc_enabled` | set | set | `global AND tenant` |
| `oidc_providers` | registers | selects from registered | subset |
| `mfa_required` | set, default `true` | may set `true`, may **not** set `false` | `global OR tenant` |
| `step_up_max_age` | ceiling | lower only | `min` |
| session idle / absolute | ceiling | lower only | `min` |

A tenant enabling a globally disabled method gets
`policy-forbidden-by-global-tier`; the attempt is audited.

**Turning MFA off** — the exact path, no shortcut exists:

1. `global.auth_policy.write`, a global-tier permission (REQ-RBA-06). No tenant
   role can hold it.
2. Step-up within 300 s (§6) — a live session is not enough.
3. Typed confirmation of the literal `DISABLE MFA FOR ALL TENANTS`. A checkbox
   is not acceptable (REQ-AUT-05).
4. A `reason`, minimum 20 characters, stored on the audit event.
5. `auth.policy.mfa_disabled` emitted with a before/after diff (REQ-AUD-04),
   `severity: critical`, plus a notification to every global operator.
6. A permanent banner on every authenticated page until re-enabled. The banner
   cannot be dismissed. Re-enabling needs the permission but no typed string.

## 6. Step-up re-authentication (REQ-AUT-07)

A step-up is a fresh TOTP code, a fresh passkey assertion, or a fresh OIDC
`prompt=login`. Re-entering a password is **not** a step-up for a user who holds
an MFA factor.

| Action | Window |
|---|---|
| Role / permission change (REQ-RBA-08) | 300 s |
| Tenant create or delete | 300 s |
| API key mint or scope change (REQ-API-04/05) | 300 s |
| Auth policy change (REQ-AUT-04/05) | 300 s |
| Any global-tier write (REQ-RBA-06) | 300 s |
| Export (REQ-GRD-13) | 900 s |
| Impersonation entry (REQ-RBA-07) | 60 s |
| Hard delete (REQ-ENT-02) | 60 s |

`session.last_step_up_at` is server-side and never extended by activity. The
check is declared per operation in the route kit (`spec/api.md`), so a route
cannot forget it: an operation tagged with a step-up action but missing
`stepUp` fails CI. Failure is `403` problem type `step-up-required`, naming the
accepted methods; the client re-proves and retries.

## 7. Recovery codes (REQ-AUT-06)

Ten codes, generated the moment the user enrols their **first** factor — not at
account creation, not on demand. Crockford base32, rendered `XXXXX-XXXXX`, 50
bits each. Shown **exactly once** on the enrolment completion screen with copy
and download, `Cache-Control: no-store`, not re-derivable server-side. Stored
Argon2id-hashed, one row per code, nullable `used_at` (REQ-SEC-07). Single-use:
consumption stamps `used_at`, emits `auth.recovery_code.consumed`, and sets
`force_enrol` so the user re-enrols before reaching the app. At three remaining,
a banner and an email. Regenerate requires step-up, invalidates all ten in one
transaction, issues ten new, emits `auth.recovery_codes.regenerated` — no
partial top-up. Zero remaining does not lock the account; recovery then needs
`global.user.recover`, reason-required and audited.

## 8. Session model (REQ-AUT-10, REQ-SEC-09)

Server-side, opaque, revocable. The cookie is a random 256-bit id; nothing is
derivable from it.

```
sessions (A03)
  id, user_id, tenant_id, state (partial|authenticated|revoked),
  created_at, last_seen_at, last_step_up_at, absolute_expires_at,
  ip inet, user_agent, method (password_totp|passkey|oidc:<provider>), amr text[],
  impersonated_by, impersonation_expires_at, superseded_by,
  revoked_at, revoked_by, revoke_reason
```

Cookies use the `__Host-` prefix, `HttpOnly`, `Secure`, `SameSite=Lax` for the
session and `Strict` for the privileged marker (REQ-SEC-09).

**Rotation on privilege change**: the id is regenerated and the old one killed on
login, MFA completion, step-up success, a role change affecting this user,
tenant switch, and impersonation entry **and** exit. Rotation writes a new row
with `superseded_by` set, so the trail stays continuous.

Idle timeout 8 h, absolute 12 h, both tenant-lowerable. The row is read per
request — Postgres is the only datastore (REQ-FND-05) — so revocation takes
effect on the next request and a revoked row fails closed. A user revokes their
own sessions including the current one; `auth.session.revoke` covers a tenant; a
global operator crosses tenants. Every revocation is audited with actor and
reason.

## 9. Account linking (REQ-AUT-09)

One `users` row holds many `identity_links` and many `mfa_factors`. Linking
starts **from an authenticated session**: the user proves the new method inside a
live session and the new `(issuer, subject)` is bound. A login never auto-links
on a matching email. If the pair is already bound elsewhere, linking is refused
(`identity-already-linked`) — users are never merged automatically.

**Unlinking the last policy-satisfying factor is refused.** The check simulates
the removal, re-evaluates the effective policy (§5), and returns
`last-factor-refused` if the remaining set cannot produce an authenticated
session. With `mfa_required: true` and password+TOTP as the only method, TOTP
cannot be removed until a passkey is enrolled. Recovery codes do **not** count —
they are break-glass, not a method. Links and unlinks are audited with the
issuer, a subject prefix (never the full subject), and the resulting factor set.

## 10. Login screen (REQ-AUT-08)

The shadcn `login-02` block, A06's tokens, every string from the `auth.*`
namespace (REQ-I18N-02). Method order follows tenant policy with the
intake-resolved default first. Passkeys use conditional mediation so the common
case is one tap. OIDC buttons are labelled from `oidc_providers.display_name`,
never a raw issuer URL. No method reveals whether an account exists and the
email field does not validate existence on blur. A rate-limit trip renders the
same generic message as a wrong password, with `Retry-After`.

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Identity key | `(issuer, subject)` | Email is mutable and provider-controlled | No |
| Entra subject claim | `oid`+`tid` | Entra `sub` is pairwise per app registration | No |
| Group-claim overage | Refuse the login | Silent empty groups strip roles | No |
| Passkey `uv: true` | Satisfies MFA alone | One ceremony, both properties | No |
| Passkey `uv: false` | Refused | REQ-AUT-02 requires user verification | No |
| TOTP drift | ±1 step | Tolerates skew without widening replay | Yes |
| Recovery codes | 10, Argon2id, single-use, not a policy factor | REQ-AUT-06; break-glass is not a method | No |
| Step-up standard window | 300 s | Fits a multi-step admin flow | Yes, lower only |
| Step-up for impersonation / hard delete | 60 s | Highest consequence | Yes, lower only |
| Session idle / absolute | 8 h / 12 h | One working day, no overnight carry | Yes, lower only |
| Session store | Postgres row read per request | REQ-FND-05, instant revocation | No |
| MFA default | Required | REQ-AUT-05 | Only as a recorded intake answer |
| OIDC without an MFA assertion | Local second factor required | An IdP that does not assert MFA has not done MFA | Yes, per provider |
| Auto-link on matching email | Never | Takeover primitive | No |
| Login block | shadcn `login-02` | REQ-AUT-08, REQ-UI-02 | No |

## How this is verified

- `pnpm test:mfa` — `tests/mfa-enforcement/**` (REQ-TST-05): no-factor user
  cannot reach `(app)` under `mfa_required`; a partial session is rejected by
  every non-MFA route; TOTP counter replay fails; `uv: false` fails; MFA-off
  demands the exact typed string and emits the critical event.
- `pnpm test:integration` — `tests/integration/auth/**`: recovery-code
  lifecycle (10 → consume 1 → regenerate invalidates all 10), session rotation
  at each of the seven triggers, revocation effective on the next request,
  last-factor unlink refusal across every method combination.
- `pnpm test:unit` — `tests/unit/auth/**`: per-provider claim mapping against
  recorded discovery and ID-token fixtures for all three providers, including
  the Entra `_claim_names` overage and an `iss` mismatch.
- `pnpm test:e2e` — `tests/e2e/auth/**` (Playwright over CDP, REQ-TST-02):
  full password+TOTP journey; passkeys via the CDP virtual authenticator; OIDC
  against the compose-dev Keycloak; step-up interception on an API-key mint.
- `pnpm test:audit` — `tests/audit-emission/**`: every REQ-AUD-01 event A03 owns
  fires once with actor, method, `amr` and result.
- `pnpm test:visual` — `tests/visual/auth.spec.ts`: `login-02` at 390/834/1440,
  light and dark, axe AA (REQ-TST-06), plus the MFA-off banner.
- `pnpm test:contract` — `packages/contracts/tests/session.spec.ts`: the
  `Session` shape A13 reads for on-behalf-of matches what A03 writes (REQ-CTR-10).
  Plus `GET /api/v1/auth/_selftest` (REQ-CTR-08).

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| Default method on the login screen | `password-totp`, passkey and OIDC also offered |
| Which OIDC providers get live config | All three; all three implemented and tested regardless |
| MFA required globally | Yes, no tenant opt-out |
| TOTP issuer label / session idle+absolute | `scope.app.title` / 8 h and 12 h |
| Self-service registration | No — users are invited by an admin |
| Password minimum length | 12 characters, no composition rules, offline breach-list check |
| May a tenant register its own OIDC provider | No — global registers, tenant selects |
