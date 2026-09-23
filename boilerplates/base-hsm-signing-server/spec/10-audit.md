# Audit

Owner: `audit-engineer`. Requirements: `SZ-AUD-001`, `SZ-AUD-002`,
`SZ-SEC-005`.

## 1. What the audit log is for

Answering, after the fact and to someone who does not trust us: *why does this
signature exist?* Every design choice below serves that question.

It follows that the log must survive the compromise of the thing it is logging.
An audit log an attacker can edit is not evidence, and one held only on the
appliance is not evidence about an appliance that was compromised.

## 2. Canonical events

Every event carries: timestamp (UTC, monotonic-checked), actor identity and how
they authenticated, action, subject, **decision**, reason, request binding where
one applies, appliance state, and the source address.

**Refusals are events.** A denied authorization, a failed unlock, a rejected
policy evaluation, a refused restore. An audit log containing only successes
cannot answer the question an incident asks, and the refusals are usually the
first evidence of an attack.

Serialisation is **canonical and frozen** — field order, encoding and number
representation are fixed, because the hash chain covers the serialised form and a
formatting change would invalidate every historical hash. It lives in
`contracts/ownership.md` and changing it requires contract review
(`spec/03-data-model.md` §3).

## 3. Tamper evidence (`SZ-AUD-001`)

Append-only enforced **at the database**, not in the application: no `UPDATE` or
`DELETE` grant for the application role, plus a trigger that rejects both. The
application being compromised is the case this defends against, so application
discipline cannot be the control.

Each event hashes its own canonical form together with the previous event's hash.
Editing event *n* invalidates every event after it, so tampering is detectable
without trusting anything but the chain.

**Checkpoints** periodically record a signed head. Two reasons:

1. Verification does not require replaying the entire chain.
2. **Truncation becomes detectable.** Deleting the last thousand events leaves a
   perfectly valid shorter chain — only a signed head from before the deletion,
   or an off-box copy, proves events are missing. This is the attack the chain
   alone does not stop, and the one people assume it does.

## 4. Getting it off the box (`SZ-AUD-002`)

Forwarded to remote syslog or a SIEM **as events are written**, not batched at
the end of a day. The forwarding target is an allowlisted egress destination
(`SZ-OS-010`).

- Transport is TLS with peer verification. Plain syslog for an audit stream is a
  tamper-and-observe channel.
- **Forwarding failure is itself an audited event and raises an alarm.** Silence
  is indistinguishable from a healthy quiet period, so absence must be noticed.
- Forwarding is **not** allowed to block signing, and the buffering policy is a
  stated decision: bounded on-box queue, and if it fills, the appliance stops
  accepting new signing requests rather than dropping audit events. The
  alternative — sign but do not record — is the worse failure.

## 5. Export (`SZ-AUD-002`)

A signed, self-verifying export: the events, the checkpoint heads, and the
verification procedure, so a third party can check the chain without our tooling
and without trusting our API.

An export that only we can verify is not evidence to anyone else.

## 6. What never enters the log (`SZ-SEC-005`)

PINs, SO-PINs, DKEK shares, passphrases, recovery codes, session tokens, OIDC
client secrets, private key material, and **artefact contents**.

The log holds the artefact *digest*. A signing appliance that logged what it
signed would be an exfiltration channel for every build it touched.

Redaction is a property of the event constructor — fields are allowlisted into
the canonical form — rather than a filter applied on the way out. A filter fails
open the first time someone adds a field.

## 7. Retention

Audit events are retained, not deleted (`spec/03-data-model.md` §4). Where
personal data must be removed, the identity is pseudonymised and the chain stays
intact: the record still proves a distinct person approved, without naming them.
Deleting rows would break the chain and destroy the evidence for every other
signature that person touched.

## 8. How this is verified

- An `UPDATE` or `DELETE` on `audit_events` by the application role fails at the
  database.
- Editing one event is detected by chain verification, at the exact event.
- Removing the last N events is detected by checkpoint comparison.
- A refusal produces an event; a full audit of a signature reconstructs requester,
  approver, binding, policy version and key.
- An export verifies with an independent implementation of the procedure.
- No secret appears in the log — asserted by scanning a populated log against a
  known-secret corpus, not by review.
- A forwarding outage raises an alarm and, once the queue fills, stops new
  signing requests rather than dropping events.
