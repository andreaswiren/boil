# REST API

Owner: `rest-api-engineer`. Requirements: `SZ-API-001`…`007`, `SZ-HSM-009`,
`SZ-HSM-011`, `SZ-INS-005`, `SZ-OS-006`, `SZ-OS-007`, `SZ-AUTH-004`,
`SZ-AUTH-007`, `SZ-SEC-006`.

Versioned under `/api/v1`. **The OpenAPI document is authoritative** — this file
explains the decisions behind it; where they disagree, the schema is the
contract (`contracts/ownership.md`) and this file is the bug.

Surface compared against NetHSM's `docs/nethsm-api.yaml` (56 endpoints, 78
operations) at commit `2a1bac5d`. `spec/17-nethsm-parity.md` records what we
adopt and what we decline.

## 1. The state machine is in the API, not inferred from failures

NetHSM returns **`412 Precondition Failed` on 74 of its 78 operations**, with the
description naming the state required — *"NetHSM is not in state Operational"*.
That is the single best idea in their API and we adopt it.

| Code | Meaning here |
|------|-------------|
| `412` | **Wrong appliance state.** Body names the current state and the required one. |
| `401` | No or bad credential. |
| `403` | Authenticated, not permitted — role, tag restriction or policy. |
| `409` | Right state, conflicting resource (duplicate id, concurrent job). |
| `429` | Rate limited (`SZ-SEC-006`), with `Retry-After`. |

A client that cannot distinguish *locked* from *broken* retries forever and the
operator sees an outage instead of a prompt. So `412` is never a generic error:
the body carries `{ state, required }`, and `GET /health/state` is
**unauthenticated** (`SZ-API-005`) so that a caller can learn this without a
credential — a locked appliance cannot authenticate anyone anyway, since the
authentication store is still ciphertext.

## 2. Authentication: where we deliberately exceed NetHSM

NetHSM's `securitySchemes` is **HTTP Basic**, single scheme, for every operation.
For a device on an isolated management network that is a defensible choice. For
an appliance signing artefacts from CI it is not, and this is the main place we
should be *more* capable rather than at parity.

| Caller | Mechanism | Why |
|--------|-----------|-----|
| CI workload | **Workload OIDC** (`SZ-AUTH-004`) — the token is bound to repository, ref and workflow | A long-lived API key in a CI secret store is the credential most likely to leak and least likely to be rotated. |
| CI, where OIDC is unavailable | mTLS with a per-workload certificate | Second choice, stated as such. |
| CI, last resort | Narrowly scoped service credential, expiring | Third choice, and the profile records that it was used. |
| Human | Session from password+TOTP or passkey (`SZ-AUTH-001`), step-up for sensitive actions (`SZ-AUTH-003`) | |
| Monitoring | `Metrics` role only (`SZ-API-006`) | Graphing must not hold an operator credential. |
| Backup client | `Backup` role only (`SZ-HSM-011`) | Fetches ciphertext it cannot read. |

**Basic auth is not offered at all.** Not deprecated — absent. Offering it means
it gets used.

## 3. The signing lifecycle — our product surface

This is the part NetHSM does not have. A signing request is a **job with a
state machine**, not a synchronous sign call (`SZ-FUN-002`).

```
POST /api/v1/signing-requests          → 201, job in `pending`
GET  /api/v1/signing-requests/{id}     → state, approvals, decision trail
POST /api/v1/signing-requests/{id}/cancel
GET  /api/v1/signing-requests/{id}/artifact   → the signed result
GET  /api/v1/signing-requests/{id}/verification → what a verifier should check
```

**The request binds to what is being signed and by whom** (`SZ-API-002`):
artifact digest, signing profile, requester identity, repository and ref, and an
expiry. The binding is recorded at submission and re-checked before the HSM is
touched, so an approval cannot be replayed against a different artifact.

**The server recomputes the digest** from the bytes it received. A
client-supplied digest is an input to be checked, never a value to trust — a
signing appliance that signs a digest it was handed is a signing oracle with
extra steps.

Large artefacts stream to a content-addressed store, and the job references the
digest rather than the upload. Signing does not hold the artefact in memory.

**Idempotency** (`SZ-API-004`): `Idempotency-Key` on every mutating operation.
A retried submission returns the original job rather than creating a second one;
a CI runner that retries on a network blip must not produce two signatures.

## 4. Key and certificate lifecycle (`SZ-API-007`)

Adopted from NetHSM, because a signing appliance whose CSR step is manual will
have its CSR step done wrong:

```
GET    /api/v1/keys/{id}/public.pem     the public half
POST   /api/v1/keys/{id}/csr.pem        CSR for a key that never leaves the HSM
GET    /api/v1/keys/{id}/cert           the issued certificate
PUT    /api/v1/keys/{id}/cert           store it after issuance
DELETE /api/v1/keys/{id}/cert
PUT    /api/v1/keys/{id}/restrictions/tags/{tag}     second authorization axis
DELETE /api/v1/keys/{id}/restrictions/tags/{tag}
```

Tag restriction is enforced **at the key** and independently of the policy engine
(`SZ-AUTH-005`), so a policy mistake does not by itself unlock every key.

**Not adopted, and recorded as decisions** (`spec/17-nethsm-parity.md` §7):
`POST /random`, and `encrypt`/`decrypt` on keys. A signing appliance is not an
entropy service, and one that decrypts is a decryption oracle.

## 5. Appliance lifecycle

```
POST /api/v1/provision            one-shot; gone after (SZ-INS-005)
POST /api/v1/unlock               (SZ-HSM-009)
POST /api/v1/lock                 back to ciphertext without a reboot
GET  /api/v1/health/{alive,ready,state,diagnose}
GET  /api/v1/metrics              Metrics role
PUT  /api/v1/config/backup-passphrase
POST /api/v1/system/backup        404 until a passphrase exists (SZ-HSM-011)
POST /api/v1/system/restore       diff, then step-up (SZ-HSM-012)
POST /api/v1/system/update        upload to the inactive root
POST /api/v1/system/commit-update available only after verification (SZ-OS-006)
POST /api/v1/system/cancel-update
POST /api/v1/system/factory-reset audited destruction (SZ-OS-007)
```

`lock` matters operationally: an operator who suspects compromise can return the
appliance to ciphertext without physical access and without a reboot that might
not come back.

## 6. Rate limiting, with numbers (`SZ-SEC-006`)

NetHSM's figures, adopted because they are checkable: **one failed unlock per
second per source address**, and **one failed authentication per second per
source address and username**. Per-username matters — limiting only by address
lets an attacker behind one NAT spray many accounts, and limiting only by
username lets a distributed attacker bypass it entirely.

Successful requests are not limited by this; a CI fleet signing legitimately must
not be throttled by a control aimed at guessing.

## 7. Everything is audited, including refusals

Every mutating operation and every authorization failure emits an audit event
(`SZ-AUD-001`) carrying the caller, the bound identity, the decision and the
reason. **A denied request is the more interesting record**, and an audit log
that only contains successes cannot answer the question an incident asks.

No request or response body is logged wholesale — the audit event carries the
digest and the decision, never the artefact and never a credential
(`SZ-SEC-005`).

## 8. How this is verified

- Every operation is reachable only in its declared state; calling it in another
  returns `412` with both states named.
- `GET /health/state` answers without a credential, including while locked.
- A `Metrics` credential cannot read a key, a job or a backup.
- A `Backup` credential fetches a backup and cannot decrypt it.
- A replayed `Idempotency-Key` returns the original job, not a second signature.
- A submission whose bytes do not match its claimed digest is refused before the
  HSM is opened.
- An approval for artefact A cannot authorize the signing of artefact B.
- Rate limits are asserted at the stated numbers, per address **and** per
  username.
- The OpenAPI document and the implementation are checked against each other in
  CI; drift fails the build rather than being discovered by a client.
