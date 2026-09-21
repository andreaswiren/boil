# Changelog

All notable changes to this repository are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Entries cite the requirement IDs they affect, so a change can be traced to the
requirement that motivated it.

## [Unreleased]

## [0.2.0] — 2026-09-21

Four subsystems added to `base-admin-panel`: a first-run setup wizard,
certificate automation, an HAProxy edge, and the settings surfaces. 57 new
requirements (215 → 272), two new build agents (24 → 26), Wave 3 now 15-wide.

### Added

**First-run setup wizard (`REQ-WIZ-01` … `REQ-WIZ-14`, agent A24)**
- A wizard that launches at first login and cannot be skipped. Every other route
  redirects to it while setup is incomplete, and the API refuses non-wizard calls
  with a distinct error code rather than a generic 403.
- The shipped account is `admin@example.invalid` with a password **generated at
  first boot** — never a fixed default, never in the repo or the image. It is
  constrained to completing setup: it holds no tenant-data permission and cannot
  call the API. It is not a global admin with a temporary password, which is the
  failure this design exists to prevent.
- Creating the real admin and destroying the bootstrap credential happen in one
  transaction. MFA enrolment with recovery codes is mandatory before that step
  can complete (`REQ-AUT-05`, `REQ-AUT-06`).
- SMTP must pass a **live verification send** before email-based password and OTP
  recovery is enabled. Configuration that has never delivered a message does not
  count as configured.
- Environment guidance reads actual runtime config through A01's env schema and
  reports missing versus insecure-default, rather than printing a static
  checklist.
- Resumable: each step either completes and records, or leaves nothing behind.
- Completion signs the session out, so the first real login is a real login.

**Certificate automation (`REQ-ACME-01` … `REQ-ACME-18`, agent A25)**
- All four validation paths: HTTP-01, DNS-01, TLS-ALPN-01 and **DNS-PERSIST-01**.
  The last one is real and newly practical: Let's Encrypt announced it
  2026-02-18, the record is a persistent TXT at `_validation-persist.<domain>`
  binding an ACME account and CA, CA/B ballot SC-088v3 passed in October 2025,
  and it suits multi-tenant platforms specifically.
- Renewal is **ARI-driven** (ACME Renewal Information), not a fixed fraction of
  lifetime. That distinction is load-bearing: Let's Encrypt's short-lived profile
  is 160 hours and expects renewal every 2–3 days with at-least-daily ARI checks,
  so a "renew at two-thirds of lifetime" rule is simply wrong there.
- Check interval configurable down to 1 hour; safety margin configurable. Those
  are the only two renewal knobs a user should ever need.
- Full ACME protocol debug logs in the renewal settings screen — every step,
  request, response, challenge transition, DNS lookup and error — reusing the
  existing `console-stream` protocol rather than inventing a second one, and
  subject to the same redaction rules.
- Guided DNS setup checks propagation against the domain's **authoritative**
  nameservers, because a cached negative answer from a recursive resolver makes a
  correct record look wrong.

**HAProxy edge (`REQ-PROX-01` … `REQ-PROX-12`, agent A01)**
- HAProxy is the default and only shipped edge, present even when the stack sits
  behind another proxy. Long-lived connections are load-bearing here — the debug
  console streams over SSE — and a proxy that buffers or coalesces breaks that
  feature while passing every short-request test.
- `REQ-PROX-06` therefore asserts that events emitted 5s apart **arrive** 5s
  apart, not that the endpoint returns 200.
- Three topologies: `self` (default, we own the edge and ACME end to end),
  `behind-proxy` (an upstream terminates public TLS), `delegated` (no HAProxy).
  Challenge-type availability follows from the topology, so the wizard steers the
  user rather than letting an order fail at issuance.
- Hitless certificate installation via HAProxy's Runtime API (`set ssl cert` +
  `commit ssl cert`). **Recorded trap:** Runtime API changes are in-memory only
  and lost on stop, so the installer writes to disk *and* applies live, and the
  test restarts the edge and re-asserts. Disk-only serves nothing; runtime-only
  silently reverts to the expired certificate on the next restart.
- Forwarded client address is trusted only from a configured trusted-proxy list.
  The audit trail records source IP, so a wrong client address is an integrity
  defect in the audit record, not a cosmetic one.

**Settings surfaces (`REQ-SET-01` … `REQ-SET-12`, agent A05)**
- Three always-distinguishable scopes: personal, tenant, global. Each panel
  states its scope *before* the save, shows the effective value and its source,
  and says so when a higher scope has locked it.
- Panels are contributed by the domains that own the data through a registry. No
  shared settings array exists — the same rule that keeps the parallel wave safe.
- Owned by A05, which already owned the settings shell. Adding an agent for a
  surface that already has an owner is the speculative generality the Karpathy
  lens exists to catch.

**Self-sufficiency (`REQ-FND-11`)**
- `docker compose up` on a clean host with a domain pointed at it yields a
  working HTTPS deployment: edge terminating TLS, certificate provisioned,
  migrations applied, app serving. No PaaS, no external orchestrator, no manual
  step between the command and a login page. A platform may sit on top; none is
  required.

### Changed

- **Docker Compose is the deployment target; a PaaS is one supported platform on
  top of it.** `REQ-WIZ-08` previously named a specific third-party platform as
  the subject of a `MUST`, which is the wrong shape for a requirement. It is now
  deployment guidance for the plain compose path, with platform notes as a
  separated subsection. No requirement text names a deployment vendor.
- `REQ-ACME-03` and `REQ-PROX-03` describe `behind-proxy` generically — a PaaS, a
  load balancer, a CDN, a hand-rolled proxy. The mode was always the right
  abstraction; the vendor was never part of it.
- `REQ-FND-04` names the `edge` HAProxy service.
- Every wave-width reference updated from 13 to 15 across 20 files.
- Contract member index extended with `wizard-state`, `certificate`,
  `settings-registry` and `edge-topology`.

### Fixed

Two additive CCRs, both surfaced by writing the settings panel inventory rather
than by discovering a blank screen at G6:

- **`AuditEvent.settingsScope`.** The envelope is `.strict()` and published no
  scope field, so `REQ-SET-09` was unsatisfiable and "every global change last
  week" was not a query. The two cheaper-looking alternatives are recorded as
  rejected: scope inside `target.id` turns a column filter into a prefix match,
  and a correlated second event doubles the trail and adds a breakable pairing.
- **Thirteen missing permission strings.** Enforcing "a global-scope panel must
  be gated by a `global.*` string" turned a vague gap into a list: five global
  panels had no permission at all. Since an unresolved permission denies, they
  would have shipped invisible — present in code, absent from the UI, nothing
  failing.

Also resolved: error message keys live at `<domain>.errors.<code_tail>` with
A02's `errors` namespace reserved for cross-domain codes, because the domain
that defines an error owns its wording; and `precision: "milli"` was added to the
time contract because the console renders sub-second timestamps and would
otherwise have formatted locally, breaking the single-formatter rule.

### Notes

- Still no generated application. Every claim remains a design claim.
- `REQ-FND-11`'s guarantee is the one most worth testing first, because it is the
  claim a user meets in their first thirty seconds.


## [0.1.0] — 2026-09-21

First release. Establishes the repository as a collection of boilerplates and
skills, and lands the complete prompt structure for the first boilerplate.

Assembled across several commits on one branch before any push, so 0.1.0 is the
first version with a consumer and the intermediate commits never shipped. From
here, `CLAUDE.md` rule 4 applies per change.

**97 files, ~18,000 lines, all prompt structure — no generated application yet.**

### Added

**Repository**
- Collection structure: `boilerplates/<name>/` plus a shared skill library at
  `.claude/skills/`.
- `CONVENTIONS.md` — the rules every boilerplate follows: self-containment,
  required structure, permanent requirement IDs, no versions from memory,
  ownership before parallelism, nothing self-approves.
- `scripts/check-conventions.sh` — the enforcement for all of the above. It
  verifies self-containment, required files, that every cited requirement ID is
  defined, that every requirement carries a status, that every agent named in an
  ownership map exists, that internal references resolve, and that every
  version-manifest entry carries its source and check timestamp.
- `boil-new-boilerplate` skill — scaffolds a conforming boilerplate.
- Single-boilerplate consumption: sparse checkout, `degit`, or handing an agent
  the folder path. Nothing in a boilerplate reaches outside its own folder.
- `docs/parallel-agent-builds.md` — the transferable method: the four ways a
  parallel agent build fails, and the specific fix for each.
- `README.md`, `SECURITY.md`, `CHANGELOG.md`, `TODO.md`, `CLAUDE.md`, `VERSION`.

**`base-admin-panel` — the prompt structure**
- `spec/requirements.md` — **215 requirements** with stable `REQ-*` IDs across 25
  domains: 213 `MUST`, 1 `SHOULD`, 1 `OPT`.
- `spec/traceability.csv` — 215 rows generated from the register, mapping every
  requirement to its owning agent, contract member, blocking gate and
  specification document. Gate load: G4 54, G6 45, G7 43, G8 34, G5 18, G3 8,
  G2 7, G1 6.
- `spec/agents.md` — 24 build agents across 5 waves plus 4 gate agents.
- 13 domain specifications: auth, RBAC and tenancy, entity model, datagrid,
  theming, screenspace, i18n, time, observability, API, data normalization, and
  `baseline.md` recording what is taken from
  `arhamkhnz/next-shadcn-admin-dashboard` and what is deliberately deviated from.
- `prompts/00-master-orchestrator.md` — wave dispatch, the G0–G8 ladder, CCR
  arbitration, loop discipline, and a table of what to do when each thing goes
  wrong.
- `contracts/README.md` — contract law (REQ-CTR-01 … REQ-CTR-10): declaration and
  central assembly, the G3 freeze, additive-only change, the CCR process, and
  fixture-based consumption. This is what makes a 13-agent parallel wave safe.
- `contracts/ownership.md` — single-owner map for every path, route group, table
  and migration namespace, including the "registry, never a shared list" rule
  that removes the shared arrays two agents would otherwise contend for.
- 18 contract artefacts across `types/`, `events/`, `openapi/` and `db/`: the
  entity envelope (REQ-ENT-01), the RFC 9457 error taxonomy (REQ-API-10), the
  shared pagination grammar (REQ-API-11), the `time` module that is the only
  formatter in the app (REQ-TIM-04), the permission catalogue (REQ-RBA-01), the
  canonical models (REQ-DAT-01), the i18n namespace registry (REQ-I18N-05), the
  audit envelope (REQ-AUD-04), the console stream protocol (REQ-AUD-08 …
  REQ-AUD-12), the notification envelope (REQ-PWA-04), the collector ingest
  envelope (REQ-OBS-05), a verified OpenAPI 3.1 skeleton (REQ-API-01), and the
  forced-RLS contract (REQ-RBA-04).
- `.claude/agents/` — **28 agent definitions**: 24 builders, each with owned
  paths, published and consumed contract members, and a verifiable definition of
  done; plus 4 blocking reviewers — two critics voting on design *and* function,
  and two independent security reviewers with separate review plans.
- `gates/` — the G0–G8 ladder, the structured per-requirement verdict schema
  (REQ-GAT-04), loop and escalation rules (REQ-GAT-05), and the Karpathy review
  lens (REQ-GAT-06).
- `.claude/skills/` — `build-orchestrate`, `contract-guard`, `version-guard`,
  `visual-qa-cdp`, `supply-chain-audit`, `release-build`.
- `versions/manifest.json` — **83 entries**, every one read from the authoritative
  registry with its source URL and check timestamp (REQ-VER-02, REQ-VER-03).
- `versions/traps.json` — 5 compatibility traps, inherited by the next build
  rather than rediscovered (REQ-VER-05).
- `versions/notes/typescript-7.md` — a real deferred decision naming the six
  dependencies that must be confirmed externally first.
- `normalizers/` — the engine contract, a JSON Schema for mapping descriptors,
  and two worked descriptors mapping deliberately dissimilar vendor payloads onto
  the same canonical model, both validated against the schema (REQ-DAT-02,
  REQ-DAT-03).
- `compliance/` — 11 documents covering EU CRA (Regulation (EU) 2024/2847) and
  CER (Directive (EU) 2022/2557), including the Annex I obligations matrix, the
  reporting runbook for obligations in force since 11 September 2026, the CVD
  policy, the Annex II/V/VII templates, and a 23-row operator-versus-product
  responsibility split.
- Theme preset `b2CjxkL2O` decoded rather than guessed: style `mira`, base colour
  `mist`, theme `emerald`, chart `emerald`, font `montserrat`, radius `small`,
  menu accent `bold`, base `radix` (REQ-UI-04).

### Verified externally rather than assumed

- All 83 dependency versions against npm, crates.io, PyPI, nodejs.org, Docker Hub
  and static.rust-lang.org.
- The `shadcn` CLI's `--preset`, `--base`, `--monorepo` and `--template` flags,
  and the preset code's decoded values.
- `/opt/pw-browsers/chromium` resolves to a real binary, while
  `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD` is **not** pre-set — so `visual-qa-cdp` says
  to export it rather than claiming it is already there.
- CRA and CER dates and deadlines, with source URLs cited per document.

### Fixed during assembly

Writing the conformance rules as a script instead of prose found defects that
prose review had not:

- 33 permission strings across 10 files violated the frozen 3-segment
  lowercase-hyphen grammar (REQ-RBA-01). The G3 assembly lint would have rejected
  every one of them.
- The RLS session setting was split between `app.tenant_id` and
  `app.current_tenant` across spec and contract. Unified on the name A04's
  declaration freezes.
- `REQ-AGT-04` was an invented requirement domain; the real ID is `REQ-OBS-02`.
- The entity-base exemption list was cited at `contracts/db/` in 6 files; the file
  is `contracts/types/entity-base.md`.
- Four contract members named in the contract law had no artefact, `time` being
  the most-cited undefined member in the whole contract.
- The fleet count was stated three different ways.
- A build-time artefact path was indistinguishable from a committed one; every
  reference to per-build state now carries its `build/` prefix.

### Known gaps, stated rather than implied

- **No application has been generated.** Every claim in the structure is a design
  claim, not an observed one. `TODO.md` lists what running it once would settle.
- `spec/screenspace.md` surface budgets are starting numbers the critics will
  argue with, not measured ones.
- `REQ-CRA-10` is structurally satisfied only: the evidence-collection tooling
  does not exist, and `obligations-matrix.md` marks the rows whose evidence is
  prose rather than a build output.
- The compliance documents carry `<<PLACEHOLDER: …>>` markers for the security
  contact, PGP key, legal entity and support dates. They are deliberately not
  invented.
- `typescript` 7.x is deferred; `syslog-pro` needs its RFC 5425 TLS support
  verified before adoption.

[Unreleased]: https://github.com/andreaswiren/boil/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/andreaswiren/boil/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/andreaswiren/boil/releases/tag/v0.1.0
