# Contract Law

The reason this build can run 13 agents at once is that the agents never talk to
each other. They talk to a contract. This file is the law that governs it.

Requirements: REQ-CTR-01 … REQ-CTR-10.

---

## 1. One coupling point

`packages/contracts` is the **only** thing two domains may share. A domain
package never imports another domain package. If `packages/audit` needs to know
what a session is, it imports `Session` from contracts — not from
`packages/auth`.

```
packages/auth ──┐
packages/rbac ──┤
packages/audit ─┼──▶ packages/contracts ◀── every consumer
packages/mail ──┤
...             ──┘
```

Enforced by an import-boundary lint rule (A01 configures it, CI fails on
violation). An agent that "just needs one type from another package" has found a
missing contract member, not an exception.

## 2. What lives in the contract

Nine kinds of member, each with exactly one publishing agent:

| Member | Artefact | Published by |
|--------|----------|--------------|
| `entity-base` | [`types/entity-base.md`](types/entity-base.md) — the `comment` / `created_*` / `updated_*` / `deleted_*` envelope and its enumerated exemptions (REQ-ENT-01) | A02 |
| `errors` | [`types/errors.md`](types/errors.md) — RFC 9457 problem types and the stable error-code taxonomy (REQ-API-10) | A02 |
| `pagination` | [`types/pagination.md`](types/pagination.md) — page/cursor params, sort and filter grammar, shared with the grid (REQ-API-11) | A02 |
| `time` | [`types/time.md`](types/time.md) — the only formatter in the app: Europe/Stockholm, `YYYY-MM-DD HH:mm:ss`, UTC storage (REQ-TIM-04) | A02 |
| `identity` | [`types/identity.md`](types/identity.md) — `Actor`, `Session`, `Tenant`, `ImpersonationContext` | A03, A04 |
| `rbac` | [`types/rbac.md`](types/rbac.md) — the permission grammar and the full catalogue (REQ-RBA-01) | A04 assembles, each domain declares its own |
| `canonical-models` | [`types/canonical-models.md`](types/canonical-models.md) — the product-agnostic model set and provenance (REQ-DAT-01) | A10 |
| `i18n-namespaces` | [`types/i18n-namespaces.md`](types/i18n-namespaces.md) — namespace ownership and the collision rule (REQ-I18N-05) | A14 registers, each domain declares its own |
| `audit-event` | [`events/audit-event.md`](events/audit-event.md) — the audit envelope, read/view kinds, redaction, hash chain (REQ-AUD-04) | A13 |
| `console-stream` | [`events/console-stream.md`](events/console-stream.md) — the debug console SSE protocol and compact mode (REQ-AUD-08) | A13 |
| `notification-event` | [`events/notification-event.md`](events/notification-event.md) — categories, channels, and the safe push payload (REQ-PWA-04) | A12 |
| `ingest-envelope` | [`events/ingest-envelope.md`](events/ingest-envelope.md) — collector ingest and the idempotency key (REQ-OBS-05) | A15 |
| API surface | [`openapi/conventions.md`](openapi/conventions.md), [`openapi/skeleton.yaml`](openapi/skeleton.yaml) — OpenAPI 3.1 generated from the runtime's Zod schemas (REQ-API-01) | A11 assembles, each domain declares its operations |
| Schema & isolation | [`db/schema-ownership.md`](db/schema-ownership.md), [`db/rls-contract.md`](db/rls-contract.md) — table ownership, migration namespacing, forced RLS (REQ-RBA-04) | A02 map, A04 policies |

## 3. Declaration, then assembly

A domain agent does not write into `packages/contracts` — only A02 does. Instead
each agent writes a **declaration file** inside its own package:

`packages/<domain>/contract.declaration.ts`

```ts
export const declaration = {
  agent: "A03",
  types: { Session: SessionSchema, MfaFactor: MfaFactorSchema },
  permissions: ["auth.session.read", "auth.mfa.enrol", "auth.mfa.reset"],
  i18nNamespace: "auth",
  operations: [ /* route contracts, Zod in and out */ ],
  events: [],
  tables: [{ name: "sessions", tenantScoped: true }],
  env: [{ name: "AUTH_SESSION_TTL", schema: z.coerce.number().int().positive() }],
} satisfies ContractDeclaration;
```

A02 collects every declaration, checks for collisions, and assembles the frozen
package. This is why two agents can both "add a permission" in the same minute
without touching the same file.

Collisions are a **hard failure at assembly**, not a silent last-write-wins:
duplicate permission string, duplicate i18n key, duplicate table name, duplicate
operation id, duplicate error code — assembly stops and names both claimants.

## 4. The freeze (gate G3)

At G3, A02 publishes `packages/contracts@1.0.0` and the contract is frozen.
Wave 3 launches against the frozen version. After the freeze:

- Adding a member is a CCR (fast path, minutes).
- Changing a member is a CCR (slow path, orchestrator arbitration).
- Removing a member is not possible before a deprecation window has elapsed.

## 5. Additive-only (REQ-CTR-03)

Once a member is in the frozen contract:

**Allowed**
- Add a new type, field, permission, error code, event, operation, namespace key.
- Add an *optional* field to an existing type.
- Widen an input union, narrow an output union.
- Add a new `/api/v1` operation.

**Not allowed**
- Rename anything. (Add the new name, deprecate the old.)
- Remove anything.
- Make an optional field required.
- Change a field's type.
- Change the meaning of a value while keeping its name — the worst of all,
  because no tool catches it. A semantic change requires a new name.

**Breaking a shipped API operation requires `/api/v2`** (REQ-API-09, REQ-CTR-09).
Both versions are served through the deprecation window stated in the CCR.

Enforced by a breaking-change detector on every commit (REQ-CTR-07). It compares
the current contract surface against the frozen baseline and fails on any
removal or narrowing. The detector is not advisory.

## 6. Contract Change Request

A CCR is a file in `build/ccr/<n>-<slug>.md`:

```md
# CCR-007 — Add `Session.impersonatedBy`
Requested by: A03    Affects: A04, A13    Kind: additive
Requirement: REQ-RBA-07

## What
Add optional `impersonatedBy?: ActorRef` to `Session`.

## Why the consumers are safe
Optional. Existing readers ignore it. A13 will read it to populate the
on-behalf-of audit field; until it does, audit records are unchanged.

## Rollout
A02 assembles → contracts 1.1.0 → A03 and A13 pick it up on their next task.
No consumer needs to change to stay correct.
```

- **Additive CCR**: A02 approves and assembles. No pause in Wave 3.
- **Breaking CCR**: the orchestrator arbitrates. Default answer is *no* — find
  the additive version. If genuinely unavoidable, it becomes a versioned change
  with a deprecation window, and every affected agent gets a task.

The orchestrator logs every CCR decision. A build with more than a handful of
breaking CCRs means the G3 freeze was premature, and that is a finding against
the orchestrator, not against the agents.

## 7. Nobody waits (REQ-CTR-05)

An agent never calls another agent's running code and never waits for another
agent to finish. It consumes:

1. **Generated clients** — A11 generates a typed client from the OpenAPI
   document at freeze time. It exists before any endpoint is implemented.
2. **Contract fixtures** — generated from the Zod schemas (REQ-CTR-06), so a
   fixture cannot drift from its schema. An agent building the grid has
   realistic paginated tenant-scoped rows on day one.
3. **Contract stubs** — every operation resolves against the fixtures until the
   owning domain lands the real implementation. Swapping stub for real is a
   configuration flag, not a code change in the consumer.

This is the whole trick. A07 finishes the datagrid without `packages/api-kit`
existing yet, because it was never consuming `packages/api-kit` — it was
consuming `pagination` + `query-params` + fixtures.

## 8. Self-test per domain (REQ-CTR-08)

Every domain publishes `GET /api/v1/<domain>/_selftest` (permission-gated,
disabled in production by default) that asserts its side of the contract:
schemas parse, permissions resolve, tables carry the entity envelope, RLS is
enabled on its tenant-scoped tables, its env vars are present.

When integration fails, the self-tests say **which owner** to hand the task to.
Integration debugging without this degenerates into the orchestrator reading
everyone's code, which is the bottleneck the whole design exists to avoid.

## 9. Interface tests belong to the contract (REQ-CTR-10)

A test that asserts "the grid sends what the API accepts" lives in
`packages/contracts/tests/` and is run by **both** A07 and A11. Neither side can
quietly satisfy its own interpretation. When such a test fails, the contract is
ambiguous and the fix is a clarifying CCR — not a patch on whichever side
happened to be looked at first.

## 10. Versioning the contract itself

`packages/contracts` follows semver strictly, and it is the one package where
semver is mechanically enforced rather than judged:

- additive member → minor
- clarification, doc, test → patch
- anything the detector flags → major, and a major requires orchestrator sign-off

Wave 3 agents pin a minor range (`^1.0.0`). A major bump mid-wave is a build
incident with a written cause.
