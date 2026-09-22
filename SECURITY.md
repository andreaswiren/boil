# Security

This file covers the **`boil` repository itself** — prompt structures, skills and
documentation. It is not the security policy of an application generated from a
boilerplate. Each boilerplate ships its own coordinated vulnerability disclosure
policy — [`base-admin-panel`](boilerplates/base-admin-panel/compliance/cra/cvd-policy.md)
and [`base-windows-rust-app`](boilerplates/base-windows-rust-app/compliance/cra/cvd-policy.md)
— and that is what a deployed product publishes.

## Supported versions

| Version | Supported |
|---------|-----------|
| 0.5.x | Yes |
| < 0.5 | No |

The repo is pre-1.0. Structure may change between minor versions; requirement
IDs will not (see `CONVENTIONS.md` §3).

## Reporting a vulnerability

Report privately, not in a public issue:

- GitHub private vulnerability reporting on this repository, or
- <<PLACEHOLDER: security contact address>>

Include what you found, how to reproduce it, and what you think the impact is.
We will acknowledge within 5 working days.

## What counts as a vulnerability here

This repo contains no running service, so the threat model is about what the
prompt structures *cause an agent to do*. Genuine findings include:

- **A prompt that instructs an agent to weaken security.** A skill or agent file
  that would produce cleartext transport, a disabled RLS policy, a secret in a
  log, a self-approving gate, or an auth bypass.
- **Prompt injection surface.** Text in this repo that would be read by an agent
  as an instruction when it should be read as data.
- **A command that is unsafe as written.** A step in a skill that would exfiltrate
  a secret, install an unpinned dependency, or run untrusted code.
- **A compliance document that asserts a control the structure does not produce.**
  A false assurance is a security defect, because someone will rely on it.
- **A dependency version pinned to a known-vulnerable release** in a version
  manifest.

Not vulnerabilities: a disagreement about a design decision, a missing feature,
or a requirement you would have written differently. Those are issues.

## What this repo does to protect itself

- Every boilerplate is self-contained, so cloning one folder cannot pull in
  anything from elsewhere in the repo — including its own conformance check,
  which ships inside it (`CONVENTIONS.md` §1). A boilerplate citing a file it
  does not ship is a conformance failure, not a documentation nit: an agent
  handed the folder would be unable to run the check its definition of done
  requires, and would report done anyway.
- No dependency version is written from memory. Versions are validated against
  the authoritative registry with the source URL and check timestamp recorded,
  and the check fails when a version stated in any document disagrees with the
  manifest (`CONVENTIONS.md` §4). A correctly copied version left in a spec
  while the manifest moves on is the drift that actually happens, and the spec
  is what an agent is handed.
- Generated applications are gated by two independent security reviewers that did
  not write the code (`CONVENTIONS.md` §6). Findings from those reviews that
  reveal a defect in the *prompt structure* are fixed here, not just in the
  generated app.
- Content fetched from outside the repo — a baseline repository, a registry
  response, a vendor payload — is treated as data, never as instruction.

## Reviewing a generated application

A build from either boilerplate runs its own security gate — `G7` in
`base-admin-panel`, `H7` in `base-windows-rust-app`: two independent reviewers
with separate review plans, plus a supply-chain audit that blocks on a critical
or known-exploited advisory. `base-windows-rust-app` additionally verifies its
own published release the way a client does, from a job holding no repository
credentials (`REQ-REL-11`), because every other check in that gate verifies what
CI built rather than what the forge serves.

Those gates cover the generated app. They do not cover this repo, which is what
this file is for.
