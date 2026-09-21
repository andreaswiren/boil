# `settings-registry` — panel descriptors, scopes, resolved values

**Published by:** A05 (`SettingsScope`, `SettingsPanelDescriptor`,
`SettingsFieldDescriptor`, `SettingsValue`). Declared by every domain that
contributes a panel. Assembled by A02.
**Requirements:** REQ-SET-02, REQ-SET-07, REQ-SET-08, REQ-SET-09, REQ-SET-10,
REQ-SET-11, REQ-SET-12, REQ-RBA-01, REQ-RBA-06, REQ-I18N-05, REQ-DOC-03,
REQ-TIM-03, REQ-ENT-01.
**Consumed by:** A01, A03, A04, A06, A07, A10, A11, A12, A13, A16, A18, A19,
A23, A25.

**The registry carries descriptors, never values.** A descriptor is ten scalars
and a component specifier — enough for A05's shell to place, gate, label, order
and document a panel without importing the domain that owns it (REQ-CTR-01).
Values resolve per request through §4 and are stored per §6. The design and the
panel inventory are `spec/settings.md`; this is the frozen shape.

---

## 1. `SettingsScope` (REQ-SET-02)

```ts
// packages/settings/contract.declaration.ts — ordered narrowest to widest
export const SettingsScopeSchema = z.enum(["personal", "tenant", "global"]);
export const SETTINGS_SCOPE_ORDER = ["personal", "tenant", "global"] as const;
export type SettingsScope = z.infer<typeof SettingsScopeSchema>;
```

These are the three tiers of `contracts/types/identity.md` §4 seen from the
settings surface: `personal` is the actor, `tenant` is `session.tenant`,
`global` is the tier with `tenantId: null`. Comparison is by index in
`SETTINGS_SCOPE_ORDER`, for the same reason `GLOBAL_TIER_ORDER` is.

## 2. `SettingsPanelDescriptor` (REQ-SET-08)

```ts
export const SettingsPanelDescriptorSchema = z.object({
  /** "<domain>.<panel>", globally unique. Also the deep-link segment (REQ-SET-12). */
  id: z.string().regex(/^[a-z][a-z0-9-]*\.[a-z][a-z0-9-]*$/),
  scope: SettingsScopeSchema,
  /** The owning agent. One panel, one owner (REQ-CTR-04). */
  agent: z.string().regex(/^A\d{2}$/),
  /** Gates rendering. Deny-by-default; an unresolved string hides the panel. */
  permission: PermissionStringSchema,
  /** Gates every mutation. Defaults to `permission`. */
  writePermission: PermissionStringSchema.optional(),
  /** The declaring agent's own namespace (REQ-I18N-05). Never a literal. */
  i18nNamespace: z.string().regex(/^[a-z][a-z0-9]*$/),
  /** Mandatory; a panel without one fails the gate (REQ-DOC-03). */
  helpTopicId: z.string().min(1),
  order: z.number().int(),                 // hint; ties break by `id` ascending
  /** True if any field can affect actors other than the caller (REQ-SET-10). */
  blastRadius: z.boolean(),
  store: z.enum(["preferences", "domain"]),  // A05's table, or the domain's (§6)
  component: z.string().min(1),              // resolved at build time by A05
  fields: z.array(SettingsFieldDescriptorSchema).nonempty(),
}).strict();
```

`order` is a hint, not an identity: two panels may declare `40` and the shell
breaks the tie by `id`. A nondeterministic settings order fails the visual
baseline (REQ-TST-03).

## 3. `SettingsFieldDescriptor`

```ts
export const SettingsFieldDescriptorSchema = z.object({
  /** Unique within the panel. The `?f=` anchor target (REQ-SET-12). */
  id: z.string().regex(/^[a-z][a-z0-9-]*$/),
  /** Under `i18nNamespace`. Mandatory — no user-visible literal (REQ-I18N-02). */
  labelKey: z.string().min(1),
  descriptionKey: z.string().min(1).optional(),
  kind: z.enum(["boolean", "enum", "string", "number", "duration", "timezone", "secret"]),
  /** Narrower than the panel's, never wider. Absent means the panel's applies. */
  permission: PermissionStringSchema.optional(),
  lockable: z.boolean().default(false),      // holder may lock it (REQ-SET-11)
  blastRadius: z.boolean().default(false),   // confirm when users > 1 (REQ-SET-10)
  /** Locale-independent uppercase ASCII token. Required iff `blastRadius`. */
  confirmToken: z.string().regex(/^[A-Z0-9 ]{8,80}$/).optional(),
}).strict();
```

A `secret` field is write-only: a set/rotate affordance, never a current value,
and redacted from the audit diff (REQ-AUD-05). `duration` is integer seconds
rendered only by `packages/contracts/time` (REQ-TIM-04); `timezone` holds an
IANA identifier, default `Europe/Stockholm` (REQ-TIM-01).

## 4. `SettingsValue` — the resolved shape (REQ-SET-11)

```ts
export const SettingsValueSchema = z.object({
  key: z.string(),                       // "<panelId>.<fieldId>"
  /** The value that is actually in force for this actor, right now. */
  value: z.unknown(),
  /** Which scope the effective value came from. */
  source: SettingsScopeSchema,
  /** True when a wider scope declared it non-overridable. */
  locked: z.boolean(),
  /** The scope that locked it. Null iff `locked` is false. */
  lockedBy: SettingsScopeSchema.nullable(),
}).strict();
```

The four are read together: a panel renders the effective value, states its
source, and where `locked` is true renders the control read-only naming
`lockedBy` rather than accepting an edit it will discard. The algorithm is
`spec/settings.md` §6 — a lock short-circuits before the narrower lookup, so
`source` can never be narrower than `lockedBy`. A write against a locked key is
refused with `settings.locked_by_higher_scope` (422), a path for the API caller
since the UI never offers the control.

## 5. Collision rules A02 enforces at assembly

A collision is a **hard failure** naming both claimants, never last-write-wins
(`contracts/README.md` §3).


| Check | Fails when | Why it is fatal |
|---|---|---|
| Duplicate panel id | Two declarations share `id` | The id is the deep link and the mount key; the second panel would be unreachable and which one renders would depend on collection order |
| Scope / permission namespace | `scope: "global"` with a non-`global.*` `permission`, or a narrower scope with a `global.*` one | `global.*` is a reserved namespace (`rbac.md` §3) and is never grantable to a tenant role. A tenant string on a global panel renders the global scope for a tenant admin — the disclosure REQ-SET-07 exists to prevent |
| Unresolved permission | `permission` or `writePermission` is not in the assembled `rbac` registry | It resolves to deny (REQ-RBA-02), so the panel would ship invisible with no error |
| Missing help topic | `helpTopicId` absent, or not in A16's registry | REQ-DOC-03: a shipped feature without a help topic fails the documentation gate. Help is not a follow-up |
| Field without an i18n key | `labelKey` absent, or outside the declaring agent's `i18nNamespace` | REQ-I18N-02 forbids a user-visible literal; REQ-I18N-05 forbids writing into another domain's namespace |
| Duplicate field id | Two fields in one panel share `id` | The `?f=` anchor and the audit diff key both stop being unique |
| `blastRadius` without a token | `blastRadius: true` and no `confirmToken` | REQ-SET-10 requires a typed confirmation; a checkbox is not acceptable |
| Foreign panel path | A declaration's `component` resolves outside its own package | REQ-CTR-04 — the panel would be a second owner of A05's surface |

```bash
jq -r '.declarations[].settingsPanels[]? | select(.scope=="global")
  | select(.permission | startswith("global.") | not) | .id' \
  build/contract-surface.json && echo "GLOBAL PANEL ON A TENANT PERMISSION"
```

## 6. Storage: `user_preferences` (A05)

A05 owns the table (`contracts/db/schema-ownership.md`). It holds every
`store: "preferences"` value at **two** of the three scopes, told apart by one
nullable column:

```sql
user_preferences (A05)                  -- entity envelope; `comment` exempt (REQ-ENT-01)
  id         uuid primary key,
  tenant_id  uuid not null references tenants(id),   -- the RLS scope (REQ-RBA-03)
  user_id    uuid     references users(id),           -- NULL => this tenant's default
  key        text not null,                           -- "<panelId>.<fieldId>"
  value      jsonb not null,
  locked     boolean not null default false,          -- tenant lock (REQ-SET-11)
  unique nulls not distinct (tenant_id, user_id, key)
```

`user_id IS NOT NULL` is a personal value; `user_id IS NULL` is the tenant
default. One table, one predicate, no second policy to keep in step.
`tenantScoped: true`, justified: every row is either a member's preference or
that tenant's default, and neither means anything outside the tenant. A05
declares the flag and **A04 owns the policy**, as for every tenant-scoped table
(REQ-RBA-04) — A05 writes no SQL under `db/policies/`.

**Global-scope preference defaults are not rows.** A `tenant_id NULL` row is
invisible under `tenant_id = current_setting('app.current_tenant', true)::uuid`
(`contracts/db/rls-contract.md`), so a global default would need a second table
outside RLS and a second read path. It needs neither: the global default of a
preference is the validated env value — `SHELL_DEFAULT_TIMEZONE` and its
siblings (REQ-FND-07) — which is what REQ-TIM-03's "system default" and
REQ-I18N-04's fourth level already mean. Global **policy** settings are not
preferences: they live in the owning domain's tables under `store: "domain"`,
and A05 routes the submit without touching them.

## 7. Additive vs breaking

**Additive**
- A new panel in a domain's own namespace, at any scope; a new field on an
  existing panel; a new optional field on a descriptor; a new `kind`.
- Setting `lockable: true` on a field that was not — it widens what a holder may
  declare and changes no resolved value until a lock is set.

**Breaking**
- Renaming a panel or field `id`. Both are deep-link targets (REQ-SET-12) and
  the audit diff key; a rename breaks every stored link and orphans the stored
  values. Add the new id, deprecate the old.
- Making `confirmToken`, `helpTopicId` or `labelKey` optional.
- Inserting a scope into `SETTINGS_SCOPE_ORDER` anywhere but the widest end, or
  reordering it: every precedence comparison silently changes meaning.
- **Moving a setting between scopes.** This is breaking *and* semantically
  dangerous, and it is the one to refuse hardest. The key `<panelId>.<fieldId>`
  keeps its name while the question it answers changes — "my date format"
  becomes "this tenant's date format". Stored rows do not move with it: a
  personal value promoted to tenant scope is still `user_id IS NOT NULL` and is
  now unreachable by a resolver that looks for the tenant row, and a tenant
  value demoted to personal scope silently becomes one person's. Nothing fails.
  The breaking-change detector sees the same key with the same type
  (REQ-CTR-07), the schema still parses, and the audit diffs still write — while
  every resolved value is quietly wrong for a different population than before.
  This is the change-meaning-under-the-same-name case `contracts/README.md` §5
  calls the worst of all, "because no tool catches it". A setting that must
  change scope gets a **new key at the new scope**, the old key deprecated with
  a removal version, and a stated migration for the stored rows (REQ-CTR-03,
  REQ-CTR-09).
