# Tenant Switching

An actor with access to more than one tenant can move between them. The
semantics are **A04 rbac-tenancy**'s; the chooser UI is **A05 ui-shell**'s, with
its mobile treatment **A27 mobile-ux**'s. Three owners, one behaviour, and the
seam between them is a contract rather than a shared file.

## Requirements covered

REQ-RBA-09, REQ-RBA-10, REQ-RBA-11, REQ-RBA-12, REQ-UI-13, REQ-UI-14, REQ-UI-15,
REQ-RBA-03, REQ-AUD-01, REQ-AUD-04, REQ-MOB-04.

## 1. A switch changes the session, server-side

This is the requirement the whole document exists to protect (REQ-RBA-09).

```
POST /api/v1/tenancy/switch   { tenantId }   → 204, Set-Cookie: rotated session
```

The tenant is then read from the session on every subsequent request, exactly as
REQ-RBA-03 already requires. It is never read from a query string, a header, a
body field, or a client store.

**The bug this prevents, stated plainly:** a chooser that appends `?tenant=<id>`
and an API that honours it. It works perfectly in testing, because in testing
the person switching is entitled to both tenants. It is a horizontal privilege
escalation in production, because the parameter is a client-supplied claim and
the server believed it. RLS does not save you here — the app sets its tenant GUC
from whatever it believes the tenant is, so a forged parameter forges the RLS
predicate too (`contracts/db/rls-contract.md` §3).

The switch endpoint is the **only** place a tenant id is accepted from a client,
and its entire job is to decide whether that claim is true before turning it
into session state.

## 2. The list is derived, not supplied

`GET /api/v1/tenancy/accessible` returns the tenants the **session's actor** can
reach, computed server-side from their grants (REQ-RBA-10). The client renders
what it is given and never filters a longer list down.

Requesting a switch to a tenant outside that set is denied **and audited** — not
merely absent from the UI. A denial that leaves no record is a probe that leaves
no record, and the first thing an attacker does is enumerate.

| Situation | Response | Audited |
|-----------|----------|---------|
| Tenant in the actor's grants | 204, session rotated | `tenancy.switch` with previous and new tenant |
| Tenant exists, actor has no grant | `403` `tenancy.not_accessible` | `tenancy.switch-denied` |
| Tenant does not exist | `403` `tenancy.not_accessible` — **the same response** | `tenancy.switch-denied` |
| Actor is impersonating | Target's grants apply, not the operator's (REQ-IMP-02) | Both identities recorded |

The last two rows of the first column deliberately return the same error. A
distinguishable "no such tenant" turns the endpoint into a tenant-existence
oracle, which is the enumeration primitive for every later attack.

## 3. What a switch must invalidate

A switch is a context change, and **data that survives it is a cross-tenant leak
with a friendly UI** (REQ-RBA-11). Everything below is invalidated before the
new context renders:

| Surviving state | Why it leaks | Action on switch |
|-----------------|--------------|------------------|
| Session cookie | The old session carries the old tenant | Rotate; the old id is dead immediately |
| Client query cache | Holds rows from tenant A keyed by a query that looks tenant-neutral | Clear entirely — not invalidate-and-refetch, clear |
| Open SSE streams (console, notifications) | Server-side filtered on the *old* session (REQ-AUD-08) | Close and reopen after rotation |
| In-flight requests | Will return tenant A's rows into tenant B's screen | Abort; do not render late responses |
| Optimistic mutations | Would apply tenant A's pending write into tenant B | Discard; surface anything unsaved before switching |
| Datagrid preferences | Scoped per grid **and per tenant** (REQ-GRD-08) | Re-read for the new tenant; do not carry over |
| Personal preferences (theme, locale, timezone) | Not tenant-scoped | Keep — they are the user's, not the tenant's |

The last row matters as much as the others: invalidating too much makes the
switch feel like a logout, and a switch that feels like a logout is one people
avoid, which pushes them into a second browser profile and out of the audit
trail.

## 4. One tenant, no chooser

With exactly one accessible tenant there is no chooser, no switch path, and no
disabled control (REQ-RBA-12). A control that cannot do anything teaches people
that controls are decorative, and that lesson transfers to controls that matter.

The endpoints still exist and still enforce — the absence is presentational
only, because an actor's grants can change between page loads.

## 5. The chooser

**Position is part of the requirement** (REQ-UI-13): top-left, directly beneath
the logotype. That is where a multi-tenant operator looks to answer the question
they need answered before acting — *whose data am I about to change* — and
putting it in an avatar menu at the far corner makes that question expensive to
ask.

| Property | Requirement | Why |
|----------|-------------|-----|
| Current tenant legible closed | REQ-UI-14 | The answer must be available without an interaction, or people stop checking |
| Keyboard reachable, type-ahead | REQ-UI-14 | An operator with 200 tenants navigates by typing, not scrolling |
| Scales to a few hundred | REQ-UI-14 | A `<select>` of 400 options is a list, not a chooser: virtualised, searchable, recent-first |
| Confirms before switching when there is unsaved work | §3 | Discarding an optimistic mutation silently is a data-loss bug wearing a UX hat |
| Distinct when impersonating | REQ-IMP-05 | The chooser shows the **target's** tenants, and the banner says whose |

### Mobile (REQ-UI-15, A27)

The meaning survives; the geometry does not. The current tenant stays visible in
the header — it is the same question, and a phone is where people are most
likely to be acting quickly. Switching is reachable within the thumb zone
(REQ-MOB-04) and is not buried behind a nested menu.

Where the header genuinely cannot carry the tenant name at `phone-min`, it
carries a short form with the full name in the sheet — truncation is acceptable,
hiding is not.

## 6. Auditing

Every switch and every denial emits an event carrying **both** the previous and
the new tenant (REQ-AUD-01, REQ-AUD-04). "Switched to Acme" is half a record:
the question an investigator asks is what the actor could see immediately
before, and a record that omits the previous tenant cannot answer it.

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|----------|--------|-----|---------------------|
| Where the tenant lives | Server-side session only | REQ-RBA-03; a parameter is a client claim | No |
| Switch mechanism | `POST /api/v1/tenancy/switch` + session rotation | One place accepts a tenant claim and validates it | No |
| Unknown vs unauthorised tenant | Identical `403` | Prevents a tenant-existence oracle | No |
| Client cache on switch | Cleared, not invalidated | Invalidation leaves rows readable during refetch | No |
| Personal preferences on switch | Preserved | They belong to the user, not the tenant | No |
| Chooser position | Top-left beneath the logotype | REQ-UI-13 | No |
| Chooser at one tenant | Absent, not disabled | REQ-RBA-12 | No |
| Unsaved-work confirmation | On | Silent discard is data loss | Yes |
| Recent-tenants ordering | Most-recent first, then alphabetical | Operators return to the same few | Yes |

## How this is verified

| Requirement | Test |
|-------------|------|
| REQ-RBA-09 | `tests/integration/tenancy/switch-session.spec.ts` — after a switch, assert the new tenant comes from the session; then replay a request with `?tenant=<other>` and assert it is ignored, not honoured. |
| REQ-RBA-09 | `tests/integration/tenancy/no-param.spec.ts` — a route-surface scan asserting **no** route reads a tenant id from query, header or body except the switch endpoint. This is the regression guard; the bug re-enters through a new route, not an edited one. |
| REQ-RBA-10 | `tests/integration/tenancy/accessible-list.spec.ts` — the list equals the actor's grants; a switch to a non-granted tenant returns 403 and emits `tenancy.switch-denied`; an unknown tenant returns the identical body and status. |
| REQ-RBA-11 | `tests/integration/tenancy/switch-invalidation.spec.ts` — seed tenant A data into every store in §3, switch, and assert each is empty. The grid-preference and SSE rows are the ones that regress. |
| REQ-RBA-12 | `tests/e2e/tenancy/single-tenant.spec.ts` — a one-tenant actor sees no chooser in the DOM, not a hidden or disabled one. |
| REQ-UI-13, REQ-UI-14 | `tests/visual/tenant-chooser.spec.ts` — position asserted against the logotype's bounding box; keyboard-only switch completes; a 400-tenant fixture stays interactive and type-ahead narrows it. |
| REQ-UI-15 | A21's touch matrix at all three mobile breakpoints: current tenant visible in the header, switch control inside the thumb zone (REQ-MOB-04). |
| REQ-AUD-04 | `tests/integration/audit/tenant-switch.spec.ts` — both previous and new tenant present on every switch event. |

## Open to intake

| Question | Default if unanswered |
|----------|----------------------|
| Can a non-admin hold grants in more than one tenant? | Yes. The chooser is not an admin feature; it appears for anyone with more than one grant. |
| Expected maximum tenants per actor | 50. Above ~200 the chooser must be virtualised, and A00 records the number so A05 does not discover it from a support ticket. |
| Should a switch require re-authentication? | No. Step-up is for privilege escalation (REQ-AUT-07); a switch moves sideways within existing grants, and requiring re-auth trains people to re-enter credentials on a prompt, which is the phishing behaviour we spend the rest of the product discouraging. |
| Remember the last tenant across sessions? | Yes, as a personal preference. Login lands in the last tenant used, stated in the header. |
