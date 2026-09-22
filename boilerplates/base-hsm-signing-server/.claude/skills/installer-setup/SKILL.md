---
name: installer-setup
description: Implement the one-command Debian installer and one-time TLS setup wizard mode with idempotency and rollback. Use for deployment/bootstrap work.
---

# installer-setup

## Instructions
1. Read `AGENTS.md`, the relevant requirement IDs, and applicable specs.
2. Identify trust boundaries and secrets before implementation.
3. Prefer typed, minimal interfaces and fail-closed behavior.
4. Add tests for positive, negative, replay, authorization, and failure cases.
5. Update traceability and operator/developer documentation.

## Security baseline
Never weaken key isolation, expose generic execution, place secrets in process arguments, or approve a signing request without binding it to an immutable artifact digest and signing context.
