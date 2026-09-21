# Capability map

What this prompt structure needs a runtime to be *able to do*, and how each
runtime provides it. This file and agent frontmatter are the only two places a
product's tool name is allowed to appear (REQ-PORT-03). Requirements and specs
name capabilities; the map does the translation (REQ-PORT-02).

Read with `portability/README.md` for the model, and `portability/muse-code.md`
for the Muse Code adapter itself.

## How to read the columns

| Column | Means |
|--------|-------|
| Capability | The thing that has to get done. No product in the wording. |
| Why the structure needs it | The part of the build that stops working without it. |
| Claude Code | The reference implementation's name for it (REQ-PORT-01). |
| Muse Code | Muse Code running Muse Spark 1.3. |
| If unavailable | The REQ IDs that become unverifiable on a runtime that lacks it (REQ-PORT-06). |

`unconfirmed` is not hedging and it is not a guess. It means this build could not
read the vendor's own documentation for that item — `dev.meta.ai` and
`developer.meta.com` are both blocked by this environment's egress proxy — so the
cell carries the check to run instead of a flag we would be inventing. A
fabricated flag is worse than a visible gap, because a flag gets pasted.

## The map — reading, writing and running things

The first six are the floor: read, write, edit, shell, content search, glob. A
runtime missing any of them cannot run this boilerplate, and the honest answer is
to say so rather than run a partial build and present it as a build. The last
two, fetch and web search, are what make G2 possible at all — every version and
every price in this build is external or it does not exist (REQ-VER-02,
REQ-COST-05).

| Capability | Why the structure needs it | Claude Code | Muse Code | If unavailable |
|---|---|---|---|---|
| Read a file | Every agent reads `spec/requirements.md`, its own agent file, the frozen contract. | `Read` | Present in substance: it is a repo-aware CLI coding agent and reads `AGENTS.md` as project rules. Exact tool name `unconfirmed` — read the tool list in `muse --help` and the tools block of `~/.config/muse/settings.json`. | Nothing in this boilerplate is verifiable. Do not start a build. |
| Write a file | Ten mockups, `versions/manifest.json`, gate verdicts, the release records. | `Write` | Present in substance. Exact tool name `unconfirmed` — same check. | REQ-MOC-02, REQ-VER-03, REQ-GAT-04, REQ-REL-03, REQ-REL-04, REQ-REL-05, REQ-REL-06. |
| Edit in place | A gate finding is fixed by changing the lines the finding names, not by rewriting the file (`gates/loop-rules.md`). | `Edit` | Present in substance. Exact tool name `unconfirmed`. | REQ-GAT-05 — a bounded loop is judged on the diff per round. REQ-COST-07 — rework cannot be attributed to a finding without one. REQ-CTR-03 — additive-only is a claim about a diff. |
| Run a shell command | pnpm and Turborepo, Docker Compose, migrations, the breaking-change detector, every test suite, `git`. | `Bash` | Present. Headless form `muse exec "<prompt>"`, with approval waivable via `--disable-approval` / `--yolo` (`unconfirmed`, third-party; confirm in `muse --help`). | REQ-FND-02, REQ-FND-04, REQ-CTR-07, REQ-CTR-08, REQ-TST-01, REQ-TST-02, REQ-TST-05, REQ-SUP-01, REQ-SUP-02, REQ-SUP-05, REQ-REL-01. Without a shell this is a document, not a build. |
| Search file contents | Contract collision detection, the import-boundary check, the hardcoded-literal check, the telemetry assertion. | `Grep` | Present in substance; exact name `unconfirmed`. Shell `grep` is an adequate substitute where no first-class tool exists. | REQ-CTR-01, REQ-CTR-07, REQ-I18N-02, REQ-SUP-06. |
| List files by glob | Ownership enforcement — did this agent write outside its paths — and artefact counting (`ls -d mockups/m*/ \| wc -l`). | `Glob` | Present in substance; exact name `unconfirmed`. Shell equivalents suffice. | REQ-CTR-04, REQ-MOC-02, REQ-MOC-03. |
| Fetch a URL | A20 validates every version against its registry; A26 reads published pricing; A19 reads advisories. | `WebFetch` | Present in substance; exact name `unconfirmed`. Note that egress may be proxied or blocked in your environment regardless of the runtime. | REQ-VER-01, REQ-VER-02, REQ-VER-03, REQ-COST-05, REQ-SUP-02. A version or a price from the model's memory is the exact failure these requirements exist to prevent, so the build stops at G2 instead of guessing. |
| Search the web | Finding the authoritative source before fetching it; advisory and suspicious-package research. | `WebSearch` | `unconfirmed` — check the tool list. Fetch alone is workable when the URL is already known. | REQ-VER-01, REQ-SUP-02, REQ-SUP-03. |

## The map — dispatch and skills

This is where the structure is most opinionated and where a runtime is most
likely to differ. The fleet model (`spec/agents.md`) needs three things: a
subagent, several of them at once, and a procedure that loads when it is needed
rather than sitting in every context.

| Capability | Why the structure needs it | Claude Code | Muse Code | If unavailable |
|---|---|---|---|---|
| Dispatch a subagent | 31 agents, each with one owned surface, and a reviewer that is never the author. | `Task`, from `.claude/agents/` | Present: Muse Code is described as a multi-agent CLI, and its lifecycle-event list includes `SubagentStart` and `SubagentStop` (third-party source, `unconfirmed`). A plugin may carry `*.agent.md` files. A third-party report says children run one level deep and cannot spawn their own children — `unconfirmed`. | REQ-GAT-02, REQ-GAT-07, REQ-CTR-04, REQ-CTR-05. One context doing all the work cannot independently review itself; the build degrades to a single agent with a checklist. |
| Dispatch several subagents **concurrently** | Wave 3 is 15-wide. S1 and S2 are launched together with no shared context. | One message containing several tool calls. | Present, cap `unconfirmed` and sources conflict: one says two simultaneous subagents per session on the standard tier, another says roughly core count minus two clamped to 2–16. Measure it rather than trust it — dispatch A08 and A21 and watch whether both start before either finishes. | **No requirement becomes unverifiable.** Concurrency buys wall-clock, not evidence. Run the wave in batches or sequentially, produce the same artefacts, and write `sequential` in the wave row of the cost table (REQ-COST-06, REQ-COST-11). One thing does change: REQ-GAT-02 requires S1 and S2 not to see each other's findings, so sequential runs of those two must be in separate sessions, not one after the other in one context. |
| Load a skill on demand | Six skills hold the procedures: `build-orchestrate`, `contract-guard`, `version-guard`, `visual-qa-cdp`, `supply-chain-audit`, `release-build`. | `Skill`, or the `/name` form | **Confirmed**: Muse Code scans repo-local `.claude/skills` and `.codex/skills`, and ships `muse skills import --from claude`. Our skills are discoverable where they already are. The invocation syntax is `unconfirmed` — if there is no slash form, instruct the agent to read `.claude/skills/<name>/SKILL.md` as a file. | No REQ is lost. A skill is a procedure, and a procedure can always be read as a file. What is lost is cache economy, which shows up in REQ-COST-08's cache-read ratio. |

## The map — restriction, economics and state

The rows that decide whether a gate verdict means anything, and whether the cost
table is evidence or decoration.

| Capability | Why the structure needs it | Claude Code | Muse Code | If unavailable |
|---|---|---|---|---|
| Per-agent tool restriction | C1, C2, S1 and S2 get `Write` for `build/gates/` and nothing else. A gate agent that edits product code has become the defect. | `tools:` in agent frontmatter | `unconfirmed`. Settings hold a tools block and plugin agents are `*.agent.md` files, but this build could not confirm that a per-agent `tools` field is honoured; reporting on comparable harnesses says custom subagents inherit the parent's tools. Assume inheritance until you can show otherwise. | REQ-GAT-07 does not become unverifiable — it becomes structurally unenforceable, degrading from "the gate agent *cannot* write product code" to "the gate agent is *told not to*". Compensating control, recorded in `build/gates/<gate>/`: after every gate agent returns, `git diff --name-only` must show changes only under `build/gates/`. Anything else voids that verdict and the round re-runs. REQ-CTR-04 degrades the same way, with the same control. |
| Per-agent model selection | A26 is the cheapest agent in the fleet on purpose — spending build-model tokens to report on build-model spend is the one joke this design must not make (REQ-COST-04). | `model:` in agent frontmatter | `unconfirmed`. Muse Spark 1.3 is the model Muse Code runs; whether a per-agent override is read from a `*.agent.md` frontmatter is not confirmed. Related: `runtime_capabilities` reportedly gates background observer agents that make their own model calls. | REQ-COST-04's economics flatten — every agent runs the session model and A26's cost line stops being negligible. REQ-COST-01 still requires the model be named, so name the single model and state that every agent ran on it. |
| Report token usage | Every hand-off reports input, output, cache-read and cache-write tokens plus the model and effort it ran at. | Usage is returned with each agent result. | Partly, and indirectly. Third-party reports say Muse Code writes an append-only `session.jsonl` per session under `~/.local/share/muse/sessions/YYYY/MM/DD/<session-uuid>/`, whose `model_completed` events carry `input_tokens`, `output_tokens`, `cached_tokens`, `cache_read_tokens`, `cache_write_tokens` and `reasoning_tokens` — all `unconfirmed`. Check: `ls ~/.local/share/muse/sessions` and read one file before relying on it. | REQ-COST-01, REQ-COST-06 and REQ-COST-08 become unverifiable and REQ-COST-12 takes over: the cell reads `unreported` and the total is marked incomplete. Never derive money from an estimated token count (REQ-COST-04). Reasoning tokens and observer-agent calls are real spend belonging to no agent's hand-off — give them an `unattributed` row rather than dividing them across agents. |
| Persist working state between turns | `build/` carries intake, scope, waivers, approvals, CCRs, and every gate verdict for every round. | Ordinary filesystem writes in a persistent working directory. | Present — it is a local CLI running in a working directory. | REQ-GAT-04, REQ-GAT-05, REQ-MOC-05, REQ-COST-02. A build whose gate history cannot be reconstructed has no evidence, and evidence is the point. |
| A lifecycle hook | Nothing here requires one. It is the cheapest place to automate the ownership check (REQ-CTR-04) and the gate-agent write check (REQ-GAT-07). | `hooks` in settings | Documented as a first-class `hooks` block in `~/.config/muse/settings.json`. A third-party report contradicts this, saying the wired path is a native plugin manifest (`.muse-plugin/plugin.json`) installed behind `MUSE_EXPERIMENTAL_PLUGINS=1`, and that a project-level `hooks.json` is ignored. Conflicting, therefore `unconfirmed`. | No REQ. The two checks become explicit steps in the orchestrator's turn. Slower and human-visible, not weaker. |

## The three rows that carry the most weight

**Concurrency is the row people get wrong.** It looks like the most important
capability in the map and it is the least important to the evidence. Wave 3
dispatched 15-wide and Wave 3 dispatched three at a time in five batches produce
the same files, the same self-tests and the same G4 verdict. What changes is the
wall clock and the cache-read ratio (REQ-COST-08). So a runtime with a cap of two
is not a runtime that fails REQ-PORT-06 — it is a runtime whose cost table says
`sequential` in the concurrency column and whose G4 arrives later. The single
exception is REQ-GAT-02: two security reviewers run one after another *in the
same context* have seen each other's findings, which is the one thing that
requirement forbids. Separate sessions, not sequential turns.

**Per-agent tool restriction is the row that quietly costs you a guarantee.**
REQ-GAT-07 is written as a structural claim: the agent that wrote the code never
votes on it, and a gate agent physically cannot write product code because it was
not given the tool. On a runtime where subagents inherit the parent's tools, that
claim is no longer structural. The requirement does not change and is not waived
— what changes is the evidence for it, which moves from "the tool was absent" to
"the diff was checked". Write the check into the verdict file so a later reader
knows which of the two they are looking at.

**Token usage is the row that invites fabrication.** Every other gap in this map
is visible when it is missing. A token count is not: a plausible number in a
table is indistinguishable from a measured one, and it will be trusted and
compared against another build's real number. REQ-COST-12 exists for exactly this
row. `unreported` in the cell and `incomplete` on the total is the correct
output, and it is a better artefact than a confident guess.

## Checks to run before trusting any `unconfirmed` cell above

```bash
muse --help                        # the real subcommand and tool surface
cat ~/.config/muse/settings.json   # schema_version, tools, hooks, runtime_capabilities, telemetry
ls ~/.local/share/muse/sessions    # whether per-session usage logs exist at all
```

Read the subcommand list `muse --help` actually prints. Do not assume a
subcommand that is not in it, and do not carry a flag from this file into a
command without seeing it there first.

## Adding a runtime

A new runtime adds a column here and an adapter beside this file. It never edits
a requirement, a spec, or an agent's mission (REQ-PORT-10). If a capability is
genuinely new — something no current column needs — it gets a row, and every
existing column gets an honest cell, including `n/a`.
