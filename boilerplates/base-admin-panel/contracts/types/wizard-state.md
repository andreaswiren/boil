# `wizard-state` — the setup cursor, steps and completion record

**Published by:** A24 (`WizardState`, `SetupStep`, `StepResult`, `EnvReportRow`,
`TerminationMode`, `SetupCompletion`, `readSetupGate`). Assembled by A02.
**Requirements:** REQ-WIZ-01, REQ-WIZ-03, REQ-WIZ-04, REQ-WIZ-07, REQ-WIZ-09,
REQ-WIZ-11, REQ-WIZ-12, REQ-WIZ-13, REQ-PROX-03, REQ-ACME-03.
**Consumed by:** A01 (middleware gate), A05 (`(app)` layout gate and the
settings panel), A11 (route-kit refusal), A13 (audit payloads), A23, A25
(termination mode).

Everything here is **server-derived**. No member is ever read from a request
body, query string or header. The design spec is `spec/setup-wizard.md`.

---

## 1. The rule that outranks the schemas

> Setup is complete when `completed_at` is non-null — never "complete because
> every known step has a row."

A build that ships a new mandatory step must not re-lock an install finished
under the old set, so the gate reads one column and the step set is a property of
the record, not of the code (§6).

## 2. `SetupStep` and `StepResult`

```ts
// packages/contracts/wizard-state.ts
import { z } from "zod";

/** Ordered. Position in this array is the step order (REQ-WIZ-01). */
export const SetupStepSchema = z.enum([
  "welcome-preflight",   // preflight checks, locale choice
  "create-admin",        // real global admin + MFA + recovery codes (REQ-WIZ-05)
  "smtp",                // sender identity + delivered verification (REQ-WIZ-06)
  "edge-environment",    // topology, certificate plan, env report (REQ-WIZ-07/08)
  "review-complete",     // the completion record (REQ-WIZ-11)
]);
export const SETUP_STEP_ORDER = SetupStepSchema.options;

/** A completed step. There is no `in_progress` variant — see §5. */
export const StepResultSchema = z.object({
  step: SetupStepSchema,
  runOrdinal: z.number().int().positive(),   // 1 = first run; a re-run appends n+1
  state: z.literal("complete"),
  completedAt: UtcInstantSchema,
  resultDigest: z.string().length(64),       // sha256 of the redacted payload
  detail: z.record(z.unknown()),             // step facts, redacted (REQ-AUD-05)
}).strict();
```

`runOrdinal` is in the key, not a mutable counter: `setup_steps` is append-only,
so a re-run never overwrites the evidence of the first run (REQ-WIZ-12).

## 3. `WizardState` and `TerminationMode`

```ts
/** Mirrors `TLS_TERMINATION_MODE` (REQ-PROX-03, REQ-ACME-03). A24 records the
 *  operator's answer; the authoritative value is A01's parsed env, because it
 *  decides which ports are bound at boot (`spec/acme-tls.md` §2). */
export const TerminationModeSchema = z.enum(["self", "behind-proxy", "delegated"]);

export const WizardStateSchema = z.object({
  cursor: SetupStepSchema,
  completedAt: UtcInstantSchema.nullable(),  // non-null = done; the gate's only input
  requiredSteps: z.array(SetupStepSchema).nonempty(),  // frozen at completion
  completedSteps: z.array(StepResultSchema),
  terminationMode: TerminationModeSchema.nullable(),  // read through from parsed env
  bootstrapActive: z.boolean(),              // false once the teardown commits
  realAdmin: ActorRefSchema.nullable(),
}).strict();

/** What the middleware and the route kit read. Cheap, cacheable per request. */
export const SetupGateSchema = z.object({
  complete: z.boolean(),
  cursor: SetupStepSchema,
}).strict();
```

`ActorRefSchema` and `UtcInstantSchema` come from `contracts/types/identity.md`
and `contracts/types/entity-base.md`. `readSetupGate(): SetupGate` is registered
by `packages/setup` at boot; A01 and A05 call the contract, never that package
(REQ-CTR-01).

## 4. The completion record (REQ-WIZ-11)

```ts
export const SetupCompletionSchema = z.object({
  completedAt: UtcInstantSchema,
  completedBy: ActorRefSchema,              // the real admin, never the bootstrap
  requiredSteps: z.array(SetupStepSchema).nonempty(),
  /** sha256 over the ordered (step, runOrdinal, completedAt, resultDigest) tuples. */
  stepsDigest: z.string().length(64),
  appVersion: z.string(),
  contractVersion: z.string(),
}).strict();
```

Immutable once written. A re-run (REQ-WIZ-12) appends a `StepResult` and never
rewrites this record, so a `stepsDigest` mismatch against the current rows means
exactly "a step has been re-run".

**Derived server-side only:** `cursor` (the first step in `SETUP_STEP_ORDER`
without a `runOrdinal: 1` row), `bootstrapActive`, `realAdmin`, `stepsDigest`,
`resultDigest`, `terminationMode` (A01's parsed env — step 4 records the answer,
not the mode) and every `EnvReportRow.state`. A client reads `SetupGate` and
`WizardState` and sets none of them.

## 5. Table shapes

```sql
setup_state (A24)                      -- singleton, NOT tenant-scoped (§7)
  id smallint primary key default 1 check (id = 1),
  bootstrap_email text not null,       -- 'admin@example.invalid'
  bootstrap_password_hash text,        -- Argon2id; NULL after teardown (REQ-WIZ-04)
  bootstrap_disabled_at timestamptz, bootstrap_session_id text,  -- 256-bit opaque
  bootstrap_session_expires_at timestamptz, real_admin_actor_id uuid,
  draft jsonb not null default '{}',   -- echo-safe only; never a credential
  completed_at timestamptz, completed_by uuid, required_steps text[],
  steps_digest text, app_version text, contract_version text,
  -- plus the REQ-ENT-01 envelope

setup_steps (A24)                      -- append-only, NOT tenant-scoped
  step text not null, run_ordinal int not null,
  state text not null check (state = 'complete'),
  result jsonb not null, result_digest text not null,
  completed_at timestamptz not null,
  primary key (step, run_ordinal)
  -- no UPDATE/DELETE grant to the app role, same posture as REQ-AUD-03
```

There is no row for a step in progress: a step's effects and its row commit in
one transaction, so "started but not finished" is not representable (REQ-WIZ-09).
Drafts live in `setup_state.draft`, overwritten freely, holding nothing a leak
would matter for.

## 6. Additive vs breaking

**Additive**

- A new `EnvReportRow.state` or `severity`, a new optional field on
  `WizardState` or `StepResult`, a new `TerminationMode` appended to the enum.
- **A new step appended to `SETUP_STEP_ORDER`** — additive *only* under §1. The
  gate reads `completed_at`, and `requiredSteps` on an existing record still
  lists the old set, so a finished install stays finished and does not re-lock:
  the new step surfaces as a pending post-setup task in the global settings
  panel, recorded with `runOrdinal: 1`. An install still in setup when the
  version lands picks it up, because `requiredSteps` is written at completion.

**Breaking**

- Inserting a step in the middle of `SETUP_STEP_ORDER`: `cursor` is derived from
  position, so every stored cursor silently changes meaning. Append instead.
- Making the gate "all known steps have a row", which re-locks every existing
  install on the next deploy — the failure §1 exists to prevent.
- Removing or renaming a step id that any `setup_steps` row references.
- Making `StepResult.state` a union with a partial value: every consumer reads
  the presence of a row as completion.
- Adding `tenant_id` to either table (§7), or letting a client supply `cursor`,
  `completedAt` or `terminationMode`.
- Making `terminationMode` a stored column here: it would be writable by a
  request but effective only after a rebuild, and two sources for one truth is
  the silent semantic change REQ-CTR-03 forbids.

## 7. Why setup state is not tenant-scoped

`tenantScoped: false` on both tables, so A04 generates no policy (REQ-RBA-04).
Setup runs before any `tenants` row exists, and the tenant is derived from a
session (REQ-RBA-03) the bootstrap principal cannot hold — an RLS policy here
would deny the wizard reading its own cursor, which is a boot failure, not
isolation. Isolation comes from the shape: one row enforced by a `CHECK`, no
tenant column to leak across, and a re-run surface gated on `global.*` with
step-up. Per-tenant onboarding, if ever needed, is a new table and a CCR.
