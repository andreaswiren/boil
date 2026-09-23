# Threat model

Owner: `threat-modeler` with `security-architect`. Reviewed independently by
`security-reviewer` and `adversarial-reviewer` (rule 5) before any security
feature is called complete.

## 1. What this appliance is for

It converts *authorization* into *signatures*. Every threat below is a way of
getting a signature without the authorization, or of learning something that
would let someone do that later.

## 2. Assets

| Asset | Why it is the target |
|-------|---------------------|
| Publisher identity | The point of the whole system. A signature under it is trusted by every machine that trusts the certificate. |
| Non-exportable signing keys | Cannot be stolen, only *used*. So the attack is on the use path, not the storage. |
| DKEK shares and wrapped backups | The one path by which key material legitimately leaves a device. |
| HSM PIN / SO-PIN | Turns physical access into signing ability. |
| Approvals and policies | Forging an approval is equivalent to stealing a key, and cheaper. |
| Audit evidence | Attacked *after* the fact, to make the rest unprovable. |
| Administrator identities | The shortest path to changing policy so an attack becomes authorized. |
| Appliance integrity | The root the other assets rest on. |

## 3. Adversaries, in the order they matter

1. **A compromised build agent.** The expected case, not the exotic one. CI is
   the largest untrusted surface touching this appliance, and an agentic build
   system that can be induced to submit an artefact is the realistic route to a
   signed malicious binary. Mitigated by binding the request to digest, ref and
   workload identity (`SZ-API-002`) and by requiring human approval that shows
   those bindings (`SZ-PWA-003`).
2. **An insider with an operator session.** Has legitimate access and needs no
   exploit. Mitigated by separation of duties: an operator requests, a different
   identity approves, and step-up is required for anything destructive
   (`SZ-AUTH-003`).
3. **A remote attacker against the web tier.** The largest code surface.
   Contained by the architecture (`spec/01-architecture.md` §1) rather than by
   the web tier being correct.
4. **Someone with physical access.** Mitigated by the disk being useless off the
   appliance (`SZ-OS-009`), setup mode being permanently closed
   (`SZ-INS-003`), and the maintenance console needing its own credential
   (`SZ-OS-005`).
5. **A supply-chain compromise** in a dependency of the web tier or a daemon.
   Mitigated by lockfiles, review of new dependencies, and the fact that a
   compromised web dependency still cannot reach a device node.

## 4. Threats and what actually stops them

| Threat | Control | Requirement |
|--------|---------|-------------|
| Malicious artefact submitted by a compromised agent | Digest recomputed server-side; approval bound to the digest; human sees it | `SZ-API-002`, `SZ-PWA-003` |
| Signing-oracle abuse — using the appliance to sign attacker-chosen bytes | Policy resolves the key; no arbitrary mechanism; no raw PKCS#11 | `SZ-API-003`, `SZ-SEC-003` |
| Replayed approval against a different artefact | The approval carries the binding and is re-checked before the HSM is opened | `SZ-API-002` |
| **Push fatigue** — approver taps to make it stop | A notification is never authorization. Approval needs a transaction-bound code or WebAuthn step-up, shown with the artefact's details | `SZ-PWA-002` |
| Stolen admin session | Step-up for sensitive actions; sessions bound and short | `SZ-AUTH-003` |
| HSM PIN leakage | Never in a command line, an environment variable, a URI or a log | `SZ-SEC-005` |
| DKEK leakage | Shares never on the appliance; assembled only inside the HSM | `SZ-HSM-004` |
| Root compromise of the running system | Cannot unseal the Device Key — PCR 11 has moved past the sealing policy by then | `SZ-OS-009` |
| Persistence after compromise | Root filesystem is verity-protected and cannot be written | `SZ-OS-008` |
| SSRF via timestamp or OIDC URLs | Provider allowlist; default-deny egress with named destinations | `SZ-OS-010` |
| Setup-mode takeover | One-shot; permanently unavailable after initialization except from the physical console | `SZ-INS-003` |
| Network lockout during a firewall change | Transactional with automatic rollback unless connectivity is confirmed | `SZ-OS-002` |
| Audit deletion or edit | Append-only, hash-chained, checkpointed, forwarded off-box | `SZ-AUD-001`, `SZ-AUD-002` |
| Weak entropy at key generation | Refuse to become operational rather than generate a key we cannot vouch for | `SZ-SEC-011` |

## 5. Trust boundaries, stated as assumptions

Written as assumptions because that is what they are, and an assumption that is
never written down is never re-examined:

- **The HSM is trusted** to keep a non-exportable key non-exportable. If that
  fails, nothing here compensates.
- **The TPM is trusted** to refuse an unseal under a non-matching policy.
- **The kernel is trusted.** This is the largest assumption in the document and
  the one most likely to be false. See §7.
- **CI is not trusted.** Ever, including our own.
- **The operator's browser is partly trusted**: it renders the approval, so it
  can lie about what is being approved. WebAuthn step-up binds the approval to a
  key the browser cannot forge, which narrows but does not remove this.
- **The network is not trusted**, including the management network.

## 6. What an attacker gets from each compromise

| Compromise | What they get | What still holds |
|-----------|---------------|------------------|
| nginx | Request bodies in flight | No device access; no signing without policy and approval |
| Next.js | The product surface, sessions, the database | Cannot sign without `signerd` agreeing; cannot run a command |
| `signerd` | **Signing ability and the Domain Key** | Policy is still enforced in-process; audit is already forwarded |
| `osd` | Root on the appliance | Cannot unseal the Device Key (§4); cannot rewrite the verity root |
| The disk, offline | Ciphertext | Everything |
| One DKEK custodian | One share | Nothing — all shares are required |

`signerd` is the crown jewel and the document says so plainly. It is the smallest
of the three daemons for exactly that reason.

## 7. The residual risk, not hedged

A Debian kernel is millions of lines of C. A local privilege escalation in it
gives an attacker `signerd`'s memory, and therefore the Domain Key and signing
ability for as long as the appliance is unlocked. **No control in this document
prevents that.** What limits it:

- The appliance is unlocked only while operating; `lock` returns it to ciphertext
  (`SZ-HSM-009`).
- Non-exportable keys still cannot be extracted — an attacker gets *use* while
  they hold the box, not a key they keep afterwards.
- Every use is audited, and the audit is already off the box (`SZ-AUD-002`).

NetHSM answers this with a formally verified separation kernel. We answer it with
a smaller blast radius and better evidence. An operator whose threat model is a
remote attacker holding kernel exploits should buy NetHSM; this document exists
so that choice is made knowingly (`spec/17-nethsm-parity.md` §1).
