# Product

Owner: `product-owner`. Requirements: `SZ-FUN-001`, `SZ-FUN-002`.

## 1. What it is

A dedicated signing appliance. Artefacts go in with a request, a human authorizes
them against what is actually being signed, and a signature comes out under a key
that never leaves an HSM.

It is deliberately **not** a general-purpose HSM service. It does not encrypt, it
does not decrypt, and it does not hand out random numbers
(`spec/17-nethsm-parity.md` §7). Every capability it declines is one fewer way to
turn it into an oracle.

## 2. Who uses it, and what each needs

| Role | Needs | Never gets |
|------|-------|-----------|
| **CI / build systems** | Submit an artefact, learn the outcome, fetch the signed result | A key, a shell, a choice of mechanism |
| **Requesters** (engineers) | See what they asked for and where it is | The ability to approve their own request |
| **Approvers** | Enough context to make a real decision, on a phone, in a minute | A notification that is by itself an approval |
| **Administrators** | Identity, policy, HSM, certificate and appliance management through structured controls | A command line |
| **Auditors** | Complete, tamper-evident history including refusals | Any ability to change it |
| **Monitoring** | Counters | Anything else (`SZ-API-006`) |
| **Backup clients** | Ciphertext on a schedule | The ability to read it (`SZ-HSM-011`) |

The separation that matters: **a requester is never an approver for the same
request.** This is not a configurable convenience.

## 3. The signing request is a state machine (`SZ-FUN-002`)

Explicit, server-side, and the same whether the request came from the API or the
UI:

```
submitted ──▶ policy-evaluated ──▶ awaiting-approval ──▶ approved ──▶ signing ──▶ signed
     │               │                     │                              │
     │               ▼                     ▼                              ▼
     └──────────▶ rejected             expired                        failed
```

- **`policy-evaluated`** is a distinct state because a rejection there is a
  *policy* answer and must be explainable — which rule, which value, what the
  requester should do about it. "Denied" without a reason produces a support
  ticket rather than a fix.
- **`expired`** exists because an approval that can be used at any future time is
  an approval that will be used at a bad one.
- The transition into `signing` re-checks the binding. Nothing that was true at
  approval time is assumed to still be true.

Every transition is an audit event (`SZ-AUD-001`), including the ones that end in
`rejected` — those are the interesting ones.

## 4. The dashboards (`SZ-FUN-001`)

Two, because the questions are different.

**Operator/user dashboard** answers *where is my thing*: recent requests and
their state, what is waiting on me, what I signed recently. A requester should
never need to ask a human where a request is.

**Administrator dashboard** answers *is the appliance healthy*: state
(`Operational` / `Locked` / `Failed`), both HSMs and whether their DKEK check
values still match, certificate expiry, last successful backup, pending TPM
re-enrolment (`SZ-OS-009`), and audit forwarding health.

The two items most likely to be discovered too late are **certificate expiry**
and **a DR HSM whose KCV no longer matches**, so both are dashboard items rather
than report items.

## 5. What "done" looks like for this product

- A CI job can submit and collect a signature without a human copying anything.
- An approver on a phone can tell what they are approving without opening a
  laptop.
- An administrator can do everything routine without SSH (`SZ-OS-003`).
- An auditor can reconstruct any signature's full history — who asked, who
  approved, against what, under which policy and which key.
- Losing the primary HSM costs a documented procedure, not the business.

## 6. Explicit non-goals

- **General-purpose crypto service.** See §1.
- **Multi-site clustering.** DR is a second HSM and a restore
  (`spec/17-nethsm-parity.md` §7).
- **Signing without approval.** A fully automated path exists only where policy
  explicitly grants it for a named profile, and that grant is itself audited and
  visible on the dashboard. It is never the default.
