# Verdict Schema

Every gate agent emits one JSON file per dimension per round (REQ-GAT-04):

```
build/gates/<gate>/<reviewer>-<dimension>-r<round>.json
build/gates/G6/C1-design-r1.json
build/gates/G7/S2-code-r2.json
```

A verdict is **per REQ ID**. "Looks good" is not a verdict. Neither is a prose
summary, a bullet list, or an approval with no `findings` array. The orchestrator
rejects a malformed verdict and re-dispatches the reviewer.

A finding with no `evidence` is not a finding. A finding with no `fix` is a
complaint.

## Schema

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://base-admin-panel/gates/verdict.schema.json",
  "type": "object",
  "additionalProperties": false,
  "required": ["gate", "reviewer", "dimension", "round", "reviewedAt",
               "scope", "findings", "votes", "decision"],
  "properties": {
    "gate":      { "enum": ["G6", "G7"] },
    "reviewer":  { "enum": ["C1", "C2", "S1", "S2"] },
    "dimension": { "enum": ["design", "function", "code"] },
    "round":     { "type": "integer", "minimum": 1, "maximum": 3 },
    "reviewedAt":{ "type": "string", "format": "date-time",
                   "description": "UTC, per REQ-TIM-03" },
    "commit":    { "type": "string", "pattern": "^[0-9a-f]{40}$" },
    "reviewPlan": {
      "type": "object",
      "description": "Mandatory for S1/S2 on a larger change (REQ-GAT-03). Stated before execution.",
      "required": ["statedBefore", "areas"],
      "properties": {
        "statedBefore": { "const": true },
        "areas": {
          "type": "array", "minItems": 5,
          "items": { "enum": ["best-practice", "rls", "endpoints",
                              "authentication", "leakage"] }
        },
        "method": { "type": "string" }
      }
    },
    "scope": {
      "type": "object",
      "description": "Frozen at round 1. Widening between rounds is a violation (loop-rules.md).",
      "required": ["paths", "reqIds"],
      "properties": {
        "paths":  { "type": "array", "items": { "type": "string" }, "minItems": 1 },
        "reqIds": { "type": "array", "items": { "$ref": "#/$defs/reqId" }, "minItems": 1 }
      }
    },
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["id", "req", "verdict", "severity", "evidence",
                     "defect", "fix", "owner"],
        "properties": {
          "id":       { "type": "string", "pattern": "^F-[0-9]{3}$" },
          "req":      { "$ref": "#/$defs/reqId" },
          "verdict":  { "enum": ["pass", "fail", "na"] },
          "severity": { "enum": ["critical", "high", "medium", "low", "info"],
                        "description": "critical|high block the gate. na findings carry info." },
          "naReason": { "type": "string",
                        "description": "Required when verdict is na. 'Out of scope' is not a reason." },
          "evidence": {
            "type": "array", "minItems": 1,
            "items": {
              "type": "object",
              "required": ["kind", "path"],
              "properties": {
                "kind":    { "enum": ["file", "screenshot", "test", "command",
                                      "har", "sql", "log"] },
                "path":    { "type": "string" },
                "locator": { "type": "string",
                             "description": "line range, selector, test name, viewport+theme" },
                "excerpt": { "type": "string", "maxLength": 600 }
              }
            }
          },
          "defect":   { "type": "string", "minLength": 40,
                        "description": "What is specifically wrong, measured. Not an adjective." },
          "fix":      { "type": "string", "minLength": 20,
                        "description": "What would make it pass. Direction, not a patch." },
          "owner":    { "type": "string", "pattern": "^A[0-9]{2}$",
                        "description": "Owning agent from contracts/ownership.md" },
          "carriedFrom": { "type": "integer", "minimum": 1,
                           "description": "Round this defect was first raised. Third carry escalates (REQ-GAT-05)." },
          "ownerResponse": { "enum": ["fixed", "disputed", "waiver-requested"] }
        }
      }
    },
    "votes": {
      "type": "array",
      "description": "One entry per dimension this reviewer votes on. C1 and C2 each vote design AND function (REQ-GAT-01).",
      "minItems": 1,
      "items": {
        "type": "object",
        "required": ["dimension", "vote", "criterion"],
        "properties": {
          "dimension": { "enum": ["design", "function", "code"] },
          "vote":      { "enum": ["approve", "reject"] },
          "criterion": { "type": "string",
                         "description": "The pass criterion applied, e.g. 'zero critical/high findings and no G1 layout drift'" },
          "karpathyLens": {
            "type": "object",
            "description": "Mandatory for C1 and C2 every build (REQ-GAT-06, karpathy-lens.md).",
            "required": ["overcomplication", "surgical", "assumptions", "verifiable"],
            "properties": {
              "overcomplication": { "enum": ["pass", "fail"] },
              "surgical":         { "enum": ["pass", "fail"] },
              "assumptions":      { "enum": ["pass", "fail"] },
              "verifiable":       { "enum": ["pass", "fail"] }
            }
          }
        }
      }
    },
    "decision": {
      "type": "object",
      "required": ["blocking", "rationale"],
      "properties": {
        "blocking":  { "type": "boolean",
                       "description": "true if any open finding is critical or high." },
        "rationale": { "type": "string", "minLength": 30 },
        "escalate":  { "type": "boolean",
                       "description": "true when a defect has failed three rounds (REQ-GAT-05)." },
        "disagreement": { "type": "string",
                          "description": "Required when escalate is true: both positions, stated fairly." }
      }
    },
    "notReviewed": {
      "type": "array",
      "description": "Paths in scope the reviewer could not reach, and why. Silence here is dishonest.",
      "items": { "type": "string" }
    }
  },
  "$defs": {
    "reqId": { "type": "string", "pattern": "^REQ-[A-Z0-9]{3,4}-[0-9]{2}$" }
  }
}
```

## Filled example

```json
{
  "gate": "G6",
  "reviewer": "C1",
  "dimension": "design",
  "round": 2,
  "reviewedAt": "2026-09-21T14:32:08Z",
  "commit": "4f1c9ab2d70e5583a1cc90b7e2f4d6a81b3c0e9f",
  "scope": {
    "paths": ["apps/panel/components/shell/**", "apps/panel/app/(app)/admin/**",
              "packages/datagrid/**", "build/screenshots/r2/**"],
    "reqIds": ["REQ-UI-07", "REQ-UI-09", "REQ-UI-10", "REQ-UI-11",
               "REQ-GRD-02", "REQ-GRD-03", "REQ-MOC-05"]
  },
  "findings": [
    {
      "id": "F-001",
      "req": "REQ-UI-10",
      "verdict": "fail",
      "severity": "high",
      "evidence": [
        { "kind": "screenshot", "path": "build/screenshots/r2/admin-users-390-dark.png",
          "locator": "390x844, dark" },
        { "kind": "test", "path": "tests/visual/budget.spec.ts",
          "locator": "surface budget > admin.users > mobile",
          "excerpt": "expected chrome <= 56px, received 96px" }
      ],
      "defect": "The users grid toolbar spends 96px of a 640px usable mobile viewport on chrome. The declared budget in packages/screenspace/budgets.ts is 56px. Search field, chooser trigger and density toggle are stacked instead of on one row.",
      "fix": "Collapse chooser and density into one overflow trigger on the same row as search, keeping search top-left (REQ-GRD-02) and the trigger top-right (REQ-GRD-03). Re-assert the 56px budget.",
      "owner": "A07",
      "carriedFrom": 1,
      "ownerResponse": "disputed"
    },
    {
      "id": "F-002",
      "req": "REQ-UI-07",
      "verdict": "fail",
      "severity": "critical",
      "evidence": [
        { "kind": "screenshot", "path": "build/screenshots/r2/admin-users-390-light.png",
          "locator": "390x844, light" },
        { "kind": "file", "path": "apps/panel/components/shell/bottom-nav.tsx",
          "locator": "L18-L24", "excerpt": "className=\"hidden md:flex\"" }
      ],
      "defect": "There is no bottom navigation at 390px. The sidebar is rendered as a hamburger drawer and bottom-nav.tsx is gated to md and up, so mobile is a narrowed desktop. Primary action sits at the top-right, outside thumb reach.",
      "fix": "Render bottom-nav below md with the four permitted primary destinations, move the primary action to a thumb-reachable FAB or bottom bar slot, and keep the drawer for secondary nav only.",
      "owner": "A05",
      "carriedFrom": 1,
      "ownerResponse": "fixed"
    },
    {
      "id": "F-003",
      "req": "REQ-UI-11",
      "verdict": "pass",
      "severity": "info",
      "evidence": [
        { "kind": "test", "path": "build/gates/G5/axe-report.json",
          "locator": "admin.users, both themes", "excerpt": "0 violations at AA" }
      ],
      "defect": "No contrast or focus-order violation found at AA in either theme on the reviewed surfaces.",
      "fix": "None required.",
      "owner": "A05"
    },
    {
      "req": "REQ-MOC-05",
      "id": "F-004",
      "verdict": "fail",
      "severity": "medium",
      "evidence": [
        { "kind": "file", "path": "build/approvals.md",
          "locator": "L12", "excerpt": "Winner: layout 07 — split-pane list/detail" },
        { "kind": "screenshot", "path": "build/screenshots/r2/admin-users-1440-light.png",
          "locator": "1440x900, light" }
      ],
      "defect": "The human approved layout 07, a split-pane list/detail at desktop. The built admin surface navigates to a full-page detail route and leaves the list behind. This is drift from the approved layout, not an implementation detail.",
      "fix": "Restore the split pane at 1440: list retains state on the left, detail renders in the right pane. Full-page detail stays as the below-md path.",
      "owner": "A05",
      "carriedFrom": 2
    }
  ],
  "votes": [
    { "dimension": "design", "vote": "reject",
      "criterion": "zero critical/high findings and no drift from the G1-approved layout",
      "karpathyLens": { "overcomplication": "pass", "surgical": "pass",
                        "assumptions": "fail", "verifiable": "pass" } },
    { "dimension": "function", "vote": "approve",
      "criterion": "every REQ in scope has a pass verdict backed by evidence",
      "karpathyLens": { "overcomplication": "pass", "surgical": "pass",
                        "assumptions": "pass", "verifiable": "pass" } }
  ],
  "decision": {
    "blocking": true,
    "rationale": "F-002 is critical: REQ-UI-07 is unmet, mobile is a narrowed desktop. F-001 is high and now on its second round with the owner disputing the budget rather than the measurement.",
    "escalate": false
  },
  "notReviewed": [
    "apps/panel/app/(app)/console/** — no screenshot captured at 390px in round 2; re-request from A21."
  ]
}
```

## Rules the schema does not enforce

- `scope` is set at round 1 and copied verbatim on later rounds. Widening it is a
  violation (`loop-rules.md`).
- `severity` grades the requirement's status, not the reviewer's mood. An unmet
  `MUST` is at least `high`.
- `carriedFrom` is what makes REQ-GAT-05 mechanical. Round minus `carriedFrom`
  reaching 2 — a third failed round on the same defect — sets `escalate: true`
  and `disagreement`.
- A reviewer never writes `ownerResponse` for its own findings' resolution
  without evidence from the owner's fix. It is a record, not a guess.
