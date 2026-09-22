# The Gate Model

A gate is a point where the build stops and something has to be proven. Nine of
them, `H0` through `H8`, in one fixed order. A gate does not pass because the
work looks finished. It passes because a named reviewer wrote a structured
verdict saying it passed, with evidence.

Gates here are `H0`–`H8`. The admin-panel boilerplate uses `G0`–`G8`; the
namespaces differ so a verdict file can never be read against the wrong ladder.

Requirements: REQ-GAT-01 … REQ-GAT-08, plus the per-gate IDs cited in
`gate-ladder.md`.

---

## The ladder

| Gate | Name | Blocks | Human in the loop |
|------|------|--------|-------------------|
| H0 | Intake resolved | everything | yes — answers the scope questions |
| H1 | Design approved | **all feature work** (REQ-GAT-08) | yes — **names the winner** |
| H2 | Version validation | every `Cargo.toml` dependency line (REQ-VER-02) | only on a major jump (REQ-VER-04) |
| H3 | Contract freeze | the launch of Wave 3 (REQ-CTR-02) | only to arbitrate a breaking CCR |
| H4 | Crate self-test | H5 | no |
| H5 | Integration | H6 and H7 | no |
| H6 | Design & function critique | H8 | only on escalation (REQ-GAT-05) |
| H7 | Security review | H8 | only on escalation |
| H8 | Release candidate | the tag, the publish, the manifest | yes — accepts the RC |

Entry condition, exact checks, runner, pass criterion and failure target for
every gate are in `gate-ladder.md`.

## What blocks what

The order is strict. There is no "we will come back to H2".

- **H1 is a hard stop on a human, and it is the one that matters here.** No
  feature work exists before a human names a design direction (REQ-MOC-08,
  REQ-GAT-08). Not scaffolding with a bit of UI, not "we restyle later". A
  `crates/ui` view written before H1 is a build defect, not a head start,
  because every view downstream is styled against H1's output.
- **H2 is a hard stop on external truth.** Nothing enters a `Cargo.toml` against
  a remembered version. No dependency line, no toolchain pin, before
  `versions/manifest.json` carries a source URL and a timestamp per entry
  (REQ-VER-03).
- **H3 is a hard stop on collisions.** Wave 3 is nine agents wide. It launches
  against a frozen `contracts 1.0.0` or it does not launch (REQ-CTR-02,
  `contracts/README.md` §4).
- **H4 localises failure.** Each crate proves its own side of the contract before
  anything is wired together — interface tests run by both sides (REQ-CTR-10) — so
  an H5 failure names one owner instead of nine.
- **H5 is the honest gate.** Two targets built, a clean Windows image, a real
  signed manifest, and the upgrade path from the **previous released version**
  (REQ-TST-02). Everything before H5 can be true on a developer's machine and
  false on a user's.
- **H6 and H7 are independent of each other.** A security fix re-opens H6 only if
  it changed a surface D1 or D2 voted on; the orchestrator makes that call and
  records it.

## Who votes

Build agents run checks. Gate agents vote. These are not the same act.

- **H0–H5 are mechanical.** A check passes or it fails, and the owning build
  agent runs it. There is no judgement, so there is no vote. The exception is
  H1's winner, which is a human decision and not a check at all.
- **H6 is voted by D1 (`critic-design`) and D2 (`critic-function`).** Both vote
  on **both** dimensions, design and functions: four verdicts, all four must pass
  (REQ-GAT-01). One `fail` on a blocking finding blocks the gate.
- **H7 is voted by T1 (`security-alpha`) and T2 (`security-beta`)**, launched in
  the same message with no shared context, neither seeing the other's findings
  before submitting (REQ-GAT-02). On anything larger than a single-file fix each
  states a written review plan first — common best practice, the FFI and
  `unsafe` surface, elevation and privilege boundaries, the update trust chain,
  and IPC — then executes it (REQ-GAT-03). B11's supply-chain report must be
  clean in the same round.
- **H8 is assembled by B17** from the verdict files and accepted by the human.

**No gate is self-approved (REQ-GAT-07).** The orchestrator enforces it by never
assigning a build task to D1, D2, T1 or T2. Those IDs appear in no wave in
`spec/agents.md` and own nothing in `contracts/ownership.md`; they write only to
`build/gates/`.

## Verdicts

Every gate agent emits a structured, per-REQ verdict file:

```
build/gates/<gate>/<reviewer>-<dimension>-r<round>.json
build/gates/H6/D1-design-r1.json
build/gates/H7/T2-code-r2.json
```

Conforming to `verdict-schema.md`. A finding names the requirement, the severity,
the evidence path, what specifically is wrong, and what would fix it.

"Looks good" is not a verdict (REQ-GAT-04). Neither is "I reviewed the updater
and it seems fine". A verdict with zero findings and no evidence paths is rejected
by the orchestrator and the reviewer is re-dispatched.

## How loops terminate

Full rules in `loop-rules.md`. The short form:

1. Each finding routes to the **owning agent** for its evidence path, from
   `contracts/ownership.md`. The reviewer never fixes anything.
2. The owner fixes only what the finding names, and reports. The **same**
   reviewer re-reviews at round `N+1`.
3. A reviewer may not widen scope between rounds. New territory noticed in round
   2 is a round-1 finding in the next cycle, not an extra condition on this one.
4. **Three failed rounds on the same defect escalates to the human**
   (REQ-GAT-05) with both positions stated. There is no fourth round. The human
   rules, the ruling is recorded in `build/gates/escalations/`, and the gate
   closes on it — including a ruling of "ship as is", which is a documented
   accepted risk rather than a silent pass.

## The standing lens

The Karpathy guidelines are not a gate and not a round. They are a lens both
critics run on **every** build (REQ-GAT-06), recorded as a `karpathyLens` block
in every D1 and D2 verdict. The lens never blocks on its own — it blocks through
the requirement the smell damaged, at that requirement's severity. The checklist,
with the smells specific to this codebase, is `karpathy-lens.md`.

## The standing cost criterion

Every gate in `gate-ladder.md` carries one more pass criterion that is not
repeated per gate:

> **The cost table has been updated and presented in the orchestrator's reply
> before the verdict** (REQ-COST-02). Token counts come from each agent's
> `AgentReport` usage (REQ-COST-01); money is derived, and every money figure
> cites the unit price it used and that price's confidence (REQ-COST-03).

A gate may pass with an **incomplete** total: where a runtime did not report
usage the cell reads `unreported` and the total says so (REQ-COST-04). A gate may
not pass with a **fabricated** total, and a `0` where nothing was reported is
fabrication.

Rework is attributed to the finding that caused it (REQ-COST-05), so a loop round
has a visible price and the third round of a defect is expensive on the record as
well as on the clock.

If intake declared a cost ceiling and this gate crosses it, the orchestrator
**pauses and asks**. A pause is not a gate failure and does not start a round.
