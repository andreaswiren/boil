# Settings Surfaces

Three scopes — personal, tenant, global — one shell, and a registry that lets a
domain add a panel without touching the shell. Owned by **A05** (`ui-shell`):
`packages/settings/**`, `apps/<app>/app/(app)/settings/**`, and the
`user_preferences` table. A05 publishes `settings-registry`; it consumes `rbac`,
`session`, `theme-tokens`, `time` and `i18n`. **Not a new agent:** A05 already
owns the settings shell and the preference store (`contracts/ownership.md`), the
scopes are chrome plus a registry, and each panel's content belongs to the
domain that owns the data — A05 renders a certificate panel without knowing what
a certificate is. An agent for a surface that already has an owner is the
speculative generality `gates/karpathy-lens.md` catches (`spec/agents.md`).

## Requirements covered

REQ-SET-01 … REQ-SET-12 (primary), REQ-RBA-01, REQ-RBA-02, REQ-RBA-06,
REQ-AUT-04, REQ-AUT-05, REQ-AUT-07, REQ-AUD-01, REQ-AUD-04, REQ-AUD-05,
REQ-TIM-03, REQ-TIM-05, REQ-I18N-02, REQ-I18N-04, REQ-DOC-03, REQ-UI-11,
REQ-UI-12, REQ-CTR-01, REQ-CTR-04, REQ-CTR-08.

## 1. Three scopes, and the test that assigns a setting (REQ-SET-02)

| Scope | What it is for | Accountable for a wrong value |
|---|---|---|
| `personal` | How the app looks, reads and formats for one person, plus the factors, sessions and keys on their identity (REQ-SET-03) | That user |
| `tenant` | One tenant's policy, identity and defaults, inside the ceiling the global tier set (REQ-SET-04, REQ-AUT-04) | That tenant's admin |
| `global` | The deployment: cross-tenant policy, the tenant estate, the infrastructure every tenant shares (REQ-SET-05) | The operator running it |

**The test, and it is one sentence:** a setting belongs to the *narrowest* scope
whose holder can be held accountable for the value being wrong.

A date format is nobody's problem but the reader's — personal. Audit retention
is the tenant's legal exposure — tenant. A syslog collector address is one host
shared by every tenant — global. "It was convenient here" is not the test.

When two scopes both look accountable that is not two settings. It is **one
setting at the wider scope with a narrower override** (§6), or a policy at the
wider scope and a preference inside it. MFA is the canonical case: *whether* it
is required is global (REQ-AUT-05), *which* methods satisfy it is tenant
(REQ-AUT-04), *which factors you enrolled* is personal (REQ-AUT-06).

Settings is a first-class navigation entry at every breakpoint, never an item
behind an avatar menu (REQ-SET-01).

## 2. Panel inventory

Two conventions hold across all three tables. **Where a domain publishes no read
string for a resource, the panel renders on its write string** — narrower, never
wider, and deny-by-default makes that safe (REQ-RBA-02); we do not invent a read
permission for symmetry. And **a `global`-scope panel must be gated by a
`global.*` string** (REQ-RBA-06, `contracts/types/rbac.md` §3), or a tenant
admin holding a tenant-namespace string would be shown the global scope — the
disclosure REQ-SET-07 exists to prevent.

`†` marks a string that follows the grammar (REQ-RBA-01) but is not yet in
`contracts/types/rbac.md` §6. Each is an additive declaration by the named owner
(`rbac.md` §8, fast path); a panel whose permission does not resolve in the
assembled registry denies, and so does not render.

### Personal (REQ-SET-03)

| Panel | Panel id | Owner | Renders on | Writes on | Store |
|---|---|---|---|---|---|
| Profile | `auth.profile` | A03 | `auth.profile.read` † | `auth.profile.write` † | domain |
| Theme & appearance | `theme.appearance` | A06 | `shell.preferences.read` | `shell.preferences.write` | preferences |
| Language (REQ-I18N-04) | `i18n.locale` | A05 | `shell.preferences.read` | `shell.preferences.write` | preferences |
| Timezone & date format (REQ-TIM-05) | `time.profile` | A05 | `shell.preferences.read` | `shell.preferences.write` | preferences |
| Notification preferences | `notify.preferences` | A12 | `notify.preference.read` | `notify.preference.write` | domain |
| MFA factors | `auth.mfa-factors` | A03 | `auth.mfa.enrol` | `auth.mfa.enrol` | domain |
| Recovery codes | `auth.recovery-codes` | A03 | `auth.recovery-code.regenerate` | `auth.recovery-code.regenerate` | domain |
| Active sessions | `auth.sessions` | A03 | `auth.session.read` | `auth.session.revoke` | domain |
| Own API keys | `api.keys-own` | A11 | `api.key.read-own` | `api.key.mint-own` | domain |

### Tenant (REQ-SET-04)

| Panel | Panel id | Owner | Renders on | Writes on | Store |
|---|---|---|---|---|---|
| Tenant identity | `tenancy.identity` | A04 | `tenancy.tenant.read` | `tenancy.tenant.write` | domain |
| Branding & theme default | `theme.tenant` | A06 | `tenancy.tenant.read` | `tenancy.tenant.write` | preferences |
| Enabled auth methods | `auth.policy` | A03 | `auth.policy.read` | `auth.policy.write` | domain |
| SMTP sender identity | `mail.sender` | A12 | `mail.sender.write` | `mail.sender.write` | domain |
| Audit retention & legal hold | `audit.retention` | A13 | `audit.retention.read` | `audit.retention.write`, `audit.legal-hold.write` | domain |
| Grid defaults | `grid.tenant-default` | A07 | `grid.prefs.read` | `grid.tenant-default.write` † | preferences |
| Tenant API keys | `api.keys-tenant` | A11 | `api.key.read-any` | `api.key.revoke-any` | domain |

### Global (REQ-SET-05)

| Panel | Panel id | Owner | Renders on | Writes on | Store |
|---|---|---|---|---|---|
| System-wide auth policy | `auth.global-policy` | A03 | `global.auth-policy.mfa-disable` | same | domain |
| Tenant administration | `tenancy.tenants` | A04 | `global.tenant.read-any` | `global.tenant.create`, `.suspend`, `.archive` | domain |
| Global roles | `rbac.global-roles` | A04 | `global.role.write-any` | same | domain |
| SMTP relay | `mail.global-smtp` | A12 | `global.mail-sender.write` | same | domain |
| Syslog forwarding | `audit.global-sink` | A13 | `global.audit-sink.write` † | same, plus `global.audit-retention.write` | domain |
| Certificates (REQ-ACME-16) | `acme.certificates` | A25 | `global.certificate.read` † | `global.certificate.admin` † | domain |
| Normalizer mappings (REQ-DAT-03) | `canonical.mappings` | A10 | `global.normalizer-mapping.read` † | `global.normalizer-mapping.write` † | domain |
| Telemetry posture (REQ-SUP-06) | `supply.telemetry` | A19 | `global.telemetry.read` † | `global.telemetry.admin` † | domain |
| Support & end-of-support dates (REQ-CRA-08) | `compliance.support-window` | A18 | `global.compliance.read` † | `global.compliance.write` † | domain |
| Backup & restore (REQ-CER-03) | `platform.backup` | A01 | `global.backup.read` † | `global.backup.run` † | domain |

**Store** is the descriptor's choice, not the shell's. `preferences` means A05's
`user_preferences` row, written through A05's `PUT /api/v1/shell/preferences`
with the scope in the body — A07 never opens A05's table and A05 never
interprets a density value. `domain` means the owning domain's own table and
operation; A05 renders and routes the submit, and writes nothing (REQ-CTR-04).
Global-scope *preference* defaults are not rows: they are the validated env
values (`SHELL_DEFAULT_TIMEZONE`, REQ-FND-07), which is what REQ-TIM-03's
"system default" and REQ-I18N-04's fourth level already mean.

## 3. Scope is legible before the save, not after (REQ-SET-06)

Four mechanisms, all rendered by the shell from the descriptor so a panel author
cannot omit one:

1. **A scope chip beside every mutating control**, not only in the header:
   `Personal`, `<tenant-slug>`, `Global · all tenants`. Text, not colour alone —
   a colour-only signal fails AA contrast and a colour-blind operator
   (REQ-UI-11).
2. **A distinct surface treatment per scope.** Personal is the default card;
   tenant adds a header band carrying the tenant name; global renders inset with
   a persistent left rail and the destructive accent from `theme-tokens`,
   contrast-checked in both themes.
3. **The affected count inline**, next to the control, before the save:
   "Applies to 312 users in 14 tenants" (§7).
4. **The submit label names the scope**: "Save for all tenants", never "Save".

A heading that says *Global* is insufficient on its own for three concrete
reasons. It is read once on entry while the click happens 800 px further down,
out of view. Panels are deep-linkable (REQ-SET-12), so a user can arrive
mid-panel and never see it. And on a phone the panel is a sheet whose header
scrolls away above the thumb arc holding the primary action (REQ-UI-07). Scope
must be adjacent to the control that commits it.

## 4. Permission gating, and the empty-scope rule (REQ-SET-07)

| Level | Rule |
|---|---|
| Scope | Renders iff at least one of its descriptors passes `can(actor, permission)`. Zero permitted panels means the scope does not exist |
| Panel | Filtered from the registry before render. Absent from the DOM, not hidden by CSS |
| Field | May declare its own permission. Unpermitted fields are omitted |

All three resolve server-side; client filtering is presentation only
(REQ-RBA-02). The two read-only states must not be conflated: **no permission →
the field is absent**; **locked by a higher scope → present, read-only, naming
the scope that locked it** (§6). Absence is "not your business"; locked is "your
business, decided above you". A direct hit on a scope route the actor may not
see returns `common.not_found` (404), not 403 — the reasoning of
`tenancy.cross_tenant` (`contracts/types/errors.md` §4): a 403 confirms the
surface exists.

**Why an empty scope is worse than an absent one.** An empty *Global* tab
advertises a capability the actor does not hold. It reads as a broken build
rather than an access boundary, so it produces a support ticket instead of an
understanding. It discloses the shape of the estate — that a global tier exists,
and roughly what it administers — to an actor holding nothing in it, the same
leak the 404-not-403 rule closes a layer down. And it invites a tenant admin to
ask for the empty tab to be "fixed", which is a privilege-escalation
conversation started by a rendering bug.

## 5. The registry: a domain contributes from its own package (REQ-SET-08)

There is **no shared settings array.** A domain writes a `settingsPanels` entry
in its own `contract.declaration.ts` and a component inside its own package. A02
collects the declarations, applies the collision rules
(`contracts/types/settings-registry.md` §5) and freezes them into
`settings-registry`. A05's shell reads the frozen registry, filters by
permission, and mounts components by scope and order.

```ts
// packages/acme/contract.declaration.ts — A25, never a file under apps/<app>/
settingsPanels: [{
  id: "acme.certificates",
  scope: "global",                          // REQ-SET-05
  agent: "A25",
  permission: "global.certificate.read",    // renders
  writePermission: "global.certificate.admin",
  i18nNamespace: "acme",                    // REQ-I18N-05
  helpTopicId: "settings.certificates",     // REQ-DOC-03
  order: 60,
  blastRadius: true,                        // REQ-SET-10
  store: "domain",
  component: "@app/acme/settings/CertificatesPanel",
}],
```

A25 never opens a file under `apps/<app>/app/(app)/settings/`, and A05 never
learns what a certificate is — it reads ten scalar fields and a component
specifier. Same mechanism as `nav-registry`, command-palette entries, help topic
links and notification categories: **registry, never a shared list**
(`contracts/ownership.md`). It keeps the wide wave parallel, because two agents
adding a panel in the same minute touch two different files (REQ-CTR-04). A
panel component imports `packages/contracts` and its own package, nothing else
(REQ-CTR-01); the boundary lint fails on anything more.

## 6. Precedence and the effective value (REQ-SET-11)

**Personal overrides tenant overrides global, except where a higher scope
declares the value non-overridable.** A lock is a property of the policy, not of
the UI, and the owning domain declares it at the scope that holds it.

```
resolve(key, actor) -> SettingsValue
  g := global value          (policy row, or the env default for a preference)
  if g.locked              -> { value: g.value, source: "global", locked: true }
  t := tenant value for actor.tenantId
  if t exists and t.locked -> { value: t.value, source: "tenant", locked: true }
  p := personal value for actor.id
  if p exists              -> { value: p.value, source: "personal", locked: false }
  if t exists              -> { value: t.value, source: "tenant",   locked: false }
  return                      { value: g.value, source: "global",   locked: false }
```

A lock short-circuits **before** the narrower lookup, so a stored narrower value
can never win over a lock, including one stored before the lock was set. Every
panel shows the **effective value and its source**, phrased as the source rather
than as a state — "Europe/Stockholm — your tenant's default", "Emerald — from
your tenant's default", "Page size 50, from your tenant's default"
(`spec/time.md` §5, `spec/theming.md` §2, `spec/datagrid.md` §7). Where `locked`
is true the control is read-only and carries the lock sentence naming the scope.
A locked control is never a live control that posts and fails: the server still
refuses with `settings.locked_by_higher_scope` (422), but that path is for the
API caller, not the UI's way of telling a user no.

**Worked example — MFA required (REQ-AUT-05), a non-overridable global.**

| Scope | Panel | What the user sees |
|---|---|---|
| global | `auth.global-policy` | `MFA required: on`. Editable by `global.auth-policy.mfa-disable`; turning it off needs the typed literal `DISABLE MFA FOR ALL TENANTS`, step-up and a reason (`spec/auth.md` §5) |
| tenant | `auth.policy` | `MFA required: on`, read-only, "Required by global policy — cannot be changed here". Which *methods* satisfy it stays editable within the global ceiling (REQ-AUT-04); a globally disabled method is refused with `auth.policy_forbidden_by_global` |
| personal | `auth.mfa-factors` | No requirement toggle at all. Enrolment only; unlinking the last factor that satisfies policy is refused with `auth.identity_last_factor` (REQ-AUT-09) |

Disable MFA globally and the tenant control becomes editable, its `source`
flipping from `global` to `tenant` on the next resolve. Any earlier tenant value
was shadowed by the lock, not deleted — which is why the algorithm
short-circuits instead of clearing the narrower row.

## 7. Blast radius and typed confirmation (REQ-SET-10)

| Change | Typed confirmation |
|---|---|
| Any `personal` change | No |
| `tenant` change affecting only the actor | No |
| `tenant` change affecting other members — auth methods, retention, branding, grid defaults | Yes |
| Any `global` write | Yes |
| A `global` write that narrows — disabling a method, shortening retention, revoking estate-wide | Yes, plus step-up (REQ-AUT-07) and a reason of at least 20 characters |

A field is eligible only if its descriptor declares `blastRadius: true`; the
shell then demands confirmation when `affectedCount.users > 1`. The confirmation
states, in order: the setting's name, the **before and after value**, the scope,
the affected tenants named up to ten then `+N more`, the affected user count,
whether it takes effect immediately or at next login, and the token to type. A
checkbox is not acceptable (REQ-AUT-05).

The token is a locale-independent uppercase ASCII literal declared by the field;
`DISABLE MFA FOR ALL TENANTS` is the shipped example. It is a machine token
interpolated into a catalogue message, not copy, so it does not breach
REQ-I18N-02 — a translated token would make the confirmation weaker in Swedish
than in English. A mismatch returns `settings.confirmation_mismatch` (422).

**The count is computed by the owning domain, not the shell** — A05 cannot count
what a certificate renewal affects. The domain implements
`countAffected(scope, change) -> { tenants: TenantRef[], users: number,
effective: "immediate" | "next-login" }`, evaluated server-side against the same
predicate the write will use and under the actor's own permissions, so it never
names a tenant the actor cannot see. It runs twice: for the inline count in §3,
and inside the confirmation. If the two disagree the save is refused with
`settings.blast_radius_changed` (409) — the operator confirmed a sentence
containing a number, and a different number is a different sentence.

## 8. Auditing a settings change (REQ-SET-09)

Every settings write emits the owning domain's own event — `auth.policy.write`,
`tenancy.tenant.write`, `audit.retention.write` — with `kind: "policy"`, the
before/after diff, the permission demanded and the actor (REQ-AUD-01,
REQ-AUD-04). A13 redacts the diff before storage, so a credential changed on an
SMTP panel never reaches the trail in cleartext (REQ-AUD-05). `occurredAt` is
UTC `timestamptz`, rendered only by `packages/contracts/time` (REQ-TIM-04). A
confirmed change also records the token typed, the reason, and `affectedCount`
as confirmed — the record shows what the operator was told, not only what
happened.

**The scope must be a field on the record, not an inference.** A diff alone
cannot answer "was MFA turned off for one tenant or for the estate", which is
the first question after an incident and the difference between a tenant admin
exercising their authority and an operator overriding it. Two identical diffs at
two scopes are two different events; a trail that cannot separate them is not
evidence. REQ-SET-09 therefore needs `AuditEvent.settingsScope: SettingsScope |
null`, which `contracts/events/audit-event.md` §1 does not publish and whose
schema is `.strict()`. A05 files it as an additive optional field on A13's
envelope (`contracts/README.md` §5); until A13 assembles it, no panel satisfies
REQ-SET-09. Both alternatives are worse: encoding the scope into `target.id`
turns a column filter into a prefix match, and a correlated second event doubles
the trail and adds a pairing that can break the way an unpaired impersonation
`enter` does (`spec/rbac-tenancy.md` §7).

## 9. Search, deep links and help (REQ-SET-12)

- **Deep links.** Every panel is a route, `/(app)/settings/<scope>/<panel-id>`;
  a field anchors at `?f=<fieldId>`. Panel ids are unique by assembly, so the
  URL space needs no second registry. A link to a panel the recipient may not
  see resolves to 404, per §4.
- **Search.** A05 builds the index at build time from every descriptor plus its
  fields' i18n keys in every shipped locale, and filters by permission at query
  time — a Swedish operator finds "kvarhållning" and an English one "retention"
  for the same panel. The index holds labels and help text, never values, so it
  cannot disclose content past a permission check. The same entries feed the
  command palette (REQ-UI-12).
- **Help.** `helpTopicId` is mandatory. A panel without one fails assembly, and
  A16 fails the documentation gate on a topic id that does not resolve
  (REQ-DOC-03). Topics are localised and permission-aware (REQ-DOC-04).

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Scope assignment | The narrowest scope whose holder is accountable for a wrong value | One sentence, or the scopes blur within a year | No |
| Two scopes both look right | One setting at the wider scope with a narrower override | Duplicate settings disagree and the UI cannot say which won | No |
| Scope legibility | Chip beside every control, per-scope surface, inline affected count, scope-naming submit label | A heading is off-screen at the moment of the click | No |
| Colour as a scope signal | Never alone | AA contrast and colour blindness (REQ-UI-11) | No |
| Empty permitted scope | Not rendered; a direct route hit is 404 | It leaks the estate's shape and reads as a bug | No |
| Panel contribution | Declaration in the domain's own package; no shared array | REQ-SET-08, REQ-CTR-04 | No |
| Global-scope panel permission | Must be in the `global.*` namespace | A tenant string would render the global scope | No |
| Missing read string | Render on the write string | Narrower, never wider | No |
| Preference store | `user_preferences` at personal and tenant scope, env default at global | A global preference row needs a non-tenant-scoped table and a second RLS branch for nothing | No |
| Domain settings store | The owning domain's table and operation | REQ-CTR-04 | No |
| Precedence | personal > tenant > global, lock short-circuits first | REQ-SET-11 | No |
| Locked control | Read-only, naming the locking scope; the 422 is for API callers | Silently discarding an edit is the failure REQ-SET-11 names | No |
| Confirmation token | Uppercase ASCII literal declared by the field | A translated token is weaker in one locale | No |
| Affected count | Computed by the owning domain, twice, under the actor's permissions | The shell cannot count another domain's rows | No |
| Audit scope | `AuditEvent.settingsScope`, additive on A13's envelope | Two identical diffs at two scopes are two different events | No |
| Panel order | `order` hint, ties broken by panel id ascending | A nondeterministic order fails the visual diff | Yes |

## How this is verified

- `pnpm test:contract` — `packages/contracts/tests/settings-registry.spec.ts`
  (REQ-CTR-10): every descriptor parses; no duplicate panel id; every permission
  resolves in the assembled `rbac` registry; every `global`-scope panel carries a
  `global.*` string; every panel has a `helpTopicId`; every field has an i18n key
  in its declaring agent's namespace; a collision names both claimants.
- `pnpm test:permissions` — `tests/permission-denial/settings/**` (REQ-TST-05):
  a panel requested without its permission is absent from the payload; a scope
  with zero permitted panels is absent and its route returns 404; a write holding
  only the read permission returns 403.
- `pnpm test:unit` — `tests/unit/settings/**`: the §6 algorithm against a table of
  (global, tenant, personal, lock) inputs including a stored personal value under
  a global lock; source labelling; token matching including case and whitespace.
- `pnpm test:e2e` — `tests/e2e/settings/**`: the §6 MFA example at all three
  scopes; a locked control is read-only and never posts; a save with a stale count
  returns `settings.blast_radius_changed`; a field deep link focuses the field;
  search finds a panel by its `sv` label.
- `pnpm test:visual` — `tests/visual/settings.spec.ts` (REQ-TST-03): every scope
  at 390/834/1440 in light and dark; the scope chip in the viewport alongside the
  submit control at 390; AA contrast on the global treatment in both themes.
- `pnpm test:audit` — `tests/audit-emission/settings/**`: every panel's write
  emits `kind: "policy"` with a redacted diff and `settingsScope` equal to the
  panel's scope; a confirmed change records the token, reason and `affectedCount`.
- `pnpm lint:boundaries` — no panel component imports a package other than
  `packages/contracts` and its own (REQ-CTR-01).
- `GET /api/v1/shell/_selftest` — the registry is non-empty, every component
  resolves, every `helpTopicId` resolves against A16's registry, and every
  declared scope has at least one panel (REQ-CTR-08).

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| Are all three scopes present | Yes. A single-tenant deployment still renders tenant and global, because the global tier exists (REQ-RBA-06) |
| May a tenant lock a setting against personal override | Yes, per field, where the owning domain declares the field lockable |
| Which tenant settings are locked by default | None. The global tier locks only `mfaRequired` (REQ-AUT-05) |
| Typed confirmation at tenant scope | Required where the change affects other members |
| Panel order within a scope | The `order` hints declared per §2 |
| Settings search in the command palette | On (REQ-UI-12) |
