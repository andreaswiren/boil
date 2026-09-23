---
name: identity-stepup
description: Local password+TOTP, passkeys/WebAuthn, Entra OIDC, sessions, step-up authentication and recovery, with anti-phishing as the design goal. Load for any login, session or approval-authentication work.
---

# Identity and step-up

Design: `spec/04-identity-auth.md`.

## Non-negotiable

**Password-only login does not exist** — unimplemented, not merely disabled
(`SZ-AUTH-001`).

**Passkeys are preferred over TOTP** and the UI should say so. Passkeys are
origin-bound, so a phishing page cannot relay them. TOTP is a shared secret a
convincing page harvests in real time — and an appliance that signs software is
worth a convincing page.

## OIDC: key on subject, never email

Key federated identity on **tenant + subject** (`SZ-AUTH-002`). Email addresses
get reassigned, and an account keyed on email silently becomes a different person
when a leaver's address is reused. Store the email to display; never match on it.

Discovery URLs are an **SSRF primitive** — fetch only from allowlisted
destinations (`SZ-OS-010`).

## Step-up is about the action, not the session

Step-up re-authenticates for a specific action, so a stolen session is not enough
(`SZ-AUTH-003`). Required for: approving, DKEK ceremonies, restore, factory
reset, policy and role changes, unlock/lock, egress and firewall changes.

**For approvals, derive the WebAuthn challenge from the request binding.** Then
the assertion is evidence about *that request* rather than proof a human was
present, and it cannot be replayed against a different one. This is the single
most important implementation detail in the file.

## Sessions

Server-side, opaque cookie, `HttpOnly` + `Secure` + `SameSite=Strict` +
`__Host-` prefix, rotated on privilege change, short-lived.

## Recovery codes

Generated when a second factor is enrolled, shown once, stored **hashed**,
single-use. An appliance with no recovery path grows a support process that
bypasses authentication, which is worse than the codes.

## Rate limiting with numbers

One failed unlock per second per address; one failed authentication per second
per address **and** username (`SZ-SEC-006`). Both dimensions — per-address alone
lets an attacker behind one NAT spray accounts; per-username alone lets a
distributed attacker through.

**Rate-limit, do not disable accounts.** An attacker who can lock out accounts by
guessing has a denial-of-service primitive.

## Definition of done

- [ ] Password-only cannot be configured.
- [ ] An OIDC identity survives an email change and does not survive a subject
      change.
- [ ] A step-up action refuses an hour-old session.
- [ ] An approval assertion does not verify against a different request.
- [ ] Rate limits asserted at the stated numbers, both dimensions.
- [ ] Every authentication failure is audited.
