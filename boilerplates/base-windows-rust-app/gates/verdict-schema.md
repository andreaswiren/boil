# Verdict Schema

Every gate agent emits one JSON file per dimension per round (REQ-GAT-04):

```
build/gates/<gate>/<reviewer>-<dimension>-r<round>.json
build/gates/H6/D1-design-r1.json      build/gates/H7/T2-code-r2.json
```

A verdict is **per REQ ID**. "Looks good" is not a verdict; neither is a prose
summary, a bullet list, or an approval with an empty `findings` array. The
orchestrator rejects a malformed verdict and re-dispatches the reviewer. A finding
with no `evidence` is not a finding, and one with no `fix` is a complaint.

## Schema

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://base-windows-rust-app/gates/verdict.schema.json",
  "type": "object", "additionalProperties": false,
  "required": ["gate","reviewer","dimension","round","reviewedAt","scope","findings","votes","decision"],
  "properties": {
    "gate":       { "enum": ["H6", "H7"] },
    "reviewer":   { "enum": ["D1", "D2", "T1", "T2"] },
    "dimension":  { "enum": ["design", "function", "code"] },
    "round":      { "type": "integer", "minimum": 1, "maximum": 3 },
    "reviewedAt": { "type": "string", "format": "date-time", "description": "UTC" },
    "commit":     { "type": "string", "pattern": "^[0-9a-f]{40}$" },
    "target":     { "enum": ["x86_64-pc-windows-msvc", "aarch64-pc-windows-msvc", "both"],
                    "description": "Which build the evidence came from. ARM64 is not an afterthought (REQ-FND-04)." },
    "reviewPlan": { "type": "object", "required": ["statedBefore", "areas"],
      "description": "Mandatory for T1/T2 on anything larger than a single-file fix, stated before execution (REQ-GAT-03).",
      "properties": {
        "statedBefore": { "const": true },
        "areas":  { "type": "array", "minItems": 5,
                    "items": { "enum": ["best-practice","ffi-unsafe","elevation","update-trust-chain","ipc"] } },
        "method": { "type": "string", "minLength": 80, "description": "How each area is executed, in order." } } },
    "scope": { "type": "object", "required": ["paths", "reqIds"],
      "description": "Frozen at round 1, copied verbatim afterwards. Widening is a violation (loop-rules.md §3).",
      "properties": {
        "paths":  { "type": "array", "minItems": 1, "items": { "type": "string" } },
        "reqIds": { "type": "array", "minItems": 1, "items": { "$ref": "#/$defs/reqId" } } } },
    "findings": {
      "type": "array", "minItems": 1,
      "items": {
        "type": "object", "additionalProperties": false,
        "required": ["id","req","verdict","severity","evidence","defect","fix","owner"],
        "properties": {
          "id":       { "type": "string", "pattern": "^F-[0-9]{3}$" },
          "req":      { "$ref": "#/$defs/reqId" },
          "verdict":  { "enum": ["pass", "fail", "na"] },
          "severity": { "enum": ["critical","high","medium","low","info"],
                        "description": "critical and high block the gate. An unmet MUST is at least high." },
          "naReason": { "type": "string", "description": "Required when verdict is na. 'Out of scope' is not a reason." },
          "evidence": { "type": "array", "minItems": 1, "items": {
              "type": "object", "required": ["kind", "path"], "properties": {
                "kind":    { "enum": ["file","command","test","screenshot","log","manifest",
                                      "registry-diff","acl-dump","sigcheck","procmon","event-log","crash-record"] },
                "path":    { "type": "string" },
                "locator": { "type": "string", "description": "line range, test name, command, theme+DPI, pipe or service name, registry key" },
                "excerpt": { "type": "string", "maxLength": 600 } } } },
          "defect": { "type": "string", "minLength": 40, "description": "What is wrong, at a location, measured. Not an adjective." },
          "fix":    { "type": "string", "minLength": 20, "description": "What would make it pass. Direction, not a patch." },
          "owner":  { "type": "string", "pattern": "^B(0[0-9]|1[0-8])$", "description": "From contracts/ownership.md" },
          "carriedFrom":   { "type": "integer", "minimum": 1, "description": "Round first raised; a third failed round escalates (REQ-GAT-05)." },
          "ownerResponse": { "enum": ["fixed", "disputed", "waiver-requested"] },
          "bothReviewers": { "type": "boolean", "description": "Orchestrator-set when T1 and T2 raised it independently." }
        }
      }
    },
    "votes": {
      "type": "array", "minItems": 1,
      "description": "One entry per dimension this reviewer votes on. D1 and D2 each vote design AND function (REQ-GAT-01).",
      "items": { "type": "object", "required": ["dimension", "vote", "criterion"], "properties": {
          "dimension": { "enum": ["design", "function", "code"] },
          "vote":      { "enum": ["approve", "reject"] },
          "criterion": { "type": "string", "description": "The pass criterion applied." },
          "karpathyLens": { "type": "object",
            "description": "Mandatory in every D1 and D2 verdict, every round (REQ-GAT-06, karpathy-lens.md).",
            "required": ["overcomplication", "surgical", "assumptions", "verifiable"], "properties": {
              "overcomplication": { "enum": ["pass", "fail"] }, "surgical":   { "enum": ["pass", "fail"] },
              "assumptions":      { "enum": ["pass", "fail"] }, "verifiable": { "enum": ["pass", "fail"] } } } } },
    "decision": { "type": "object", "required": ["blocking", "rationale"], "properties": {
        "blocking":     { "type": "boolean", "description": "true if any open finding is critical or high." },
        "rationale":    { "type": "string", "minLength": 30 },
        "escalate":     { "type": "boolean", "description": "true when a defect has failed three rounds (REQ-GAT-05)." },
        "disagreement": { "type": "string", "description": "Required when escalate is true: both positions, stated fairly." } } },
    "notReviewed": { "type": "array", "items": { "type": "string" },
      "description": "Paths or requirements in scope the reviewer could not reach, and why. Silence here is dishonest." }
  },
  "$defs": { "reqId": { "type": "string", "pattern": "^REQ-[A-Z]{2,4}-[0-9]{2}$" } }
}
```

## Filled example

```json
{
  "gate": "H7", "reviewer": "T1", "dimension": "code", "round": 1,
  "reviewedAt": "2026-09-22T09:14:51Z", "target": "x86_64-pc-windows-msvc",
  "commit": "b07c4e1f9a2d5e3380cc1147ae62f9d4b5081c6a",
  "reviewPlan": {
    "statedBefore": true,
    "areas": ["best-practice", "ffi-unsafe", "elevation", "update-trust-chain", "ipc"],
    "method": "1. manifest, linker hardening, path resolution. 2. every unsafe block in crates/ffi against its stated invariant. 3. each --install path and what runs elevated. 4. trust chain read-only, T2 leads. 5. pipe creation, DACL, caller token check."
  },
  "scope": {
    "paths": ["crates/ffi/**", "crates/install/**", "crates/service/**", "packaging/app.manifest"],
    "reqIds": ["REQ-FND-06", "REQ-FND-11", "REQ-INST-04", "REQ-SEC-06", "REQ-SEC-09", "REQ-SVC-03"]
  },
  "findings": [
    { "id": "F-001", "req": "REQ-SEC-09", "verdict": "fail", "severity": "critical",
      "evidence": [
        { "kind": "file", "path": "crates/service/src/ipc/endpoint.rs", "locator": "L61-L74",
          "excerpt": "let sd = SecurityDescriptor::null(); // default ACL" },
        { "kind": "acl-dump", "path": "build/gates/H7/acl/pipe-appd.txt",
          "locator": "\\\\.\\pipe\\appd-ipc", "excerpt": "Everyone: FILE_ALL_ACCESS" }],
      "defect": "The named pipe is created with a null security descriptor, so Everyone has full access, and the server dispatches the first message without GetNamedPipeClientProcessId or any token check. Any local user drives service commands, the update transition included.",
      "fix": "Create the pipe with an explicit DACL for the installing user's SID and SYSTEM only, then authenticate the caller's token per connection before dispatch, per the ipc-contract member.",
      "owner": "B08" },
    { "id": "F-002", "req": "REQ-FND-11", "verdict": "fail", "severity": "high",
      "evidence": [{ "kind": "manifest", "path": "packaging/app.manifest", "locator": "L9",
          "excerpt": "<requestedExecutionLevel level=\"requireAdministrator\" />" }],
      "defect": "The shipped manifest requests requireAdministrator, so the tray app runs elevated for its whole lifetime instead of only the install path elevating at the moment of need.",
      "fix": "Set the manifest to asInvoker; keep elevation in the re-launched installer instance only (REQ-INST-04).",
      "owner": "B01" },
    { "id": "F-003", "req": "REQ-FND-06", "verdict": "fail", "severity": "high",
      "evidence": [
        { "kind": "file", "path": "crates/ffi/src/shell.rs", "locator": "L128-L141",
          "excerpt": "// SAFETY: hwnd is valid for the lifetime of the call" },
        { "kind": "command", "path": "build/gates/H7/cmd/grep-hwnd.txt",
          "locator": "rg -n stored_hwnd crates", "excerpt": "crates/tray/src/icon.rs:44: self.stored_hwnd = hwnd;" }],
      "defect": "The stated invariant is false. crates/tray stores the HWND and reuses it after an Explorer restart has destroyed the window, so the wrapper is called with a stale handle on the re-registration path (REQ-TRY-02).",
      "fix": "Take the HWND by a guard type that cannot outlive the window, or re-resolve it inside the wrapper and return an error for a destroyed window. Then restate the invariant to match.",
      "owner": "B01" },
    { "id": "F-004", "req": "REQ-SVC-03", "verdict": "pass", "severity": "info",
      "evidence": [{ "kind": "command", "path": "build/gates/H7/cmd/sc-qc.txt", "locator": "sc qc appd",
          "excerpt": "SERVICE_START_NAME: NT SERVICE\\appd" }],
      "defect": "The service runs under a virtual service account rather than LocalSystem, no requirement forcing otherwise.",
      "fix": "None required.", "owner": "B08" }
  ],
  "votes": [
    { "dimension": "code", "vote": "reject",
      "criterion": "zero critical or high findings across the five planned areas" }
  ],
  "decision": {
    "blocking": true,
    "rationale": "F-001 is critical: the IPC endpoint is world-writable and unauthenticated, which makes the service's update transition callable by any local user. F-002 and F-003 are high and independent of it."
  },
  "notReviewed": [
    "crates/update/** — trust chain is T2's area this round; read only for the elevation path.",
    "aarch64 build — no ACL dump captured on ARM64; re-request from B14 if F-001 recurs."
  ]
}
```

## Rules the schema does not enforce

- `severity` grades the requirement's status, not the reviewer's mood. An unmet
  `MUST` is at least `high`, and every requirement in this register but
  REQ-SVC-01 is a `MUST`.
- `carriedFrom` makes REQ-GAT-05 mechanical: `round - carriedFrom` reaching 2 is
  a third failed round, which sets `escalate: true` and requires `disagreement`.
- A reviewer never writes `ownerResponse` without evidence from the owner's fix.
  It is a record, not a guess.
- `notReviewed` is not optional honesty. A `pass` on a requirement whose evidence
  was never captured is a fabricated verdict, and reading the evidence paths
  catches it.
