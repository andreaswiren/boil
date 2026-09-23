# Conventions

Rules every boilerplate in this repo follows. They exist so that a boilerplate
can be cloned, copied or handed to an agent on its own and still work.

## 1. Self-containment

A boilerplate folder must work when it is the only thing you have.

- **No path may reach outside the boilerplate folder.** No `../`, no
  `../../skills/...`, no symlink out. If a boilerplate needs a skill, the skill
  lives in the boilerplate's own `.claude/skills/`.
- **No boilerplate depends on another boilerplate.** Shared ideas get copied,
  not linked. For prompt assets this is the right trade: a copy that diverges is
  better than a link that breaks a sparse checkout.
- **The folder explains itself.** `README.md` for a human, `CLAUDE.md` for an
  agent, and enough structure that an agent pointed at the folder with no other
  context knows what to do first.
- **No document may tell anyone to run a file the folder does not ship.** This
  is the rule that is easiest to break by accident: six agent briefs once ended
  with "run `./scripts/check-conventions.sh` from the repository root", which is
  a file that is not in the folder those briefs ship in. Each boilerplate
  therefore carries its own `scripts/check-boilerplate.sh` and, where it has a
  matrix, its own `scripts/gen-traceability.py`.

Check it, along with every other rule in this file — from inside one
boilerplate, or across all of them from the root:

```bash
cd boilerplates/<name> && ./scripts/check-boilerplate.sh
./scripts/check-conventions.sh    # from the repository root
```

That script is the enforcement. It verifies self-containment, the required
structure, that every cited requirement ID is defined, that every requirement
carries a status, that every agent named in an ownership map exists, that
internal document references resolve, and that every version-manifest entry
carries its source and check timestamp. Run it before every commit.

Paths under `build/` are per-build working state and are expected to be absent —
which is why a reference to one must always carry its `build/` prefix.

## 2. Required structure

```
boilerplates/<name>/
├── README.md              # what it produces, how to run it — for a human
├── CLAUDE.md              # operating instructions — for an agent
├── AGENTS.md              # byte-identical to CLAUDE.md (§4), for runtimes that read it
├── .claude/
│   ├── agents/            # the expert fleet, one file per agent
│   └── skills/            # skills this boilerplate needs
├── scripts/
│   ├── check-boilerplate.sh   # the conformance check, runnable from here alone
│   └── gen-traceability.py    # where the boilerplate has a matrix
├── spec/                  # requirements with stable IDs, per-domain specs
├── prompts/               # the orchestrator and phase prompts
└── <domain folders>       # contracts/, gates/, compliance/, versions/, …
```

`spec/requirements.md` is mandatory and must use stable IDs. Everything else in
the boilerplate cites those IDs rather than restating requirements in prose.

Where a boilerplate keeps a traceability matrix, it is **generated** from the
register by `scripts/gen-traceability.py` and never hand-edited — a matrix that
can drift from the register is worse than no matrix, because it is trusted.
The check regenerates it and fails if the committed copy differs.

### Every boilerplate proves its own progress

Three things are mandatory because a build that skips them reports success it has
not earned, and the report is indistinguishable from the true one:

1. **One validation command**, defined before the first agent is dispatched and
   green on the empty scaffold — typecheck or compile, lint at zero warnings,
   tests, and a build. Agents run it before every hand-off, gates run it at every
   gate, the human runs the same thing. A gate that assembles its own set of
   checks drifts from what developers run, and the drift only ever shows up in
   the direction where the gate passes a tree that does not build.

2. **A validation block on every hand-off** — the command, the exit code, the
   commit sha, the runner's own counts, the suppression counts and the output
   tail — checked mechanically. An orchestrator that reads the diff and forms a
   view about whether the work looks finished is the failure this replaces.
   Nothing may be reported as compiling, passing or still working without a
   command that produced that result in the same session, at the same sha.

3. **Tests and captures as evidence, not deliverables.** A test is written and
   seen to fail before the behaviour exists, and the failing sha is recorded; no
   test is skipped or disabled to reach green; every `MUST` maps to a test or to
   a recorded reason it cannot be tested. Screenshots run as a continuous feed
   from a single live instance — every hand-off that touches a surface, every
   phase boundary, every gate — delivered both in the reply and to a durable
   folder, each image with a sidecar naming the sha it was taken at.

The boilerplate names its own commands and its own IDs. What is not optional is
that a phase cannot end on a tree nobody compiled, and a requirement cannot be
called done on a test nobody watched fail.

## 3. Stable requirement IDs

Format: `REQ-<DOMAIN>-<nn>`, e.g. `REQ-GRD-08`.

- An ID is permanent. A requirement that changes meaning gets a new ID; the old
  one is marked superseded.
- Never renumber. The IDs are referenced from agent prompts, gate verdicts,
  changelog entries and commit messages.
- Every requirement carries a status: `MUST`, `SHOULD` or `OPT`.

## 4. No versions from memory

No boilerplate hardcodes a dependency version in prose. Versions live in a
manifest that is validated against the authoritative registry at build time,
with the source URL and the check timestamp recorded.

A version written from memory is wrong by the time it is committed.

A version *copied correctly* into a spec and then left there is wrong a month
later, which is the harder failure: the manifest gets re-validated and the spec
does not, and an agent builds against the spec it was handed.
`scripts/check-conventions.sh` therefore fails on any `` `crate` X.Y.Z `` in any
document that disagrees with the manifest entry for that crate.

## 5. Ownership before parallelism

A boilerplate that dispatches more than one agent at a time must declare, in a
file, which agent owns which path. Two agents writing the same file is a defect
in the ownership map, not a merge to resolve.

## 6. Nothing self-approves

A boilerplate that generates code must define at least one reviewer that did not
write the code. The agent that produced an artefact never votes on it.

## 7. Style

Boilerplate documents are read by agents, and agents follow specifics and ignore
adjectives.

- Decide. "Consider using X" is a failed spec. Write "we use X, because Y".
- Prefer a command, a path, a schema or a number over an adjective.
- No filler, no marketing tone, no emoji.
- State failure modes bluntly: what breaks, and what to do instead.
- Cite the requirement ID for every requirement-derived claim.

## 8. Repo-level versioning

The repo carries its own semver in `VERSION`, bumped every time work lands, with
`CHANGELOG.md` updated in Keep a Changelog form. A boilerplate may additionally
version itself internally; the repo version covers the collection.
