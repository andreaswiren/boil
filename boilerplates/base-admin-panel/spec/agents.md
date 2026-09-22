# The Expert Fleet

One part of the app, one expert agent, one owner. Agent IDs are stable and are
the only way to refer to an agent — prompts, gates, ownership and traceability
all cite `A01`…`A23`, `C1`, `C2`, `S1`, `S2`.

Full prompts live in `.claude/agents/<id>-<slug>.md`. This file is the index and
the contract between agents: who owns what, who publishes what, who consumes
what.

## Reading the table

- **Publishes** — the contract members this agent is the sole author of. Nobody
  else may add to these.
- **Consumes** — contract members it reads. It reads them through the frozen
  contract and generated fixtures (REQ-CTR-05), never by calling another agent's
  running code.
- **Wave** — which parallel wave it runs in. Same wave means genuinely
  concurrent: no agent in a wave depends on another agent in that wave.

---

## Wave 0 — Intake & framing (sequential, fast)

| ID | Agent | Owns | Publishes | Consumes |
|----|-------|------|-----------|----------|
| A00 | `intake-analyst` | `build/intake.md`, `build/scope.md`, `build/navigation.md` | resolved intake answers, waiver list, the resolved menu | user's input description |

A00 turns a short description into a resolved scope: which `OPT` requirements are
on, which entities exist, which integrations, which locales, the tenant model,
and the app name. It asks the human **only** the questions whose answers change
the build, and defaults the rest loudly.

## Wave 1 — Mockups & approval (blocking on a human)

| ID | Agent | Owns | Publishes | Consumes |
|----|-------|------|-----------|----------|
| A06 | `ui-theming` | `packages/theme/**` | `theme-tokens` | preset `b2CjxkL2O` |
| A08 | `mockup-designer` | `mockups/` | 10 layout theses as a runnable Next.js + Tailwind + shadcn workspace | `build/navigation.md`, `theme-tokens`, `spec/screenspace.md`, `spec/baseline.md` |
| A21 | `visual-qa` | `tests/visual/**`, `build/screenshots/**` | screenshot sets | any renderable surface |
| C1 | `critic-design` | `build/gates/G1/` | design verdict per round | A08's mockups |
| A28 | `fleet-supervisor` | `build/supervision.md`, `build/supervision/**` | check-in record, revivals | every dispatched agent |
| A27 | `mobile-ux` | `build/gates/G1/` | mobile verdict per round | A08's 390px renders |

**This wave is ordered, not concurrent.** `A00`'s `build/navigation.md` and
`A06`'s `theme-tokens` both complete **before** `A08` starts (REQ-MOC-10,
REQ-MOC-13): a mockup built without them invents a palette and a menu, and the
sidebar width, collapse breakpoint and chrome budget are all consequences of the
menu. `A08` then builds the ten theses **in the shipping stack** — Next.js,
Tailwind, shadcn at the preset, TanStack Table for every grid (REQ-MOC-07,
REQ-MOC-08) — because a standalone HTML page can contain none of those and so
proves nothing about whether the layout is achievable in them.

`C1` and `A27` review every round **before the human is asked** (REQ-MOC-11).
Neither wrote the mockups (REQ-GAT-07).

A08 produces exactly ten layouts (REQ-MOC-02), A06 supplies the real theme so
the mockups are honest, A21 screenshots all thirty renders (10 × 3 viewports) and
they are presented in chat. **The build stops here until a human names a winner.**

## Wave 2 — Foundation & the contract freeze (sequential, then frozen)

| ID | Agent | Owns | Publishes | Consumes |
|----|-------|------|-----------|----------|
| A20 | `version-validator` | `versions/**` | `manifest.json` | registries, external sources |
| A01 | `arch-foundation` | `apps/<app>/` scaffold, `docker/**` incl. the `edge` HAProxy service, `compose*.yml`, `packages/config/**`, `packages/crypto/**` | `env-schema`, `crypto`, `egress-client`, `edge-topology` | `manifest.json` |
| A02 | `contract-steward` | `packages/contracts/**`, `contracts/ownership.md` | the whole contract surface index, `errors`, `entity-base`, `pagination` | every agent's published members |

A20 runs first — nothing is installed against a remembered version. A01 scaffolds.
A02 assembles every domain's declared contract members into one frozen package and
publishes `packages/contracts@1.0.0`. **Gate G3 freezes it.** From here, change is
CCR-only (REQ-CTR-02).

## Wave 3 — Parallel domain build (the wide wave)

Every agent below starts at the same moment against the frozen contract and
contract fixtures. None of them can block another.

| ID | Agent | Owns | Publishes | Consumes |
|----|-------|------|-----------|----------|
| A03 | `auth-identity` | `packages/auth/**`, `apps/<app>/app/(auth)/**` | `session`, `auth-policy`, `mfa` | `entity-base`, `rbac`, `audit-event`, `theme-tokens`, `i18n:auth` |
| A04 | `rbac-tenancy` | `packages/rbac/**`, `packages/tenancy/**`, `db/policies/**` | `rbac` (permission strings), `tenancy`, `rls-contract` | `entity-base`, `session` |
| A05 | `ui-shell` | `apps/<app>/components/shell/**`, `apps/<app>/app/(app)/layout.tsx`, `packages/screenspace/**`, `packages/settings/**`, `packages/editor/**`, `apps/<app>/app/(app)/settings/**` | `nav-registry`, `screenspace`, `surface-budget`, `settings-registry`, `editor` | `theme-tokens`, `rbac`, `i18n:nav`, `mobile-primitives`, approved layout |
| A07 | `datagrid` | `packages/datagrid/**` | `grid-def`, `grid-prefs`, `query-params` | `pagination`, `theme-tokens`, `rbac`, `i18n:grid` |
| A09 | `pwa-offline` | `apps/<app>/app/manifest.ts`, `packages/pwa/**`, service worker | `push-subscription`, `notification-category` | `session`, `theme-tokens` |
| A10 | `data-normalization` | `services/normalizer/**`, `packages/canonical/**` | `canonical-models`, `mapping-descriptor`, `provenance` | `entity-base` |
| A11 | `api-openapi` | `packages/api-kit/**`, `apps/<app>/app/api/**` route kit, `apps/<app>/app/(app)/api-docs/**` | `openapi-document`, `api-key`, `route-contract` | `errors`, `rbac`, `session`, `pagination` |
| A12 | `notifications-comms` | `packages/mail/**`, `packages/notify/**`, `templates/**` | `mail-template`, `notification-event`, `outbox` | `theme-tokens`, `i18n:mail`, `push-subscription` |
| A13 | `audit-observability` | `packages/audit/**`, `packages/logging/**`, `packages/syslog/**`, `apps/<app>/app/(app)/console/**` | `audit-event`, `log-record`, `console-stream` | `entity-base`, `session`, `tenancy`, `redaction` |
| A14 | `i18n` | `packages/i18n/**`, `locales/**` | `i18n-namespace` registry, ICU catalogues | every domain's key declarations |
| A15 | `rust-remote-agent` | `agents/collector/**` (Rust) | `agent-enrolment`, `ingest-envelope` | `canonical-models`, mTLS identity |
| A19 | `supply-chain` | `security/supply-chain/**`, `.github/workflows/supply-chain.yml` | SBOM, advisory report, suspicious-code report, telemetry kill-list | the lockfiles |
| A23 | `test-engineer` | `tests/**` (except `tests/visual/**`), `packages/fixtures/**` | seeded fixtures, contract interface tests | every contract member |
| A24 | `setup-wizard` | `packages/setup/**`, `apps/<app>/app/(setup)/**` | `wizard-state`, `setup-step` | `session`, `auth-policy`, `mfa`, `rbac`, `mail-template`, `env-schema` |
| A25 | `acme-tls` | `packages/acme/**`, `packages/tls/**` | `acme-account`, `certificate`, `cert-renewal`, `dns-provider` | `crypto`, `egress-client`, `notification-event`, `audit-event`, `settings-registry` |
| A27 | `mobile-ux` | `packages/mobile/**` | `mobile-primitives`, `touch-budget` | `theme-tokens`, `screenspace`, `nav-registry`, approved layout |

### Time & format is not an agent

`REQ-TIM-*` is owned by A02 inside `packages/contracts/time`, because a second
formatting module is the failure mode the requirement exists to prevent. Every
other agent imports it and none of them may format a date locally.

## Wave 4 — Integration & narrative (after Wave 3 self-tests pass)

| ID | Agent | Owns | Publishes | Consumes |
|----|-------|------|-----------|----------|
| A16 | `docs-help` | `apps/<app>/app/(app)/help/**`, `docs/help/**` | help topic registry | every feature's topic declaration |
| A17 | `chart-architect` | `docs/architecture/**`, chart sources | C4 + sequence + dataflow + topology charts | the real code, not the plan |
| A18 | `compliance-cra-cer` | `compliance/**` | CRA + CER document set | SBOM, audit contract, crypto posture, RTO/RPO |
| A22 | `release-manager` | `CHANGELOG.md`, `README.md`, `SECURITY.md`, `TODO.md`, `VERSION`, version fields | the release record | gate verdicts |
| A26 | `cost-accountant` | `versions/pricing.json`, `versions/pricing.md`, `build/costs.md` | the cost table | every agent's `AgentReport.usage` |

A16 and A17 run last on purpose: they document what was built, not what was
planned. A17 reads the code to draw the charts; drawing from the spec is the
defect the requirement is guarding against (REQ-DOC-08).

## Gate agents — never in a wave, never self-approving

| ID | Agent | Lens | Votes on |
|----|-------|------|----------|
| C1 | `critic-design` | Design, interaction, density, honesty of the UI | design **and** functions |
| C2 | `critic-function` | Product completeness, edge cases, does it actually do the thing | design **and** functions |
| S1 | `security-alpha` | Independent security review, own plan | code |
| S2 | `security-beta` | Independent security review, own plan | code |

C1 and C2 both vote on both dimensions (REQ-GAT-01) — two lenses, four verdicts.
S1 and S2 are launched in the same message with no shared context and do not see
each other's findings before submitting (REQ-GAT-02).

**No gate agent may have written any of the code it reviews (REQ-GAT-07).** The
orchestrator enforces this by never assigning a build task to a gate agent ID.

## Fleet summary

| | Count | Who |
|---|---|---|
| Intake | 1 | `A00` |
| Wave 1 (mockups, **ordered**) | 3 + 2 reviewers | `A06` → `A08` `A21` → `C1` `A27` |
| Cross-wave supervision | 1 | `A28`, for the duration of every wave |
| Wave 2 (foundation, sequential) | 3 | `A20` `A01` `A02` |
| Wave 3 (parallel domains) | **16** | `A03` `A04` `A05` `A07` `A09` `A10` `A11` `A12` `A13` `A14` `A15` `A19` `A23` `A24` `A25` `A27` |
| Wave 4 (narrative) + release | 4 | `A16` `A17` `A18` `A22` |
| Cross-wave | 1 | `A26` |
| **Build agents** | **29** | `A00`–`A28` |
| Gate agents (blocking, never build) | 4 | `C1` `C2` `S1` `S2` |
| **Total** | **33** | |

### Why mobile has its own agent and settings does not

`REQ-UI-07` has demanded a genuine mobile design rather than a narrowed desktop
since 0.1.0, and until 0.4.0 it had no dedicated owner — A05 owned the desktop
shell and the mobile shell together. That is exactly the arrangement the
requirement warns about: when one agent owns both, mobile is what gets finished
second, and "responsive" becomes the word for it.

So A27 owns the mobile primitives and the mobile half of every surface budget,
and the domains compose them. This is not the settings case, where A05 already
owned the surface and adding an agent would have been speculative generality
(`gates/karpathy-lens.md`). Here the split is the fix, and it mirrors the reason
nothing self-approves: separating the work from the thing that would otherwise
absorb it.

A27 is a builder, not a reviewer. `C1 critic-design` still votes on mobile and
still checks for a narrowed desktop — an owner and a critic are different jobs.

### Why Monaco is A05's and not a new agent's

`packages/editor/**` is one well-bounded component. A05 already owns the shared
UI primitives and the design-token path `REQ-MON-08` needs for the editor theme,
and `REQ-MON-10`'s touch fallback consumes A27's primitives rather than
duplicating them. An agent per component is the proliferation the Karpathy lens
catches.

### The two cross-wave agents

- **`A21 visual-qa`** is listed in Wave 1 because that is where it first runs,
  but it screenshots anything that renders. With A27 in the fleet it also runs
  the touch-emulation matrix `REQ-MOB-11` requires — a narrowed desktop browser
  does not exercise touch targets, the on-screen keyboard, or safe-area insets.
- **`A26 cost-accountant`** runs at every gate, on the cheapest model in the
  fleet on purpose (REQ-COST-04): spending Opus tokens to report on Opus token
  spend would be the one joke this design must not make.

The edge proxy (`REQ-PROX-*`) is A01's and the settings surfaces (`REQ-SET-*`)
are A05's, because both already owned those surfaces.

The critical path is
`A00 → A06 → A08/A21 → C1/A27 → human → A20 → A01 → A02 → [Wave 3] → [Wave 4] → C1/C2 → S1/S2 → A22`,
with `A26` reporting alongside each gate rather than on the path.

Wave 3 is where the time is, and it is 16-wide.
