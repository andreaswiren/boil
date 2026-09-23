---
name: audit-tamper-evidence
description: Canonical append-only audit events, hash chaining, checkpoints, export, remote syslog and redaction. Load whenever an auditable action is added or the event schema changes.
---

# Audit and tamper evidence

Design: `spec/10-audit.md`.

## The log must survive the compromise of what it logs

So append-only is enforced **at the database** — no `UPDATE`/`DELETE` grant for
the application role, plus a trigger that rejects both. Application-level
discipline is not the control, because the application is the thing being
defended against.

## Checkpoints catch what the chain cannot

Hash chaining detects an **edit**. It does not detect a **truncation** — deleting
the last thousand events leaves a valid shorter chain.

Only a signed checkpoint from before the deletion, or an off-box copy, proves
events are missing. People routinely assume the chain covers this; it does not.
Implement both.

## Canonical serialisation is frozen

Field order, encoding and number representation are fixed, because the hash
covers the serialised form. A formatting change invalidates every historical
hash, so the serialisation is a contract (`contracts/ownership.md`) and changing
it requires contract review.

## Refusals are the interesting events

Log denied authorizations, failed unlocks, rejected policy evaluations, refused
restores. A log containing only successes cannot answer the question an incident
asks, and refusals are usually the first evidence of an attack.

## Redaction by construction

Fields are **allowlisted into** the canonical form. Never a filter on the way
out — a filter fails open the first time someone adds a field.

Never logged: PINs, SO-PINs, DKEK shares, passphrases, recovery codes, session
tokens, client secrets, key material, and **artefact contents**. The log holds the
digest; an appliance that logged what it signed would be an exfiltration channel
for every build it touched.

## Forwarding

Off-box as events are written, over TLS with peer verification
(`SZ-AUD-002`). Plain syslog for an audit stream is tamper-and-observe.

**Forwarding failure is itself audited and raises an alarm** — silence and health
look identical otherwise. Buffer is bounded; when it fills, **stop accepting
signing requests** rather than dropping events. Sign-but-do-not-record is the
worse failure.

## Definition of done

- [ ] `UPDATE`/`DELETE` on audit events fails at the database.
- [ ] An edit is detected at the exact event; a truncation is detected by
      checkpoint comparison.
- [ ] Export verifies with an independent implementation.
- [ ] A populated log scanned against a known-secret corpus contains none.
- [ ] Forwarding outage alarms, and a full queue halts new signing.
