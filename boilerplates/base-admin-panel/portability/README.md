# Portability

This boilerplate is a prompt structure: 354 requirements, a fleet of 33 agents, a
nine-gate ladder, and the contract law that lets 15 of those agents write code at
the same time without colliding. None of that is a Claude Code feature. Claude
Code is the runtime it was written and proved on, and it is the reference
implementation — not a dependency (REQ-PORT-01).

Three files:

| File | What it is |
|------|------------|
| `portability/README.md` | This file. The model, and the rules for adding a runtime. |
| `portability/capability-map.md` | What the structure needs a runtime to be able to do, and how each runtime provides it (REQ-PORT-02). |
| `portability/muse-code.md` | The adapter for Muse Code running Muse Spark 1.3 (REQ-PORT-04). |

## Runtimes today

| Runtime | Status | Where |
|---------|--------|-------|
| Claude Code | Reference implementation. The agent frontmatter and skill invocation in this repo are written in its dialect. | `.claude/agents/`, `.claude/skills/` |
| Muse Code (Muse Spark 1.3) | Adapter. Paste-ready prompt plus corrections. | `portability/muse-code.md` |
| Anything else | No adapter. Write one from the map — the map is the specification for an adapter, and it is enough to write one from. | — |

## What is portable by construction

Most of this boilerplate. Every requirement, every spec, every contract document
and every gate document is plain Markdown that names no tool and no product
(REQ-PORT-03). `spec/requirements.md` says a screenshot is captured at three
viewports in both themes; it does not say which tool captures it.
`gates/gate-ladder.md` says four verdicts must pass at G6; it does not say how a
reviewer is dispatched. That discipline was not free to maintain and this is the
payoff: on a new runtime, none of those files is touched.

Portable as written:

- `spec/**` — requirements, the fleet, the domain specs.
- `contracts/**` — ownership, contract law, the CCR process.
- `gates/**` — the ladder, the loop rules, the Karpathy lens.
- `prompts/00-master-orchestrator.md` — one exception, noted below.
- The body of every agent file: the mission, the owned requirements, the owned
  paths, the definition of done, the hand-off shape.
- The body of every `SKILL.md`.

## What needs translation

Four things, and they are small:

| Thing | Where it lives | Why it needs translating |
|-------|----------------|--------------------------|
| Agent frontmatter `tools:` | `.claude/agents/*.md` | The values are Claude Code tool names. Another runtime has its own, and may not honour a per-agent restriction at all. |
| Agent frontmatter `model:` | `.claude/agents/*.md` | `opus` and `claude-haiku-4-5` are Anthropic model ids. A26's cheap-tier economics (REQ-COST-04) depend on a per-agent override existing. |
| Skill loading | `CLAUDE.md`, the skills themselves | `/build-orchestrate` is Claude Code's invocation syntax. The skill *content* is portable; the way you ask for it is not. |
| Subagent dispatch | `prompts/00-master-orchestrator.md` | "Launch every agent in a wave in a single message with multiple tool calls" describes a Claude Code mechanism. The *intent* — N agents started before any finishes — is runtime-neutral and is what the adapter restates. |

That is the whole translation surface. Everything else in the repo reads the same
on any runtime that can do the things in the map.

## The rule for adding a runtime

Adding a runtime adds an adapter and a capability-map column. It never edits a
requirement, a spec, or an agent's mission (REQ-PORT-10).

This is not a style preference. A requirement edited to suit a runtime is a
requirement that now encodes that runtime, and the next runtime edits it again in
the other direction. Two edits in and the register is a record of tooling history
rather than of what the product must do. The same argument rules out the obvious
shortcut of forking the structure per runtime: two copies of a prompt structure
diverge, and one structure plus an adapter does not (REQ-PORT-04).

The adapter's job is narrow. It corrects what its target would otherwise misread,
and it does not restate a requirement (REQ-PORT-05). An adapter that explains
REQ-GAT-01 in its own words has created a second source of truth that will drift
from the first, and the drift will be discovered at a gate.

So an adapter contains: the vocabulary translation, the dispatch mechanics in the
target's terms, the runtime-level settings the build needs (telemetry —
REQ-PORT-07), any tier or privacy decision the runtime forces (REQ-PORT-08), and
the list of requirements that are unverifiable on it (REQ-PORT-06). It contains
no requirement text.

## How an adapter is verified

By running it, not by reading it (REQ-PORT-09).

The test is one wave. Run Wave 1 on the target — A06 for the theme, then A08 and
A21 — and compare the artefacts against a Claude Code run of the same wave:

- `mockups/m01/` … `mockups/m10/` exist. Exactly ten, no more (REQ-MOC-02).
- `mockups/theses.ts` has ten entries with distinct layout theses.
- `build/screenshots/mockups/` holds 30 PNGs — ten theses at 390, 834 and 1440
  (REQ-MOC-03).
- The screenshots were presented in the reply, not only written to disk
  (REQ-MOC-04).

Same paths, same counts, same ten distinct theses. Wave 1 is the right test
because it exercises dispatch, concurrency, file writes, a shell, a headless
browser and the human-in-the-loop stop at G1 — most of the map — and it fails
loudly and cheaply when something is wrong.

Muse Spark 1.3 has a larger context window and reportedly finishes with fewer
tool calls, so it may well reach those artefacts by a different route. The route
is not what is being compared. The artefacts are.

## Honest limits

- **Only Claude Code has a run behind it.** The Muse Code adapter is written from
  externally confirmed facts about that runtime plus this structure's own needs.
  Until someone runs Wave 1 on it, it is an untested adapter and
  `portability/muse-code.md` says so at the top.
- **Several Muse Code cells in the map are `unconfirmed`.** Meta's documentation
  hosts are blocked by this environment's egress proxy, so those cells carry the
  check to run instead of a value. Nothing was invented to fill them.
- **Per-agent tool restriction may not survive the port.** If it does not,
  REQ-GAT-07 stops being a structural guarantee and becomes an instruction plus a
  diff check. That is weaker, it is recorded, and it is not hidden.
- **The cost table may be incomplete on a runtime that does not expose usage.**
  REQ-COST-12 governs: `unreported`, and the total marked incomplete.
- **Portability is not a promise of identical output.** Two runtimes will write
  different code for the same requirement. The gates, not the runtime, decide
  whether the code is acceptable — which is the reason this structure can be
  ported at all.
