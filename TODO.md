# TODO

Live status for the `boil` repository. Updated in the same commit as the work it
describes (`CLAUDE.md` hard rule 4).

Repo version: **0.1.0**

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
- [x] `spec/requirements.md` — 215 requirements, 25 domains, stable IDs
- [x] `spec/traceability.csv` — 215 rows, every requirement mapped to owner
      agent, contract member, gate and spec document; generated from the register
- [x] `spec/agents.md` — 24 build agents in 5 waves, 4 gate agents
- [x] `prompts/00-master-orchestrator.md` — dispatch, gates, CCRs, loop discipline
- [x] `contracts/README.md` — contract law (REQ-CTR-01 … REQ-CTR-10)
- [x] `contracts/ownership.md` — single-owner map for paths, routes, tables,
      migration namespaces
- [x] `contracts/types/`, `contracts/events/`, `contracts/openapi/`,
      `contracts/db/` — concrete contract artefacts
- [x] `.claude/agents/` — 28 agent definitions
- [x] `gates/` — G0–G8 ladder, verdict schema, loop rules, Karpathy lens
- [x] `.claude/skills/` — 6 operational skills
- [x] `spec/` — 13 domain specifications
- [x] `versions/manifest.json` — 83 externally validated entries with source URL
      and check timestamp (REQ-VER-02, REQ-VER-03)
- [x] `normalizers/` — engine contract, descriptor JSON Schema, two worked
      descriptors validated against it (REQ-DAT-02, REQ-DAT-03)
- [x] `compliance/` — CRA and CER document sets

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
