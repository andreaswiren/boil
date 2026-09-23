# Validation & Compilation (REQ-VAL-01 … REQ-VAL-14)

The register says a build proves its progress. This document says with what
command, at which moment, and what the record looks like.

The failure it exists to prevent has a shape. An agent writes nine files, reads
them back, concludes they are consistent, and writes "implemented REQ-GRD-04,
tests added". The tree does not compile. Nothing discovers this until a gate two
waves later, by which time fourteen other agents have built on the assumption
that it did. Every rule below is a consequence of that one paragraph.

---

## 1. One command (REQ-VAL-01)

`pnpm validate` is defined by `A01` in Wave 0, before any domain exists, and it
is the only validation entry point in the build:

```jsonc
// package.json — the root script. A01 owns it; nobody else edits it.
{
  "scripts": {
    "validate":        "turbo run typecheck lint test build --continue",
    "validate:quick":  "turbo run typecheck lint --continue",
    "validate:full":   "pnpm validate && pnpm test:integration && pnpm test:e2e && pnpm validate:image"
  }
}
```

| Command | Who runs it | When |
|---------|-------------|------|
| `pnpm validate --filter <pkg>` | the owning agent | before every hand-off (REQ-VAL-02) |
| `pnpm validate` | the orchestrator | at every wave boundary and every gate (REQ-VAL-05) |
| `pnpm validate:full` | `A23` | `G5` and every gate after it (REQ-VAL-14) |

There is no second list. A gate that assembles its own set of checks drifts from
the one agents run, and the drift is only ever discovered in the direction that
matters: the gate passes a tree that does not build.

**Wave 0 ordering.** `pnpm validate` must exist and exit zero on the empty
scaffold before the first domain agent is dispatched. A validation command
authored in Wave 3, when there is already something to hide, is authored to pass.

## 2. The validation block (REQ-VAL-02, REQ-VAL-03)

Every `AgentReport` (`contracts/types/agent-report.md`) carries one. It is
machine-checked, not read:

```json
{
  "validation": {
    "command": "pnpm validate --filter @app/grid",
    "exitCode": 0,
    "sha": "4f2a9c1e8b7d6a5c4b3e2f1a0d9c8b7a6e5d4c3b",
    "startedAt": "2026-09-23T14:02:11Z",
    "durationMs": 184230,
    "counts": { "passed": 143, "failed": 0, "skipped": 0, "focused": 0 },
    "suppressions": { "tsExpectError": 0, "eslintDisable": 2, "allow": 0 },
    "outputTail": "…last 40 lines verbatim…",
    "redFirst": [
      { "req": "REQ-GRD-04", "test": "grid/filters.spec.ts:88", "redSha": "3c1b…", "greenSha": "4f2a…" }
    ]
  }
}
```

The orchestrator rejects the hand-off and re-dispatches when:

- the block is absent;
- `exitCode` is non-zero;
- `sha` is not the tree's current head;
- `counts.skipped` or `counts.focused` is non-zero (REQ-TST-12);
- `redFirst` is missing an entry for a REQ the agent claims (REQ-TST-09);
- `suppressions` rose against the previous gate's totals (REQ-VAL-07).

**This check is mechanical on purpose.** The orchestrator does not read the diff
and form a view about whether the work looks finished; forming that view is what
it did before this requirement existed, and it was wrong in the one direction
that costs a wave.

## 3. What may not be claimed (REQ-VAL-04)

Three sentences, none of which may appear in a report without a command behind
them in the same session:

- "It compiles." — `tsc` said so, this session, at this sha, or it is unknown.
- "The tests pass." — a runner printed counts, or it is unknown.
- "This still works." — the suite ran after the change, or it is unknown.

A result from round 2 is not evidence about round 3. The tree changed; that is
what a round is.

## 4. Phase boundaries (REQ-VAL-05)

| Gate | What must compile or build, even though the product does not exist yet |
|------|------------------------------------------------------------------------|
| `G0` | the live instance's status page builds and serves (REQ-LIV-01) |
| `G1` | `pnpm --filter mockups build` — the mockup workspace is a real Next.js build (REQ-MOC-07) |
| `G2` | the scaffold installs from the manifest and builds at the pinned versions |
| `G3` | `packages/contracts` typechecks, generates its client and its fixtures, and the regeneration diff is empty (REQ-VAL-13) |
| `G4` | the workspace typechecks and lints clean; every domain's `_selftest` is green |
| `G5` | the image builds, the stack boots, migrations apply from empty, `ready` is healthy (REQ-VAL-14) |
| `G6`–`G8` | everything above, re-run at the sha under review (REQ-VAL-08) |

## 5. Warnings and suppressions (REQ-VAL-06, REQ-VAL-07)

Warnings are errors: `--max-warnings=0` for ESLint, zero `tsc` diagnostics,
`-D warnings` for clippy. A build that permits warnings accumulates them until
nobody reads the output at all, which is the state in which a real error is
missed.

Every suppression carries its trade in the line above it:

```ts
// eslint-disable-next-line @typescript-eslint/no-explicit-any -- REQ-DAT-03:
// the normalizer's input is untrusted and genuinely unknown until parsed.
// Remove when the source publishes a schema. Owner: A10.
```

A suppression without a REQ ID and a removal condition is a lint failure of its
own. The count per class goes in every validation block, and a gate compares it
against the previous gate: **suppressions rising is the ordinary way a red tree
becomes green**, so the count is watched rather than the intent trusted.

## 6. One sha (REQ-VAL-08)

Validation records, capture sidecars (REQ-CAP-03) and gate verdicts each name a
commit sha. A gate whose evidence spans two shas is refused: what
each piece of evidence describes is real, and the tree they jointly describe
never existed.

## 7. The shared-tree stop (REQ-VAL-11)

Wave 3 runs fifteen agents concurrently. If `packages/contracts`, the workspace
config, the lockfile or the root tsconfig goes red, every one of them is building
against a base that does not compile.

The orchestrator: stops dispatching into that wave, names the failing file and
its owner from `contracts/ownership.md`, routes the fix to that owner alone, and
resumes on green. Agents already running are not killed — they are told, and
their hand-offs are validated against the repaired tree.

## 8. The record (REQ-VAL-12)

```
build/validation/
├── wave-0/A01.json
├── wave-3/A07.json          one per hand-off
├── wave-3/A07/test-output.txt   the runner's own output (REQ-TST-15)
├── G4.json                  one per gate, whole-tree
├── req-coverage.md          generated: every MUST → its test (REQ-TST-11)
└── suppressions.md          per gate, per class, with the delta
```

Kept, not summarised. A summary of validation history is a claim about
validation history, and this document exists because claims were the problem.
