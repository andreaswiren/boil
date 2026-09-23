---
name: remote-pkcs11-compat
description: The optional PKCS#11 compatibility module as a policy-constrained API client, never network access to the HSM. Load for external provider compatibility work.
---

# Remote PKCS#11 compatibility

Design: `spec/08-remote-pkcs11.md`. **Optional** — off unless intake enables it.

## What it is

A PKCS#11 provider `.so` that runs on the **caller's** machine and speaks the
appliance's REST API. There is no listener on the appliance that speaks PKCS#11;
the appliance's attack surface is unchanged by this feature existing
(`SZ-SEC-003`).

It exists because someone will otherwise build a real remote PKCS#11 bridge.

## Refuse, do not approximate

Return `CKR_FUNCTION_NOT_SUPPORTED` for: `C_GenerateKeyPair`, `C_CreateObject`,
`C_DestroyObject`, `C_WrapKey`, `C_UnwrapKey`, `C_Decrypt`, `C_DeriveKey`,
sensitive `C_GetAttributeValue`, and any mechanism the profile does not fix.

A convenience shim here is a hole in the policy engine. Key lifecycle is an
appliance operation with approval and audit, not a library call; the DKEK path is
a ceremony, not an API.

## Approval is not waived for PKCS#11 callers

The temptation is obvious — PKCS#11 callers expect synchronous signing. Exempting
them would make the approval requirement depend on which client library called,
which is not a security control.

Block until approved, or return a pending error to poll. Configured per profile,
never bypassed. Genuine unattended signing is a policy grant, visible on the
dashboard.

## Credentials

Authenticate as a **workload** (OIDC, then mTLS, then a scoped credential). The
module never holds an HSM PIN — there is nothing for a PIN to authenticate to
from there.

## Audit

Identical completeness to the same operation over REST, plus the channel. An
operation whose audit trail depends on the client library has two security
models.

## Definition of done

- [ ] No PKCS#11 listener on the appliance — asserted by port scan.
- [ ] `C_FindObjects` returns only policy-visible keys, and differs per workload.
- [ ] Every refused function returns the PKCS#11 error, not a partial
      implementation.
- [ ] A profile requiring approval does not sign through the module without one.
