---
name: pwa-approvals
description: Installable PWA, Web Push, and signing approvals bound to transaction details with number matching or WebAuthn step-up. Load for any approval or mobile notification work.
---

# PWA approvals

Design: `spec/09-pwa-approvals.md`.

## The failure being designed against is push fatigue

An approver receiving notifications all day learns to dismiss them, and the
dismissal gesture becomes the approval gesture. Every MFA-push compromise of the
last decade worked this way.

**A push notification is never authorization** (`SZ-PWA-002`). It is a prompt to
come and look.

## What approval requires

1. **The approver sees what is being signed** (`SZ-PWA-003`): artefact name and
   digest suffix, requester, repository and ref, profile, expiry. Specifics — an
   approver who cannot tell two requests apart is acknowledging, not approving.
2. **A transaction-bound proof**: a challenge code, or a WebAuthn assertion whose
   challenge derives from the request binding.

## Number matching has a direction, and it is the control

The code is displayed **in the context that raised the request** and typed **in
the approval app**. Not the reverse.

A code shown in the approval app and read out elsewhere can be harvested by an
attacker who induced the approver to open the app — which is the push-fatigue
scenario exactly. Requiring the approver to fetch the code from the requesting
context means they must be the initiator or in contact with them.

## The service worker is a delivery mechanism

It receives a push, shows a notification, opens the app. It does **not** cache
request details, hold a session, or decide anything. Whatever it stores is
whatever an attacker gets from the device.

**Notification payloads carry no artefact details** — an id and "you have a
request". Details come from an authenticated fetch. Notifications render on lock
screens, and a digest on a lock screen is a leak.

## Approval requires connectivity

Read offline; **never queue an approval**. A queued approval cannot have its
binding re-checked when it takes effect, and it fires when the approver is no
longer looking. "Will submit when online" is precisely the property an approval
must not have.

## Definition of done

- [ ] An approval with a valid session and no transaction proof is refused.
- [ ] An assertion for request A does not verify for request B.
- [ ] Notification payloads contain no artefact name, digest or repository.
- [ ] Every `SZ-PWA-003` field visible at 320 px and at the largest system font,
      with actions **below** the details.
- [ ] Digest suffix never truncated below the fixed length.
- [ ] A requester cannot approve their own request.
