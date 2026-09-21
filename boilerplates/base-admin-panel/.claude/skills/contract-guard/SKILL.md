---
name: contract-guard
description: Enforces contract law for the base-admin-panel monorepo — collects every packages/*/contract.declaration.ts, fails hard on duplicate permission strings, i18n keys, table names, operation ids or error codes while naming both claimants, runs the breaking-change detector against the frozen packages/contracts@1.0.0 baseline, writes Contract Change Requests, and checks that no domain package imports another domain package. Load at gate G3, on any commit that touches packages/contracts or a declaration file, when a CCR is requested, or when asked about "contract freeze", "collision", "breaking change", "additive only", or "import boundary".
---

# Contract Guard

Contract law is `contracts/README.md`. Requirements: REQ-CTR-01 … REQ-CTR-10.
Only A02 writes inside `packages/contracts`. Every other agent declares.

## 1. Collect the declarations

```bash
ls -1 packages/*/contract.declaration.ts services/*/contract.declaration.ts 2>/dev/null
pnpm -w exec tsx scripts/contracts/collect.ts > build/contract-surface.json
```

Expect one declaration per Wave 3 agent that publishes a member. Cross-check the
declared `agent` field against `spec/agents.md`.

```bash
grep -h 'agent:' packages/*/contract.declaration.ts | sed 's/.*"\(A[0-9]*\)".*/\1/' | sort
```

**When this fails:** a declaration is missing. Do not assemble a partial
contract — a member that arrives after the freeze is a CCR for every consumer.
Task the missing agent and hold G3.

## 2. Collision detection — hard failure

Five collision classes stop assembly (`contracts/README.md` §3). Last-write-wins
is never acceptable.

```bash
# duplicate permission string
jq -r '.declarations[] | .agent as $a | .permissions[]? | "\(.)\t\($a)"' build/contract-surface.json \
  | sort | awk -F'\t' '{c[$1]=c[$1]" "$2; n[$1]++} END{for(k in n) if(n[k]>1) print "PERMISSION",k,"claimed by:"c[k]}'

# duplicate table name
jq -r '.declarations[] | .agent as $a | .tables[]?.name | "\(.)\t\($a)"' build/contract-surface.json \
  | sort | awk -F'\t' '{c[$1]=c[$1]" "$2; n[$1]++} END{for(k in n) if(n[k]>1) print "TABLE",k,"claimed by:"c[k]}'

# duplicate operation id
jq -r '.declarations[] | .agent as $a | .operations[]?.operationId | "\(.)\t\($a)"' build/contract-surface.json \
  | sort | awk -F'\t' '{c[$1]=c[$1]" "$2; n[$1]++} END{for(k in n) if(n[k]>1) print "OPERATION",k,"claimed by:"c[k]}'

# duplicate i18n namespace, and duplicate key inside a namespace
jq -r '.declarations[] | "\(.i18nNamespace)\t\(.agent)"' build/contract-surface.json \
  | sort | awk -F'\t' '{c[$1]=c[$1]" "$2; n[$1]++} END{for(k in n) if(n[k]>1) print "I18N-NS",k,"claimed by:"c[k]}'

# duplicate error code
jq -r '.declarations[] | .agent as $a | .errors[]?.code | "\(.)\t\($a)"' build/contract-surface.json \
  | sort | awk -F'\t' '{c[$1]=c[$1]" "$2; n[$1]++} END{for(k in n) if(n[k]>1) print "ERROR-CODE",k,"claimed by:"c[k]}'
```

Also enforce the permission grammar `<domain>.<resource>.<action>` (REQ-RBA-01):

```bash
jq -r '.declarations[].permissions[]?' build/contract-surface.json \
  | grep -vE '^[a-z0-9-]+\.[a-z0-9-]+\.[a-z0-9-]+$' && echo "MALFORMED PERMISSION STRING"
```

Exact failure text to emit — name both claimants, never one:

```
CONTRACT ASSEMBLY FAILED — collision
  class:     permission string
  member:    audit.event.read
  claimants: A13 (packages/audit/contract.declaration.ts)
             A11 (packages/api-kit/contract.declaration.ts)
  fix:       one claimant renames to its own domain prefix, or A02 adds a
             shared member and both consume it. Assembly does not proceed.
```

**When this fails:** a collision is reported but both agents insist the member is
theirs. That is an ownership bug — route to the orchestrator to amend
`contracts/ownership.md`, not a negotiation between the two agents.

## 3. Freeze the baseline (G3)

```bash
pnpm --filter @app/contracts build
pnpm contracts:fixtures          # generated FROM the Zod schemas (REQ-CTR-06)
pnpm contracts:client            # typed client from the OpenAPI document (REQ-API-01)
node scripts/contracts/snapshot.mjs > packages/contracts/.baseline/1.0.0.json
git add packages/contracts/.baseline/1.0.0.json
```

A hand-written fixture is a defect — delete it and regenerate. Wave 3 pins
`^1.0.0`.

## 4. Breaking-change detector

Runs on every commit against the frozen baseline (REQ-CTR-07). It is not
advisory; it fails the build.

```bash
node scripts/contracts/snapshot.mjs > /tmp/contract-head.json
node scripts/contracts/detect-breaking.mjs \
  --baseline packages/contracts/.baseline/1.0.0.json \
  --head /tmp/contract-head.json
echo "exit=$?"
```

What counts as breaking — any one of these fails:

| Change | Verdict |
|--------|---------|
| Rename a type, field, permission, error code, event, operation or namespace key | **breaking** — add the new name, deprecate the old |
| Remove anything | **breaking** — not possible before the deprecation window elapses |
| Optional field → required | **breaking** |
| Change a field's type (including narrowing an input union or widening an output union) | **breaking** |
| Change the meaning of a value while keeping its name | **breaking, and the worst** — no tool catches it, so it is caught in review. A semantic change requires a new name |

Additive-only allowances (REQ-CTR-03):

- new type, field, permission, error code, event, operation, namespace key
- a new **optional** field on an existing type
- widen an *input* union, narrow an *output* union
- a new `/api/v1` operation

Breaking a shipped API operation requires `/api/v2` (REQ-API-09, REQ-CTR-09).
Both versions are served through the window stated in the CCR.

Failure text:

```
BREAKING CHANGE DETECTED — build blocked (REQ-CTR-07)
  member:   Session.tenantId
  baseline: optional string
  head:     required string
  kind:     optional→required
  owner:    A03 (packages/auth)
  fix:      keep tenantId optional; add tenantIdRequired or validate at the
            call site. If genuinely unavoidable, file a breaking CCR — the
            orchestrator arbitrates and the default answer is no.
```

## 5. Write a CCR

One file, `build/ccr/<n>-<slug>.md`, following the template in
`contracts/README.md` §6. Required sections: **What**, **Why the consumers are
safe**, **Rollout**. Header line carries `Requested by`, `Affects`, `Kind:
additive|breaking`, and the `REQ-` ID.

- **Additive CCR** → A02 approves and assembles. Contracts minor bump. No pause
  in Wave 3.
- **Breaking CCR** → orchestrator arbitrates. Attach your recommended additive
  alternative. Default answer is no.

Semver is mechanical here (`contracts/README.md` §10): additive member → minor;
clarification, doc or test → patch; anything the detector flags → major, and a
major requires orchestrator sign-off. A major bump mid-wave is a build incident
with a written cause.

## 6. Import-boundary check

REQ-CTR-01: a domain package never imports another domain package. The only
cross-domain coupling is `packages/contracts`.

```bash
# any domain package importing another domain package
grep -rnE "from ['\"]@app/(auth|rbac|tenancy|screenspace|theme|datagrid|pwa|canonical|api-kit|mail|notify|audit|logging|syslog|i18n|fixtures)" \
  packages --include='*.ts' --include='*.tsx' \
  | grep -vE "^packages/contracts/" \
  | awk -F/ '{print}' \
  | grep -vE "^packages/([a-z-]+)/.*@app/\1"
```

Also run the lint rule A01 configured, which is the enforcement point CI uses:

```bash
pnpm -w lint:boundaries
```

Failure text:

```
IMPORT BOUNDARY VIOLATION (REQ-CTR-01)
  file:   packages/audit/src/session-ref.ts:4
  import: @app/auth
  rule:   a domain package imports only @app/contracts
  fix:    this is a MISSING CONTRACT MEMBER, not an exception. File an
          additive CCR moving the needed type into packages/contracts and
          import it from there.
```

**When this fails:** the violation is in a test file or a type-only import and
someone argues it is harmless. It is not — `import type` still couples the build
graph and defeats REQ-CTR-05. Add the contract member.

## 7. Per-domain self-test and interface tests

```bash
curl -sf https://localhost/api/v1/<domain>/_selftest | jq .
pnpm --filter @app/contracts test        # run by BOTH producer and consumer
```

REQ-CTR-08: the self-test names which owner to hand the task to. REQ-CTR-10:
when an interface test fails the contract is ambiguous — the fix is a clarifying
CCR, not a patch on whichever side was looked at first.
