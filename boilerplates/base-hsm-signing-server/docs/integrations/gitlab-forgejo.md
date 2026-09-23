# GitLab, Forgejo and Gitea CI

## Choose the identity mechanism first

**Prefer workload OIDC** where the platform exposes trustworthy job identity
claims. The token is minted per job, is short-lived, and carries the project, ref
and pipeline — so the appliance can verify *what is building* rather than trust
what the job says about itself.

Where the platform cannot mint OIDC, use **mTLS** with a narrowly scoped service
identity. A long-lived API token in a CI variable is the last resort: it is the
credential most likely to leak and least likely to be rotated, and the signing
profile records that it was used.

## The rule that makes this safe

**Policy constrains repository, project, ref, environment and signing profile —
from the token's claims, never from JSON the job supplied.**

A compromised runner can put any repository name in a request body. It cannot
mint a token for a project it does not build. That distinction is the whole
control: anything the job *states* is an assertion, anything the appliance can
*derive* from a verified token is evidence.

So policy rules are written against claims. A rule matching a body field is not a
rule.

## Practical notes

- The appliance recomputes the artefact digest from the bytes it receives. Send
  the artefact; do not expect a client-supplied digest to be trusted.
- Use an `Idempotency-Key` on submission. A runner that retries on a network blip
  must not produce two signatures.
- A profile requiring approval will return a pending state. Poll it; do not
  configure the pipeline to treat pending as failure.
- Verify the returned signature in the pipeline before publishing. The appliance
  verifies its own output, and so should you.

## Before you start

Confirm the appliance's egress allowlist includes your timestamp authority, and
that your runner network can reach the appliance. Default-deny egress means an
integration is unreachable until its destinations are named
(`spec/11-os-appliance.md` §3).
