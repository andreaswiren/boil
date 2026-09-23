---
name: os-control-rpc
description: The typed root OS control daemon over a Unix socket, with no generic command execution — network, firewall, services, updates, logs and support bundles. Load for any privileged appliance operation.
---

# OS control RPC

Design: `spec/01-architecture.md` §2. `osd` is the only root service.

## The rule, and the pressure against it

**No generic exec primitive crosses the boundary** (`SZ-SEC-003`). Not
`run(cmd)`, not `sh -c`, not a diagnostics endpoint taking a command name and
arguments.

The pressure always arrives as *"we just need to run one command for
diagnostics"*. Granting it makes every other boundary in the architecture
decorative. When a needed operation is missing, the answer is **a new typed
operation with a review**, never a passthrough.

`collect_support_bundle()` exists precisely so "we need shell for support" has a
real answer: a typed operation producing a redacted archive.

## Shape

Each operation is a named RPC with a typed schema and a fixed implementation:
`set_network_config(struct)`, `restart_service(enum)`, `apply_firewall(struct)`,
`collect_support_bundle()`. Enums, not strings that become arguments.

- Unix socket with a restrictive DACL; the caller is authenticated by peer
  credentials, not by a token in the payload.
- **`osd` and `signerd` do not talk.** Neither is a path to the other's
  privilege.
- Every operation is audited with its parameters (`SZ-AUD-001`).

## Transactional changes (`SZ-OS-002`)

Network and firewall changes apply, then wait for confirmation, then commit —
otherwise they **roll back automatically**. The operator is usually remote and
the change is usually why they can no longer reach the box.

The rollback timer starts before the change is applied, not after, and is not
cancellable from the network path that the change might break.

## Validate in the daemon

Never trust the web tier's validation — it is the larger attack surface and it is
across a trust boundary. Parse and validate every field in `osd`, and reject
rather than coerce.

Fail closed (`SZ-SEC-004`): an ambiguous request is a refused request.

## Definition of done

- [ ] No code path reaches a shell, `exec` with caller-influenced arguments, or
      a template that builds a command line.
- [ ] Every operation has a typed schema, validated in the daemon.
- [ ] A network change with unconfirmed connectivity rolls back automatically.
- [ ] Support bundles are redacted — verified by scanning one for secrets.
- [ ] `osd` cannot reach the HSM and `signerd` cannot reach `osd`.
