# Portability

Claude Code is the reference implementation for running this build, not a
dependency (REQ-PORT-01).

## What is portable by construction

Every requirement, spec, contract, gate document and compliance file in this
boilerplate is plain Markdown with no runtime-specific instruction
(REQ-PORT-02). The register, the ownership map, the gate ladder and the verdict
schema are readable and executable by any agent that can read files, write
files and run a shell command.

## What needs translating

| Thing | Why it is runtime-specific |
|-------|---------------------------|
| Agent frontmatter `tools:` | Names Claude Code's tool set |
| Agent frontmatter `model:` | Names Anthropic model ids — including `claude-haiku-4-5` for `B18`, which is an economic choice rather than a capability one |
| "Launch every agent in a wave in one message" | Expresses concurrency in Claude Code's terms |
| `.claude/agents/` and `.claude/skills/` discovery | A path convention |
| Skill invocation | `/name` is Claude Code syntax |

`capability-map.md` is the translation layer. It names what the structure needs
a runtime to be able to do, and where a runtime cannot do it, **which
requirements become unverifiable** (REQ-PORT-03). That last column is the
point: an unverifiable requirement is reported, never quietly dropped.

## Adding a runtime

Add an adapter and a column to the capability map. Do not edit a requirement, a
spec, or an agent's mission — two copies of a prompt structure diverge, one
structure plus an adapter does not.

Verify an adapter by **running one wave on the target** and comparing the
artefacts, not by reading it. For this boilerplate the natural test is Wave 1:
three to five mockups that each build with `cargo build -p mockup-<n>`, run, and
produce a light and a dark screenshot. The artefacts are objective, and the
build either succeeds or does not.

## Runtimes today

| Runtime | Status |
|---------|--------|
| Claude Code | Reference implementation |
| Anything else | Write an adapter from the capability map. The sibling boilerplate at `../base-admin-panel/portability/muse-code.md` is a worked example of the shape, for a different target. |

## One thing that does not port

Telemetry must be off in the **agent runtime** as well as in the product
(REQ-PORT-04, REQ-FND-10). That is a property of the tool doing the building and
it has to be checked per runtime — the structure cannot assert it on the
runtime's behalf.
