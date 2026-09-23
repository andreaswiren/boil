---
name: hsm-pkcs11
description: Nitrokey HSM 2 via OpenSC, PC/SC and PKCS#11 — device identity, session handling, key generation, CSR and certificate objects, and the mechanisms the signer is allowed to use. Load for any HSM integration work.
---

# HSM and PKCS#11

Design: `spec/05-hsm-dkek.md`, `spec/06-signing.md` §5.

## Identity, not enumeration

**Address the token by serial.** Slot and reader order change when a device is
re-seated or a reader is added, and a DR unit that silently becomes slot 0 is how
a ceremony runs against the wrong device (`SZ-HSM-005`).

Resolve the serial at daemon start and on every reconnect, and **fail closed**
when the expected serial is absent. Never fall back to "the first token found".

## What `signerd` may do, and what it must refuse

`signerd` holds the only handle to the device (`SZ-SEC-002`). It accepts a key
reference **the policy engine resolved** — never a PKCS#11 URI, label or id from
a caller — and uses the mechanism the signing profile fixes, never one chosen per
call.

It is **not a PKCS#11 proxy** (`SZ-SEC-003`). No mechanism enumeration for
callers, no arbitrary object access, no `C_Decrypt`, no key lifecycle by library
call.

## Secrets

- **The PIN never appears in a command line, an environment variable that gets
  logged, or a `pkcs11:` URI** (`SZ-SEC-005`, rule 10). It reaches the provider
  through a channel that does not show up in `/proc`.
- PIN retry counters are finite. Handle a wrong-PIN path deliberately — an
  automatic retry loop will brick a production token.
- Never log the key handle, the PIN, or a digest's preimage.

## Sessions

Long-lived sessions die when a reader glitches. Detect, reconnect, re-resolve by
serial, and re-verify the token is the expected one before continuing — a
reconnect that lands on a different device is worse than a failure.

Serialise access: concurrent sessions against one SmartCard-HSM produce
intermittent failures that read like hardware faults.

## Testing

Software mode (emulator or software token) for CI, **real-HSM mode tagged** for
release (`spec/14-testing.md` §4). Be explicit that software mode cannot prove
DKEK ceremonies, KCV comparison, PIN retry behaviour or reader enumeration — mark
those REQ IDs `unverified` rather than letting the suite report green.

## Definition of done

- [ ] Device resolved by serial; an absent expected serial fails closed.
- [ ] No PIN in any process argument — asserted against `/proc` during a signing
      operation.
- [ ] A caller cannot choose a mechanism or address an unresolved key.
- [ ] Reconnect re-verifies device identity.
