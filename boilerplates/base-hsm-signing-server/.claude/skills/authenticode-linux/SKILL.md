---
name: authenticode-linux
description: Authenticode and PowerShell signing on Linux with osslsigncode, OpenSSL 3 providers, RFC 3161 timestamps and post-sign verification. Load for any Windows signing flow.
---

# Authenticode on Linux

Design: `spec/06-signing.md` §6. This is the capability NetHSM does not have —
it signs digests and has no opinion about PE files.

## The stack

- **PE and MSI** — `osslsigncode` against the HSM through OpenSSL 3's PKCS#11
  provider.
- **PowerShell** — Authenticode over the script's canonical form.

Versions are resolved by the version validator, never written from memory.

## Timestamping is not optional

**Every signature carries an RFC 3161 timestamp.** Without one, the signature
stops verifying the day the certificate expires — the defect that surfaces years
later, on machines nobody can update, long after the person who signed it left.

- The timestamp authority is an **allowlisted egress destination**
  (`SZ-OS-010`). Default-deny egress means it is unreachable until named.
- **A timestamping failure fails the signature.** Never emit an untimestamped
  signature because the TSA was down. Retry, then fail.

## Verify your own output

**Verify the signature on the appliance, before returning it.** A signing step
that reports success without verifying its own output will eventually hand a
corrupt signature to a customer, and the customer will find out first.

Check: the signature verifies, the chain builds to the expected root, and the
timestamp is present and valid.

## No PIN anywhere it can be read

`osslsigncode` and OpenSSL both accept a PIN on the command line or in a
`pkcs11:` URI. **Neither is permitted** (`SZ-SEC-005`, rule 10) — a command line
is world-readable on a running system via `/proc`.

The PIN reaches the provider through a channel that does not appear in process
arguments or the environment of a logged process. Assert it: inspect
`/proc/<pid>/cmdline` during a signing operation.

## Definition of done

- [ ] Every produced signature verifies against the key's certificate.
- [ ] Every signature carries a valid RFC 3161 timestamp.
- [ ] A TSA outage produces a failure, never an untimestamped signature.
- [ ] No PIN in any process argument — asserted, not reviewed.
- [ ] Post-sign verification runs on the appliance before the artefact is
      returned.
