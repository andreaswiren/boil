# Adapter — Muse Code (Muse Spark 1.3)

The adapter for running this boilerplate on Meta's Muse Code CLI (REQ-PORT-04).
It corrects what Muse Code would otherwise misread. It restates no requirement
(REQ-PORT-05), and it edits nothing in `spec/`, `contracts/`, `gates/` or
`.claude/` (REQ-PORT-10).

**Status: untested.** The Muse Code facts below were confirmed externally on
2026-09-21; the adapter has not yet had Wave 1 run through it. Section 7 is that
test. Anything this build could not confirm from Meta's own documentation —
`dev.meta.ai` and `developer.meta.com` are blocked by this environment's egress
proxy — is marked `unconfirmed` and carries the check to run.

## 1. What already works

Most of the surface. The adapter is small, and that is the point of having a
capability map rather than a fork.

| Already works | Why |
|---------------|-----|
| `AGENTS.md` is the entry point | Muse Code reads project instructions from `AGENTS.md`, seeded by `muse init`. This boilerplate already has one, and it points at `CLAUDE.md` and `prompts/00-master-orchestrator.md`. |
| `CLAUDE.md` is read too | Muse Code falls back to `CLAUDE.md` (and `.agents/AGENTS.md`, `.claude/CLAUDE.md`). The entry-point chain in this repo survives unchanged. |
| The six skills are discoverable where they are | Muse Code scans repo-local `.claude/skills` and `.codex/skills`. Nothing is moved and nothing is renamed. `muse skills import --from claude` exists if you want them copied into Muse's own store instead. |
| Every spec, contract and gate document | Plain Markdown naming no tool (REQ-PORT-03). `spec/requirements.md`, `spec/agents.md`, `contracts/ownership.md`, `gates/gate-ladder.md` and `gates/loop-rules.md` read identically on any runtime. |
| Every agent file's body | The mission, owned REQ IDs, owned paths, definition of done and hand-off shape are runtime-neutral prose. Only the frontmatter needs translating. |

What is left to correct: frontmatter vocabulary, one dispatch sentence, one
invocation syntax, and two runtime settings. Sections 3 onward.

## 2. The adapter prompt

Paste this into Muse Code at the start of a build, in the boilerplate's working
directory. To make it permanent instead, append it to `AGENTS.md` under a
`## Muse Code` heading — Muse Code reads that file as project rules, so it then
applies to every session in this directory without being pasted.

```
You are the build orchestrator for the base-admin-panel boilerplate in this
working directory. You dispatch agents, hold gates and arbitrate. You do not
write product code.

AUTHORITY
Read prompts/00-master-orchestrator.md now, and follow it. It is the process of
record: the wave table, the G0-G8 gate ladder, the loop rules and the failure
modes. Do not re-derive the process, do not replace it with a plan of your own,
do not improve it. Where this prompt and that file disagree about process, that
file wins; this prompt only translates mechanics it states in another runtime's
vocabulary. Then read, in order: spec/requirements.md, spec/agents.md,
contracts/ownership.md, gates/gate-ladder.md, gates/loop-rules.md.

DO NOT REWRITE THE STRUCTURE
Everything under spec/, contracts/, gates/ and .claude/agents/ is an input, not
a draft. Do not edit a requirement, do not renumber a REQ ID, do not restate a
requirement in your own words, and do not adjust an agent's mission or owned
paths to suit how you prefer to work (REQ-PORT-05, REQ-PORT-10). Where one of
those files names a tool you do not have, translate the tool and keep the
instruction intact. If you think a requirement is wrong, stop and say so to the
human - do not edit it and continue.

VOCABULARY
The agent files name Claude Code tools. Map them to yours and carry on:
  Read      -> read a file
  Write     -> create a file
  Edit      -> change part of a file in place
  Bash      -> run a shell command
  Grep      -> search file contents
  Glob      -> list files by pattern
  WebFetch  -> fetch a URL
  WebSearch -> search the web
  Task      -> start a subagent from the named agent file
  Skill     -> load the named skill from .claude/skills/<name>/; if you have no
               load mechanism, read .claude/skills/<name>/SKILL.md and follow it
portability/capability-map.md is the full map. Before you start, say which of
these you can do, which you cannot, and - for each gap - the REQ IDs from the
map's last column that become unverifiable.

AGENTS
The 31 agent files are .claude/agents/<id>-<slug>.md. Each one is a complete
subagent prompt: YAML frontmatter, then the mission. Pass the body to the
subagent as its instructions. The frontmatter is Claude Code's dialect:
- tools: is the agent's declared scope. Honour it as a hard limit even if your
  runtime cannot enforce it per subagent. C1, C2, S1 and S2 may write only to
  build/gates/.
- model: names an Anthropic model. Ignore it unless you can set a model per
  subagent, and never substitute a model name you have not seen in your own
  tooling.

DISPATCH
A wave means: every agent in the wave is started before any of them finishes.
It does not mean one message and it does not mean any particular tool-call
shape - those are Claude Code mechanics, not the requirement. Start them
however your runtime starts several subagents at once.
If you cannot run them concurrently, run them in batches or one at a time. Do
not shorten the agent list, do not merge two agents into one, and do not skip an
agent because the wave is long. Record "sequential" or the batch size in the
concurrency column of the wave row in build/costs.md. The artefacts are
identical either way; only the wall clock changes.
Two exceptions:
- Wave 2 (A20 -> A01 -> A02) is sequential by design. Never parallelise it.
- S1 and S2 must not see each other's findings (REQ-GAT-02). If you cannot run
  them at the same time, run them in two separate sessions - not two turns of
  the same session, which shares the context that requirement forbids sharing.

GATES
Nothing self-approves. Never give a build task to C1, C2, S1 or S2, and never
let an agent review its own output (REQ-GAT-07). After every gate agent
returns, run `git diff --name-only` and confirm it changed nothing outside
build/gates/; if it did, that verdict is void and the round re-runs. Record that
you ran the check in the verdict file. G1 is a human stop: ten mockups at three
viewports, the screenshots presented in your reply, and then you wait for a
named winner.

REPORTING
Every hand-off reports its own token usage - input, output, cache-read,
cache-write - and the model it ran on (REQ-COST-01). If your runtime does not
expose a number, write "unreported" and mark the total incomplete (REQ-COST-12).
Never estimate a token count, and never present derived money as a measured
figure (REQ-COST-04). Present the cost table in your reply at every gate
(REQ-COST-03).

BEFORE YOU START
Confirm telemetry is off in your own runtime settings, not only in the app you
are about to build (REQ-PORT-07, REQ-SUP-06). Confirm which pricing tier this
session bills to (REQ-PORT-08). Both procedures are in
portability/muse-code.md, sections 4 and 5. Then begin at Wave 0 with A00.
```

## 3. Corrections

Instruction shapes in this repo that a non-Claude runtime would misread.

| In the repo | Where | The misreading | Substitute |
|---|---|---|---|
| `tools: Read, Write, Edit, Bash, Grep, Glob` | frontmatter of every build agent | Reads as an allowlist in names Muse Code does not use; a runtime may ignore the line or reject the frontmatter | Translate per the map in section 2. Treat the line as the agent's declared scope regardless of whether it is enforced. |
| `tools: Read, Grep, Glob, Bash, Write` | `C1`, `C2`, `S1`, `S2` | Looks like an ordinary tool list. The point is that `Write` exists **only** for `build/gates/` (REQ-GAT-07) | Carry the scope into the subagent prompt as a sentence, then verify with `git diff --name-only`. Record in the verdict that the guarantee was checked by diff rather than enforced by tool. |
| `model: opus` | every build agent | Not a Muse model id | Muse Spark 1.3 is the build model. Do not map it to a Meta model name you have not read in your own tooling. |
| `model: claude-haiku-4-5` | `A26` (see `versions/pricing.json`) | Not a Muse model id, and A26's design assumes a cheaper tier exists (REQ-COST-04) | Per-subagent model selection is `unconfirmed` on Muse Code. If it is unavailable, A26 runs on the session model — say so in the cost table rather than leaving the reader to assume A26 was cheap. |
| "Launch every agent in a wave in a single message with multiple tool calls" | `prompts/00-master-orchestrator.md` | Reads as a rule about message formatting; a runtime with a different dispatch shape may conclude the wave cannot be run at all | "Every agent in the wave starts before any of them finishes." If concurrency is capped, batch it and record the batch size. |
| `/build-orchestrate` | `CLAUDE.md` | A slash command that may not exist | The skill is at `.claude/skills/build-orchestrate/SKILL.md` and Muse Code scans `.claude/skills`, so it is discoverable. The invocation syntax is `unconfirmed` — check `muse --help`. Reading the `SKILL.md` as a file is always a valid fallback. |
| `.claude/agents/` as the agent store | the 31 agent files | Muse Code's own agent format is `*.agent.md` inside a plugin. Whether it scans `.claude/agents/*.md` is **`unconfirmed`** | Do not move the files. The orchestrator reads the agent file and passes its body to the subagent. For native discovery, **copy** each file to `<id>-<slug>.agent.md` inside a plugin (keeping `name` and `description`); the plugin layout and discovery path are `unconfirmed` — check `muse --help` and the plugin-authoring skill that ships inside the binary. Never delete the `.claude/agents/` originals: they are the Claude Code reference implementation (REQ-PORT-01). |
| "presented in the chat response" | REQ-MOC-04, REQ-TST-04, `A21` | A CLI agent may treat writing the PNG to disk as done | The requirement is that the human sees the images in the reply. If the terminal cannot render them, list every path **and state explicitly that the images were not rendered**. That is a recorded REQ-TST-04 failure, not a pass. |
| `spec/requirements.md` as something to summarise | all agents | A model with a 1M-token context may pull the whole register in and paraphrase it into a plan | Cite REQ IDs; never paraphrase a requirement into a second wording (REQ-PORT-05). The register is the only source of truth. |

## 4. Telemetry — do this before the first build

REQ-SUP-06 disables telemetry for every tool in the stack. REQ-PORT-07 extends
that to the tool doing the building: a build that ships a telemetry-free app from
a runtime that phoned home has satisfied neither.

Muse Code's user settings are `~/.config/muse/settings.json`, and that file must
set `"schema_version": 1`. It holds model defaults, UI preferences, tool and MCP
configuration, a `hooks` block, `runtime_capabilities` toggles, and telemetry
options.

1. Read the file. `cat ~/.config/muse/settings.json`. If it does not exist, the
   CLI writes it on first run; a minimal valid file is `{"schema_version": 1}`.
2. Find the telemetry keys **by reading them**. The exact key names are
   `unconfirmed`: start with
   `grep -iE 'telemetry|analytic|metric|usage|report|crash' ~/.config/muse/settings.json`
   and read the whole block it lands in. Never paste a key name from here or
   anywhere else — an invented key is silently ignored, which looks like success.
3. Check `runtime_capabilities` in the same file. Third-party reporting says
   Muse Code runs background observer agents (memory recall, skill recall, goal
   tracking, verification), three on by default, each making its own model calls
   (`unconfirmed`). They are both off-session traffic and unattributed spend, so
   they matter twice here: REQ-PORT-07 and REQ-COST-01.
4. Confirm against the tool itself: `muse --help`, and any settings or config
   subcommand it lists. Take the key names from what it prints.
5. Assert, do not assume — that is REQ-SUP-06's actual discipline. Record the
   exact keys and values you set, with the date, in `build/gates/G7/`, and give
   them to `A19` so the telemetry kill-list covers the runtime as well as the
   built app (REQ-PORT-07).

If a telemetry option cannot be found or cannot be turned off, that is a finding
for G7, stated plainly, not a footnote.

## 5. The contributor-tier decision

Muse Spark 1.3 is billed two ways. Prices are recorded in
`versions/pricing.json` (`A26` owns that file — do not edit it here).

| Endpoint | Input / 1M | Cached input / 1M | Output / 1M | Data |
|---|---|---|---|---|
| Standard | ~$1.25 | ~$0.15 | ~$4.25 | Not used to improve Meta products |
| Contributor | ~$0.10 | ~$0.002 (`unconfirmed`) | ~$0.20 | Meta **may use prompts and outputs** to improve its products |

Roughly 12x cheaper on input and 21x cheaper on output. The discount *is* the
data term; it is not a volume discount that happens to come with one.

What this build sends through the model: the security posture of the panel, the
credential and secret-handling guidance, the RLS policy design for every
tenant-scoped table, the compliance evidence set, and the operator's own
description of their tenants and users. That is the material the cheap tier
buys with.

So it is a recorded decision, never a default (REQ-PORT-08):

- **Recommendation: the standard endpoint.** Use contributor only where the
  operator has decided otherwise in writing.
- Record the decision — endpoint, who decided, when, and why — in
  `build/scope.md` with the rest of the intake decisions, and name it in the
  release record (REQ-REL-08).
- **Check the tier before the first build, not after.** Several third-party
  sources report that Muse Code starts on a contributor model by default (one
  names `muse-spark-1.3-contributor`) and that you must switch to opt out. This
  is `unconfirmed` and it is material: read the model default in
  `~/.config/muse/settings.json` and confirm the endpoint in whatever billing or
  account view `muse --help` points to. Do not infer the tier from the price you
  expected to pay.
- A contributor-tier run of this boilerplate on real tenant data is a decision
  about disclosure, not about budget. Price it that way.

## 6. What is unverifiable on this runtime

From the last column of `portability/capability-map.md` (REQ-PORT-06). Each line
is conditional on a check in that file coming back negative — run the checks
first. Nobody should meet this list for the first time at G7.

| If this is unavailable | These stop being verifiable |
|---|---|
| Per-agent tool restriction | REQ-GAT-07 and REQ-CTR-04 — structurally. They survive as an instruction plus a `git diff --name-only` check, which is weaker evidence and must be labelled as such in the verdict. |
| Per-agent model selection | REQ-COST-04's economics — A26 stops being the cheap agent it was designed to be. |
| Token usage reporting | REQ-COST-01, REQ-COST-06, REQ-COST-08. REQ-COST-12 takes over: `unreported`, total incomplete. |
| Concurrent subagents | **Nothing.** Wall clock only — plus the REQ-GAT-02 caveat about running S1 and S2 in separate sessions. |
| Skill loading | Nothing. Read the `SKILL.md` as a file. Cache economy suffers (REQ-COST-08). |
| Fetch a URL / search the web | REQ-VER-01, REQ-VER-02, REQ-VER-03, REQ-COST-05, REQ-SUP-02. The build stops at G2 rather than installing against a remembered version. |
| A lifecycle hook | Nothing. The ownership and gate-write checks become explicit orchestrator steps. |
| Image rendering in the reply | REQ-MOC-04, REQ-TST-04. Record the failure; do not redefine the requirement as "written to disk". |

## 7. Verification

An adapter is verified by running it, not by reading it (REQ-PORT-09).

**The test.** Run Wave 1 on Muse Code: `A06` first so the theme exists, then
`A08` and `A21`. Ten mockups, three viewports. Stop at G1 as the ladder says.

**What "the same" means.** Compare against a Claude Code run of the same wave:

- Same artefact paths: `mockups/m01/` … `mockups/m10/`, `mockups/README.md`,
  `mockups/theses.ts`, `build/screenshots/mockups/`.
- Same counts: `ls -d mockups/m*/ | wc -l` is 10 (REQ-MOC-02);
  `ls build/screenshots/mockups/*.png | wc -l` is 30 — ten theses at 390, 834
  and 1440 (REQ-MOC-03).
- Ten **distinct layout theses** in `mockups/theses.ts`, differentiated by
  layout and not by palette. Ten variations of one thesis is a failed wave even
  when the file count is right.
- Screenshots present, and presented in the reply (REQ-MOC-04).
- Every thesis links A06's real `tokens.css`, and no remote origin is referenced
  (REQ-MOC-06, REQ-SUP-07).

**What is not being compared.** Muse Spark 1.3 has a 1,048,576-token context
window, up to 943,718 output tokens, and Meta reports roughly 20% fewer tool
calls and 25% fewer tokens to finish a job than Muse Spark 1.2. So it may reach
these artefacts by a visibly different route: fewer reads, larger single passes,
less back-and-forth. That is not a defect and it is not a match criterion. The
artefacts are what is being compared, and the gates are what judge them.

Record the result in `build/gates/G1/` alongside the wave's verdicts — pass,
fail, and every `unconfirmed` cell the run resolved — then update the map's Muse
Code column. That is how an `unconfirmed` becomes a fact.
