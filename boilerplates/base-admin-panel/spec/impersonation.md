# Impersonation

A global operator entering a user's session, seeing what that user sees, and
leaving a trail that says so. It is an authorized account takeover by
construction (REQ-IMP-01), so every control here bounds it.

**A04** owns the semantics — permission model, session object, entry, exit,
refusals: `packages/rbac/**`, `packages/tenancy/**`,
`apps/<app>/app/(app)/admin/**`. **A05** owns the banner
(`apps/<app>/components/shell/**`), registered by `packages/tenancy` as a shell
surface entry — registry, never a shared list. A04 mints no sessions (A03) and
writes no audit rows (A13).

This extends `spec/rbac-tenancy.md` §7, which owns tenancy, RLS and the
REQ-RBA-07 control table; §7 is the frozen statement, this is the design behind
it. `ImpersonationContext` is frozen in `contracts/types/identity.md` §6 and
extended — never redefined — in `contracts/types/impersonation.md`.

## Requirements covered

REQ-IMP-01 … REQ-IMP-12, REQ-RBA-02, REQ-RBA-06, REQ-RBA-07, REQ-AUT-07,
REQ-AUT-10, REQ-AUD-01, REQ-AUD-04, REQ-ENT-04, REQ-MOB-03, REQ-MOB-04,
REQ-SET-09, REQ-SET-10, REQ-TIM-04, REQ-TIM-06, REQ-TST-05.

## 1. The permission model, which is the whole thing (REQ-IMP-02)

The effective set inside an impersonated session is the **target's, exactly**.
Not the operator's. Never the union.

```
effective(session)          = session.permissions
session.permissions at mint = resolve(subject's roles in the entered tenant)
```

The operator's set is read **once**, before the impersonated session exists:
`can(operator, "global.impersonation.impersonate")` plus a fresh step-up (§3).
After the mint it is in scope of no evaluation — not a fallback, not an override.

### The union bug

```ts
// The defect REQ-IMP-02 exists to prevent. One line, and it reads well.
const permissions = [...operator.permissions, ...subject.permissions];
```

It arises naturally, because impersonation gets built as a **decoration of the
request context**: the operator's context is already loaded when the middleware
runs, so the middleware adds the subject on top. Every other middleware in the
stack augments what it receives; this one has to replace it. The degenerate form
is easier still — `Object.assign(ctx, { userId, tenantId })` leaves
`ctx.permissions` untouched, so the effective set is the operator's alone while
every label on screen says the subject's name.

**It is invisible in testing.** The natural test is "impersonate and walk the
app", and it passes completely, because a too-wide set never produces an error:
the operator can do everything, so nothing fails, so nothing is reported. The
only test that catches it asserts an **absence** (§12).

**It makes every audit record from the window a false statement.** A row says
this was done in this account and this permission was satisfied there. Under a
union the second half is untrue for every row, so reconstructing what was
possible in that account — the trail's purpose — returns the wrong answer,
confidently.

### Where it is enforced, server-side

| Layer | What it does | Failure mode covered |
|---|---|---|
| Mint (A04) | Writes the subject's resolved grants onto the new session row; the operator appears only as `impersonated_by` | A merge where the session is created |
| `can()` (A04) | Takes one set, from the session; there is no argument position for a second (`contracts/types/impersonation.md` §5) | A union at evaluation time |
| RLS (A04) | `app.current_tenant` comes from the impersonated session's tenant | A cross-tenant read inside the window |

One RLS rule deserves its own line: **an impersonated session does not set
`app.global_tier`.** The additive cross-tenant `SELECT` policy in
`spec/rbac-tenancy.md` §6 keys on that setting, so inside the window it never
matches and the operator sees the subject's rows — not the subject's rows plus
everything an operator may read. Leaving it set is the same union bug in SQL,
and a permission test never reaches it.

A subject holding a `global.*` grant is peer impersonation, refused before the
mint (§8). A tenant role can never hold one (`contracts/types/rbac.md` §3.1).

## 2. The session model (REQ-IMP-09)

A **distinct session object**, not a mutation of the operator's.

```
sessions (A03)                  -- a new row; the operator's row is untouched
  id = <new>, user_id = subject, tenant_id = the entered tenant
  permissions              = the subject's, resolved at mint (§1)
  impersonated_by          = the operator's user id
  impersonation_expires_at = now() + ttl   the enforced time box
  last_step_up_at          = NULL          and it can never be set (§7)

impersonation_sessions (A04)    -- narrative state, tenantScoped: true
  impersonation_id pk, session_id, operator_session_id,
  operator, subject, tenant_id, reason, ticket, started_at, expires_at,
  status active|exited|expired|revoked, ended_at, ended_by, end_reason,
  approver, approved_at,        -- peer impersonation only (§8)
  return_to                     -- where exit lands the operator
```

Two rows, because A04 may not add a column to A03's table. A03's row carries
what every request checks without a join; A04's carries what is read when
something is decided or shown. `impersonation_sessions` arrives as an additive
CCR against `contracts/db/schema-ownership.md`, and A04 generates its RLS policy
like any other tenant-scoped table.

**The operator's own session is held, alive, alongside** — not revoked, not
superseded, not rewritten. The cookie is re-issued to point at the impersonated
session, which is the rotation `spec/auth.md` §8 requires, but the operator's
row keeps `superseded_by` null, because a superseded row is one nothing can
return to. A request presenting the operator's own session id while the
impersonation is live is refused with `tenancy.impersonation_session_held`
(403); without that, a replayed cookie value is an un-bannered operator session
running beside a bannered one.

**Why mutating the operator's session in place is the design that breaks.**
Overwrite `user_id`, `tenant_id` and `permissions` on that row and exit becomes
a *reversal*: it reconstructs values that were overwritten, from a cookie, a
snapshot column or memory, and every failed reconstruction lands the operator
somewhere wrong — usually logged out (§6). Revocation is worse: killing the
impersonation kills the operator's only session, so a second operator cannot
stop the first without ending their own view of what happened. With a distinct
row, exit is a revoke plus a cookie re-issue.

The impersonated session appears in the operator's session list
(`auth.session.read`, REQ-AUT-10) and in the estate list, where another operator
ends it with `global.auth-session.revoke-any`.

## 3. Entry (REQ-IMP-01, REQ-IMP-04, REQ-AUT-07)

`POST /api/v1/rbac/impersonation`, A04's operation, `stepUp: true`.

| Control | Value | Source |
|---|---|---|
| Permission | `global.impersonation.impersonate` | `contracts/types/rbac.md` §6 |
| Step-up | fresh within **60 s** | `spec/auth.md` §6 |
| Reason | required, 8–500 chars, free text | `identity.md` §6 |
| Time box | 1800 s default, ceiling `RBAC_IMPERSONATION_MAX_SECONDS` ≤ 14400 s | `spec/rbac-tenancy.md` §7 |
| Enabled | deployment env **and** policy row, both on | §10 |

The reason is **typed**, and that word is load-bearing: free text with a minimum
length, never a dropdown of canned reasons. A dropdown makes "Customer support"
the first option, and the trail then records a click that is identical across
every impersonation that ever happens. It is the route's own required `reason`
field, not a tightened `comment` (`contracts/openapi/conventions.md` §5).

The time box is **not extendable**: exit and re-enter, writing a second reason
and a second event pair. An extend button turns a bounded window into an
unbounded one.

Refused before the mint, each audited with `result: "denied"`: the feature
disabled (`tenancy.impersonation_disabled`); a global-tier target without
approval (`tenancy.impersonation_peer_refused`); an impersonation already live
for this operator or this subject (`tenancy.impersonation_active` — one at a
time on each side, so the subject's activity view is never ambiguous about who
was in the account); a suspended tenant (`tenancy.tenant_suspended`); a missing
reason (`tenancy.impersonation_reason_missing`); an unreachable target, which
returns `tenancy.cross_tenant` at **404** like any other
(`contracts/types/errors.md` §4).

`.claude/agents/A04-rbac-tenancy.md` caps `RBAC_IMPERSONATION_MAX_SECONDS` at
3600 and `spec/rbac-tenancy.md` §7 sets 4 h: the spec is the frozen value, the
prompt a pre-freeze draft, as `contracts/types/rbac.md` §4 records for the draft
permission names.

Entry emits `global.impersonation.enter` and the `global.impersonation-started`
notification to holders of `global.audit.read-any`. Peers see an entry happen
rather than reading about it later in a trail nobody opened.

## 4. The audit record already exists (REQ-IMP-03)

REQ-IMP-03 needs no new envelope field. The three that carry it were frozen for
REQ-RBA-07: `actor` = the **subject**, `onBehalfOf` = the **operator**, and
`impersonationId` correlating enter, every event inside, and exit — with
`tenant` the entered tenant and `comment` the typed reason
(`contracts/events/audit-event.md` §1). `contracts/types/identity.md` §6 is the
normative mapping; where prose elsewhere reads it the other way round, §6 wins.
`expiresAt` is not copied onto every event; it is on the
`impersonation_sessions` row that `impersonationId` keys.

What this spec adds is the **invariant**: inside the window `onBehalfOf` and
`impersonationId` are non-null on *every* event, set by the emitter from the
session rather than by call sites. The entity columns go the other way —
`created_by` / `updated_by` hold the **operator**'s actor id (REQ-ENT-04). The
row records who acted; the trail records in whose account.

## 5. The banner (REQ-IMP-05)

Persistent, non-dismissible, on every screen, for the whole session. A05 owns
it; its strings live in the `rbac` i18n namespace.

- **Every screen** includes modals: the banner renders in the topmost layer and
  dialog overlays start beneath it. A dialog covering the banner is a failing
  visual test at 390, 834 and 1440 in both themes (REQ-TST-03).
- **Contents**: the subject's name, the entered tenant, the remaining time, the
  reason on hover or tap, and the exit control (§6).
- **Remaining time** is rendered by `packages/contracts/time` (REQ-TIM-04) in
  the operator's own timezone (`spec/time.md` §5), relative with the absolute
  instant in the title (REQ-TIM-06).
- **Mobile**: sticky at the top so the subject's name is never scrolled away,
  with the exit control duplicated in the action bar inside the thumb arc
  (REQ-MOB-04), ≥ 44×44 px with ≥ 8 px clearance (REQ-MOB-03), never adjacent to
  a destructive action.
- It is **chrome** and is budgeted as chrome: A05 declares a banner delta per
  surface and A21 asserts the impersonating state at each tested breakpoint
  (REQ-UI-10). Over budget is a finding against the budget, not a licence to
  hide the banner.

**Why a toast or a one-time notice fails.** Impersonation is a state that lasts.
Operators are interrupted, open a second tab, come back after lunch, and a
dismissed notice leaves nothing on screen saying whose account this is. An
action taken by an operator who has forgotten they are impersonating is an
unattributed action: the trail puts it in a window nobody was watching, and the
operator later describes it as something the user must have done.

## 6. Exit, expiry and revocation (REQ-IMP-06, REQ-IMP-04)

`DELETE /api/v1/rbac/impersonation`, `stepUp: false` — exit is never harder than
entry. One action from anywhere, because the banner is everywhere. It revokes
the impersonated session, re-issues the operator's cookie from
`operator_session_id`, and lands on `return_to`, the route they were on when
they entered. **Never a login screen.**

Landing logged out breaks the audit thread concretely: the operator
re-authenticates into a *new* session, so actions before and after the window
are joined only by wall-clock time. What happens more often is worse — the
operator does not re-authenticate at all, closes the tab, and the impersonated
session stays alive until the time box lapses.

**Expiry runs the same code path**, deliberately. The first request after
`impersonation_expires_at` fails closed with `tenancy.impersonation_expired`
(403); the response re-issues the operator's cookie and redirects to
`return_to`. A separate expiry path is exercised once a month, and the
rarely-exercised path is the one that lands on login. A login appears only if
the operator's own session has itself expired. **Revocation** by a second
operator holding `global.auth-session.revoke-any` is the same path, answering
`tenancy.impersonation_revoked` (403).

All three emit `global.impersonation.exit` exactly once per `impersonationId`
with `result: "exited" | "expired" | "revoked"` (`spec/rbac-tenancy.md` §7). An
unpaired `enter` is a defect the verify job reports
(`spec/observability.md` §6): an operator who can end a session without an exit
event can act unobserved.

## 7. What is refused inside the window (REQ-IMP-07)

This is the section that turns impersonation from account takeover into a
bounded capability. It is for seeing what the subject sees, not for becoming
them permanently.

| Refused action | Permission it would use | Refusal code | The escalation it would be |
|---|---|---|---|
| Change password | `auth.profile.write`, credential route | `tenancy.impersonation_refused_credential` | The operator sets a secret they know and returns later — no banner, no time box, no trail |
| Change email | `auth.profile.write` | `tenancy.impersonation_refused_credential` | Email is the recovery channel; owning it delivers every future reset to the operator |
| Enrol an MFA factor | `auth.mfa.enrol` | `tenancy.impersonation_refused_mfa` | A factor the operator holds turns a 30-minute window into a standing credential |
| Remove or reset a factor | `auth.identity.unlink`, `auth.mfa.reset` | `tenancy.impersonation_refused_mfa` | Drops the account below policy, onto factors the operator can drive |
| Generate recovery codes | `auth.recovery-code.regenerate` | `tenancy.impersonation_refused_recovery_code` | Ten single-use passwords to the operator, and regeneration invalidates the subject's ten in the same transaction (`spec/auth.md` §7) — the subject is locked out, the operator is not |
| Mint an API key as the subject | `api.key.mint-own` | `tenancy.impersonation_refused_api_key` | A bearer credential with the subject's permissions (REQ-API-04) that outlives the time box and shows no banner to anyone |
| Change roles or assignments | `rbac.role.write`, `rbac.role.assign` | `tenancy.impersonation_refused_role_change` | The account grants itself more, and the trail reads as the subject escalating themselves |
| Start a nested impersonation | `global.impersonation.impersonate` | `tenancy.impersonation_refused_nested` | A second hop with no banner state to unwind and an `impersonationId` that no longer describes one window |

**A structural backstop under the list.** The impersonated session's
`last_step_up_at` is NULL and cannot be set: a step-up is proof of presence by
the account's own credentials, which the operator does not hold. Every step-up
action in `contracts/types/rbac.md` §6 is therefore already unreachable. The
explicit list still matters, because the three most dangerous entries —
password, email, MFA enrolment — are **not** step-up actions in the catalogue.

The impersonation check runs **before** the step-up check, so the answer is
`tenancy.impersonation_refused_*` and not `auth.step_up_required` — the one 403
a client is invited to act on (`contracts/types/errors.md` §4). Answering with
it would tell the operator to re-authenticate and imply a retry would work.

**A refusal is explicit**: 403, the code above, a reason from the `rbac`
namespace, and an audit event with `result: "denied"`, `onBehalfOf` and
`impersonationId` set. Hiding the button is presentation and never the
enforcement point (REQ-RBA-02). A silent no-op is worse than either — the
operator believes the password changed, tells the user so, and the support call
closes on a false statement.

Every operation declares `impersonation: "refused" | "permitted"` in its route
contract and CI fails one that declares neither — the rule that makes `audit`
mandatory with no `audit: null` (`spec/api.md` §2). Everything not listed is
permitted and audited with both identities.

## 8. Peer impersonation (REQ-IMP-08)

**Refused by default** with `tenancy.impersonation_peer_refused` (403), audited.
A target is a peer if they hold any `global.*` grant or a role with
`tier: "global"` — the namespace decides, not the tier index, so `operator`
entering `operator` is as refused as `operator` entering `superadmin`.

A tier that can enter its peers' sessions has no separation of duties left. The
two-person controls elsewhere — revocation by a second operator (§6), an
independent reading of the trail — assume the second person is outside the
first's reach, and one un-approved peer entry collapses them all.

Where the intake enables it (`RBAC_IMPERSONATION_PEER_ENABLED` plus the policy
row, both off by default), entry takes **two operators**. The requester posts
the entry; the row is created `status: "pending_approval"` and no session is
minted. A **different** actor at tier `global_admin` or above, holding
`global.impersonation.impersonate`, approves with their own step-up within 15
minutes, and the mint happens on approval. Both names are on the banner, the
approver is on the `impersonation_sessions` row, and approval emits
`global.impersonation.approve` — an additive event name in A04's namespace. The
catalogue publishes no `global.impersonation.approve` **permission**; the
approver is composed from strings that exist, and adding one is an additive CCR
(`contracts/README.md` §6).

## 9. What the subject sees (REQ-IMP-10)

The subject's own security and activity view — personal settings scope
(REQ-SET-03), gated by `auth.session.read`, filtered server-side to their own
user id — lists every impersonation of their account: who entered, when it
started and ended, how it ended (`exited` / `expired` / `revoked`), the ticket
where one was given, and the stated reason **verbatim**. A reason summarised for
display is a reason the subject cannot quote back.

A capability the subject cannot see is one they cannot challenge. The trail
satisfies an auditor; it does not satisfy the person whose account was entered,
who does not hold `audit.event.read`. If the only record of an operator reading
someone's payroll screen lives in a table that operator's colleagues administer,
the subject has no way to ask about it. The view is read-only and its rows
follow audit retention and legal hold (REQ-AUD-13).

## 10. Enablement (REQ-IMP-11)

**Off by default, behind two locks.**

1. `IMPERSONATION_ENABLED`, A04's env var, parsed at boot (REQ-FND-07), default
   `false`. When false the routes return `tenancy.impersonation_disabled` (403),
   the admin UI is absent, and the policy panel is read-only saying why.
2. The global policy row, default off, changed only at the global settings scope
   with typed confirmation naming the estate it affects (REQ-SET-10) and an
   audited before/after diff carrying `settingsScope: "global"` (REQ-SET-09).

Two locks, because they answer different questions. Some operators are
**contractually unable** to allow impersonation at all — a processor agreement
or a public-sector contract forbidding staff access to customer sessions. For
them the capability must be absent from the deployment, not merely off in a
table anyone holding the policy permission can flip at 02:00.

The policy change needs a permission the frozen catalogue does not publish:
`global.impersonation.admin` (the `admin` verb is in the closed set,
`contracts/types/rbac.md` §2), declared by A04 as an additive CCR. Until it
lands, the env var is the only switch, and it fails closed. A granted permission
with the feature disabled is still refused: enablement is checked at entry, not
at grant time.

## 11. Impersonation and tenant switching

While impersonating, the chooser lists the **subject's** tenants, derived from
the subject's grants (REQ-RBA-10 evaluated against the impersonated session's
actor) — never the operator's. An operator with 300 tenants who enters a user
with one sees no chooser at all (REQ-RBA-12), and that absence is itself the
signal that they are in the subject's world. A switch inside the window switches
the impersonated session, keeps the same `impersonationId` and the same
`expires_at` — the time box does not restart — and is audited with both
identities. `spec/tenant-switching.md` §7 has the rest.

## 12. The test suite (REQ-IMP-12)

It proves the hard parts. The easy one — an operator can enter a session —
passes in every implementation, including every broken one.

| # | Assertion |
|---|---|
| 1 | **The effective set equals the target's and excludes the operator's**: a permission the operator holds and the subject lacks is denied inside the window, at `can()` and at the route |
| 2 | Nor is it the operator's: a permission the **subject** holds and the operator lacks resolves true |
| 3 | `session.permissions` is **set-equal** to the subject's grants — exact comparison, never a superset check |
| 4 | `app.global_tier` is unset: a cross-tenant `SELECT` that succeeds for the operator returns zero rows while impersonating |
| 5 | Each refusal in §7 returns its own code at 403, writes a `denied` audit row and changes no state — asserted against the row |
| 6 | A refusal answers `tenancy.impersonation_refused_*`, never `auth.step_up_required`; `last_step_up_at` cannot be set by any route |
| 7 | Expiry ends the session: the first request after `expires_at` fails closed, emits `exit` with `result: "expired"`, and returns the operator to their own session, not a login screen |
| 8 | Exit restores the operator's permission set and tenant, and the final URL is `return_to`, asserted as a URL |
| 9 | Revocation by a second operator emits `exit` with `result: "revoked"` and the same return |
| 10 | Every event in the window has non-null `onBehalfOf` and `impersonationId` and `actor` equal to the subject; `enter` and `exit` pair on all three exit paths |
| 11 | Entry without a reason, over the ceiling, against a global-tier target, or with `IMPERSONATION_ENABLED=false` is refused, each with its own code |
| 12 | Peer approval by the **same** actor is refused; by a second qualifying actor it mints |
| 13 | The subject's activity view shows operator, both timestamps, status and the verbatim reason |
| 14 | The banner is present on every routed surface including with a dialog open, at 390/834/1440 in both themes, exit control ≥ 44×44 px |

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Effective permissions | The subject's, exactly | REQ-IMP-02; a union is not expressible in `can()` | No |
| Session | A distinct row; the operator's held intact | Exit is a lookup, not a reconstruction | No |
| `app.global_tier` in the window | Unset | Otherwise the cross-tenant read policy is a union by another route | No |
| Step-up in the window | Impossible; `last_step_up_at` stays NULL | The operator does not hold the account's credentials | No |
| Time box | 1800 s default, 14400 s ceiling, not extendable | `spec/rbac-tenancy.md` §7 | Yes, lower only |
| Refusal declaration | Required per operation, no default | An omission must not read as "permitted" | No |
| Peer impersonation | Refused; two-operator approval where enabled | REQ-IMP-08 | Yes, to enable |
| Enablement | Off; env lock plus audited policy row | REQ-IMP-11 | Yes, to enable |
| Concurrency | One live impersonation per operator and per subject | An ambiguous activity view is not a record | No |

## How this is verified

- `pnpm test:permissions` — `tests/impersonation/effective-set.spec.ts`: 1–4,
  the assertions whose absence fails silently in production.
- `pnpm test:integration` — `refusals.spec.ts` (5–6) and `lifecycle.spec.ts`
  (7–9, 11–12) against the two-tenant plus global-operator fixture (REQ-TST-07).
- `pnpm test:audit` — `tests/audit-emission/impersonation.spec.ts`: 10, with the
  unpaired-`enter` case.
- `pnpm test:e2e` — A23's journey: entry, a refusal, a switch, exit, final URL.
- `pnpm test:visual` — A21 captures the banner at 390/834/1440 in both themes
  with a dialog open and asserts the budget delta (14, REQ-UI-10).
- `GET /api/v1/rbac/_selftest` — enablement, the configured ceiling, and the
  count of `enter` events with no matching `exit`.

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| Impersonation at all | Disabled — both locks off (REQ-IMP-11) |
| Who may impersonate | `operator` and above, with the permission and step-up |
| Time box | 1800 s default, 4 h ceiling |
| Peer impersonation | Refused, with no approval path configured |
| Notify the subject in real time | No — the activity view is the record (§9) |
| Write actions in the window | Permitted except §7; every row carries the operator's actor id |
