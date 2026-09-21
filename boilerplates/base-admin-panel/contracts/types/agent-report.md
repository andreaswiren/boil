# `agent-report` — the hand-off every agent writes

**Published by:** A02. **Produced by:** every agent — `A00`…`A26`, `C1`, `C2`,
`S1`, `S2`, no exemption. **Consumed by:** the orchestrator (routing, gate
presentation), A26 (`build/costs.md`), A22 (`build/release/record.json`).
**Requirements:** REQ-COST-01, REQ-COST-06 … REQ-COST-08, REQ-COST-12,
REQ-CTR-04, REQ-CTR-10, REQ-GAT-04, REQ-REL-08, REQ-TIM-03, REQ-TIM-04.

Every agent already writes a hand-off into `build/agents/<agent-id>/`. This
contract makes it machine-readable and attaches token usage. It is the **only**
route by which a token count reaches `build/costs.md`: A26 reads reports and
never infers a spend from a transcript, a character count or a comparable agent
(REQ-COST-01). An agent that hands off without a `usage` object has not
finished, and the orchestrator re-dispatches it for the report.

---

## 1. Where it lives

```
build/agents/<agent-id>/<task-id>-r<round>[.s<segment>].report.json
build/agents/A07/T-0041-r1.report.json
build/agents/C1/T-0088-r2.report.json      # a reviewer reports usage too
build/agents/A10/T-0052-r1.s2.report.json  # second model segment, same task
```

`report.md` remains the prose hand-off a human reads; the JSON is authoritative
and A26 reads only the JSON. One report per `(agent, task, round, segment)`. A
`segment` exists only when one task genuinely ran on two models or two effort
levels. A sub-agent's spend is reported by that sub-agent under its own id with
`parentTaskId` set, never folded into its parent's numbers.

## 2. `AgentReport`

```ts
export const AgentIdSchema  = z.string().regex(/^(A[0-2][0-9]|C[12]|S[12])$/);
export const TaskIdSchema   = z.string().regex(/^T-[0-9]{4}$/);
export const WaveSchema     = z.enum(["0", "1", "2", "3", "4", "gates", "release"]);
export const FindingRefSchema =
  z.string().regex(/^G[0-9]\/(C[12]|S[12])-(design|function|code)-r[1-3]#F-[0-9]{3}$/);

export const ArtefactSchema = z.object({          // one owner per path (REQ-CTR-04)
  path:   z.string().min(1),                      // repo-relative
  kind:   z.enum(["source", "migration", "test", "doc", "screenshot",
                  "fixture", "config", "verdict"]),
  action: z.enum(["created", "modified", "deleted"]),
}).strict();

export const EvidenceSchema = z.object({
  kind:    z.enum(["file", "test", "command", "screenshot", "sql", "log"]),
  path:    z.string().min(1),
  locator: z.string().optional(),                 // line range, test name, viewport+theme
}).strict();

export const ClaimSchema = z.object({
  req:      z.string().regex(/^REQ-[A-Z0-9]+-[0-9]{2}$/),
  status:   z.enum(["satisfied", "partial", "not-satisfied"]),
  evidence: z.array(EvidenceSchema).min(1),
  note:     z.string().optional(),                // required by §5 unless "satisfied"
}).strict();

export const AgentReportSchema = z.object({
  schemaVersion: z.literal("1.0.0"),
  agentId: AgentIdSchema,  wave: WaveSchema,  taskId: TaskIdSchema,
  parentTaskId: TaskIdSchema.nullable(),          // set by a sub-agent, else null
  round:   z.number().int().min(1).max(3),        // bounded loop (REQ-GAT-05)
  segment: z.number().int().min(1).default(1),
  startedAt: Timestamp,  endedAt: Timestamp,      // UTC, contracts/types/time.md §1
  status:    z.enum(["complete", "blocked", "refused"]),
  blockedBy: z.string().min(20).nullable(),       // what, and who owns the unblock
  artefacts: z.array(ArtefactSchema),             // [] is legal for a reviewer
  claims:    z.array(ClaimSchema),
  attribution: CostAttributionSchema,             // §4
  usage:       TokenUsageSchema,                  // §3
}).strict();
export type AgentReport = z.infer<typeof AgentReportSchema>;
```

`startedAt` and `endedAt` are RFC 3339 `Z` instants from
`packages/contracts/time` (REQ-TIM-03, REQ-TIM-04): no agent formats its own
clock, so durations across concurrent agents are comparable.

## 3. `TokenUsage` — `null` means unreported, and never zero

```ts
export const TokenUsageSchema = z.object({
  inputTokens:      z.number().int().nonnegative().nullable(),
  outputTokens:     z.number().int().nonnegative().nullable(),
  cacheReadTokens:  z.number().int().nonnegative().nullable(),
  cacheWriteTokens: z.number().int().nonnegative().nullable(),
  model:            z.string().min(1).nullable(),   // key in versions/pricing.json
  effort:           z.enum(["low", "medium", "high", "xhigh"]).nullable(),
}).strict();
export type TokenUsage = z.infer<typeof TokenUsageSchema>;
```

Every key is **mandatory and nullable**: an absent key fails validation; a
present `null` says *this runtime did not tell me* (REQ-COST-12).

`0` and `null` are different facts, and conflating them is the defect this
schema exists to prevent. `0` asserts a measurement — the runtime reported no
cache reads, so the cache saved nothing. `null` asserts ignorance. Written as
`0`, an unreported figure is silently summable: it lands in a subtotal, the
subtotal in a total, the total gets a `$` in front of it, and someone plans
against a number smaller than reality by an unknown amount. Nothing downstream
recovers the gap, because a written zero is indistinguishable from a real one. A
`null` propagates instead — the cell reads `unreported`, the subtotal carries
`incomplete`, and the reader knows which rows they cannot trust.

`model` must be a key under `providers.*.models` in `versions/pricing.json`. An
unknown model is not a reason to substitute a similar one: the counts stand and
the money cell reads `unpriced` with the model named (REQ-COST-04, REQ-COST-05).
Cache reads are their own field because they are priced differently from fresh
input and the fresh-to-cached ratio is the lever the structure controls
(REQ-COST-08); summed into `inputTokens`, that lever is invisible.

## 4. `CostAttribution` — what caused this spend (REQ-COST-07)

```ts
export const CostAttributionSchema = z.discriminatedUnion("cause", [
  z.object({ cause: z.literal("wave-build") }).strict(),
  z.object({ cause: z.literal("gate-finding-fix"), finding: FindingRefSchema }).strict(),
  z.object({ cause: z.literal("ccr"), ccr: z.string().regex(/^CCR-[0-9]{3}$/) }).strict(),
  z.object({ cause: z.literal("rework"), reason: z.string().min(40) }).strict(),
  z.object({ cause: z.literal("integration-debug"), gate: z.enum(["G4", "G5"]) }).strict(),
]);
```

| Cause | Means | Required detail |
|---|---|---|
| `wave-build` | Planned first-pass work inside the agent's own paths | — |
| `gate-finding-fix` | Raising, fixing or re-reviewing one named finding | the finding ref |
| `ccr` | Assembling or adopting a contract change | the CCR id |
| `rework` | Redone work with no finding behind it: a dropped task, a bad dispatch, an ownership violation sent back | a 40-character reason |
| `integration-debug` | Localising a G4 or G5 failure across owners | the gate |

This field makes a defect's cost one number instead of three rows in three
domains. `gate-finding-fix` is claimed by the **reviewer** that raised the
finding as well as the owner that fixed it, so a finding's total covers the
review, the fix and the re-review (`spec/cost-reporting.md` §5).

A reviewer cannot know at dispatch what it will find, so a first review round
reports `wave-build`. A26 may **re-attribute** it to the finding it raised and
records the rewrite. Re-attribution moves a row between buckets; it never
changes a count — A26 rewriting one is a build defect.

## 5. What A02 validates at assembly

Assembly runs `pnpm contracts:validate-reports` over `build/agents/**`. Each
rule is a hard failure naming the file and — where two parties are involved —
**both claimants**, exactly as a permission-string collision does
(`contracts/README.md` §3).

1. `.strict()` parse — an unknown key fails, because an agent inventing
   `estimatedTokens` is an agent inventing a number — and
   `(agentId, taskId, round, segment)` is unique across `build/agents/**`, with
   two files on one key failing by both paths.
2. Ownership collision: every `artefacts[].path` resolves to `agentId` in
   `contracts/ownership.md`. Another agent's path fails naming both (REQ-CTR-04);
   a path no row matches is a bug in the ownership map.
3. Claim collision: two agents claiming `satisfied` on one REQ ID fails naming
   both — `traceability.csv` has one owner per requirement — and every
   `claims[].req` exists in `spec/requirements.md`. IDs are never invented.
4. `status: "complete"` requires a `satisfied` claim and a `usage` object;
   `"blocked"` requires `blockedBy`; a `partial` or `not-satisfied` claim
   requires `note`.
5. `endedAt >= startedAt`, both parsing as RFC 3339 `Z`; a `gate-finding-fix`
   finding ref resolves to a verdict file under `build/gates/`; a non-null
   `usage.model` is a key in `versions/pricing.json`.

Validation never checks whether a `usage` figure is *plausible*. The only honest
sources are the runtime and `null`, and a heuristic rejecting surprising numbers
would train agents to report unsurprising ones.

The interface test both sides run (REQ-CTR-10) is
`packages/contracts/tests/agent-report.interface.test.ts`: what A26 aggregates
parses under the schema agents emit, `null` survives the round trip without
becoming `0`, and `sum(agent usage)` equals `build/costs.md` for a fixture
build. When it fails the contract is ambiguous and the fix is a clarifying CCR.

## 6. Additive vs breaking

**Additive**
- A new optional field on `AgentReport`: a duration, a sub-agent count, a
  runtime label.
- A new nullable field on `TokenUsage`, e.g. a reasoning-token count a runtime
  starts to expose. The schema requires the key only from the version that added
  it; A26 prints `unreported` for older rows.
- A new `CostAttribution` cause (old reports keep theirs; A26 gains a bucket),
  or a new `kind` in `ArtefactSchema` or `EvidenceSchema`.

**Breaking — orchestrator arbitration (REQ-CTR-03)**
- Changing what `null` means in `TokenUsage` — the worst breaking change in this
  contract, and the reason `null` is specified here rather than left to
  convention. Nothing fails, no detector fires, and every total ever recorded
  silently re-interprets: two builds compared under REQ-COST-10 are compared
  under two definitions of one column, and it looks fine. A semantic change
  needs a new field name.
- Making a nullable `TokenUsage` field non-nullable: it forces the fabrication
  REQ-COST-12 forbids. Likewise removing or renaming a field, or narrowing the
  `status`, `cause` or `effort` enums.
- Changing `FindingRefSchema` or `TaskIdSchema`: every historical attribution
  stops resolving, un-pricing every recorded defect.
