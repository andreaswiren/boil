---
name: nextjs-secure-admin
description: Secure Next.js App Router admin surfaces — Server Components by default, typed actions, CSP with nonces, and no path from the web tier to a device or to root. Load for SignZone web work.
---

# Secure Next.js admin

Design: `spec/16-ui.md`, `spec/01-architecture.md`.

## What this tier is not allowed to be

The web tier is the largest dependency tree in the appliance and it renders
untrusted input. It holds **no device access and no root** (`SZ-SEC-002`). It can
*ask* `signerd` for a signature and *request* a typed operation from `osd`; it
decides neither.

If a change would give the web tier a new capability rather than a new request,
that is an architecture change and needs review.

## Defaults

- **Server Components by default.** Client components are a deliberate choice,
  one at a time.
- Data access through typed server actions and route handlers. No generic query
  endpoint; the browser never holds a database credential.
- **No secret in the client bundle** — asserted by scanning the built output,
  not by convention (`SZ-SEC-005`).

## CSP is a security control here, not a checkbox

Per-request nonces, no `unsafe-inline`, no `unsafe-eval`, and **the app works
without them** rather than needing an exception (`SZ-SEC-007`).

The approval screen is where a human decides what gets signed. A script injected
there can lie about what is being approved. WebAuthn step-up narrows it — the
assertion binds to a challenge derived from the request — but CSP is what stops
the injection.

## Sessions

Server-side, opaque cookie, `HttpOnly` + `Secure` + `SameSite=Strict` +
`__Host-` prefix, rotated on privilege change.

## Errors that help

A `412` says "the appliance is Locked; unlock it to continue" with the required
state — not "request failed". A policy denial names the rule. An expired request
says expired.

## Definition of done

- [ ] Built client bundle contains no secret — scanned.
- [ ] CSP has no `unsafe-inline` or `unsafe-eval` and the app works.
- [ ] No route gives the web tier a device path or a root operation.
- [ ] Client components are enumerable and each was a decision.
- [ ] Error states name the state, the rule or the reason.
