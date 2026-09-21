# Changelog

All notable changes to this repository are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Entries cite the requirement IDs they affect, so a change can be traced to the
requirement that motivated it.

## [Unreleased]

## [0.1.0] — 2026-09-21

First release. Establishes the repository as a collection of boilerplates and
skills, and lands the complete prompt structure for the first boilerplate.

### Added

**Repository**
- Repository identity as a collection of boilerplates (`boilerplates/<name>/`)
  and a shared skill library (`.claude/skills/`).
- `CONVENTIONS.md` — the rules every boilerplate follows: self-containment,
  required structure, permanent requirement IDs, no versions from memory,
  ownership before parallelism, nothing self-approves.
- `CLAUDE.md` / `AGENTS.md` — operating instructions for agents working in the
  repo.
- `boil-new-boilerplate` skill — scaffolds a conforming boilerplate and verifies
  self-containment.
- Sparse-checkout and `degit` instructions so a single boilerplate can be cloned
  or handed to an agent on its own.

**`base-admin-panel` boilerplate**
- `spec/requirements.md` — 215 requirements with stable `REQ-*` IDs across 25
  domains, each carrying a `MUST` / `SHOULD` / `OPT` status.
- `spec/traceability.csv` — every requirement mapped to its owning agent,
  contract member, blocking gate and specification document. Generated from the
  requirement register so it cannot drift.
- `spec/agents.md` — the 24 build agents plus 4 gate agents, organised into 5
  waves, with publishes/consumes per agent.
- `prompts/00-master-orchestrator.md` — wave dispatch, the G0–G8 gate ladder,
  CCR arbitration, and loop discipline.
- `contracts/README.md` — contract law: declaration and assembly, the G3 freeze,
  additive-only change, the CCR process, and fixture-based consumption. This is
  what makes a 13-agent parallel wave safe (REQ-CTR-01 … REQ-CTR-10).
- `contracts/ownership.md` — single-owner map for every path, route group, table
  and migration namespace (REQ-CTR-04).
- `contracts/types/`, `contracts/events/`, `contracts/openapi/`, `contracts/db/`
  — concrete contract artefacts including the entity envelope (REQ-ENT-01), the
  RFC 9457 error taxonomy (REQ-API-10), the shared pagination grammar
  (REQ-API-11), the audit envelope (REQ-AUD-04), the console stream protocol
  (REQ-AUD-08 … REQ-AUD-12), an OpenAPI 3.1 skeleton (REQ-API-01) and the RLS
  contract (REQ-RBA-04).
- `.claude/agents/` — 28 agent definitions (24 builders, 4 blocking reviewers), each with owned paths,
  published and consumed contract members, and a verifiable definition of done.
- `gates/` — the G0–G8 ladder, the structured per-requirement verdict schema
  (REQ-GAT-04), loop and escalation rules (REQ-GAT-05), and the Karpathy review
  lens (REQ-GAT-06).
- `.claude/skills/` — `build-orchestrate`, `contract-guard`, `version-guard`,
  `visual-qa-cdp`, `supply-chain-audit`, `release-build`.
- `spec/` domain specifications for auth, RBAC and tenancy, the entity model, the
  datagrid, theming, screenspace, i18n, time, observability, the API and data
  normalization.
- `spec/baseline.md` — what the structure takes from
  `arhamkhnz/next-shadcn-admin-dashboard` and what it deliberately deviates from.
- `versions/manifest.json` — 83 externally validated version entries, each with
  its registry source URL and check timestamp (REQ-VER-02, REQ-VER-03), plus the
  recorded compatibility traps (REQ-VER-05).
- `normalizers/` — the declarative mapping engine contract, a JSON Schema for
  mapping descriptors, and two worked descriptors mapping differently-shaped
  vendor payloads onto the same canonical model (REQ-DAT-02, REQ-DAT-03).
- `compliance/` — EU CRA (Regulation (EU) 2024/2847) and CER (Directive (EU)
  2022/2557) documentation sets, including the Annex I obligations matrix, the
  reporting runbook for obligations in force since 11 September 2026, the CVD
  policy, and the operator-versus-product responsibility split.
- Theme preset `b2CjxkL2O` decoded and recorded rather than guessed: style
  `mira`, base colour `mist`, theme `emerald`, font `montserrat`, radius `small`,
  menu accent `bold`, base `radix` (REQ-UI-04).

### Notes

- No application has been generated yet. This release is the prompt structure
  that generates one.
- `typescript` is recorded at its 7.x native-rewrite line and flagged as needing
  the REQ-VER-04 reviewed-decision note before adoption.
- `@types/node` is deliberately pinned to the Node LTS major rather than the
  newest published major (REQ-VER-05).

[Unreleased]: https://github.com/andreaswiren/boil/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/andreaswiren/boil/releases/tag/v0.1.0
