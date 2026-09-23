# The Gate Ladder — G0 … G8

Fixed order. Per gate: entry, checks, runner, pass criterion, failure target,
human involvement. Verdicts land in `build/gates/<gate>/` (`verdict-schema.md`).


## The cost criterion, at every gate

Every gate below carries one additional pass criterion that is not repeated in
each section:

> **The cost table has been updated and presented in the reply** (REQ-COST-02,
> REQ-COST-03). Token counts come from each agent's `AgentReport.usage`; money
> is derived and labelled with the unit price it used (REQ-COST-04). An agent
> that handed off without a usage report has not satisfied REQ-COST-01, and the
> gate does not pass on its work.

A gate may pass with an **incomplete** total — where a runtime did not expose
usage, the cell reads `unreported` and the total says so (REQ-COST-12). A gate
may not pass with a **fabricated** total, and a `0` where nothing was reported
is fabrication.

If a cost ceiling was declared at intake and this gate crosses it, the gate
**pauses and asks** rather than failing or continuing (REQ-COST-09). A pause is
not a gate failure and does not start a loop round.

## The validation criterion, at every gate

The second criterion every gate below carries without repeating it:

> **The tree is green at the sha under review** (REQ-VAL-05, REQ-VAL-08).
> `pnpm validate` has been run — this session, at this sha — and exited zero,
> with zero warnings (REQ-VAL-06), zero skipped and zero focused tests
> (REQ-TST-12). The record is at `build/validation/<gate>.json` with the
> command, the exit code, the counts, the duration and the output tail
> (REQ-VAL-12).

A gate does not pass on an agent's statement that the tree builds. It passes on
an exit code someone obtained by running the command (REQ-VAL-04). These are
different things, and the gap between them is where a wave gets lost.

Three derived refusals, all mechanical:

- **Evidence spanning two shas does not pass** (REQ-VAL-08). Each
  piece may be true; the tree they jointly describe never existed.
- **A suppression count that rose since the previous gate is a finding**
  (REQ-VAL-07), with each new occurrence named and its REQ trade read. Rising
  suppressions is the ordinary way a red tree becomes a green one.
- **A stale capture does not pass** (REQ-CAP-10). Every surface the gate covers
  has a capture at this sha, with its console clean (REQ-CAP-07).

## The capture criterion, at every gate

> **The capture feed is current and has been delivered both ways**
> (REQ-CAP-01, REQ-CAP-04): the images are in the reply, `build/screenshots/`
> holds them with their sidecars, and `/_build/screenshots` on the live instance
> serves them. Three viewports, both themes, interacted states, console clean
> (REQ-CAP-06 … REQ-CAP-09).


## G0 — Intake resolved
**Runs:** A00. **Entry:** the user's description exists. **Human:** yes — answers
the questions that change the build; the rest is defaulted loudly.
1. App name resolved, `apps/<app-name>/` fixed (REQ-FND-01).
2. Every `OPT` decided on or off, REQ-OBS-01 included.
3. Every `SHOULD` accepted or waived; each waiver in `build/waivers.md` cites the answer
   that granted it. Zero waived `MUST`s — a waived `MUST` fails the build.
4. Entities, integrations, locales (REQ-I18N-06), tenant model in `build/scope.md`.
5. **`build/navigation.md`** — the resolved menu derived from those entities, the
   settings sections (REQ-SET-01) and the tenant model: every group and item,
   the nesting depth, the real labels, the icons and the gating permission,
   sized for a tenant with every module enabled (REQ-MOC-13, REQ-MOC-14). G1
   cannot start without it, because the menu is what the sidebar is sized to.

6. **The live instance is up** (REQ-LIV-01) and its URL and test logins have
   been given to the human in the reply (REQ-LIV-02). It serves the build status
   page; there is no UI yet and that is expected.

7. **`pnpm validate` exists and exits zero on the empty scaffold** (REQ-VAL-01).
   Authored by `A01` in Wave 0, before there is anything to hide. A validation
   command first written in Wave 3 is a validation command written to pass.
8. **The capture pipeline runs end to end on the status page** (REQ-CAP-06):
   Playwright resolves a browser, connects over CDP to the live instance,
   captures six images, writes six sidecars and renders `/_build/screenshots`.
   Proving the pipeline works on a page with nothing at stake is much cheaper
   than discovering at `G1` that it does not.

**Pass:** `build/intake.md` + `build/scope.md` exist, every `OPT` has a value,
zero waived `MUST`s, `pnpm validate` green, the capture pipeline proven. **Fail →** A00 with the unresolved item named. A missing
human answer stalls the build; it is never guessed.

## G1 — Mockup approval
**Runs:** A00 (`build/navigation.md`) and A06 (design system) **first and to
completion**, then A08 (layouts) and A21 (capture), then C1 and A27 (review).
**Human:** yes, decisively — **the human names the winner, and is asked last.**

**Two things exist before A08 starts** (REQ-MOC-10, REQ-MOC-13). They are not
concurrent with it:

- **A06's tokens.** A08 linking a token bundle that does not exist yet is how
  ten mockups end up at a palette and a type scale the agent invented.
- **A00's navigation model.** Sidebar width, the collapse breakpoint and the
  chrome budget are all consequences of the menu, so ten theses that each invent
  their own menu are ten measurements of different things, and the human is
  asked to compare them.

1. Exactly 10 mockups differentiated by **layout**, not palette; each names its thesis
   (REQ-MOC-02); each at 390 / 834 / 1440 px — 30 renders (REQ-MOC-03).
2. **Built in the shipping stack** (REQ-MOC-07): a runnable Next.js workspace,
   Tailwind, shadcn/ui at preset `b2CjxkL2O` on base `radix`, one route per
   thesis. `pnpm --filter mockups build` succeeds. **Standalone `index.html`
   fails this gate** — it can contain no shadcn component, no Tailwind build and
   no TanStack Table, so it cannot answer the only question the phase asks.
3. **Real components, not lookalikes** (REQ-MOC-08): the dashboard and login
   surfaces compose `dashboard-01` and `login-02` (REQ-UI-01, REQ-UI-02); every
   tabular surface is TanStack Table (REQ-GRD-01). No hand-written `<table>`.
4. **Every grid shows its real chrome** (REQ-MOC-12): fuzzy search top-left,
   column chooser top-right, a sort indicator, one type-aware column filter, and
   pagination at the bottom (REQ-GRD-02 … REQ-GRD-05, REQ-GRD-09). A grid drawn
   as bare rows hides the chrome the layout must accommodate, which invalidates
   the comparison the human is being asked to make.
5. **Navigation conventions follow the baseline** (REQ-MOC-09, REQ-UI-03,
   `spec/baseline.md`), and **every thesis renders the same menu** — the one in
   `build/navigation.md`, with its real labels, real nesting depth and real item
   count (REQ-MOC-13, REQ-MOC-14). Sized honestly: the longest label a tenant
   with every module enabled actually sees, not a convenient short one.
6. **No mockup declares a design value** (REQ-MOC-10): no hex, no raw radius,
   font stack or spacing number outside A06's tokens. Grep the mockup sources —
   a literal is a fail, not a note.
7. Screenshots presented in the chat response, not only on disk (REQ-MOC-04),
   and captured by **A21 over CDP from a production build** of the mockup
   workspace — `pnpm --filter mockups build && start`, never `next dev` and
   never a file path (REQ-TST-02, REQ-MOC-07). A render carrying the dev
   overlay is a picture of the toolchain; a build that fails here is a G1 fail
   reported as such, not something to screenshot around.
8. Chrome-vs-content budget per surface stated and visible (REQ-UI-10).
9. **C1 and A27 have both passed this round** (REQ-MOC-11), neither having
   written the mockups (REQ-GAT-07). C1 judges design; A27 judges the 390px
   renderings against the touch and mobile budgets. Verdicts at
   `build/gates/G1/C1-design-r<N>.json` and `build/gates/G1/A27-mobile-r<N>.json`.

**Pass:** checks 1–9 green, the live instance serving the mockups at the URL the
human was given (REQ-LIV-02, REQ-LIV-03) — they browse them, not only the
screenshots — **then** a human names one layout or an explicit
hybrid of named ones, recorded in `build/approvals.md` (REQ-MOC-05). The human is
asked last, not first: their attention is the one resource in this build that
cannot be re-run, and spending it on a set two reviewers would have rejected is
the waste this gate exists to prevent.

**Blocks:** all production UI code — nothing under `apps/<app>/components/**` or
`app/(app)/**` exists before this.

**Fail →** A08 for another round, or one narrowing question to the human. A
round that fails checks 2, 3, 4, 5 or 6 is not a design disagreement and is not
taken to the human at all — it is a mockup set built against the wrong stack,
and the human cannot fix that by choosing.

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
5. `strict` + `noUncheckedIndexedAccess`, zero TS errors (REQ-FND-03), ESLint at
   `--max-warnings=0` (REQ-VAL-06).
6. **Every Wave 3 hand-off carried a green validation block at its own sha**
   (REQ-VAL-02) — fifteen of them, checked, not sampled. A hand-off accepted
   without one was accepted in error and its work is unverified (REQ-VAL-03).
7. **Red-first evidence for every claimed REQ** (REQ-TST-09): each agent's
   `validation.redFirst` names the test, the failing sha and the passing sha.
8. **The four silent suites pass here, not first at `G5`** (REQ-TST-16): tenant
   isolation, permission denial, MFA enforcement, audit emission.
9. **`build/validation/req-coverage.md` regenerated** (REQ-TST-11): every `MUST`
   in the register maps to a test or to a recorded reason it cannot be tested.
10. **Generated artefacts regenerate to an empty diff** (REQ-VAL-13): the typed
    client, the fixtures, the traceability matrix.

**Pass:** every self-test green, interface tests green, both linters and the
detector clean, every hand-off validated, coverage map complete. **Fail →** the single owning agent the failing self-test names.
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

6. **`pnpm validate:full` green** (REQ-VAL-14): the workspace validates, the
   image builds, the stack boots, migrations apply from empty and
   `/api/health/ready` is healthy. A workspace that typechecks and an image that
   starts are two different claims and both are being made here.
7. **The capture feed covers every surface at this sha** with interacted states
   and a clean console (REQ-CAP-07 … REQ-CAP-10) — a page whose fetch 500s and
   whose error boundary renders tidily photographs as a working feature.

**Pass:** all suites green, `validate:full` green, capture feed current at this
sha, budgets met. **Fail →** the
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
   two G7 verdicts on file, all passing, all naming this sha (REQ-VAL-08).
   `build/validation/req-coverage.md` shows a test or a recorded
   untestable-reason per `MUST` (REQ-TST-11); zero skipped, zero focused, zero
   quarantined tests (REQ-TST-12, REQ-TST-14); the suppression ledger shows no
   unexplained rise across the ladder (REQ-VAL-07).
4. Semver bumped, level derived from the change set and recorded (REQ-REL-02).
5. `CHANGELOG.md` in Keep a Changelog form citing REQ IDs (REQ-REL-03); `README.md`,
   `SECURITY.md` and `TODO.md` with live gate state current (REQ-REL-04/05/06).
6. Committed and pushed; the commit message records gate outcomes and the bump reason
   (REQ-REL-01, REQ-REL-08).

**Pass:** all of the above and the human accepts. **Fail →** A22 for the record
files, the owning agent for a red `MUST`, back to G6 or G7 if a fix touched a
reviewed surface.

**Additionally at G8:** the build total is written into the release record
(REQ-COST-10), with its completeness flag and the price confidence it was
derived at. A release whose cost is unrecorded cannot be compared to the next
one, which is most of the reason to measure it.
