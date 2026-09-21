# Token Accounting & Cost Reporting

What the build spent, on what, and why. Owned by **A26** (`cost-accountant`):
`versions/pricing.json`, `versions/pricing.md` and `build/costs.md`. A26 owns no
product code, no table and no route. It consumes `agent-report`
(`contracts/types/agent-report.md`) from every agent plus the verdicts under
`build/gates/`, and publishes one file the orchestrator reads aloud at every
gate. The agents measure, A26 counts, the orchestrator presents — and no step in
that chain may estimate the step before it (REQ-COST-05).

## Requirements covered

REQ-COST-01 … REQ-COST-12, REQ-REL-08, REQ-VER-02, REQ-VER-03, REQ-GAT-05,
REQ-CTR-04, REQ-PORT-08, REQ-TIM-03, REQ-TIM-04.

## 1. Two columns, never one (REQ-COST-04)

There are two kinds of number in this file and they are never added together,
never averaged together and never shown in the same column.

| | Measured | Derived |
|---|---|---|
| What | Token counts | Money |
| Source | The runtime, via `agent-report.usage` | tokens × unit price from `versions/pricing.json` |
| If missing | `unreported` (REQ-COST-12) | `unpriced`, with the model named |
| Can be wrong by | Nothing — it is a measurement or it is absent | The accuracy of the price |

Every money cell carries the unit price that produced it, in its row or in its
column header. Without a visible price a figure is not reproducible and a reader
cannot tell a stale price from a current one.

Each price in `pricing.json` carries a `confidence`: `verified` means this build
fetched the provider's own page and got HTTP 200; `secondary` means a cache, a
snippet or an aggregator. **A table built on `secondary` prices is labelled an
estimate in its own heading.**

Right now every price in this repository is `secondary`: `docs.claude.com`
returns 302 and neither `www.anthropic.com/pricing` nor
`dev.meta.ai/docs/pricing-rate-limits` is reachable through this environment's
egress proxy (`versions/pricing.json` → `egressNote`, 2026-09-21). Every money
column this build produces is therefore an estimate, says so in its heading, and
stays one until a fetch succeeds. Nobody upgrades a `confidence` because a
number looks familiar (`versions/pricing.md`, "Confidence levels"). Token counts are unaffected —
they are measured, exact, and useful when the prices are not.

## 2. `build/costs.md` — the table itself (REQ-COST-02, REQ-COST-06)

This is the shape; copy it. Waves are sections, agents are rows, each wave
closes with a subtotal, gate rounds get their own section because a round is a
separate cost (REQ-COST-06), and the file ends with one total.

```markdown
# Build cost — <app-name>

Prices: `versions/pricing.json` @ 2026-09-21T22:18:53Z, **confidence `secondary`
for every entry** → every money column below is an **estimate** (REQ-COST-04).
Rates are USD per 1M tokens. Cache-read and cache-write money is `unpriced`:
`claude-opus-5` has no cache rate recorded, and a ratio is not assumed
(REQ-COST-08, REQ-COST-12). Ceiling: $150.00 (intake). Spent: $110.29 (74%).

## Wave 3 — parallel domain build

| Agent | Task   | R | Model         | Rate in/out | Fresh in | Cache rd | Cache wr |   Out |  $ in | $ out | $ cache | Row $ |
|-------|--------|---|---------------|-------------|---------:|---------:|---------:|------:|------:|------:|---------|------:|
| A03   | T-0031 | 1 | claude-opus-5 | 5.00/25.00  |     180k |     320k |      60k |  210k |  0.90 |  5.25 | unpriced|  6.15 |
| A04   | T-0032 | 1 | claude-opus-5 | 5.00/25.00  |     165k |     300k |      45k |  190k |  0.83 |  4.75 | unpriced|  5.58 |
| A05   | T-0033 | 1 | claude-opus-5 | 5.00/25.00  |     150k |     280k |      40k |  175k |  0.75 |  4.38 | unpriced|  5.13 |
| A07   | T-0034 | 1 | claude-opus-5 | 5.00/25.00  |     190k |     340k |      50k |  230k |  0.95 |  5.75 | unpriced|  6.70 |
| A09   | T-0035 | 1 | claude-opus-5 | 5.00/25.00  |      95k |     200k |      25k |  110k |  0.47 |  2.75 | unpriced|  3.22 |
| A10   | T-0036 | 1 | claude-opus-5 | 5.00/25.00  |     140k |     250k |      35k |  160k |  0.70 |  4.00 | unpriced|  4.70 |
| A11   | T-0037 | 1 | claude-opus-5 | 5.00/25.00  |     170k |     310k |      45k |  200k |  0.85 |  5.00 | unpriced|  5.85 |
| A12   | T-0038 | 1 | claude-opus-5 | 5.00/25.00  |     110k |     220k |      30k |  130k |  0.55 |  3.25 | unpriced|  3.80 |
| A13   | T-0039 | 1 | claude-opus-5 | 5.00/25.00  |     175k |     330k |      50k |  205k |  0.88 |  5.12 | unpriced|  6.00 |
| A14   | T-0040 | 1 | claude-opus-5 | 5.00/25.00  |unreported|unreported|unreported|unrep. |unrep. |unrep. | unrep.  |unrep. |
| A19   | T-0041 | 1 | claude-opus-5 | 5.00/25.00  |      85k |     150k |      20k |   95k |  0.43 |  2.38 | unpriced|  2.81 |
| A23   | T-0042 | 1 | claude-opus-5 | 5.00/25.00  |     120k |     230k |      35k |  140k |  0.60 |  3.50 | unpriced|  4.10 |
| A24   | T-0043 | 1 | claude-opus-5 | 5.00/25.00  |     105k |     195k |      28k |  125k |  0.53 |  3.12 | unpriced|  3.65 |
| A25   | T-0044 | 1 | claude-opus-5 | 5.00/25.00  |     115k |     205k |      30k |  135k |  0.58 |  3.38 | unpriced|  3.96 |
| **Wave 3 subtotal** — 13 of 14 reported, **incomplete** ||||| **1 800k** | **3 330k** | **493k** | **2 105k** | **9.02** | **52.63** | unpriced | **61.65** |

A14 ran on a runtime that returned no usage block: the row is `unreported`, the
subtotal is incomplete, and neither is zero (REQ-COST-12).

## Gate rounds (REQ-COST-06, REQ-COST-07)

| Gate | R | Agent | Cause                     | Fresh in | Cache rd |  Out | $ in | $ out | Row $ |
|------|---|-------|---------------------------|---------:|---------:|-----:|-----:|------:|------:|
| G6   | 1 | C1    | gate-finding-fix F-011 ¹  |     120k |     260k |  55k | 0.60 |  1.38 |  1.98 |
| G6   | 1 | C1    | wave-build (function)     |     110k |     250k |  50k | 0.55 |  1.25 |  1.80 |
| G6   | 1 | C2    | wave-build (design)       |     115k |     255k |  48k | 0.58 |  1.20 |  1.78 |
| G6   | 1 | C2    | wave-build (function)     |     125k |     265k |  60k | 0.62 |  1.50 |  2.12 |
| G6   | 2 | A07   | gate-finding-fix F-011    |      60k |     140k |  45k | 0.30 |  1.12 |  1.42 |
| G6   | 2 | C1    | gate-finding-fix F-011    |      70k |     180k |  25k | 0.35 |  0.62 |  0.97 |
| G7   | 1 | S1    | wave-build (code)         |     140k |     300k |  80k | 0.70 |  2.00 |  2.70 |
| G7   | 1 | S2    | wave-build (code)         |     135k |     290k |  78k | 0.68 |  1.95 |  2.63 |
| **Gates subtotal** |||| **875k** | **1 940k** | **441k** | **4.38** | **11.02** | **15.40** |

¹ Re-attributed by A26 from `wave-build`: this review round raised F-011.
Tokens unchanged (`contracts/types/agent-report.md` §4).

## Cost of defects (REQ-COST-07)

| Finding | What | Rounds attributed | $ |
|---------|------|-------------------|---:|
| G6/C1-design-r1#F-011 | Datagrid server-mode sort dropped the secondary key (REQ-GRD-04) | C1 r1 review, A07 r2 fix, C1 r2 re-review | **4.37** |

## Total

| | Fresh in | Cache rd | Cache wr | Out | $ in | $ out | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| Waves 0–4 + gates + release + A26 | 3 690k | 6 865k | 1 037k | 3 713k | 18.27 | 92.02 | **110.29** |

**Estimate, incomplete.** Every price is `secondary`; cache money is `unpriced`;
one agent row is `unreported`. Cached input is 65% of all input tokens.
```

Waves 0, 1, 2 and 4 and the release row use the same two shapes. A26's own
rows are in the table too — nine dispatches, $0.25 on `claude-haiku-4-5` —
because an accountant that exempts itself reports on a build that did not
happen.

## 3. Presentation at each gate (REQ-COST-03)

The orchestrator prints a short table **in its reply** at every gate — not a
path to `build/costs.md`, not "costs are tracked in the build directory". A cost
read at G8 is a cost nobody could act on; the point of presenting at G1 is that
G3 has not happened yet and the build can still change. What differs by gate is
the width, not the presence:

| Gate | What the reply shows |
|------|----------------------|
| G0–G2 | Spend to date, the ceiling and the share used. Three lines. |
| G3 | Spend to date plus the **Wave 3 estimate**, because this is the last moment before the expensive part (REQ-COST-11). |
| G4, G5 | Wave 3 actual against the estimate, with the variance, and any `integration-debug` attribution. |
| G6, G7 | Per-round gate costs and the cost-of-defects table. This is where rework becomes visible. |
| G8 | The full table: per wave, per gate, the total, and what is `unreported` or `unpriced`. Copied into the release record (REQ-COST-10, REQ-REL-08). |

Each carries the estimate label while prices are `secondary` and states what is
missing. A reply showing a clean total when a row reads `unreported` is a lie by
rounding.

## 4. Estimate, then actual (REQ-COST-11)

Before a wave, A26 publishes an estimate. After it, the actual, with variance.

The estimate is derived in this order, and it always states which rule it used:

1. **Prior builds.** Median per-agent spend for the same wave from previous
   builds' `build/costs.md`, scaled by agent count. Preferred, and the reason
   cost history is kept.
2. **This build's earlier waves.** Wave 3 from Wave 2's measured per-agent
   average, scaled by agent count and a stated wave factor.
3. **A stated assumption.** No history: A26 prints the assumption — "180k fresh
   in, 200k out per Wave 3 agent, 14 agents, `claude-opus-5` at 5.00/25.00" —
   and labels the estimate with it. An assumption on the page can be argued
   with; an unstated one cannot.

```markdown
| Wave | Estimate | Actual  | Variance | Basis                                   |
|------|---------:|--------:|---------:|-----------------------------------------|
| 2    |    12.00 |   10.13 |     -16% | rule 3, stated assumption               |
| 3    |    55.00 |   61.65 |     +12% | rule 2, Wave 2 per-agent average × 14   |
```

A variance over ±25% on two consecutive waves is a finding **about the
estimator**, filed by A26 against its own basis with the rule that failed and
the correction. Never against the wave: the wave cost what it cost, and the
measurement is not the thing that was wrong.

## 5. Rework attribution (REQ-COST-07)

This is the most useful number the table produces: it prices defects rather
than work.

C1 reviews the datagrid at G6 round 1 and raises **F-011**: server-mode sort
drops the secondary sort key (REQ-GRD-04). It routes to A07, which owns
`packages/datagrid/**`; A07 fixes it in round 2 and C1 re-reviews and passes.
Three dispatches, three rows, one cause:

| Row | Cause | $ |
|---|---|---:|
| C1 design review, r1 | `gate-finding-fix` F-011 (re-attributed) | 1.98 |
| A07 fix, r2 | `gate-finding-fix` F-011 | 1.42 |
| C1 design re-review, r2 | `gate-finding-fix` F-011 | 0.97 |
| | **F-011 total** | **4.37** |

Without attribution those tokens land in three different places: two in "gate
overhead" and one inside A07's subtotal, where the domain that had to fix the
defect appears to have been expensive. With attribution, one defect costs $4.37
and that is the number you compare against tightening the contract at G3.

Rules that keep it honest:

- The reviewer that raised the finding attributes to it, as well as the owner
  that fixed it. A review that finds nothing is `wave-build`.
- A26 may re-attribute a row's cause and records that it did; it never changes
  a count (`contracts/types/agent-report.md` §4).
- A finding escalated after three rounds (REQ-GAT-05) keeps all three rounds
  under its id. That total is the argument for escalating earlier.
- A round with no finding behind it is `rework` with a written reason, not
  `wave-build`. A dropped task is a cost, and hiding it in the wave subtotal
  makes the wave look worse than it was.

## 6. Cache reads (REQ-COST-08)

Cache reads get their own column because they are priced differently — where
the rate is published at all — and because the fresh-to-cached ratio is the one
cost lever this structure actually controls.

The structure's shape is what caches well. `packages/contracts@1.0.0` is frozen
at G3 and then read by fifteen agents that do not talk to each other
(REQ-CTR-01, REQ-CTR-02). Identical prefix, fifteen readers, no edits: that is
the best case a prompt cache has. The same is true of `spec/requirements.md` and
`contracts/ownership.md`. A build that re-derives the contract per agent would
pay fresh-input rates fifteen times for the same bytes.

So the ratio is a design metric, not an accounting detail. The worked example
above runs at 65% cached input. A wave whose cached share drops is a wave whose
agents are reading different things — usually because the contract moved under
them, which is also a G3 finding against the orchestrator.

Where a model has no `cacheRead` rate in `pricing.json` — `claude-opus-5` today
— the count is still reported and the money cell reads `unpriced`. No ratio is
assumed: a plausible multiplier is still a fabricated number.

## 7. The ceiling (REQ-COST-09)

A ceiling is declared at intake, in dollars, and recorded in `build/intake.md`.
A00 asks for it; if the human says nothing there is no ceiling, and the table
says "no ceiling declared" rather than inventing one.

When the running total plus the next wave's estimate would cross it, the
orchestrator **pauses and asks**: spend to date, the ceiling, the estimate that
crosses it, and what deferring each item would save. It does not abort — a build
abandoned at 80% has spent 80% and produced nothing — and it does not continue
quietly, because an overrun found afterwards is the failure the ceiling was
declared to prevent.

The human answers — raise the ceiling, narrow the scope, or stop here — and the
answer is recorded in `build/approvals.md`. A ceiling crossed without a recorded
answer is a build defect.

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Source of token counts | `agent-report.usage`, nothing else | A26 that reads transcripts is an A26 that estimates | No |
| Unreported usage | `unreported`, total marked incomplete | A fabricated number gets trusted (REQ-COST-12) | No |
| `0` vs `null` | Different facts; `0` only when the runtime said 0 | A zero silently deflates a total | No |
| Money with a `secondary` price | Shown, labelled an estimate, price beside it | A hidden estimate is worse than a labelled one | No |
| Money with no price at all | `unpriced`, model named, tokens still shown | A ratio guessed is a number invented | No |
| Cache reads | Own column, never merged into fresh input | It is the lever the structure controls | No |
| Gate presentation | Short table in the reply | A file reference is not a presentation (REQ-COST-03) | No |
| Estimate basis | Prior builds → this build's waves → stated assumption | Named, in that order, always printed | No |
| Estimator variance | ±25% twice consecutively is a finding against the estimate | The wave is not the thing that was wrong | No |
| Ceiling default | None declared | An invented ceiling pauses a build for no reason | Yes |
| Ceiling crossed | Pause and ask, with the saving from each option | Aborting wastes what was spent | No |
| A26's own spend | A row in the table like everyone else | An exempt accountant reports a build that did not happen | No |

## How this is verified

- `pnpm contracts:validate-reports` — every file under `build/agents/**` parses
  as `AgentReport`, `.strict()`; no `(agent, task, round, segment)` collision;
  every `usage` key present; every non-null `usage.model` resolves in
  `versions/pricing.json` (REQ-COST-01).
- Null fidelity: every `unreported` cell has a null in a report and every null
  has a cell. A cell reading `0` whose report says `null` fails (REQ-COST-12).
- Reconciliation: the totals in `build/costs.md` equal the `jq` sum over
  `build/agents/**/*.report.json` field by field. A mismatch is A26's defect,
  not a rounding tolerance (REQ-COST-02).
- Attribution closure: every `gate-finding-fix` reference resolves to a finding
  in `build/gates/**`, and every blocking finding has at least one attributed
  row. A finding that cost nothing means a round went unreported (REQ-COST-07).
- Price provenance: every money column states a rate; every rate is in
  `versions/pricing.json` with a `source`, a `checkedAt` and a `confidence`. A
  rate not in the file fails (REQ-COST-04, REQ-COST-05), and `checkedAt` within
  `policy.staleAfterDays` (14) is what keeps the estimate label off that
  ground.
- Gate presentation: each gate's build-log entry records that the table was
  presented in the reply, with the figure shown (REQ-COST-03).
- Release: `build/release/record.json` carries the build total, its completeness
  flag and the price confidence it rests on (REQ-COST-10, REQ-REL-08).

## What this does not do

- **It does not price the operator's own time.** Hours are not in
  `agent-report`, and an invented hourly rate would sit beside measured tokens
  and borrow their credibility.
- **It does not price the generated app's runtime costs.** Hosting, Postgres,
  egress and certificates are the deployment's economics, not the build's, and
  they do not belong in totals compared build to build.
- **It never presents a token count it did not receive.** Not interpolated from
  a similar agent, not inferred from output length, not carried over from a
  previous build. `unreported` is a complete answer.

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| Cost ceiling for the build | None declared; the table says so |
| What happens at the ceiling | Pause and ask (never abort, never continue) |
| Estimate basis when no history exists | Rule 3, the stated assumption, printed in full |
| Cheaper training-on-traffic tier (REQ-PORT-08) | Not used; using it is a recorded decision |
| Cost table at every gate | Yes — not overridable (REQ-COST-03) |
