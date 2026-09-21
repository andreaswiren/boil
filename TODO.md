# TODO

Live status for the `boil` repository. Updated in the same commit as the work it
describes (`CLAUDE.md` hard rule 4).

Repo version: **0.3.0**

---

## Done

### Repository
- [x] Collection structure: `boilerplates/<name>/` plus a shared skill library
- [x] `CONVENTIONS.md` — self-containment, required structure, permanent
      requirement IDs, no versions from memory, ownership before parallelism,
      nothing self-approves
- [x] `CLAUDE.md` / `AGENTS.md` operating instructions
- [x] `boil-new-boilerplate` skill
- [x] Single-boilerplate consumption: sparse checkout, `degit`, or handing an
      agent the folder path
- [x] `README.md`, `SECURITY.md`, `CHANGELOG.md`, `VERSION`

### base-admin-panel — prompt structure
- [x] `spec/requirements.md` — 294 requirements, 31 domains, stable IDs (292 MUST, 1 SHOULD, 1 OPT)
- [x] `spec/traceability.csv` — 294 rows, every requirement mapped to owner
      agent, contract member, gate and spec document; generated from the register
- [x] `spec/agents.md` — 27 build agents in 5 waves plus 4 gate agents; Wave 3 is 15-wide
- [x] `prompts/00-master-orchestrator.md` — dispatch, gates, CCRs, loop discipline
- [x] `contracts/README.md` — contract law (REQ-CTR-01 … REQ-CTR-10)
- [x] `contracts/ownership.md` — single-owner map for paths, routes, tables,
      migration namespaces
- [x] `contracts/` — 22 artefacts across `types/`, `events/`, `openapi/`, `db/`
- [x] `.claude/agents/` — 31 agent definitions (27 builders, 4 blocking reviewers)
- [x] `gates/` — G0–G8 ladder, verdict schema, loop rules, Karpathy lens
- [x] `.claude/skills/` — 6 operational skills
- [x] `spec/` — 18 domain specifications, incl. setup wizard, ACME/TLS, edge proxy, settings and cost reporting
- [x] `portability/` — capability map and the Muse Code adapter (untested)
- [x] `versions/pricing.json` + `pricing.md` — prices with per-entry confidence
- [x] `scripts/check-conventions.sh` — passes clean on the whole repo
- [x] `versions/manifest.json` — 83 externally validated entries with source URL
      and check timestamp (REQ-VER-02, REQ-VER-03)
- [x] `normalizers/` — engine contract, descriptor JSON Schema, two worked
      descriptors validated against it (REQ-DAT-02, REQ-DAT-03)
- [x] `compliance/` — 11 CRA and CER documents
- [x] `versions/traps.json` — 5 inherited compatibility traps (REQ-VER-05)

---

## Must resolve before the contract freeze (G3)

Three contract members that the setup wizard's steps legally depend on. They are
not design gaps — `spec/setup-wizard.md` specifies all three fully and builds
against fixtures — but each is a member no agent has declared yet, and
REQ-CTR-01 forbids A24 reaching into another package to do the work itself.
A02 assembles them at G3, or Wave 3 starts with a step that cannot be
implemented.

- [ ] **`identity.provisionGlobalAdmin`** (A03 publishes, A24 consumes). Creating
      the real admin writes `users`, `credentials`, `mfa_factors` and
      `recovery_codes` — all A03's tables. Without this member, REQ-WIZ-05 has no
      legal implementation. Specified as: idempotency key
      `(setup_state.id, lower(email))`, atomic, returns `ActorRef`.
- [ ] **A shared transaction handle, or an accepted invariant** (A02 decides).
      REQ-WIZ-04 says the real admin is created and the bootstrap credential
      destroyed "in one transaction", but the contract publishes no cross-package
      transaction handle. A24 specified the invariant instead — strict ordering,
      a guarded `WHERE` that makes teardown a no-op on replay, and a
      crash-injection test — so the property held is "the credential is destroyed
      only after a reachable admin exists". If a shared `tx` handle lands in
      contracts, this collapses to a true single transaction with no spec change.
      Either outcome is fine; leaving it undecided is not.
- [ ] **`readSetupGate()`** (A02 publishes, A01 and A05 call). REQ-WIZ-13's
      route-level redirect runs in `middleware.ts` (A01) and `(app)/layout.tsx`
      (A05), and neither may import `packages/setup`. Specified using the same
      boot-registration pattern A13 uses for `emitAuditEvent`. The API half needs
      no new member — `setup.incomplete` → 503 already comes from A11's route kit.

Two additive CCRs from this work are already assembled, so they are not on this
list: `AuditEvent.settingsScope` and the `acme` / `edge` values on the
`console-stream` domain enum.

---

## In progress

Nothing. 0.1.0 is the complete prompt structure; nothing is half-landed.

---

## Planned

### Prove the structure by running it
The structure has never produced an application. Until it has, every claim in it
is a design claim, not an observed one.

- [ ] Run one full build end to end against a real intake paragraph.
- [ ] Record the actual wall-clock per wave, so the "13-wide" claim has a number
      behind it.
- [ ] Count the Contract Change Requests raised in Wave 3. The G3 freeze quality
      is measured by CCR volume; a high count means the freeze checklist in
      `prompts/00-master-orchestrator.md` needs another item.
- [ ] Record how many rounds G6 and G7 actually take, and whether the
      three-round escalation rule (REQ-GAT-05) fires.
- [ ] Feed every defect the build revealed in the *structure* back into the
      structure, not just into the generated app.

### Gaps known now
- [ ] **Verify the Muse Code adapter by running one wave on it** (REQ-PORT-09).
      It is written in full and untested; there is no Muse Code binary here and
      Meta's hosts are blocked by the egress proxy. Until that run happens the
      adapter is a well-researched draft.
- [ ] **Confirm whether Muse Code defaults to the contributor tier.** Several
      sources say it does. If so, a fresh install has already sent prompts to a
      training-eligible tier, and the REQ-PORT-08 decision belongs before the
      first run. `cat ~/.config/muse/settings.json` and check which model id the
      session reports.
- [ ] **Upgrade at least one price to `verified`.** Every entry in
      `versions/pricing.json` is `secondary` because the vendor pricing pages are
      proxy-blocked here. Until one is verified, every money column in every
      build is an estimate.
- [ ] Muse Code's exact tool names, per-agent tool restriction, per-subagent
      model override, subagent concurrency cap, usage-log path, telemetry keys
      and hooks location are all `unconfirmed` with a check recorded. Each needs
      running once against the real binary.
- [ ] `REQ-FND-11` is the claim most worth testing first: `docker compose up` on
      a clean host yielding working HTTPS with nothing else installed. It is what
      a user meets in their first thirty seconds, and nothing has verified it.
- [ ] `DNS-PERSIST-01` production availability must be re-confirmed at build time
      (`REQ-ACME-05`). Let's Encrypt targeted Q2 2026; A25 checks rather than
      assumes.
- [ ] The HAProxy Runtime API certificate flow needs a restart-survival test, not
      just an install test — Runtime API changes are in-memory only
      (`REQ-PROX-09`).
- [ ] `spec/screenspace.md` surface budgets are starting numbers, not measured
      ones. They will be wrong until a real build argues with them (REQ-UI-10).
- [ ] `typescript` is at its 7.x native-rewrite line. Needs the REQ-VER-04
      reviewed-decision note and external confirmation that Next.js, Biome and
      drizzle-kit support it before a build adopts it.
- [ ] `syslog-pro` needs verifying for RFC 5424 structured data and RFC 5425 TLS
      before adoption, or replacing with direct framing over a `tls.TLSSocket`
      (REQ-AUD-07, REQ-SEC-05).
- [ ] The CRA and CER documents carry `<<PLACEHOLDER: …>>` markers for the
      security contact, PGP key, legal entity and support dates. A release must
      fill them; they are deliberately not invented.
- [ ] No canonical model set is defined yet beyond the worked `canonical.device`
      example — A00 resolves the model set per intake, but a starter set of
      identity / organisation / asset / event would save a wave.

### Next boilerplates
- [ ] Decide the second boilerplate. Candidates: a service/API-only backend with
      the same contract discipline and no UI; a data-pipeline boilerplate reusing
      the normalizer engine; a CLI tool boilerplate.
- [ ] Extract what is genuinely reusable across boilerplates into the repo-level
      skill library — but only after a second boilerplate exists, so the
      abstraction is drawn from two cases rather than guessed from one.

---

## Blocked

Nothing.

---

## Gate state

The G0–G8 ladder applies to a *build*, not to the repo. No build has run, so no
gate has a state. This section becomes meaningful on the first run.

| Gate | State |
|------|-------|
| G0 … G8 | not yet exercised |
