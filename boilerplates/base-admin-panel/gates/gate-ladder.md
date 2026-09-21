# The Gate Ladder — G0 … G8

Fixed order. Per gate: entry, checks, runner, pass criterion, failure target,
human involvement. Verdicts land in `build/gates/<gate>/` (`verdict-schema.md`).

## G0 — Intake resolved
**Runs:** A00. **Entry:** the user's description exists. **Human:** yes — answers
the questions that change the build; the rest is defaulted loudly.
1. App name resolved, `apps/<app-name>/` fixed (REQ-FND-01).
2. Every `OPT` decided on or off, REQ-OBS-01 included.
3. Every `SHOULD` accepted or waived; each waiver in `build/waivers.md` cites the answer
   that granted it. Zero waived `MUST`s — a waived `MUST` fails the build.
4. Entities, integrations, locales (REQ-I18N-06), tenant model in `build/scope.md`.

**Pass:** `build/intake.md` + `build/scope.md` exist, every `OPT` has a value,
zero waived `MUST`s. **Fail →** A00 with the unresolved item named. A missing
human answer stalls the build; it is never guessed.

## G1 — Mockup approval
**Runs:** A08 (layouts), A06 (real theme), A21 (capture). **Human:** yes,
decisively — **the human names the winner.**
1. Exactly 10 mockups differentiated by **layout**, not palette; each names its thesis
   (REQ-MOC-02); each at 390 / 834 / 1440 px — 30 renders (REQ-MOC-03).
2. Screenshots presented in the chat response, not only on disk (REQ-MOC-04).
3. Real rendered HTML at preset `b2CjxkL2O` (REQ-UI-04, REQ-MOC-06) — honest typography,
   density, control sizes. Not drawings.
4. Chrome-vs-content budget per surface stated and visible (REQ-UI-10).

**Pass:** a human names one layout or an explicit hybrid of named ones, recorded
in `build/approvals.md` (REQ-MOC-05). **Blocks:** all production UI code —
nothing under `apps/<app>/components/**` or `app/(app)/**` exists before this.
**Fail →** A08 for another round, or one narrowing question to the human.

## G2 — Version validation
**Runs:** A20. **Entry:** G1 passed. **Human:** only on a major jump (REQ-VER-04).
1. Latest **stable** per language, runtime, framework, library and base image — no
   prerelease, no RC (REQ-VER-01) — each confirmed externally against npm, crates.io,
   PyPI, Docker Hub, nodejs.org, postgresql.org (REQ-VER-02), and written to
   `versions/manifest.json` with **source URL** and **timestamp** (REQ-VER-03).
2. Node = current LTS, PostgreSQL = current stable, both confirmed (REQ-VER-06). Base
   images pinned by digest (REQ-FND-09).
3. Compatibility traps recorded; `@types/node` tracks the Node **LTS** major, not the
   newest published major (REQ-VER-05).

**Pass:** zero entries without source URL and timestamp, zero prereleases, a
migration note per major jump. **Blocks:** every install — no `pnpm add`, no
`FROM`, no `Cargo.toml` dependency line before this (REQ-FND-06). **Fail →** A20.
A version that cannot be confirmed externally is a hard fail, never a fallback to
memory.

## G3 — Contract freeze
**Runs:** A02. **Entry:** G2 passed, A01 scaffold in place. **Human:** only to
arbitrate a breaking CCR (REQ-CTR-09).
1. Every `packages/<domain>/contract.declaration.ts` collected.
2. **Zero collisions** — duplicate permission string, i18n key, table name, operation id
   or error code stops assembly and names both claimants.
3. A02 publishes `entity-base`, `errors`, `pagination`, `time` — the only formatter in
   the app (REQ-TIM-04); `contracts@1.0.0` published, Wave 3 pins `^1.0.0`.
4. Fixtures generated **from** the Zod schemas (REQ-CTR-06); typed client generated from
   the OpenAPI document (REQ-API-01).
5. Import-boundary lint configured and failing on a domain-to-domain import
   (REQ-CTR-01). Breaking-change detector armed on the baseline (REQ-CTR-07).

**Pass:** 1.0.0 published, zero collisions, fixtures and client generated,
detector armed. **Blocks:** the launch of Wave 3 — 13 agents do not start against
a moving contract (REQ-CTR-02). **Fail →** A02 plus the agent declaring the
colliding member.

## G4 — Domain self-test
**Runs:** each Wave 3 agent for its own domain; A23 for interface tests.
**Entry:** Wave 3 reported complete. **Human:** no.
1. `GET /api/v1/<domain>/_selftest` green for every domain (REQ-CTR-08): schemas parse,
   permissions resolve, tables carry the envelope, RLS enabled on its tenant-scoped
   tables, env vars present.
2. `packages/contracts/tests/` interface tests pass, run by **both** producer and
   consumer (REQ-CTR-10).
3. Import-boundary lint clean workspace-wide (REQ-CTR-01); breaking-change detector
   clean against 1.0.0 (REQ-CTR-07).
4. Migration lint clean — no table missing the envelope and not listed exempt in
   `contracts/types/entity-base.md` (REQ-ENT-03).
5. `strict` + `noUncheckedIndexedAccess`, zero TS errors (REQ-FND-03).

**Pass:** every self-test green, interface tests green, both linters and the
detector clean. **Fail →** the single owning agent the failing self-test names.
Localised failure is the point of the self-test.

## G5 — Integration
**Runs:** A23, with A21 for capture. **Entry:** G4 passed. **Human:** no.
1. Stack boots from `compose.yml`: `app`, `db`, `smtp-relay`, `reverse-proxy`
   (REQ-FND-04). Migrations apply from empty; `/api/health/ready` reports DB,
   migrations, SMTP and syslog sink healthy (REQ-FND-10).
2. Seeded deterministic fixtures load — two tenants, a global operator, a user per role
   (REQ-TST-07). E2E critical journeys pass under Playwright over CDP (REQ-TST-01/02).
3. Tenant-isolation suite: cross-tenant read **and** write per table returns zero rows
   or raises (REQ-RBA-05). Permission-denial, MFA-enforcement and audit-emission suites
   pass (REQ-TST-05).
4. The three easily-faked behaviours proven by test: console stream, grid preference
   round-trip, read-audit emission (REQ-TST-08).
5. Screenshots at multiple points across mobile/tablet/desktop and light/dark
   (REQ-TST-03), presented in chat (REQ-TST-04). axe at AA in both themes (REQ-TST-06);
   surface budgets assert at every breakpoint (REQ-UI-10).

**Pass:** all suites green, screenshot set complete, budgets met. **Fail →** the
owning agent per `contracts/ownership.md`; a failure spanning owners goes to the
orchestrator to split, never to whoever is nearest.

## G6 — Design & function critique
**Reviewers:** C1 and C2. **Entry:** G5 passed, evidence available. **Human:**
only on escalation after three failed rounds (REQ-GAT-05).

Both critics vote on **both** dimensions — four verdicts, all must pass
(REQ-GAT-01): `C1-design-r<N>`, `C1-function-r<N>`, `C2-design-r<N>`,
`C2-function-r<N>` in `build/gates/G6/`. C1 leads on design, interaction and
density, and judges against the layout the human approved at G1 — drift from it
is a finding. C2 leads on completeness and edge cases: the requirement
implemented shallowly. Both run the Karpathy lens every build (REQ-GAT-06).

**Pass:** all four verdicts `blocking: false`, zero open `critical` or `high`
findings. **Fail →** each finding to the owning agent named in it; re-review by
the **same** critic on round `N+1` (`loop-rules.md`).

## G7 — Security review
**Reviewers:** S1 and S2 independently, plus A19. **Entry:** G5 passed. A G6 fix
does not re-open a completed S1/S2 review unless it touched a reviewed surface;
the orchestrator records that call. **Human:** only on escalation.
1. S1 and S2 launched **in the same message**, no shared context, neither seeing the
   other's findings before submitting (REQ-GAT-02).
2. For a larger change each states a written review plan first — common best practice,
   RLS, endpoints, authentication, privacy/integrity leakage — then executes it
   (REQ-GAT-03).
3. S1 covers architecture and boundaries: authn and session integrity, authorization
   completeness per route, RLS correctness and bypass paths, tenant isolation, global
   tier and impersonation, step-up, CSRF including Server Actions, the API key model.
4. S2 covers data, crypto and leakage: transit encryption on every interface including
   inside the compose network (REQ-SEC-01), envelope encryption and KEK rotation,
   redaction across every sink, the debug console as an exfiltration channel
   (REQ-AUD-12), push payloads (REQ-PWA-04), service-worker caching (REQ-PWA-03), SSRF
   and egress, the normalizer as an untrusted-input parser.
5. A19 clean in the same round: inventory complete (REQ-SUP-01), no critical or
   known-exploited advisory (REQ-SUP-02), suspicious-code scan clean (REQ-SUP-03),
   telemetry kill-list asserted (REQ-SUP-06), egress inventory matching the documented
   set (REQ-SUP-08).

**Pass:** `S1-code-r<N>.json` and `S2-code-r<N>.json` both `blocking: false`,
A19's report zero blocking entries. **Fail →** the owning agent per finding; same
reviewer, round `N+1`. A finding raised by **both** reviewers is a stronger
signal, not a duplicate to suppress.

## G8 — Release candidate
**Runs:** A22. **Entry:** G6 and G7 both passed. **Human:** yes — accepts the RC.
1. Every shipped feature has a help topic (REQ-DOC-03), localised and permission-aware
   (REQ-DOC-04). Charts regenerated from the real code, theme-aware, legible on mobile,
   none stale (REQ-DOC-06/07/08).
2. Compliance set generated from repository state (REQ-CRA-10); SBOM per build
   (REQ-CRA-03); CER set current.
3. **Every `MUST` green** — a `MUST` is never waived (REQ-REL-07). Four G6 verdicts and
   two G7 verdicts on file, all passing.
4. Semver bumped, level derived from the change set and recorded (REQ-REL-02).
5. `CHANGELOG.md` in Keep a Changelog form citing REQ IDs (REQ-REL-03); `README.md`,
   `SECURITY.md` and `TODO.md` with live gate state current (REQ-REL-04/05/06).
6. Committed and pushed; the commit message records gate outcomes and the bump reason
   (REQ-REL-01, REQ-REL-08).

**Pass:** all of the above and the human accepts. **Fail →** A22 for the record
files, the owning agent for a red `MUST`, back to G6 or G7 if a fix touched a
reviewed surface.
