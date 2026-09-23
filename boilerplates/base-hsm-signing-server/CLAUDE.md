# base-hsm-signing-server — operating instructions

You have been pointed at a boilerplate. It builds **SignZone**: a hardened Linux
signing appliance around a Nitrokey HSM 2 — a Next.js admin surface, privileged
Rust daemons, a REST signing API, a PWA approval app, and a DKEK backup and
recovery ceremony — using a 34-agent fleet.

> **`CLAUDE.md` and `AGENTS.md` in this directory are byte-identical.** Some
> runtimes read one, some read the other, and Muse Code reads `AGENTS.md` and
> prints a warning that it is ignoring `CLAUDE.md`. That warning is expected and
> costs nothing here, because there is nothing in the ignored file that is not
> in the one being read. Do not "fix" it by deleting either file — that breaks
> the other runtime. `scripts/check-boilerplate.sh` fails if the two drift.

## Start here

**If the user has described what they want** — even in a sentence — read
`prompts/00-master-orchestrator.md` and follow it. That file is the process of
record and it is the entry point on every runtime, because it is a file rather
than a feature.

**If the user has not described anything yet** — ask for a paragraph. What gets
signed, who approves it, which HSM, and whether the appliance is
internet-reachable. The rest has defaults.

**If the user is asking a question about this boilerplate** rather than asking
you to run it — answer from `spec/requirements.md` and the relevant `spec/`
document. Do not start a build to answer a question.

## The map

| File | What it is |
|------|------------|
| `prompts/00-master-orchestrator.md` | How the build runs. Read this first. |
| `spec/requirements.md` | 59 requirements with stable `SZ-*` IDs. The source of truth. |
| `spec/00-product.md` … `16-ui.md` | One specification per domain, each ending with how it is verified. |
| `spec/17-nethsm-parity.md` | The gap analysis against NetHSM, and the divergences decided on purpose. Read it before adding an endpoint. |
| `spec/18-backup-restore.md` | The backup design: two secrets to read a backup, and the backup client holds neither. |
| `spec/11-os-appliance.md` | Read-only verity root, LUKS2 sealed to PCR 7 + 11, and what that costs to operate. |
| `contracts/ownership.md` | Who owns which path. The routing table for tasks and findings. |
| `.claude/agents/` | The 34 agent prompts themselves. |
| `.claude/skills/` | 19 domain skills — PKCS#11, DKEK ceremonies, Authenticode on Linux, appliance hardening, and the rest. |
| `spec/traceability.csv` | Every requirement mapped to an owner. |

**The ID prefix here is `SZ-`, not `REQ-`.** It is load-bearing across the whole
tree; `CONVENTIONS.md` §3 requires IDs that are stable and never renumbered, not
one particular spelling, and the conformance check derives the prefix from the
register rather than assuming one.

## Non-negotiable operating rules

1. Read `spec/requirements.md` and the applicable spec before changing code.
2. Every change must cite requirement IDs in the PR/commit notes.
3. Respect file ownership in `contracts/ownership.md`.
4. Do not silently change public contracts: OpenAPI, RPC schemas, DB migrations, security policy schema, or audit event schema require contract review.
5. Security-critical code requires two independent reviews: `security-reviewer` and `adversarial-reviewer`.
6. The web process is unprivileged. It may not execute arbitrary OS commands, expose a generic remote shell, or access the HSM directly.
7. The privileged OS daemon exposes only typed allowlisted operations.
8. The signer daemon exposes only signing/HSM operations allowed by policy. It is not a generic PKCS#11 network bridge.
9. Never persist or log HSM PINs, SO-PINs, DKEK shares, passkey private material, session secrets, OIDC secrets, or plaintext recovery codes.
10. No secret may be placed in a CLI argument or PKCS#11 URI.
11. Every signing job must bind the approval to artifact digest, signing profile, requester, repository/ref, and expiration.
12. PWA/mobile approvals require transaction details plus a short-lived transaction code or WebAuthn step-up. A push notification alone is never authorization.
13. Destructive HSM/DKEK/OS/network operations require step-up authentication and immutable audit events.
14. Network/firewall changes require automatic rollback if management connectivity is not confirmed.
15. Setup mode must become permanently unavailable after successful initialization unless explicitly reset from the physical maintenance console.
16. Prefer fail-closed behavior.
17. Tests are part of the requirement, not optional cleanup.
18. **No private key material is ever committed.** `.gitignore` excludes it, and
    the conformance check verifies that — but the check is the backstop, not the
    control. A git history is not something you can un-leak.

## Mandatory security behaviour

These are the ways this system is most likely to be broken by someone trying to
be helpful. Each one has a plausible-sounding reason to do it anyway.

- **Never solve OS management by adding a web shell.** The typed allowlisted
  daemon exists precisely so that this is never the easy option (rule 7).
- **Never expose the Nitrokey HSM over raw TCP PKCS#11.** The remote provider is
  a policy-constrained API client, not a network path to the device (rule 8).
- **Never put a PIN in a `pkcs11:` URI**, an environment variable that appears in
  logs, a process argument, source control, or a logged API payload (rule 10).
- **Never bypass approval or audit controls for a test or for convenience.** A
  test that needs the control disabled is testing a system that will not ship.
- **A security-sensitive TODO fails closed and is marked `SECURITY-BLOCKED`**,
  never implemented as permissive behaviour to be tightened later.
- **Treat source and build agents as untrusted relative to the signing
  boundary.** The appliance signs what policy allows, not what a caller claims.

## Required development sequence

`discover -> contract -> threat model -> implement -> unit test -> integration test -> security review -> adversarial review -> docs -> acceptance`

Parallel work starts only after contracts are frozen for the phase.

## Where this folder sits

**This folder becomes the project root. It is not a folder you add to a
project.** The build writes the application beside `spec/` and `contracts/`, at
the paths `contracts/ownership.md` names with no prefix.

1. **Copy this folder out of the collection before you build in it.** A build in
   place overwrites the boilerplate's own `README.md` and drops build output into
   the collection repository. The repository README has the one-line command.
2. **Do not nest it inside an existing project.** Every path here is relative to
   this folder, so nested they are ambiguous between two roots and an agent will
   pick one silently. If you find yourself running inside a subdirectory of a
   larger project, **stop and say so** rather than guessing a prefix.
3. **`spec/`, `contracts/` and `docs/` stay.** They are the register every review
   cites and the documentation the appliance ships with, not scaffolding to
   delete once the code exists.

## This folder is self-contained

Nothing here reaches outside `boilerplates/base-hsm-signing-server/`. If you want
a file from a sibling directory, that is a bug — someone will clone this folder
on its own.

## Style

Decide. "Consider using X" is a failed spec; write "we use X, because Y". Prefer
a command, a path, a schema or a number over an adjective. State failure modes
bluntly: what breaks, and what to do instead.
