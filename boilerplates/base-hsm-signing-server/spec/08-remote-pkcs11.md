# Remote PKCS#11 compatibility

Owner: `remote-provider-engineer`. Requirements: `SZ-API-003`, `SZ-SEC-003`.
**Optional** — off unless intake enables it.

## 1. What this is, and what it must never become

Some tooling only speaks PKCS#11. The compatibility module exists so those tools
can work against the appliance, and it is **a policy-constrained API client that
presents a PKCS#11 interface locally** — never network access to the HSM.

The distinction is the entire specification:

| A remote PKCS#11 bridge | This module |
|------------------------|-------------|
| Exposes the token over the network | Exposes nothing; it is a client |
| Caller picks mechanism and object | Policy resolves both |
| `C_Login` carries the HSM PIN | The PIN never leaves `signerd`; the module authenticates as a workload |
| Enumeration reveals the key store | Enumeration returns the keys policy grants, and nothing else |
| A signing oracle if credentials leak | Still bound by policy, approval and audit |

`SZ-SEC-003` forbids a raw network PKCS#11 interface. This module does not
weaken that rule; it exists because someone will otherwise build one.

## 2. Where it runs

On the **caller's** machine, as a PKCS#11 provider `.so` loaded by their tool. It
speaks the appliance's REST API over TLS. There is no listener on the appliance
that speaks PKCS#11 — the appliance's surface is unchanged by this feature
existing.

## 3. The surface it implements, and the surface it refuses

Implemented: `C_Initialize`, `C_GetSlotList`, `C_OpenSession`, `C_Login` (against
a workload credential, not a PIN), `C_FindObjects` over policy-visible keys,
`C_SignInit` / `C_Sign` for the mechanisms the profile fixes, and reading public
keys and certificates.

**Refused, returning `CKR_FUNCTION_NOT_SUPPORTED`:**

- `C_GenerateKeyPair`, `C_CreateObject`, `C_DestroyObject` — key lifecycle is an
  appliance operation with approval and audit, not a library call.
- `C_WrapKey`, `C_UnwrapKey` — the DKEK path is a ceremony
  (`spec/05-hsm-dkek.md`), not an API.
- `C_Decrypt`, `C_DeriveKey` — the appliance does not decrypt at all
  (`spec/17-nethsm-parity.md` §7).
- `C_GetAttributeValue` for anything sensitive.
- Any mechanism not fixed by the signing profile. A caller choosing a mechanism
  is a caller choosing a weakness.

An unimplemented function returns the PKCS#11 error rather than approximating the
behaviour. A convenience shim here is a hole in the policy engine.

## 4. Approval still applies

A `C_Sign` against a profile requiring approval **blocks until the approval
happens**, or returns a pending error the caller can poll — configured per
profile, never bypassing.

The temptation is obvious: PKCS#11 callers expect synchronous signing, so it is
natural to exempt them. That exemption would mean the approval requirement is
whatever the caller's library happens to be, which is not a security control.
Where a profile genuinely needs unattended signing, that is a policy grant
(`spec/06-signing.md` §3) and it is visible on the dashboard.

## 5. Credentials and audit

The module authenticates as a workload (`SZ-AUTH-004`) — OIDC first, mTLS
second, a scoped credential last. It never holds an HSM PIN, because there is
nothing for a PIN to authenticate to from there.

Every operation through the module is audited identically to the same operation
through the REST API, and the event records that it arrived through the
compatibility module. An operation whose audit trail depends on which client
library called it is an operation with two security models.

## 6. How this is verified

- The appliance exposes no PKCS#11 listener — asserted by port scan, not by
  design intent.
- `C_FindObjects` returns only policy-visible keys for the authenticated
  workload, and a second workload sees a different set.
- Every refused function returns `CKR_FUNCTION_NOT_SUPPORTED` rather than a
  partial implementation.
- A mechanism outside the profile is refused.
- A profile requiring approval does not sign through the module without one.
- Audit events from the module are indistinguishable in completeness from REST
  events, and carry the module as the channel.
