# Identity, authentication and authorization

Owner: `auth-identity-engineer` with `rbac-policy-engineer`. Requirements:
`SZ-AUTH-001`…`007`, `SZ-SEC-004`, `SZ-SEC-006`.

## 1. Human authentication (`SZ-AUTH-001`)

**Password-only login does not exist.** Not discouraged — unimplemented. Local
production users authenticate with password + TOTP, or with a passkey.

Passkeys are preferred and the UI says so, for one reason: they are
**origin-bound**, so a phishing site cannot relay them. TOTP is a shared secret
a convincing page can harvest in real time, and an appliance that signs software
is worth a convincing page.

Recovery codes are generated when a second factor is enrolled, shown once,
stored hashed, and single-use. An appliance with no recovery path produces a
support process that bypasses authentication, which is worse than the codes.

## 2. Federated identity (`SZ-AUTH-002`)

Microsoft Entra ID over OIDC, keyed on **tenant + subject**. Never on email.

Email addresses are reassigned, and an account keyed on email silently becomes
someone else when a leaver's address is reused. The subject claim is stable and
opaque; the email is a display attribute we store for humans to read and never
match on.

Issuer configuration is explicit — issuer URL, allowed tenant, allowed audience —
and discovery documents are fetched from an allowlisted destination
(`SZ-OS-010`), because an OIDC discovery URL is an SSRF primitive otherwise
(`spec/02-threat-model.md` §4).

## 3. Workload identity (`SZ-AUTH-004`)

A preference order, stated so the weakest option is a recorded decision rather
than a default:

1. **Workload OIDC.** The token is minted by the CI platform per job and carries
   repository, ref and workflow. Short-lived, not stored, and bound to the thing
   that is actually building.
2. **mTLS** with a per-workload certificate, where the platform cannot mint OIDC.
3. **A narrowly scoped, expiring service credential**, last resort, and the
   signing profile records that it was used.

A long-lived API key in a CI secret store is the credential most likely to leak
and least likely to be rotated. Where one is used anyway, it is scoped to one
profile, expires, and its use is visible on the dashboard.

## 4. Step-up (`SZ-AUTH-003`)

Sensitive actions require a **recent, fresh** authentication — not a session that
was strong once.

| Action | Why step-up |
|--------|-------------|
| Approving a signing request | The whole product |
| DKEK ceremony, restore, factory reset | Irreversible |
| Policy or role change | Changes what is authorized next |
| Unlock, lock | Changes the appliance's state |
| Egress or firewall change | Can exfiltrate or lock out |

Step-up is **WebAuthn where the user has a passkey**, because it binds the
assertion to the challenge and the origin. For approvals the challenge is derived
from the request binding (`spec/09-pwa-approvals.md`), so the step-up is evidence
about *that* request rather than proof the human is still present.

## 5. Roles (`SZ-AUTH-007`)

Four, each with a stated power, and a role not in this list does not exist:

| Role | Can | Cannot |
|------|-----|--------|
| `Administrator` | Manage identity, policy, keys, devices, appliance lifecycle | Approve a request they raised; read key material |
| `Operator` | Submit requests, approve requests raised by others | Change policy or roles |
| `Metrics` | Read counters | See a request, a key or a backup |
| `Backup` | Fetch backups | Decrypt them |

"Administrator" is not a synonym for "can read key material". No role can, and
the HSM is what enforces it.

## 6. Two independent authorization axes

The mistake worth designing against is a single point of authorization failure.
So there are two, and both must agree:

1. **The policy engine** (`spec/06-signing.md`) — resolves profile, key, required
   approvals and constraints.
2. **Tag restriction at the key** (`SZ-AUTH-005`) — a key carries tags, a user
   carries tags, and use requires a match. Enforced where the key is used, not
   where policy is evaluated.

A policy-engine bug therefore does not by itself unlock every key, and a tag
misconfiguration does not bypass policy.

## 7. Namespaces (`SZ-AUTH-006`)

Where two teams share an appliance, a namespace scopes users and keys, and maps
to an HSM key domain (`spec/05-hsm-dkek.md` §2) so one tenant's wrapped backups
cannot be unwrapped into another's. `SHOULD`, blocking unless intake states the
appliance is single-tenant — because retrofitting namespaces onto a populated
appliance means re-keying.

## 8. Sessions and rate limiting

Sessions are server-side, referenced by an opaque cookie — `HttpOnly`, `Secure`,
`SameSite=Strict`, `__Host-` prefix — rotated on privilege change, and short.

Rate limits carry numbers (`SZ-SEC-006`): one failed unlock per second per source
address, one failed authentication per second per source address **and** username.
Both dimensions, because per-address alone lets an attacker behind one NAT spray
accounts, and per-username alone lets a distributed attacker through.

Every authentication failure is audited (`SZ-AUD-001`). Lockout is
rate-limiting rather than account disabling: an attacker who can disable accounts
by guessing has a denial-of-service primitive.

## 9. How this is verified

- Password-only login cannot be configured, not merely defaults off.
- An OIDC identity whose email changes remains the same user; one whose subject
  changes does not.
- A step-up-requiring action refuses a session that authenticated an hour ago.
- An approval's WebAuthn assertion does not verify against a different request.
- `Metrics` and `Backup` credentials are asserted to fail on every other endpoint.
- Rate limits are asserted at the stated numbers, both dimensions.
- A requester cannot approve their own request, through the API or the UI.
