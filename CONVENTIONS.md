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

Check it, along with every other rule in this file:

```bash
./scripts/check-conventions.sh
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
├── AGENTS.md              # pointer to CLAUDE.md, for non-Claude agents
├── .claude/
│   ├── agents/            # the expert fleet, one file per agent
│   └── skills/            # skills this boilerplate needs
├── spec/                  # requirements with stable IDs, per-domain specs
├── prompts/               # the orchestrator and phase prompts
└── <domain folders>       # contracts/, gates/, compliance/, versions/, …
```

`spec/requirements.md` is mandatory and must use stable IDs. Everything else in
the boilerplate cites those IDs rather than restating requirements in prose.

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
