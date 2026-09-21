# Running agents in parallel without breaking each other

The method behind `base-admin-panel`, written down separately because it is
transferable to any boilerplate in this repo.

The problem: you want fifteen expert agents building one application at once.
The naive version fails in four specific ways, and each one has a specific fix.

---

## Failure 1 — They edit the same file

Two agents both need a navigation entry. Both open `sidebar-items.ts`. The second
write silently discards the first, or you spend the afternoon merging.

**Fix: single ownership, declared in a file.**

Every path, route group, database table and migration namespace maps to exactly
one agent. The map is a document (`contracts/ownership.md`), not a convention.
An agent writing outside its owned paths has produced a build defect — the
orchestrator rejects the task result rather than merging it.

**Fix: registry, never a shared list.**

The deeper problem is that a shared array *exists*. Remove it. An agent adds its
navigation entry, settings panel, command-palette action, help topic or
notification category inside its **own** package, and the shell reads the
registry. There is no `sidebar-items.ts` to contend for.

This is the single highest-leverage change. Most "agents can't work in parallel"
problems are really "the architecture has shared mutable lists in it".

Migrations get the same treatment: `db/migrations/<agent-id>/<timestamp>__<slug>.sql`.
Namespaced by owner, so two agents cannot produce a conflicting ordinal.

---

## Failure 2 — They wait for each other

The grid agent needs the API. The API agent needs the auth model. The auth agent
needs the tenancy model. Fifteen agents, and thirteen of them are idle.

**Fix: nobody consumes another agent's code. They consume a contract.**

One shared package is the only cross-domain coupling. No domain package imports
another domain package — enforced by an import-boundary lint, not by good
intentions. An agent that "just needs one type from another package" has found a
missing contract member, not an exception.

**Fix: generated clients and schema-derived fixtures, available before any
implementation exists.**

At the freeze, a typed client is generated from the API document and fixtures are
generated from the schemas. The grid agent builds against realistic paginated
tenant-scoped rows on day one, while the API agent has not started. Swapping a
stub for the real implementation is a configuration flag, not a code change in
the consumer.

Fixtures must be *generated from the schema*, never hand-written. A hand-written
fixture drifts from the contract, and then two agents are building against
different truths while both believe they are compliant.

---

## Failure 3 — A rename invalidates twelve agents at once

Someone renames `Session.user` to `Session.actor` on hour three. Twelve agents
are mid-task against the old name. Every one of them is now wrong, and none of
them knows it.

**Fix: freeze the contract, then allow additive change only.**

After the freeze:

- **Allowed** — add a type, a field (optional), a permission, an error code, an
  event, an operation, a namespace key; widen an input union; narrow an output
  union.
- **Not allowed** — rename anything, remove anything, make an optional field
  required, change a field's type.
- **Worst of all, and the one no tool catches** — change the *meaning* of a value
  while keeping its name. A semantic change requires a new name.

A breaking change needs arbitration, and the default answer is no: go find the
additive form. When it is genuinely unavoidable it becomes a versioned change
(`v1` → `v2`) with both served through a stated deprecation window.

**Fix: a breaking-change detector on every commit.** It compares the current
contract surface against the frozen baseline and fails on any removal or
narrowing. Advisory detection is not detection.

**The freeze gate is the whole game.** Freeze too early and you pay in breaking
change requests, each one stalling every consumer of the changed member. Freeze
too late and the agents sit idle. The measurable signal is *how many breaking
change requests arrive during the parallel wave* — a high count is a finding
against the orchestrator, not against the agents.

---

## Failure 4 — Everything is "done" and nothing works

Fifteen agents report success. The app does not boot. The orchestrator now reads
fifteen agents' code to find out why, and becomes the bottleneck the whole design
existed to remove.

**Fix: every domain proves its own side of the contract.**

Each domain publishes a self-test route asserting what it promised: its schemas
parse, its permissions resolve, its tables carry the required columns, its
isolation policy is enabled, its config is present. When integration fails, the
self-tests name the owner. The orchestrator routes a task; it does not debug.

**Fix: interface tests belong to the contract, not to either side.**

A test asserting "the grid sends what the API accepts" lives in the contract
package and is run by *both* agents. Neither can quietly satisfy its own
interpretation. When such a test fails the contract is ambiguous, and the fix is
a clarifying change to the contract — not a patch on whichever side someone
happened to look at first.

---

## What the orchestrator actually does

Not code review. Not integration debugging. Four things:

1. **Dispatch** a wave — every agent in it launched in one message, so they are
   genuinely concurrent rather than accidentally serialised.
2. **Arbitrate** contract change requests. Additive: approve, assemble, no pause.
   Breaking: default no.
3. **Reject** ownership violations and reassign.
4. **Route** gate findings to the owning agent.

If the orchestrator is reading domain code, the design has failed somewhere
upstream.

---

## Gates, and why they must actually block

An agent asked "is this good?" says yes. That is not dishonesty, it is the
absence of an adversary.

- **Nothing self-approves.** The agent that wrote the artefact never votes on it.
  Enforced structurally: build tasks are never assigned to a reviewer ID.
- **Independent reviewers do not see each other's findings** before submitting.
  Two reviewers sharing context produce one review with extra steps. A finding
  both raise independently is a *stronger* signal, not a duplicate to suppress.
- **Verdicts are structured and per-requirement.** "Looks good" is not a verdict.
  A finding without evidence is not a finding.
- **Loops are bounded.** Findings route to the owner; the owner fixes only what
  the finding names; re-review is the same reviewer at round N+1 and may not
  widen scope. Three failed rounds on one defect escalates to a human with the
  disagreement stated. The orchestrator does not break the tie.

The bound matters more than it looks. Without it, a reviewer and an owner who
genuinely disagree will loop until the budget runs out, and the build ends with
neither a decision nor a product.

---

## What this buys

The parallel wave is the only wide part of the build; everything else is
sequential by necessity (you cannot freeze a contract before the declarations
exist) or narrow by nature (documentation, release). So the speed-up is bounded
by how much of the work lives in the wide wave, and the job of the design is to
push work into it and keep it there.

The things that pull work *out* of the wide wave, in order of how much damage
they do:

1. A shared mutable list.
2. A consumer that waits for a producer instead of a fixture.
3. A rename after the freeze.
4. An orchestrator that reviews code.

Every rule above exists to prevent one of those four.
