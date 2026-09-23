---
name: installer-setup
description: The one-command Debian installer and one-time setup wizard, with idempotency, irreversible-step handling and rollback. Load for deployment or bootstrap work.
---

# Installer and setup

Design: `spec/13-installer-setup.md`.

## Idempotent, and resumable

Running twice reaches the same state; running after a partial failure resumes
rather than compounding. Never ask for a secret you could generate, and never
generate one you cannot show exactly once.

## Two steps cannot be undone

**The recovery key** is displayed once and never stored on the appliance. Without
it, a kernel or firmware change at the wrong moment is unrecoverable. Require
explicit confirmation that it was recorded — the one place in this product where
a "yes I wrote it down" checkbox is a real control.

**The Device Key** is generated only after the entropy gate passes
(`SZ-SEC-011`). Halt rather than proceed with a warning: a key from weak entropy
must be rotated and everything it signed re-examined.

## Setup mode closes permanently (`SZ-INS-003`)

HTTPS, a cryptographically random one-time token printed on the console — not a
default password, not an open form.

When setup completes, the **code path is gone**, not disabled by a flag. Setup
mode is by construction the one part of the system that creates an administrator
without an existing administrator, so anything that can re-enter it is a
privilege escalation path. Re-entry requires the physical console or a factory
reset.

## The DKEK gate (`SZ-HSM-003`)

**Refuse** production key generation on an HSM without a settled DKEK Key Check
Value. Hard stop, not a warning — `--dkek-shares` is fixed at `--initialize` and
initialising destroys existing keys, so the alternative is discovered months
later when the primary dies.

## Refuse clearly

No TPM (unless attended-only is chosen explicitly), Secure Boot disabled, a
non-empty target disk without confirmation naming it, or any configuration
leaving setup mode reachable. Each refusal names the condition and the remedy —
an installer that fails with a stack trace is one people work around.

**Never disable TLS verification** to make something work (`SZ-INS-004`).

## Definition of done

- [ ] A second run changes nothing; an interrupted run resumes.
- [ ] Setup mode is unreachable after completion, including by direct URL and by
      database manipulation.
- [ ] The token is single-use and expires.
- [ ] Key generation refused without a settled DKEK KCV.
- [ ] The installer halts on an unavailable entropy source.
- [ ] The recovery key appears once and is absent from the filesystem after —
      verified by scanning.
