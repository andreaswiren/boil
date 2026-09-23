# Architecture

Owner: `security-architect` with `nextjs-architect` and `rust-service-engineer`.
Requirements: `SZ-SEC-002`, `SZ-SEC-003`, `SZ-OS-001`, `SZ-HSM-001`.

## 1. Four processes, and the reason for each boundary

```
   CI / build systems            operators, approvers
   (untrusted)                   (browser, PWA)
          │                              │
          ▼            HTTPS             ▼
   ┌──────────────────────────────────────────┐
   │ nginx — TLS termination, rate limit       │  unprivileged
   └──────────────────┬───────────────────────┘
                      ▼
   ┌──────────────────────────────────────────┐
   │ Next.js — the whole product surface       │  unprivileged, no device access
   └───────┬────────────────────────┬─────────┘
           │ Unix socket            │ Unix socket
           ▼                        ▼
   ┌───────────────┐        ┌───────────────────┐
   │ signerd       │        │ osd               │  root, typed allowlist only
   │ PC/SC + HSM   │        │ network, services │
   └───────┬───────┘        └───────────────────┘
           ▼                        ┌───────────────────┐
     Nitrokey HSM 2                 │ dcui — tty1 only  │
     (primary + DR)                 └───────────────────┘
```

Each boundary exists because of a specific failure, not for tidiness:

| Boundary | The failure it contains |
|----------|------------------------|
| nginx → Next.js | TLS parsing and request framing are the most-attacked code in the stack, and they run somewhere that cannot reach a device node. |
| Next.js → `signerd` | Next.js is a large dependency tree that renders untrusted input. A compromise there must not become "can sign anything". It can *ask* for a signature; `signerd` decides. |
| Next.js → `osd` | Same reasoning for root. The web tier cannot run a command; it can request one of a named set. |
| `signerd` ↔ `osd` | They do not talk. Neither can ask the other for anything, so neither is a path to the other's privilege. |
| `dcui` | Local console only, never reachable over the network, so it cannot be a remote entry point (`SZ-OS-004`). |

## 2. The rule that makes the boundaries real

**No generic exec primitive crosses any boundary** (`SZ-SEC-003`). Not
`run(cmd)`, not `sh -c`, not a "diagnostics" endpoint that takes a command name
and arguments. `osd` exposes *operations* — `set_network_config(struct)`,
`restart_service(enum)`, `collect_support_bundle()` — each with a typed schema
and a fixed implementation.

This is the rule most likely to be eroded by a reasonable-sounding request. The
pressure always arrives as "we just need to run one command for diagnostics",
and the moment it is granted every other boundary in the diagram becomes
decorative. When a needed operation is missing, the answer is a new typed
operation with a review, never a passthrough.

`signerd` is narrower still: it exposes the signing operations policy allows, on
keys policy allows, and **is not a PKCS#11 proxy**. A caller cannot enumerate
mechanisms or objects, cannot pick an arbitrary mechanism, and cannot address a
key the policy engine did not resolve (`SZ-API-003`).

## 3. Where state lives, and what is not secret

PostgreSQL holds **application state, not secrets**: users, roles, signing
requests, approvals, policies, key *metadata*, audit events. It is on the
encrypted volume (`SZ-OS-009`) and its contents are additionally protected by the
Domain Key (`SZ-HSM-007`), but the design does not depend on the database being
confidential — it depends on private keys never being in it.

The things that are secret live where they cannot be queried: private keys inside
the HSM, the Domain Key in `signerd`'s memory only, the Device Key sealed in the
TPM, DKEK shares nowhere on the appliance at all (`spec/05-hsm-dkek.md` §5).

## 4. Language choice, and its limit

The three daemons are Rust because they sit on the privilege boundaries, and
memory-safety there is worth more than anywhere else in the system. The web tier
is TypeScript because the product surface is large and iterating on it matters.

The limit is worth stating: **Rust removes a class of bug, not the boundary's
importance**. `signerd` being memory-safe does not make it safe to hand it an
unvalidated request — it makes a logic error the likely failure instead of a
memory error. The typed allowlist and the policy engine are what make it safe;
Rust is what stops the typed allowlist being bypassed by a parser bug.

## 5. What this architecture does not achieve

Set out fully in `spec/17-nethsm-parity.md` §1, and the short version belongs
here: these are OS process boundaries on a shared kernel. A local privilege
escalation in that kernel reaches `signerd`'s memory and therefore the Domain
Key. NetHSM's separation is enforced by a formally verified separation kernel,
and ours is enforced by UID, AppArmor, seccomp and systemd sandboxing —
defence in depth, several layers of which have been bypassed before in other
systems.

What we get instead is an appliance that an ordinary team can patch, audit and
operate for years. That is the trade, and §5 of the OS spec and §1 of the parity
document both name it so a reader cannot come away with the wrong impression.
