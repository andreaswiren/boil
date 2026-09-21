# The Karpathy Lens

REQ-GAT-06. Not a gate, not a round, not a vote of its own: a standing lens that
**both** critics run on **every** build. C1 and C2 each record a `karpathyLens`
block in every verdict (`verdict-schema.md`), with four sub-verdicts:
`overcomplication`, `surgical`, `assumptions`, `verifiable`.

The four guidelines, as they apply here:

- **No overcomplication** — the simplest thing that satisfies the requirement.
- **Surgical changes** — touch what the task names, nothing adjacent.
- **Surfaced assumptions** — an assumption is stated in the code or the report,
  or it is a hidden defect.
- **Verifiable success criteria** — "done" means a command someone else can run.

A lens sub-verdict fails on evidence, like any finding. A `fail` is written as a
normal finding against the REQ ID the smell damages — REQ-SUP-04 for a
dependency, REQ-GRD-10 for a hardcoded page size, REQ-DAT-03 for a mapping in
code — graded by that requirement, not by the smell's name. The lens is how you
find it; the requirement is what blocks the gate.

## The checklist

Run all nine. Each one is a question with an answer that settles it.

### 1. An abstraction layer with one implementation

**Ask:** how many implementations exist behind this interface, and which
requirement names the second one?

**Settles it:** `grep -rn "implements <Interface>"` returns one class, and no REQ
ID predicts another. A `StorageAdapter` with only Postgres behind it contradicts
REQ-FND-05, which says PostgreSQL is the only datastore. Legitimate exceptions
exist and are named by a requirement: the grid's two data sources (REQ-GRD-12)
and the auth methods (REQ-AUT-01..03) are required plurality, not speculation.

### 2. A config knob nobody asked for

**Ask:** which intake answer or REQ ID created this env var or setting, and what
happens at boot if it is absent?

**Settles it:** the variable appears in `packages/config` and `.env.example` but
in no requirement and no `build/scope.md` line, and its default is the only value
ever used. Delete it. The inverse defect: a security-relevant value with a silent
default is a REQ-FND-07 failure, not a missing knob.

### 3. A rewrite where an edit would do

**Ask:** what does `git diff --stat` say, and what did the finding or task ask
for?

**Settles it:** a finding naming one toolbar produced a diff across eleven files
and a renamed component. That is out of bounds by `loop-rules.md` §2 — the owner
fixes only what the finding names. The mirror smell: a file rewritten wholesale
so the diff is unreviewable, hiding one real change among 400 moved lines.

### 4. An assumption baked in silently

**Ask:** where is this value or condition declared, and who can change it without
editing code?

**Settles it:** three concrete forms in this codebase.

- **A hardcoded page size.** `pageSize = 50` anywhere outside a grid definition
  violates REQ-GRD-10. Check `grep -rn "pageSize" packages apps | grep -v grid-def`.
- **An assumed single tenant.** A query with no tenant predicate, a cache key
  without `tenant_id`, a unique index that is unique globally where it should be
  unique per tenant, a "the operator's tenant" shortcut (REQ-RBA-03).
- **An assumed timezone or format.** `new Date()` rendered directly, a `YYYY-MM-DD`
  template literal, `Europe/Stockholm` hardcoded in a component rather than
  resolved user → tenant → system (REQ-TIM-03, REQ-TIM-04).

An assumption that must exist is fine when it is declared — in the contract, in
the grid definition, in `build/scope.md` — and a finding when it is only in
someone's head.

### 5. A "done" with no way to check it

**Ask:** which command, test name or recorded artefact proves this claim, and
does it pass right now?

**Settles it:** the agent's `report.md` cites a REQ ID with no test path, a test
that does not exist, or a `_selftest` route returning 200 without asserting
anything (REQ-CTR-08). Re-run every claim you intend to mark `pass`. The three
claims REQ-TST-08 singles out — console stream, grid preference round-trip,
read-audit emission — are easy to fake and need recorded evidence, not a
screenshot.

### 6. Speculative generality

**Ask:** what is the second case this generality serves, and is it in scope?

**Settles it:** a plugin system with one plugin, a resolver registry with one
resolver, a `v2` branch in a switch that nothing reaches, a generic
`EntityService<T>` used by one entity, an event bus with one subscriber.
Distinguish from required generality: the mapping engine is generic **because**
REQ-DAT-03 forbids shipping TypeScript per source, and the nav/settings/help
registries are generic **because** they are what keeps a 13-wide wave parallel
(`contracts/ownership.md`). Generality that a requirement names is not
speculation; generality an agent enjoyed writing is.

### 7. A dependency added for one function

**Ask:** where is the recorded justification (REQ-SUP-04), and how much of the
package is used?

**Settles it:** the lockfile grew, the package appears in one import, and there is
no justification entry. A date library imported for one format call while
`packages/contracts/time` exists is both this smell and a REQ-TIM-04 defect. Also
check the transitive cost with A19's inventory (REQ-SUP-01) and that the lockfile
change has a matching `package.json` change (REQ-SUP-05).

### 8. A generated file edited by hand

**Ask:** does regenerating this file reproduce it byte for byte?

**Settles it:** regenerate and diff. Candidates: the OpenAPI document (REQ-API-01
— generated from the Zod schemas, never hand-maintained), the typed client,
contract fixtures (REQ-CTR-06), the SBOM (REQ-CRA-03), the compliance set
(REQ-CRA-10), and the architecture charts (REQ-DOC-08). A hand edit here is a
defect that survives every review because it looks generated.

### 9. A test that asserts the implementation rather than the behaviour

**Ask:** would this test still pass if the feature were reimplemented correctly a
different way — and would it fail if the feature broke?

**Settles it:** read the assertions. A test spying on a private method, snapshot
tests over an entire rendered tree, a test asserting a call count instead of a
persisted row, a test that mocks the thing under test. The requirement-shaped
version of the grid preference test is "read the row back through a different
session and compare seven values" (REQ-GRD-08, REQ-TST-08) — not "the setter was
called". Also flag the mirror defect: a test that cannot fail, e.g. an `expect`
inside an unreached branch.

## Recording the lens

```json
"karpathyLens": { "overcomplication": "pass", "surgical": "pass",
                  "assumptions": "fail", "verifiable": "pass" }
```

- Mandatory in every C1 and C2 verdict, both dimensions, every round.
- A `fail` sub-verdict requires at least one finding in the same file whose
  `defect` states the smell concretely and whose `owner` comes from
  `contracts/ownership.md`. A `fail` with no finding is a malformed verdict.
- The lens never blocks on its own. It blocks through the requirement it damaged,
  at that requirement's severity — an unmet `MUST` is at least `high`.
- The lens is not a style opinion. "I would have written it differently" is not a
  `fail`; "this abstraction has one implementation and no requirement predicts a
  second, so the indirection costs a reader three files to trace one call" is.
