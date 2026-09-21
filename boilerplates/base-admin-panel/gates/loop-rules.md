# Loop Rules

What happens after a gate fails. `README.md` gives the short form; this is the
binding version. Requirements: REQ-GAT-05, REQ-GAT-07, REQ-CTR-04.

A failed gate is a routing problem, not a repair problem: the reviewer names a
defect, somebody else fixes it, the same reviewer checks it — at most three times.

## 1. Routing: the owner, never the nearest

Every finding carries an `owner` (`verdict-schema.md`). The orchestrator resolves
it from the finding's evidence path against `contracts/ownership.md`
(`grep -n "packages/audit" contracts/ownership.md`) and dispatches to that agent.

- The owner of the **path in the evidence**, not the author of the last commit
  and not the agent already awake.
- A finding whose evidence spans two owners is **split by the orchestrator** into
  one finding per owner. It is never handed to one agent to "coordinate".
- A path no row matches, or two rows match, is a bug in `contracts/ownership.md`.
  The orchestrator amends the map, logs the amendment, then dispatches. Agents
  never negotiate ownership.
- Tenant-scoped RLS policies are A04's even on a table A04 does not own; version
  and changelog files are A22's. The map decides this, not the reviewer.

## 2. The fix is bounded by the finding

The owner fixes **only what the finding names** and reports with the evidence the
reviewer asked for.

- A fix that grows into a refactor stops being a fix. The owner reports what it
  found, the orchestrator opens a new task, and the round closes on the narrow fix.
- A finding the owner believes is wrong is answered with `ownerResponse:
  "disputed"`, a reason and evidence — not a silent no-op and not a different
  change. A dispute is a legitimate move; silence is not.
- A finding the owner believes is a requirement problem is a CCR or a waiver
  request (`ownerResponse: "waiver-requested"`), decided by the orchestrator and
  the human; a `MUST` is never waived (REQ-REL-07). The owner never edits the
  verdict file — verdicts are reviewer-owned.

## 3. Re-review: same reviewer, round N+1, same scope

- The reviewer that raised the finding re-reviews it — not the other critic, not
  the orchestrator, not the owner — and carries `carriedFrom` forward so the
  round count survives a rewording.
- **A reviewer may not widen scope between rounds.** `scope.paths` and
  `scope.reqIds` are set at round 1 and copied verbatim. New territory noticed in
  round 2 is a round-1 finding in the **next** cycle, not an extra condition on
  this one. Widening is how a two-round loop becomes permanent.
- A new defect the fix itself created is in scope, as a new finding id at round
  `N` with `carriedFrom` set to that round.
- G6 and G7 are independent: a G7 fix re-opens G6 only if it changed a surface C1
  or C2 voted on, and the orchestrator makes and records that call.

## 4. The bounded loop (REQ-GAT-05)

Rounds are counted **per defect**, tracked by REQ ID plus evidence path — not by
the reviewer's wording, which changes, and not per gate. Round 1: finding raised,
owner fixes, same reviewer re-reviews. Round 2: same. Round 3 failing on the same
defect: **stop.** There is no fourth round.

On the third failure the reviewer sets `decision.escalate: true` and writes
`decision.disagreement`, and the orchestrator writes
`build/gates/escalations/<defect-slug>.md` stating plainly:

- **what the reviewer wants**, with the measurement or reproduction,
- **what the owner did** in each of the three rounds,
- **why they disagree** — the actual point of difference — and **what each would
  need** to change its mind.

The human rules. **The orchestrator does not break the tie itself** and does not
pick the cheaper side. The ruling is recorded in the escalation file and the gate
closes on it — including a ruling of "ship as is", which becomes a documented
accepted risk, not a silent pass. Failure mode to watch: the defect mutates
between rounds so nothing looks like a repeat — which is why the count keys on
REQ ID plus evidence path.

## 5. No self-approval (REQ-GAT-07)

The agent that wrote the code never votes on it. The orchestrator enforces this
mechanically, not by trust:

- **It never assigns a build task to `C1`, `C2`, `S1` or `S2`.** Those IDs are
  absent from every wave in `spec/agents.md` and own nothing in
  `contracts/ownership.md`. A dispatch handing a gate agent a fix task is an
  orchestrator defect; the gate agent refuses it.
- Gate agents hold `Write` to reach `build/gates/` and nowhere else; a gate-agent
  diff touching product code invalidates its verdict for that round.
- A build agent is never asked for a verdict on its own work. Its `report.md` is
  a claim, and claims are what reviewers test.
- At G7, S1 and S2 launch in the same message with no shared context
  (REQ-GAT-02). A finding both raise is a stronger signal, not a duplicate.

## 6. The record

Every round is logged in `build/gates/`:

```
build/gates/G6/C1-design-r1.json      round 1 verdict
build/gates/G6/C1-design-r2.json      round 2, same scope, carriedFrom set
build/gates/escalations/grid-toolbar-budget.md
```

Nothing is overwritten. Round 2 is a new file; round 1 stays as written, wrong
predictions included. **A build whose gate history is not reconstructable has no
evidence**, and evidence is the point of the ladder. `build/` is gitignored
working state, so what survives is the commit, the changelog and the verdicts A22
copies into the release notes (REQ-REL-03, REQ-REL-08).

## 7. Worked example — three rounds to escalation

**Round 1.** C1 raises `F-001` against REQ-UI-10: the users grid toolbar spends
96px of a 640px usable mobile viewport on chrome; the declared budget in
`packages/screenspace/budgets.ts` is 56px. Evidence:
`build/screenshots/r1/admin-users-390-dark.png` and the failing assertion in
`tests/visual/budget.spec.ts` ("expected chrome <= 56px, received 96px"). Owner
resolved from `packages/datagrid/**` → **A07**. Fix direction: collapse the
chooser and the density toggle into one overflow trigger on the search row,
search staying top-left (REQ-GRD-02), trigger top-right (REQ-GRD-03). A07
shrinks the search field's height to reach 72px and reports `"fixed"`.

**Round 2.** C1 re-reviews the same scope. Chrome is 72px against a 56px budget
— still failing — and the search field is now 32px tall, under the 44px touch
minimum (REQ-UI-07), so the fix created a second finding `F-005` at round 2.
`F-001` carries `carriedFrom: 1`. A07 responds `"disputed"`: it argues 56px is
unachievable with three controls and asks for an 80px budget.

The orchestrator does not raise the budget: it is A05's file, and a budget
changed to fit an implementation is a REQ-UI-10 defect in itself. A07 is told to
implement the overflow trigger the finding named.

**Round 3.** A07 adds an overflow trigger but keeps the density toggle outside
it, reaching 68px. `F-001` fails a third time (`carriedFrom: 1`, round 3). C1
sets `escalate: true` and writes the disagreement; the orchestrator writes
`build/gates/escalations/grid-toolbar-budget.md`:

- **Reviewer (C1) wants:** chrome ≤ 56px at 390px on `admin.users`, measured by
  the budget suite, with search top-left and one overflow trigger top-right.
- **Owner (A07) did:** round 1 shrank control heights (96→72px); round 2 disputed
  the budget; round 3 added the trigger but kept density outside it (→68px).
- **Why they disagree:** A07 holds that three grid controls cannot fit 56px
  without dropping the density toggle below the touch minimum. C1 holds that the
  density toggle belongs inside the overflow trigger, which makes 56px reachable.
- **Each would change its mind if:** C1 — a measurement showing 56px is
  unreachable with all controls at 44px and search top-left. A07 — a layout where
  density lives in the overflow menu without a second tap to a primary control.

No fourth round runs. The human rules — raise the budget for this surface with
the reason recorded, or confirm the overflow layout. The ruling goes in the
escalation file, the gate closes on it, and A22 carries it into the release
record.
