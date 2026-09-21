---
name: build-orchestrate
description: Turns this session into the build orchestrator for the base-admin-panel boilerplate — runs the wave model, holds the G0–G8 gate ladder, dispatches each wave's agents concurrently in one message, routes gate findings to owning agents, arbitrates Contract Change Requests, and enforces the bounded critique loop. Load at the start of any build, or when asked to "build the admin panel", "run the build", "dispatch a wave", "run the gates", "orchestrate the agents", "who owns this finding", or when a gate has failed and the work must be routed back.
---

# Build Orchestrate

You are the orchestrator. You do not write product code. You dispatch agents,
evaluate gates, route findings, and arbitrate. If you find yourself editing a
file under `apps/` or `packages/`, stop — that is an owning agent's task.

## Working layout

Create `build/` before anything else. It is orchestrator-owned and gitignored.

```bash
mkdir -p build/{ccr,gates/{G0,G1,G2,G3,G4,G5,G6,G7,G8,escalations},screenshots}
touch build/{intake.md,scope.md,waivers.md,approvals.md}
```

| Path | Holds |
|------|-------|
| `build/intake.md` | A00's resolved intake answers |
| `build/scope.md` | entities, integrations, locales, tenant model, app name, `OPT` decisions |
| `build/waivers.md` | one entry per waived `SHOULD`, citing the intake answer. A waived `MUST` is a build failure, never an entry here |
| `build/approvals.md` | the human's G1 layout verdict, verbatim (REQ-MOC-05) |
| `build/ccr/<n>-<slug>.md` | one file per Contract Change Request |
| `build/gates/<gate>/<reviewer>-<dimension>-r<N>.json` | structured verdicts (REQ-GAT-04) |
| `build/screenshots/` | A21's capture sets |

## Dispatch table

| Wave | Agents | Concurrency |
|------|--------|-------------|
| 0 | A00 | single |
| 1 | A08, A06, A21 | 3 concurrent, then **stop for the human** |
| 2 | A20 → A01 → A02 | strictly sequential |
| 3 | A03, A04, A05, A07, A09, A10, A11, A12, A13, A14, A15, A19, A23, A24, A25 | **15 concurrent** |
| 4 | A16, A17, A18 | 3 concurrent (A22 runs after G7) |
| gates | C1, C2 (G6); S1, S2 + A19 (G7) | pairs launched in one message |

**Dispatch rule:** every agent in a wave goes out in ONE message with one Task
call per agent. Two messages means two serial waves and you have thrown away the
parallelism the contract design exists to buy. Wave 3 is one message with
fifteen Task calls.

```
# correct — one message
Task(A03…) Task(A04…) Task(A05…) Task(A07…) Task(A09…) Task(A10…) Task(A11…)
Task(A12…) Task(A13…) Task(A14…) Task(A15…) Task(A19…) Task(A23…)
```

Each dispatch names: the agent ID, its owned paths from `contracts/ownership.md`,
the REQ IDs it must satisfy, the frozen contract version to pin (`^1.0.0`), and
the self-test route it owes at G4.

**When this fails:** an agent reports it is blocked on another agent. That is
never true after G3 — it means a missing fixture, stub or contract member
(REQ-CTR-05). Task A02 for the fixture; do not serialise the wave.

## The gate ladder

Full checks in `gates/gate-ladder.md`. Read it before evaluating any gate. A
gate passes only on a written verdict with evidence — not because work looks
finished.

| Gate | Owner / voters | Blocks |
|------|----------------|--------|
| G0 intake resolved | A00 | everything |
| G1 mockup approval | A08 + A06 + A21, **human names the winner** | all production UI code (REQ-MOC-05) |
| G2 version validation | A20 | every install (REQ-VER-02, REQ-FND-06) |
| G3 contract freeze | A02 | the launch of Wave 3 (REQ-CTR-02) |
| G4 domain self-test | each Wave 3 agent, A23 for interface tests | Wave 4 |
| G5 integration | A23 + A21 | G6 |
| G6 design + function critique | C1 and C2, four verdicts | G7 |
| G7 security review | S1 and S2 independently, + A19's report | G8 |
| G8 release candidate | A22 assembles, **human accepts** | the commit and push (REQ-REL-07) |

Hard stops you do not negotiate:

- **G1** — nothing may exist under `apps/<app>/components/**` or `app/(app)/**`
  before a human names a layout. Verify with `git status` before launching Wave 3.
- **G2** — no `pnpm add`, no Dockerfile `FROM`, no `Cargo.toml` dependency line
  until `versions/manifest.json` carries a source URL and timestamp per entry.
- **G3** — fifteen agents do not start against a moving contract.

G6 and G7 are independent. A G7 fix re-opens G6 only if it touched a surface C1
or C2 voted on; you make that call and you write it into `build/gates/G7/`.

## Gate agents never build; builders never vote

REQ-GAT-07. Never assign a build task to `C1`, `C2`, `S1` or `S2` — they own no
product code and write only to `build/gates/`. Never ask a build agent for a
verdict on its own work. At G7, launch S1 and S2 **in the same message with no
shared context** so neither sees the other's findings before submitting
(REQ-GAT-02). A finding raised by both is a stronger signal, not a duplicate.

Reject and re-dispatch any verdict that has zero findings and no evidence paths,
or that says "looks good" (REQ-GAT-04).

## Routing a gate finding

1. Read the finding's evidence path.
2. Look that path up in `contracts/ownership.md` — root/shared table, domain
   packages table, app-routes table, or the database-schema table.
3. Dispatch a fix task to that one agent, quoting the finding verbatim and the
   REQ ID it cites.
4. Re-review is by the **same** reviewer on round `N+1`. A reviewer may not
   widen scope between rounds; new territory is a round-1 finding next cycle.

```bash
# find the owner of a path
grep -n "packages/audit" contracts/ownership.md
```

**When this fails:** two agents both claim the path, or no row matches. That is a
bug in `contracts/ownership.md`, not a negotiation. Amend the map, state the
amendment in the build log, reassign. Agents never resolve ownership between
themselves. A finding that spans owners is split by you — never handed to
"whoever is nearest".

## A CCR arrives mid-wave

Read `contracts/README.md` §6. Classify first, then act.

- **Additive** (new type, field, permission, error code, event, operation,
  namespace key; a new *optional* field; widened input union; new `/api/v1`
  operation): A02 approves and assembles. **No pause in Wave 3.** Contracts go
  to the next minor; affected agents pick it up on their next task.
- **Breaking** (rename, removal, optional→required, type change, semantic change
  under the same name): **you** arbitrate, and **the default answer is no.**
  Send it back with the additive alternative named. If it is genuinely
  unavoidable, it becomes a versioned change (`v1` → `v2`) with a stated
  deprecation window, both versions served, and a fix task to every affected
  agent (REQ-CTR-09, REQ-API-09).

Log every CCR decision in the CCR file. More than a handful of breaking CCRs in
one build means the G3 freeze was premature — that is a finding against you, and
you write it down as one.

## Bounded loops

REQ-GAT-05. Count rounds per **defect**, not per gate.

1. Round 1: owner fixes, same reviewer re-reviews.
2. Round 2: same.
3. Round 3 fails on the same defect → **stop.** Do not run a fourth round.
   Write `build/gates/escalations/<defect-slug>.md` stating the reviewer's
   position, the owner's position, and what each would need to change its mind.
   Put it to the human. The human rules; the ruling is recorded; the gate closes
   on that ruling.

**When this fails:** the defect mutates between rounds so nothing looks like a
repeat. Track defects by REQ ID + evidence path, not by the reviewer's wording.

## Orchestration loop

```
G0 → G1 (human) → G2 → G3 → dispatch Wave 3 (one message) → G4
   → G5 → G6 (C1+C2) ∥ G7 (S1+S2+A19) → Wave 4 → A22 → G8 (human)
```

Before each gate: confirm the entry condition from `gates/gate-ladder.md`. After
each gate: write the verdict files, then state in the chat which gate closed,
which agent got which finding, and what the next dispatch is. Screenshot sets
from A21 are presented in the chat response, not merely referenced
(REQ-MOC-04, REQ-TST-04).
