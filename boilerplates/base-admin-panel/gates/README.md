# The Gate Model

A gate is a point where the build stops and something has to be proven. Nine of
them, `G0` through `G8`, in one fixed order. A gate does not pass because work
looks finished. It passes because a named reviewer wrote a structured verdict
that says it passed, with evidence.

Requirements: REQ-GAT-01 … REQ-GAT-07, plus the gate-specific IDs cited per
gate in `gate-ladder.md`.

---

## The ladder

| Gate | Name | Blocks | Human in the loop |
|------|------|--------|-------------------|
| G0 | Intake resolved | everything | yes — answers the scope questions |
| G1 | Mockup approval | all production UI code (REQ-MOC-05) | yes — **names the winner** |
| G2 | Version validation | every install (REQ-VER-02) | only on a major jump (REQ-VER-04) |
| G3 | Contract freeze | the launch of Wave 3 (REQ-CTR-02) | only to arbitrate a breaking CCR |
| G4 | Domain self-test | Wave 4 | no |
| G5 | Integration | G6 | no |
| G6 | Design & function critique | G7 | only on escalation (REQ-GAT-05) |
| G7 | Security review | G8 | only on escalation |
| G8 | Release candidate | the commit and push (REQ-REL-07) | yes — accepts the RC |

Detail for every gate — entry condition, exact checks, owner, pass criterion,
failure target — is in `gate-ladder.md`.

## What blocks what

The ladder is strictly ordered. There is no "we will come back to G2".

- **G1 is a hard stop on a human.** No production UI code exists before a human
  names a layout (REQ-MOC-05). An agent that writes `apps/<app>/components/**`
  before G1 has produced a build defect, not a head start.
- **G2 is a hard stop on external truth.** Nothing is installed against a
  remembered version (REQ-VER-02). No `pnpm add`, no `Dockerfile FROM`, no
  `Cargo.toml` line before `versions/manifest.json` carries a source URL and a
  timestamp per entry (REQ-VER-03).
- **G3 is a hard stop on collisions.** Wave 3 is 13 agents wide. It launches
  against a frozen `packages/contracts@1.0.0` or it does not launch.
- **G4 localises failure.** Each domain proves its own side of the contract
  (REQ-CTR-08) before anything is wired together, so an integration failure
  names one owner instead of thirteen.
- **G6 and G7 are the critique gates and they are independent of each other.**
  A security fix does not re-open G6 unless it changed a surface C1 or C2 voted
  on; the orchestrator decides that and records the decision.

## Who votes

Build agents run checks. Gate agents vote. These are not the same act.

- **G0–G5** are mechanical. A check passes or it fails, and the owning build
  agent runs it. There is no judgement and therefore no vote.
- **G6** is voted by **C1** (`critic-design`) and **C2** (`critic-function`).
  Both vote on **both** dimensions: design and functions. Four verdicts. All
  four must pass (REQ-GAT-01). A single `fail` on any blocking finding blocks
  the gate.
- **G7** is voted by **S1** (`security-alpha`) and **S2** (`security-beta`),
  launched in the same message with no shared context. Neither sees the other's
  findings before submitting (REQ-GAT-02). A19's supply-chain report must be
  clean in the same round (REQ-SUP-02, REQ-SUP-03).
- **G8** is assembled by A22 from the verdict files and accepted by the human.

**No gate may be self-approved (REQ-GAT-07).** The orchestrator enforces this by
never assigning a build task to `C1`, `C2`, `S1` or `S2`. Gate agents own no
product code — `contracts/ownership.md` gives them nothing, and they write only
to `build/gates/`.

## Verdicts

Every gate agent emits a structured, per-REQ-ID verdict file into
`build/gates/<gate>/<reviewer>-<dimension>-r<round>.json`, conforming to
`verdict-schema.md`. A finding names the requirement, the severity, the evidence
path, what specifically is wrong, and what would fix it.

"Looks good" is not a verdict (REQ-GAT-04). Neither is "I reviewed the auth
package and it seems fine." A verdict with zero findings and no evidence paths is
rejected by the orchestrator and the reviewer is re-dispatched.

## How loops terminate

Full rules in `loop-rules.md`. The short form:

1. A failed gate routes each finding to the **owning agent** for the path, from
   `contracts/ownership.md`. The reviewer never fixes anything.
2. The owner fixes and reports. The **same reviewer** re-reviews on round `N+1`.
3. A reviewer may not widen scope between rounds. New territory is a new round-1
   finding in the next gate cycle, not an extra condition on this one.
4. **Three failed rounds on the same defect escalates to the human**
   (REQ-GAT-05), with both positions stated. The loop does not run a fourth
   round. The human rules, the ruling is recorded in `build/gates/escalations/`,
   and the gate closes on that ruling.

## The standing lens

The Karpathy guidelines are not a gate. They are a lens applied by **both**
critics on **every** build (REQ-GAT-06): no overcomplication, surgical changes,
surfaced assumptions, verifiable success criteria. The concrete checklist, with
the specific smells to hunt in this codebase, is `karpathy-lens.md`.
