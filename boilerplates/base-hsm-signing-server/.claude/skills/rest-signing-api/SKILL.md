---
name: rest-signing-api
description: Versioned REST signing API with OpenAPI, workload auth, idempotency, digest binding, safe artefact transfer and client examples. Load for API or CI-integration work.
---

# REST signing API

Design: `spec/07-rest-api.md`. **The OpenAPI document is the contract**; this
skill is how to keep it honest.

## State is in the response, not inferred

**`412` means wrong appliance state**, with the body naming current and required.
A client that cannot distinguish *locked* from *broken* retries forever and the
operator sees an outage instead of a prompt.

`GET /health/state` answers **without authentication** — a locked appliance
cannot authenticate anyone, because the authentication store is still ciphertext.

## Auth: not Basic

NetHSM uses HTTP Basic for all 78 operations. Defensible on an isolated
management network; not for an appliance signing from CI. **Basic is absent, not
deprecated** — offering it means it gets used.

Order: workload OIDC bound to repository and ref, then mTLS, then a narrowly
scoped expiring credential whose use is recorded.

## Digests and idempotency

- **Recompute the digest server-side** from the received bytes. A client-supplied
  digest is an input to check, never a value to trust.
- **`Idempotency-Key` on every mutating operation.** A CI runner retrying on a
  network blip must not produce two signatures; a replayed key returns the
  original job.
- Large artefacts stream to a content-addressed store; the job references the
  digest. Signing never holds the artefact in memory.

## Roles

`Administrator`, `Operator`, `Metrics`, `Backup` (`SZ-AUTH-007`). `Metrics` reads
counters and nothing else; `Backup` fetches ciphertext it cannot read. Assert
both negatively — a `Metrics` credential must fail on every other endpoint.

## Audit the refusals

Every mutating operation and **every authorization failure** emits an event
carrying caller, binding, decision and reason. Never log request or response
bodies wholesale — the digest and the decision, never the artefact.

## Definition of done

- [ ] Operations are reachable only in their declared state; others return `412`
      naming both.
- [ ] `/health/state` answers unauthenticated, including while locked.
- [ ] A mismatched digest is refused before the HSM opens.
- [ ] A replayed idempotency key returns the original job.
- [ ] `Metrics` and `Backup` credentials fail everywhere else.
- [ ] OpenAPI and implementation are checked against each other in CI; drift
      fails the build.
