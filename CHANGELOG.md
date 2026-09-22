# Changelog

All notable changes to this repository are recorded here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Entries cite the requirement IDs they affect, so a change can be traced to the
requirement that motivated it.

## [Unreleased]

## [0.8.0] — 2026-09-22

Reported from a real `base-admin-panel` build: the mockups used none of the
mandated stack. No shadcn, no Tailwind, no TanStack Table, no preset, no
baseline conventions, no datagrid chrome — "a free design", in the reporter's
words. Every one of those was a MUST in the register. The register was not the
problem; nothing bound the mockup phase to it.

### Fixed

**The mockup phase could not have used the stack it was required to use.**
`A08`'s output was `mockups/m*/index.html`, and its definition of done greped
those files. A standalone HTML page can contain no shadcn component, no Tailwind
build and no TanStack Table, so the format foreclosed the entire mandated stack
by construction. `mockups/` is now a runnable Next.js workspace with Tailwind
and shadcn at the preset, one route per thesis, and `pnpm --filter mockups
build` is the check that replaced the grep (`REQ-MOC-07`).

**Nothing in the MOC requirements named the stack.** `REQ-MOC-01`…`06` specified
ten layouts, three viewports, screenshots and human approval — no library, no
preset, no baseline. `G1`'s checklist cited `REQ-UI-04` and `REQ-MOC-06` but not
`REQ-UI-01`, `REQ-UI-02`, `REQ-UI-03` or `REQ-GRD-01`. Gates verify by ID, so a
hand-rolled page passed. New `REQ-MOC-08` binds the real `dashboard-01` and
`login-02` blocks and TanStack Table; `REQ-MOC-09` binds the baseline
conventions; `G1` now cites all of them and fails a round that misses them
**without taking it to the human at all** — a mockup set built against the wrong
stack is not a design disagreement, and the human cannot fix it by choosing.

**The datagrid appeared with none of its chrome.** New `REQ-MOC-12`: a thesis
showing a grid shows fuzzy search top-left, column chooser top-right, a sort
indicator, one type-aware filter and pagination at the bottom (`REQ-GRD-02` …
`REQ-GRD-05`, `REQ-GRD-09`). This is the surface where a simplified mockup does
the most damage, because the toolbar is precisely the chrome the layout has to
accommodate.

**Mockups were built before there was anything to build them against.** `A06`'s
own brief said "dispatch in Wave 1 alongside A08", so the token bundle A08 was
required to link might not exist when A08 started — which is how ten mockups end
up at a palette the agent invented. Wave 1 is now ordered: `A06` completes
first (`REQ-MOC-10`), and no mockup declares a colour, radius, font or spacing
value of its own.

**There was no menu either.** The `nav-registry` contract belongs to `A05`, a
Wave 3 agent, so at mockup time no navigation model existed and each thesis
invented one. Sidebar width, the collapse breakpoint and the chrome budget are
all consequences of the menu, so ten invented menus are ten measurements of
different things. New `REQ-MOC-13`/`REQ-MOC-14`: `A00` publishes
`build/navigation.md` at `G0` — real labels, real depth, real item count for a
tenant with every module enabled — and all ten theses render it.

**No expert reviewed a mockup before the human did.** `C1` was dispatched at
`G6` only; its own brief judged the built interface against the layout the human
had already approved at `G1`. So the human chose from an unreviewed set, and
`REQ-GAT-07` was satisfied everywhere except the one gate whose output every
later gate is measured against. New `REQ-MOC-11`: `C1` and `A27` both pass every
round before the human is asked.

### Added

**`ORC` — fleet supervision, and `A28`.** A wave that is dispatched and then
waited on is a wave whose failures are all discovered at the end. The
orchestrator now checks in at most every five minutes (`REQ-ORC-01`) and `A28`
runs alongside every wave on a cheap model doing the same independently
(`REQ-ORC-02`). A non-responding agent is **classified before it is retried** —
`hard-stop`, `stall`, `partial`, `malformed` — because retry is correct for one
of the four, and a loop that skips the classification turns one spend limit into
ten (`REQ-ORC-03`). **A partial landing is reconciled, never accepted**
(`REQ-ORC-04`): an agent that dies after writing four of nine files leaves a
tree that reads like completion, and the gate failure two waves later gets
blamed on whoever consumed the gap. Three failed revivals escalate
(`REQ-ORC-07`); every check-in is recorded, because a wave with no entries is
indistinguishable from one nobody watched (`REQ-ORC-06`).

**The baseline is pinned and vendored** (`REQ-UI-16`). `REQ-UI-03` measured
conventions against a GitHub repo and a live demo — both moving targets, so a
build was measured against whatever they served that day. `resources/next-shadcn-admin-dashboard/`
now holds the complete tracked tree at commit `5ac5a9a8`, 340 files, with the
upstream MIT notice and a SHA-256 per file in `resources/pin.json`. Our
conventions do not apply to vendored content and the checks skip it; the pin is
verified instead, and fails on an edit — an edited reference is an undeclared
fork that silently moves what every gate compares against.

### Checks

Two more, both confirmed to fail on an injected fault:
- Vendored resources match their pin, and the upstream licence notice is present.
- Stated counts match the register and roster — it caught all seven of this
  release's own count changes as they happened.

## [0.7.2] — 2026-09-22

### Added

- **The README now offers both boilerplates as a choice**, each with its own
  copy-paste command, rather than one command and "swap the name for the other
  one". The sparse-checkout fallback is parameterised, with the PowerShell
  equivalent named.
- **A section on running under Muse Code or another non-Claude runtime**, in the
  README where someone hitting the problem will look. It quotes the `AGENTS.md`
  precedence warning verbatim, says it is expected and costs nothing because
  every `CLAUDE.md` / `AGENTS.md` pair is byte-identical, and says plainly **not
  to act on the warning's own suggestion** to remove one of the two files —
  Claude Code reads one and Muse Code reads the other. It also says skills may
  not load and that nothing depends on them.
- `base-windows-rust-app/portability/README.md` gains a Muse Code row carrying
  the two observed facts, states that no adapter is written for it yet, and
  describes the four parts an adapter has so one can be written without a
  sibling to copy. It also gains the billing-tier check: a discounted tier is
  usually discounted because prompts and outputs may be used to improve the
  vendor's products, and this build sends the update trust chain, the elevation
  and IPC design and the signing procedure through the model.

### Fixed

- **`base-windows-rust-app` named a sibling boilerplate**, pointing at
  `../base-admin-panel/portability/muse-code.md` as a worked example. Hard rule
  1 forbids depending on a sibling, and the reference was doubly broken: written
  as if relative to the boilerplate root, it resolves to a path inside the
  folder that does not exist.
- The self-containment check could not have caught it. It pattern-matched
  `../..`, so a single `../` to a sibling — the case hard rule 1 names
  explicitly — passed. It now **resolves** every `../` path against the
  directory of the file holding it and fails only on one that lands outside the
  folder, which is both stricter and free of the false positives a pattern would
  produce on `contracts/../spec/x.md`, a Rust `include_str!`, or an ellipsis in
  a URL.
- That still would not have caught this one, because the path resolved inside
  the folder. So a repo-level check now fails any boilerplate whose text names a
  sibling boilerplate, which is the rule stated directly: naming one is the
  dependency, because the reader follows the name.
- A claim in the README that both boilerplates ship an adapter prompt. Only
  `base-admin-panel` does.

## [0.7.1] — 2026-09-22

Nothing in the repository said what starts a build, and the only slash command
in the README was the one that does not.

### Fixed

- **The README never named the build trigger.** Its only slash command was
  `/boil-new-boilerplate`, under a heading reading *Adding a boilerplate*, which
  reads as "how to use one". That skill authors a *new boilerplate into the
  collection*; it lives in this repository's root `.claude/skills/` and a
  vendored boilerplate correctly does not carry it. Both READMEs now say what
  actually starts a build — a paragraph, no command — name `/build-orchestrate`
  as the optional Claude Code shortcut, and say outright that
  `/boil-new-boilerplate` is not it.
- **Neither boilerplate README had a "how to start" section at all**, and both
  opened with `cd boilerplates/<name> && claude` — the build-in-place trap 0.7.0
  removed from the repository README but not from theirs. That snippet also
  named the boilerplate's path *inside the collection*, which is wrong in the
  vendored project where the README is actually read.
- **The collection root now says it is not a project.** An agent handed a clone
  of the whole repository reads the contributor rules and will treat a build
  request as a change to the collection. That is the likeliest root cause of a
  build that goes nowhere.
- Seven more stated counts that disagreed with the register: 272, 215 twice and
  "Thirteen expert agents" in `base-admin-panel`, plus 24 and 26 agents, and the
  "fifteen agents coordinating costs 105 conversations" arithmetic, now sixteen
  and 120.

### Added

- **A stated-count check**, because the number typed into a document is never
  re-derived when the register grows, and an agent reads it as fact. Every
  "N requirements" and "N-agent fleet" must match the register and the roster.
  It found two stale counts on its first run that the seven manual fixes had
  missed, in `portability/README.md` and `prompts/00-master-orchestrator.md`.

## [0.7.0] — 2026-09-22

Answers a question the repository had never stated an answer to: where a
boilerplate is supposed to live. The answer was already implied by
`contracts/ownership.md` and contradicted by the README.

### Changed

**A boilerplate becomes the project. It is not a folder you add to one.**
- Each ownership map opens with a *Workspace root* section assigning the
  workspace manifest, the lockfile, the toolchain pin, `.github/workflows/**`
  and `README.md` / `CHANGELOG.md` / `SECURITY.md` / `TODO.md` / `VERSION` to
  agents, and the build writes the application at those paths with no prefix.
  The folder you start in is the root of what you end up with. Both entry
  points now say so, and say what to do instead.
- **Nesting a boilerplate inside an existing project does not work**, and the
  failure is silent: at `yourproject/boilerplate/`, the ownership map's
  `Cargo.toml` and `.github/workflows/**` are ambiguous between two roots and an
  agent picks one without saying. An agent that finds itself in a subdirectory
  of a larger project is now told to stop and say so rather than guess a prefix.
- **A central boilerplate folder pulled in through a skill** has the same
  problem from the other direction and two more: not every runtime loads skills
  — Muse Code 1.3.0 does not, which is what 0.6.0 fixed — and the requirement
  register, the frozen contract and the CRA conformity evidence have to live
  with the product. An auditor handed a path outside the repository is in the
  same position as one handed a gitignored file, which is the defect fixed in
  0.5.0.
- `spec/`, `contracts/`, `gates/` and `compliance/` are stated to be permanent
  rather than scaffolding to delete once the app exists.

### Fixed

- **The README told you to build inside the collection.** Its first option was
  `cd boilerplates/base-admin-panel && claude`, which has the release agent
  overwrite that boilerplate's own `README.md` with the generated project's and
  drops a workspace manifest and CI workflows into this repository. Both
  boilerplates ship a `README.md` that their release agent owns, so the
  collision was certain rather than possible. The usage section now leads with
  a one-line `degit` that copies the boilerplate to where the project should
  live, and names both things not to do.

## [0.6.0] — 2026-09-22

Both boilerplates were unusable on Muse Code, and one of them had a broken
entry point on every runtime including Claude Code. Reported from a real
deployment; the portability adapter had asserted both as working.

### Fixed

**`AGENTS.md` carried no instructions (both boilerplates and the repo root)**
- Muse Code 1.3.0 gives `AGENTS.md` precedence and **ignores** `CLAUDE.md`:
  `warning: rules file at …\CLAUDE.md is ignored this session because AGENTS.md
  takes precedence in that directory`. All three `AGENTS.md` files were
  three-line pointers *to* `CLAUDE.md`, so on that runtime an agent received a
  note telling it to read the file the tool had just refused to read. Every hard
  rule, the map, the gate ladder and the no-self-approval rule silently failed
  to load.
- `CLAUDE.md` and `AGENTS.md` are now byte-identical in all three directories,
  and the conformance check fails if they drift. The duplication is deliberate:
  a pointer is a behaviour that depends on the agent following it, while two
  identical files are a fact the runtime cannot misread. Each pair carries a
  note saying the Muse warning is expected and that deleting either file breaks
  the other runtime.
- `portability/muse-code.md` had claimed "`CLAUDE.md` is read too — Muse Code
  falls back to `CLAUDE.md` … the entry-point chain in this repo survives
  unchanged" as something that **already works**. It is a precedence rule, not a
  fallback chain, and the adapter's own status line said `untested`. Rows stated
  as facts in an untested adapter are the defect, not just the wrong row.

**`/build-orchestrate` resolved to nothing in `base-windows-rust-app`**
- `CLAUDE.md` opened by telling the agent to run `/build-orchestrate`, and
  `.claude/skills/` was an empty directory. The documented first action of the
  documented entry point failed in every runtime, Claude Code included.
- The skill now exists, written for this boilerplate rather than copied: the
  `H0`–`H8` ladder, the 23-agent wave table with Wave 3 at nine, the four
  non-negotiable rules, `T1`/`T2` in separate sessions when concurrency is
  unavailable, and the `#[non_exhaustive]` CCR trap.

### Changed

**The entry point is a file read, not a slash command**
- Both boilerplates now lead with "read `prompts/00-master-orchestrator.md` and
  follow it", because that works on every runtime: it is a file rather than a
  feature. The skill is presented as a Claude Code shortcut, with reading
  `.claude/skills/build-orchestrate/SKILL.md` as an ordinary file named as the
  fallback. Muse Code does not load skills, which is the second half of what
  this deployment hit.
- `base-admin-panel/CLAUDE.md` stated 24 agents, 215 requirements and 13
  concurrent against an actual 32, 337 and 16. That is the first file an agent
  reads.

### Added

Two conformance checks, both confirmed to fail on an injected fault rather than
assumed to work:
- `CLAUDE.md` and `AGENTS.md` must be byte-identical.
- A slash command on a line of its own must resolve to a skill the folder ships.
  The first version of this check filtered its candidates by the directory it
  was meant to verify, so it could never fail — caught by testing it, which is
  the only reason it is a check rather than decoration.

## [0.5.0] — 2026-09-22

The repository becomes a collection of two boilerplates rather than one, and
the enforcement machinery moves inside each of them. `base-windows-rust-app`
joins `base-admin-panel`: 177 requirements, 20 domains, 23 agents, gates
`H0`–`H8`.

### Added

**`base-windows-rust-app` — a Windows desktop app in Rust with `windows-rs`**
- Tray-resident, self-installing with scoped elevation, optional service mode
  and login autostart, signature-verified auto-update, SBOM embedded in the
  binary, signed releases to GitHub and Gitea from one tag, and the same EU CRA
  and CER documentation set as the admin panel.
- **The design gate blocks first and mockups are compiled programs**
  (`REQ-MOC-01`, `REQ-MOC-02`). Three to five mockups, each a Rust binary that
  builds with `cargo build -p mockup-<n>` from a clean checkout, each stating
  its direction and its tradeoff, differentiated by density, type scale, chrome
  weight and accent strategy rather than by accent colour (`REQ-MOC-06`). A
  picture proves a shape can be drawn; it does not prove the framework's
  styling model can express it, which is the only question the gate asks.
- **One FFI boundary** (`REQ-FND-03`). `crates/ffi` is the only crate that
  calls `windows-rs`. Nine agents writing their own `unsafe` Win32 calls
  produce nine assumptions about handle lifetime and string encoding, and those
  bugs are memory-unsafe rather than merely wrong.
- **Gates are `H0`–`H8`, deliberately not `G0`–`G8`.** A verdict file cannot be
  read against the wrong ladder by accident.
- 31 crate versions and the toolchain validated against crates.io and the Rust
  release channel, each with source URL and timestamp; eight compatibility
  traps recorded in `versions/traps.json` so they are inherited rather than
  rediscovered.

**Per-state design tokens (`contracts/types/design-tokens.md`)**
- `contracts/README.md` promised the `design-tokens` member carried per-state
  tokens and it carried none: `REQ-DSN-10`'s seven states existed only as prose
  in `spec/design-system.md`, which is one agent's document rather than the
  frozen coupling nine crates build against. `State`, `StateStyle`, `StateSet`
  and `Selection` now exist, stated as diffs against `StateStyle::REST`.
- Hover and active are alphas over `palette.text_primary`, so one number works
  in both themes. High contrast carries state by stroke weight and a dashed
  disabled border, never by alpha: an 8% grey over a two-colour palette is the
  tint `REQ-DSN-08` forbids, and 38% of black on white is a grey that fails the
  contrast test the theme exists to pass.
- The state set has its own test, including `differs_from_rest`. The other
  assertions fail when someone writes a wrong value; that one fails when
  someone writes no value, which is how `busy` becomes a dimmed button.

**`REQ-REL-11` — the published release is verified as a client**
- Every other release check verifies what CI built. None verified what the
  forge serves. After publishing, a job holding no repository credentials
  resolves the manifest as the shipped updater does, verifies it with the key
  extracted from the shipped binary rather than one from the release page,
  checks hash and byte count against the manifest, verifies Authenticode, and
  runs the shipped updater against the real channel — per forge, per
  architecture.

**`REQ-GAT-09` — releasing verdicts must name the same commit**
- `H8` required four `H6` and two `H7` verdicts "on file, all passing" without
  requiring them to concern the same tree. One reviewer could approve the
  design at commit A and another clear the updater at commit C, leaving
  whatever landed between them unreviewed.

### Changed

**The conformance check ships inside each boilerplate**
- Hard rule 1 says a boilerplate never reaches outside its own folder. Six
  agent briefs ended with "run `./scripts/check-conventions.sh` from the
  repository root" — a file not in the folder those briefs ship in, so an agent
  handed the folder could not run the check its own definition of done
  required. Each boilerplate now carries `scripts/check-boilerplate.sh`, and
  the root script is a driver plus the checks that only make sense from outside
  one: no boilerplate cites a file it does not ship, every boilerplate is in
  the README, and the shipped generator copies have not drifted.
- The first of those found all six citations on its first run.

**`build/` is committed in both boilerplates**
- Both declared it gitignored working state while their CRA obligations matrix
  cited `build/gates/<verdict>.json` as Annex I II(3) evidence — at the
  strongest tier, on the stated grounds that an auditor can check a path. An
  auditor cannot check a path that is not in the repository. This also makes
  `REQ-MOC-08` true: a human's design approval recorded in a gitignored file is
  not recorded.

**`H1` no longer requires breaking `H2`**
- `H1` requires every mockup to build, building needs a dependency line, and
  `H2` — which runs after `H1` — blocks every dependency line no external check
  has validated. The first gate in the ladder was unsatisfiable. `B16` now runs
  a two-entry pre-pass at `H1` for the toolchain and the chosen framework,
  validated the same way; `H2` re-reads those entries rather than re-deciding
  them.

**`H5` installs per architecture**
- It built both targets and then installed on "a clean Windows image",
  singular. The install path touches the registry, ARP, shortcuts, the service
  account and WoW64 redirection, none of which a cross-compiled binary
  exercises from an x64 runner. A `REQ` ID verified on one image is now
  reported unverified for the other rather than green (`REQ-FND-04`).

**Version drift and MSRV are enforced, not just documented (`§4`, `REQ-VER-06`)**
- `CONVENTIONS.md` §4 banned versions written from memory, and the check
  verified only that each manifest entry carried a source and a timestamp. The
  harder failure was unguarded: a version copied correctly into a spec and left
  there while the manifest is re-validated. The check now fails on any
  `` `crate` X.Y.Z `` in any document that disagrees with the manifest.
- No manifest entry carried an MSRV, so `REQ-VER-06` had nothing to check. All
  30 crate entries now carry the `rust_version` their pinned release declares,
  read from the crates.io sparse index; the real floor is 1.95, and the check
  fails when the highest recorded MSRV rises above the pinned toolchain.

### Fixed

- `Elevation::FLAT_ALL` and `HIGH_CONTRAST_LIGHT_PALETTE` were named by the
  design-tokens contract and defined nowhere — one in a comment, one not at
  all — while the contract's own test iterates all four themes by name. A
  contract snippet that names something it never defines does not compile, and
  that file is the shape nine agents build against.
- `B16`'s brief carried a parallel `VER-TRAP-*` numbering that disagreed with
  `versions/traps.json`, including one trap the register did not have, and its
  example wrote a trap id into `manifest.json` that nothing could look up. The
  register's `WIN-TRAP-*` ids are now the only ones. The `sha2`/`digest`
  pairing is `WIN-TRAP-008`, verified rather than assumed: `sha2` 0.11.0
  declares `digest ^0.11`, so a dependency holding `digest 0.10` puts two
  `Digest` generations in one binary and a hash one computes is one the other
  cannot verify — which is exactly `REQ-UPD-02`'s comparison.
- The brief's example claimed `windows` 0.62.2 needs Rust 1.74; the index says
  1.82.
- `B02`'s freeze manifest moved from `contracts/frozen.json` to
  `build/contract-freeze.json`. `contracts/` is the boilerplate's own
  specification tree, and a CI check cannot read a manifest the boilerplate
  never ships.
- Requirement and fleet counts stated inconsistently: 165 requirements in four
  places against 175 defined; a "19-agent fleet" where 19 are builders and 4
  are the reviewers rule 9 depends on; the admin panel's "28-agent fleet"
  against 32 in its roster.

## [0.4.0] — 2026-09-22

Monaco editing surfaces, a dedicated mobile-UX owner, full user impersonation,
and the tenant chooser. 337 requirements (294 → 337), 34 domains, 32 agents.

### Added

**Mobile UX (`REQ-MOB-01` … `REQ-MOB-12`, agent A27)**
- `REQ-UI-07` has demanded a genuine mobile design rather than a narrowed
  desktop since 0.1.0 and had no dedicated owner: A05 owned the desktop shell
  and the mobile shell together. That is the arrangement the requirement warns
  about — when one agent owns both, mobile is what gets finished second.
- A27 owns the mobile primitives and the mobile half of every surface budget;
  domains compose them. It owns **no route file and no shell file**, and raises
  findings against other agents' mobile renderings rather than fixing them —
  a fix by A27 would be an ownership violation that also hides the defect from
  its owner.
- `TouchBudget` extends A05's `SurfaceBudget` rather than replacing it: a
  surface can satisfy chrome-vs-content and still have 28px buttons touching
  each other, which is the dimension A05's metrics cannot express.
- Landscape is deliberately **not** a fourth breakpoint — 844×390 resolves to
  `tablet` by width and would escape the mobile budget entirely. It is handled
  by `shortViewport`, keyed off measured height.
- `REQ-UI-07` and `REQ-UI-15` move to A27 in the traceability matrix.

**Editing surfaces (`REQ-MON-01` … `REQ-MON-12`, owned by A05)**
- Monaco is the base for every text-editing surface, with formatting active per
  supported file type from one language registry. Adding a language is a
  registry entry, never a new editor.
- Self-hosted with no CDN loader, lazy-loaded against an asserted bundle budget,
  themed from the app's own design tokens, and schema-validated inline — a
  mapping descriptor shows its error on the offending line, not as a toast after
  save.
- `REQ-MON-10`: Monaco is **not** used on touch-primary viewports. Shipping a
  desktop code editor to a phone and calling it responsive is the same failure
  `REQ-UI-07` names, so the surface degrades deliberately below the breakpoint.
- Monaco is A05's, not a new agent's: one well-bounded component, and A05
  already owned the design-token path `REQ-MON-08` needs.

**Impersonation (`REQ-IMP-01` … `REQ-IMP-12`, agent A04)**
- A global operator can enter a user's session and see exactly what that user
  sees — their tenant, navigation, data and permitted actions.
- `REQ-IMP-02` carries the weight: the effective permission set is the
  **target's exactly, never the union** with the operator's. The union arises
  naturally from a context-merging middleware and is invisible in testing,
  because the operator can do everything so nothing fails. What it leaves behind
  is worse than the escalation: every audit record from that session becomes a
  false statement about what was possible.
- `REQ-IMP-07` lists what stays refused mid-impersonation — credential change,
  MFA change, recovery codes, API-key minting, role changes, nesting, peer and
  self targeting — each with the escalation it prevents. Without that list,
  impersonation is privilege escalation with a receipt.
- The impersonated session is a **distinct object**, never a mutation of the
  operator's. Mutation in place is the design that makes exit unreliable and
  revocation impossible.
- Narrowing a refusal or widening the effective-permission rule requires **S1
  and S2 sign-off**, not orchestrator arbitration — the one place in this
  structure where the arbitration default is overridden, because those changes
  pass a shape-based breaking-change detector while changing what the system
  permits.

**Tenant switching (`REQ-RBA-09` … `REQ-RBA-12`, `REQ-UI-13` … `REQ-UI-15`)**
- A chooser top-left directly beneath the logotype, shown only above one
  accessible tenant. Position is part of the requirement: it answers *whose data
  am I about to change* before acting.
- Switching changes the **session, server-side**. A chooser that appends
  `?tenant=` is the exact bug `REQ-RBA-03` exists to prevent, and it works
  perfectly in testing because the tester is entitled to both tenants. RLS does
  not save you — the app sets its tenant GUC from whatever it believes, so a
  forged parameter forges the predicate too.
- Unknown and unauthorised tenants return the **identical** 403, so the endpoint
  is not a tenant-existence oracle.
- A switch clears every tenant-scoped store — cache, SSE streams, in-flight
  requests, optimistic mutations, grid preferences — and preserves personal
  preferences. Invalidating too much makes a switch feel like a logout, and a
  switch that feels like a logout is one people avoid, which pushes them into a
  second browser profile and out of the audit trail.

### Changed

- `scripts/gen-traceability.py` replaces the generator that had been rewritten
  inline five times, and `check-conventions.sh` now regenerates the matrix and
  fails if the committed copy differs — so it cannot drift from the register.
- Wave 3 is 16-wide.

### Notes

- Three files in this release were written by the main session after the
  authoring agents hit the org spend limit mid-run: A27's definition,
  `spec/tenant-switching.md` and `contracts/types/impersonation.md`.
- Still no generated application. Every claim remains a design claim.


## [0.3.0] — 2026-09-21

Token accounting and runtime portability. 294 requirements (272 → 294), 31
agents, 128 files. `scripts/check-conventions.sh` passes clean.

### Added

**Cost reporting (`REQ-COST-01` … `REQ-COST-12`, agent A26)**
- Every agent's hand-off now carries an `AgentReport` with its token usage —
  input, output, cache-read, cache-write, plus the model and effort it ran at.
  An agent that finishes without one has not finished. Added to all 26 agent
  files that have a hand-off section.
- The orchestrator presents the cost table **at every gate**, in the reply, not
  at the end. The gate ladder carries it as a standing pass criterion.
- **`null` means unreported, never `0`.** A zero is a claim that deflates a
  total someone will then trust; `null` reads as `unreported` and marks the
  total incomplete. A gate may pass with an incomplete total and may not pass
  with a fabricated one.
- **Measured tokens and derived money are never conflated.** Every money figure
  cites the unit price it used and whether that price is `verified` or
  `secondary`.
- Rework is attributed to its cause. A G6 finding costs the reviewer's round,
  the owner's fix and the re-review, and all three attribute to that finding —
  which prices the *defect* rather than the work, and is the only figure that
  says whether the gates earn their keep.
- Cache reads are reported separately from fresh input, because the ratio
  between them is the main cost lever the structure itself controls: a frozen
  contract read by fifteen agents is exactly the shape that caches well.
- A cost ceiling is an intake question. Crossing it pauses and asks — not a gate
  failure, not a loop round, not a silent continue.
- `versions/pricing.json` + `pricing.md` get the version manifest's discipline:
  source URL, check timestamp, and a `confidence` per entry.
- A26 runs on the cheapest model in the fleet on purpose, and its own file makes
  the arithmetic concrete: spending Opus tokens to report on Opus token spend is
  a 5x overhead for addition.

**Runtime portability (`REQ-PORT-01` … `REQ-PORT-10`)**
- `portability/capability-map.md` — 16 capabilities the structure needs, one
  column per runtime, and a final column naming **which REQ IDs become
  unverifiable** where a runtime cannot provide one. A runtime that cannot
  restrict an agent's tools degrades `REQ-GAT-07` from a structural guarantee to
  a prompt-level request, and the map says so rather than letting someone find
  out at G7.
- `portability/muse-code.md` — a paste-ready adapter for Muse Code running Muse
  Spark 1.3. An adapter, not a fork: two copies of a prompt structure diverge,
  one structure plus an adapter does not.
- The adapter is small because Muse Code already scans `.claude/skills` (and
  `.codex/skills`, and ships `muse skills import --from claude`), and its
  instruction-file fallback chain is `AGENTS.md` → `CLAUDE.md` — both of which
  this boilerplate already had.
- Telemetry must be off in the **agent runtime**, not only in the generated app.
  `REQ-SUP-06` applies to the tool doing the building.

### Changed

- `REQ-FND-04`/`REQ-ACME-03`/`REQ-PROX-03`: no requirement names a deployment or
  runtime vendor. Tool names live only in agent frontmatter and the capability
  map, which is the one place a translation happens.
- A22 consumes A26's cost summary and carries total, completeness flag and price
  confidence into the release record. It does not recompute them — A26 owns the
  arithmetic, A22 owns the record.
- A00 asks two new questions: the build cost ceiling, and — before the first
  wave — the training-tier decision of `REQ-PORT-08`.

### Known gaps, stated rather than implied

- **Every price is `secondary`.** `docs.claude.com` returned 302 and both
  `anthropic.com/pricing` and `dev.meta.ai` were unreachable through this
  environment's egress proxy. Anthropic's figures trace to a bundled skill cache
  dated 2026-06-24; Meta's to search snippets. Every money column is therefore
  an estimate and says so, and a `confidence` may not be upgraded without a
  successful fetch.
- **The Muse Code adapter is untested**, and its first line says so.
  `REQ-PORT-09` requires verification by running one wave on the target; there is
  no Muse Code binary here and Meta's hosts are blocked. The one-wave test is
  written in full and has not been run.
- **Muse Code reportedly defaults to the contributor tier**, where Meta may use
  prompts and completions to improve its products. If true, a build on a fresh
  install has already sent its prompts to a training-eligible tier before anyone
  chose anything — so the `REQ-PORT-08` decision must be made *before* the first
  run. Marked `unconfirmed`, with the command to verify.
- Exact Muse Code tool names, per-agent tool restriction, per-subagent model
  override, the subagent concurrency cap (two sources conflict), the usage-log
  path, telemetry key names and the hooks location are each marked `unconfirmed`
  with a check. None was invented — a fabricated settings key is worse than a
  gap, because it would be pasted.
- Still no generated application. Every claim remains a design claim.


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

[Unreleased]: https://github.com/andreaswiren/boil/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/andreaswiren/boil/compare/v0.7.2...v0.8.0
[0.7.2]: https://github.com/andreaswiren/boil/compare/v0.7.1...v0.7.2
[0.7.1]: https://github.com/andreaswiren/boil/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/andreaswiren/boil/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/andreaswiren/boil/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/andreaswiren/boil/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/andreaswiren/boil/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/andreaswiren/boil/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/andreaswiren/boil/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/andreaswiren/boil/releases/tag/v0.1.0
