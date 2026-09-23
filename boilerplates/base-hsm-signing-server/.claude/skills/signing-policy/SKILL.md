---
name: signing-policy
description: Explainable signing-policy evaluation bound to verified CI identity, artefact digest, ref, profile, approvals and expiry. Load for any authorization decision in the signing path.
---

# Signing policy

Design: `spec/06-signing.md`. The invariant: **the appliance signs what policy
authorized, never what a caller asked for.**

## Evidence versus assertion

The distinction the whole engine rests on:

| Assertion — a caller states it | Evidence — the appliance derives it |
|-------------------------------|-------------------------------------|
| "this is repo X, ref Y" in a body | The **workload token's claims** |
| "the digest is D" | The digest **recomputed from the bytes received** |
| "I am user U" | The authenticated session |

A compromised build agent can claim any repository. It cannot mint a token for
one it does not build. **Write policy rules against claims; a rule matching a
body field is not a rule.**

## Explainability is a requirement, not a nicety

Every decision returns *which rule*, *which value*, and *what would have to
change*. An unexplainable denial becomes a support ticket, and a support ticket
becomes pressure to add a bypass — which is how policy engines die.

Evaluation is **pure and side-effect free**, so a "would this be allowed?" dry
run is possible without producing an approval or a signature.

## Versioning

Policies are **versioned and immutable**. A request records the
`policy_version_id` it was evaluated against, so "why was this allowed" is
answerable a year later. A mutable policy row makes every historical decision
unexplainable.

## The re-check

The binding is **re-verified immediately before the HSM is opened**
(`spec/06-signing.md` §4). Nothing true at approval time is assumed still true —
that window is exactly where a time-of-check/time-of-use attack lives.

## Two axes

Policy is one axis. **Tag restriction at the key** is the other
(`SZ-AUTH-005`), enforced where the key is used. Both must agree, so a
policy-engine bug does not by itself unlock every key.

## Definition of done

- [ ] Every rule matches a verified claim, never a caller-supplied field.
- [ ] Every decision carries rule, value and remedy.
- [ ] Evaluation is pure; a dry run produces nothing.
- [ ] The `policy_version_id` is recorded on the request.
- [ ] Negative tests: wrong repo, wrong ref, expired, self-approval, replayed
      approval against a different digest.
- [ ] Fail closed — an evaluation error never becomes an allow (`SZ-SEC-004`).
