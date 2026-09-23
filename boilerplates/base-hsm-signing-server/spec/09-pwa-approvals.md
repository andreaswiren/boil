# PWA and approvals

Owner: `pwa-approval-engineer` with `ui-ux-engineer`. Requirements:
`SZ-PWA-001`…`003`, `SZ-AUTH-003`.

## 1. The failure this is designed against

**Push fatigue.** An approver receiving notifications all day learns to dismiss
them, and the dismissal gesture and the approval gesture become the same
gesture. Every MFA-push compromise of the last decade worked this way.

So: **a push notification is never authorization** (`SZ-PWA-002`). It is a
prompt to come and look. The authorization happens against the request's details,
with something the notification did not carry.

## 2. What approval actually requires

Two things, and the notification is neither:

1. **The approver sees what is being signed** (`SZ-PWA-003`): artefact name and
   digest suffix, requester, repository and ref, signing profile, expiry. Not a
   count, not "a signing request" — the specifics, because an approver who cannot
   tell two requests apart is not approving, they are acknowledging.
2. **A transaction-bound proof**: either a **challenge code** shown in the
   requesting context and re-entered in the approving one, or a **WebAuthn
   assertion whose challenge is derived from the request binding**.

The WebAuthn path is preferred and is the reason it exists here: the assertion is
evidence about *that request*, not evidence that a human was present. A replayed
or phished assertion does not verify against a different binding.

## 3. The number-matching detail

Where the challenge-code path is used, the code is displayed **in the context
that raised the request** and typed **in the approval app**. Not the other way
around.

The direction is the whole control. A code shown in the approval app and typed
elsewhere can be read out by an attacker who has induced the approver to open the
app — which is precisely the push-fatigue scenario. Requiring the approver to
obtain the code from the requesting context means they must actually be the
person who initiated it, or in contact with them.

## 4. PWA, and what it is not for (`SZ-PWA-001`)

Installable, with Web Push, because approvers are not at a desk and an approval
that requires a laptop will be delegated to someone's browser tab that stays
logged in.

The service worker's job is narrow: receive a push, show a notification, open the
app. It does **not** cache request details, hold a session, or make an approval
decision. It is a delivery mechanism, and anything it stores is something an
attacker gets from the device.

Notification payloads carry **no artefact details** — only "you have a request to
review" and an id. The details come from an authenticated fetch when the app
opens. A notification is rendered on a lock screen, and a digest on a lock screen
is an information leak at best.

## 5. Offline, and why approval is not

The PWA works offline for reading. **Approval requires connectivity**, and the
app says so plainly rather than queueing.

A queued approval is an approval whose binding cannot be re-checked at the moment
it takes effect (`spec/06-signing.md` §4), and one that fires when the approver
is no longer looking. "Will submit when online" is exactly the property an
approval must not have.

## 6. Expiry and revocation

Requests expire (`spec/00-product.md` §3). An approval on an expired request is
refused with that reason, not silently ignored.

An approver can **withdraw** an approval until signing begins. After that the
answer is revocation of the signature, which is a different and much more
expensive procedure — and the UI says which side of that line the request is on.

## 7. Accessibility and the small screen

The approval surface is the one place where a design compromise becomes a
security problem. If the digest suffix is truncated to fit, two artefacts become
indistinguishable.

- Digest suffix is never truncated below the length the design fixes, at any
  viewport. The layout reflows; the evidence does not shrink.
- Approve and reject are not adjacent, and reject is not styled as the quiet
  option.
- The screen is legible at the largest supported system font without the details
  scrolling out of view above the buttons — an approver who must scroll up to see
  what they are approving will not.
- Full keyboard and screen-reader support, with the bound details announced
  before the actions.

## 8. How this is verified

- An approval submitted with only a valid session and no transaction proof is
  refused.
- A WebAuthn assertion for request A does not verify for request B.
- A notification payload contains no artefact name, digest or repository.
- The service worker holds no session or request detail after the app closes.
- The approval screen shows every field of `SZ-PWA-003` at 320 px width and at
  the largest system font, with the actions still below the details.
- A requester cannot approve their own request from the PWA.
- An expired request's approval is refused with "expired", not a generic error.
