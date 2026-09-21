# base-admin-panel

Give it a paragraph. Get back a release-candidate admin panel.

This is not a code template. It is a **prompt structure**: a fleet of 24 expert
agents, a frozen contract they build against, an ownership map that lets thirteen
of them work at the same time, and nine gates that refuse to pass work that is
not finished.

```bash
cd boilerplates/base-admin-panel
claude
```

> Build me a panel for managing customer firewall estates across ~40 tenants.
> Techs need devices, config backups and change history. Entra ID login.

The orchestrator asks the handful of questions whose answers change the build,
defaults everything else loudly, shows you ten layout mockups, and then builds.

---

## What it produces

A multi-tenant Next.js admin panel that is finished rather than started.

**Access** — RBAC with fine-grained permissions, deny-by-default and enforced
server-side. Multi-tenant with PostgreSQL Row Level Security, forced, with the
app running as a non-owner role. A global MSP/superadmin tier above tenants, with
time-boxed, reason-required, audited impersonation.

**Identity** — password + TOTP, passkeys, and OIDC against Entra ID, Authentik
and Keycloak. You choose which are enabled. MFA is required by default, and
recovery codes are issued the moment a user enrols a factor.

**Interface** — shadcn/ui on the `dashboard-01` and `login-02` blocks, themed
from preset `b2CjxkL2O` (`mira` / `mist` / `emerald` / Montserrat), with full
in-app theming at parity with the shadcn theme generator. Dark, light and system.
A real mobile design and a real desktop design, with screen space *measured* and
per-surface chrome budgets asserted in visual tests.

**Data** — an advanced TanStack datagrid: fuzzy search top-left, column chooser
top-right, multi-sort, type-aware column filters, drag reorder, resize, and every
one of those preferences persisted to the user's profile per grid. Pagination at
the bottom with per-grid page-size ranges, because a 40-row table and a
400,000-row table do not want the same options.

**Observability** — full audit including read and view logging, append-only with
a per-tenant hash chain, forwarded to syslog over TLS. A live debug console with
compact mode, coloured console formatting, and the same redaction as the audit
trail.

**Integration** — OpenAPI 3.1 generated from the runtime's own Zod schemas, with
in-app interactive docs. API keys users mint for themselves and keys admins mint
as service identities. Canonical data models fed by *declarative* mapping
descriptors executed by a Python normalizer, so adding an integration ships no
TypeScript.

**Everything else that gets forgotten** — PWA with push, SMTP with a durable
outbox, `en`/`sv` with ICU, Europe/Stockholm with correct DST and
`YYYY-MM-DD HH:mm:ss`, an always-current help section with architecture charts,
and EU CRA and CER compliance documentation generated from the repository state.

All of it under [`spec/requirements.md`](spec/requirements.md) — 215 requirements
with stable IDs, each owned by an agent and checked by a gate.

---

## How it builds

```
G0 intake        A00 resolves scope from your paragraph
G1 mockups       A08 renders 10 layouts × 3 viewports  ──▶  YOU PICK ONE
G2 versions      A20 validates every version against the real registry
G3 freeze        A02 assembles and freezes packages/contracts@1.0.0
G4 self-test     ┌─ 13 agents build simultaneously ─┐
G5 integration   └─ auth rbac shell grid pwa data   ─┘
G6 critique      C1 and C2 must both approve design AND functions
G7 security      S1 and S2 review independently; both must approve
G8 release       docs, charts, compliance, semver, changelog, push
```

Wave 3 is where the time goes, and it is thirteen agents wide. That only works
because of the freeze at G3: after it, the contract changes additively or not at
all. Nothing is renamed, removed or retyped, so no agent's work is invalidated by
another's while they are both mid-task.

Read [`prompts/00-master-orchestrator.md`](prompts/00-master-orchestrator.md) for
the mechanics, and [`contracts/README.md`](contracts/README.md) for the contract
law that makes the parallelism safe.

---

## Layout

| Path | What |
|------|------|
| [`prompts/`](prompts/) | The orchestrator and the phase prompts |
| [`.claude/agents/`](.claude/agents/) | The 24-agent fleet plus 4 gate agents |
| [`.claude/skills/`](.claude/skills/) | Orchestration, contract guard, version guard, visual QA, supply-chain audit, release |
| [`spec/`](spec/) | 215 requirements, the fleet roster, and a spec per domain |
| [`contracts/`](contracts/) | Contract law, the ownership map, types, events, OpenAPI, DB and RLS contracts |
| [`gates/`](gates/) | The G0–G8 ladder, verdict schema, loop rules, Karpathy lens |
| [`versions/`](versions/) | The externally-validated version manifest |
| [`compliance/`](compliance/) | EU CRA and CER documentation set |
| [`normalizers/`](normalizers/) | The declarative mapping engine and descriptor format |
| `build/` | Per-build working state — intake, approvals, CCRs, gate verdicts, screenshots. Gitignored. |

## Design principles

**Contracts, not conversations.** Agents never message each other. They publish
a declaration, A02 assembles it, and everyone reads the frozen result. Thirteen
agents coordinating costs 78 conversations; thirteen agents reading one contract
costs none.

**Additive-only after the freeze.** A rename mid-wave invalidates work in twelve
other agents' heads at once. So renames are not allowed — you add the new name
and deprecate the old. A breaking change needs the orchestrator's arbitration,
and the default answer is no.

**Registry, never a shared list.** There is no `sidebar-items.ts` for agents to
fight over. A domain adds a nav entry, a settings panel, a help topic or a
command-palette action inside its *own* package, and the shell reads the
registry. The shared array that would be a merge point does not exist.

**Nobody waits.** Generated clients and schema-derived fixtures exist before any
endpoint does. The datagrid agent finishes without the API agent having started.

**Nothing self-approves.** The agent that wrote the code never votes on it, and
the two security reviewers do not see each other's findings before submitting.

## Reference

Layout conventions are adapted from
[`arhamkhnz/next-shadcn-admin-dashboard`](https://github.com/arhamkhnz/next-shadcn-admin-dashboard)
— a reference, not a dependency. What we take and what we deliberately deviate
from is recorded in [`spec/baseline.md`](spec/baseline.md).
