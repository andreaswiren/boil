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
| A00 | `intake-analyst` | `build/intake.md`, `build/scope.md` | resolved intake answers, waiver list | user's input description |

A00 turns a short description into a resolved scope: which `OPT` requirements are
on, which entities exist, which integrations, which locales, the tenant model,
and the app name. It asks the human **only** the questions whose answers change
the build, and defaults the rest loudly.

## Wave 1 — Mockups & approval (blocking on a human)

| ID | Agent | Owns | Publishes | Consumes |
|----|-------|------|-----------|----------|
| A08 | `mockup-designer` | `mockups/` | 10 layout theses, rendered HTML | scope, theme preset, `spec/screenspace.md` |
| A06 | `ui-theming` | `packages/theme/**` | `theme-tokens` | preset `b2CjxkL2O` |
| A21 | `visual-qa` | `tests/visual/**`, `build/screenshots/**` | screenshot sets | any renderable surface |

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
| A05 | `ui-shell` | `apps/<app>/components/shell/**`, `apps/<app>/app/(app)/layout.tsx`, `packages/screenspace/**`, `packages/settings/**`, `apps/<app>/app/(app)/settings/**` | `nav-registry`, `screenspace`, `surface-budget`, `settings-registry` | `theme-tokens`, `rbac`, `i18n:nav`, approved layout |
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
| Wave 1 (mockups) | 3 | `A06` `A08` `A21` |
| Wave 2 (foundation, sequential) | 3 | `A20` `A01` `A02` |
| Wave 3 (parallel domains) | **15** | `A03` `A04` `A05` `A07` `A09` `A10` `A11` `A12` `A13` `A14` `A15` `A19` `A23` `A24` `A25` |
| Wave 4 (narrative) + release | 4 | `A16` `A17` `A18` `A22` |
| **Build agents** | **26** | `A00`–`A25` |
| Gate agents (blocking, never build) | 4 | `C1` `C2` `S1` `S2` |
| **Total** | **30** | |

`A21` is listed in Wave 1 because that is where it first runs, but it serves
every phase that renders something — the 30 mockup screenshots at G1 and the
integration screenshots at G5.

The edge proxy (`REQ-PROX-*`) is A01's, not a new agent's. A01 already owns
`docker/**` and the validated config source the HAProxy config is generated from
(REQ-PROX-04), and an edge that disagrees with the app about hostnames or ports
is exactly the class of bug single ownership prevents. A25 owns one seam into it:
the certificate install and reload path (REQ-PROX-09, REQ-ACME-13), which it
drives through HAProxy's runtime interface rather than by writing A01's config.

The settings surfaces (`REQ-SET-*`) are A05's, not a new agent's. A05 already
owns the settings shell, and the three scopes are chrome plus a registry — the
panels themselves are contributed by the domains that own the data. Adding an
agent for a surface that already has an owner is the speculative generality the
Karpathy lens exists to catch (`gates/karpathy-lens.md`).

The critical path is
`A00 → A06 → A08/A21 → human → A20 → A01 → A02 → [Wave 3] → [Wave 4] → C1/C2 → S1/S2 → A22`.

Wave 3 is where the time is, and it is 15-wide. Everything else is either
sequential by necessity or narrow by nature.
