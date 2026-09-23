# Ownership Map

Every path in the generated app has exactly one owning agent (REQ-CTR-04).
This is the document that makes a 15-wide parallel wave possible: agents do not
coordinate, they do not merge, and they do not negotiate — they write inside
their own paths and read everyone else's work through the frozen contract.

**An agent writing outside its owned paths is a build defect.** The orchestrator
treats it as a failed task and reassigns, rather than accepting the diff.

`<app>` is the app name resolved at intake (REQ-FND-01: `apps/<app-name>/`).

## Root & shared

| Path | Owner | Notes |
|------|-------|-------|
| `package.json`, `pnpm-workspace.yaml`, `turbo.json`, `tsconfig.base.json` | A01 | Version fields are A22's (see below) |
| `docker/**`, `compose.yml`, `compose.dev.yml`, `compose.prod.yml` | A01 | Includes the `edge` HAProxy service (REQ-PROX-01) |
| `docker/haproxy/**`, the generated HAProxy config | A01 | Generated from the same validated config source as the app (REQ-PROX-04). A25 owns only the certificate-install and reload path it shares (REQ-PROX-09, REQ-ACME-13). |
| `.env.example` | A01 | Every agent *declares* its vars; A01 writes the file |
| `packages/config/**` | A01 | The single env schema |
| `packages/crypto/**` | A01 | Envelope encryption, KEK rotation, egress client |
| `packages/contracts/**` | A02 | Frozen at G3. CCR-only afterwards |
| `versions/manifest.json`, `versions/traps.json`, `versions/notes/**` | A20 | |
| `CHANGELOG.md`, `README.md`, `SECURITY.md`, `TODO.md`, `VERSION`, all `version` fields | A22 | No other agent edits these, ever |
| `versions/pricing.json`, `versions/pricing.md`, `build/costs.md` | A26 | The only agent that derives money. It owns no product code and no table. |
| `build/supervision.md`, `build/supervision/**` | A28 | The supervisor. It owns no product path and votes at no gate, and it never finishes a dead agent's work — completing someone else's task hides the failure and takes an ownership violation at the same time (REQ-ORC-02). |
| `scripts/validate/**`, the `validate` / `validate:quick` / `validate:full` scripts | A01 | The one validation entry point (REQ-VAL-01). Written in Wave 0 and green on the empty scaffold before the first domain agent is dispatched. |
| `apps/<app>/app/_build/**` | A01, except `_build/screenshots` (A21) | The build status page, serving from Wave 0 and for the whole build (REQ-LIV-01, REQ-CAP-05). |
| `build/validation/**` | the orchestrator writes the gate records; each agent writes its own `wave-<n>/<agent>.json` | Per-hand-off and per-gate proof that the tree was green (REQ-VAL-12). `req-coverage.md` is A23's, generated (REQ-TST-11). |
| `build/screenshots/**` | A21 | Images, sidecars and `index.json`. The capture feed, not a gate deliverable (REQ-CAP-01 … REQ-CAP-05). |
| `build/navigation.md` | A00 | The resolved menu, derived at G0. G1 cannot start without it: the sidebar is sized to it (REQ-MOC-13, REQ-MOC-14). |
| `resources/**` | nobody | Vendored third-party reference, pinned by `resources/pin.json`. **No agent edits it.** Our conventions do not apply to it and the conformance check skips it (REQ-UI-16). |
| `.github/workflows/**` | A01, except `supply-chain.yml` (A19) | |
| `.gitignore` | A01 | Present from the first commit. It never excludes `build/`, `resources/`, `mockups/` or the self-hosted fonts (REQ-FND-12, REQ-FND-13). |

## Domain packages

| Path | Owner |
|------|-------|
| `packages/auth/**` | A03 |
| `packages/rbac/**`, `packages/tenancy/**`, `db/policies/**` | A04 |
| `packages/screenspace/**` | A05 |
| `packages/theme/**` | A06 |
| `packages/datagrid/**` | A07 |
| `packages/pwa/**` | A09 |
| `packages/canonical/**`, `services/normalizer/**` | A10 |
| `packages/api-kit/**` | A11 |
| `packages/mail/**`, `packages/notify/**`, `templates/**` | A12 |
| `packages/audit/**`, `packages/logging/**`, `packages/syslog/**` | A13 |
| `packages/i18n/**`, `locales/**` | A14 |
| `agents/collector/**` (Rust) | A15 |
| `packages/fixtures/**` | A23 |
| `packages/setup/**` | A24 |
| `packages/acme/**`, `packages/tls/**` | A25 |
| `packages/settings/**` | A05 |
| `packages/editor/**` (Monaco, REQ-MON-01) | A05 |
| `packages/mobile/**` | A27 |

## App routes — the contested surface

Routes are where parallel agents would otherwise collide. They are split by
route group, and **each route group has one owner**:

| Path | Owner |
|------|-------|
| `apps/<app>/app/layout.tsx`, `app/(app)/layout.tsx` | A05 |
| `apps/<app>/app/(auth)/**` | A03 |
| `apps/<app>/app/(app)/admin/**` | A04 |
| `apps/<app>/app/(app)/console/**` | A13 |
| `apps/<app>/app/(app)/api-docs/**` | A11 |
| `apps/<app>/app/(app)/help/**` | A16 |
| `apps/<app>/app/(app)/settings/**` | A05 shell and the three scope surfaces (personal / tenant / global), panels contributed per-domain via `settings-registry` (REQ-SET-08) |
| `apps/<app>/app/(setup)/**` | A24 — the first-run wizard, reachable only while setup is incomplete (REQ-WIZ-13) |
| `apps/<app>/app/api/**` | A11 owns the route kit and the `/api/v1` tree; each domain owns its own subtree under it |
| `apps/<app>/components/shell/**` | A05 |
| `apps/<app>/app/manifest.ts`, `sw.ts` | A09 |

### How a domain adds a page without touching A05's shell

A05 publishes `nav-registry` and a slot contract. A domain agent adds a route
file inside **its own** subtree and a registry entry inside **its own** package.
A05's shell reads the registry at build time. Nobody edits a shared navigation
array — that array does not exist.

The same pattern covers settings panels, command-palette entries, help topic
links and notification categories. A settings panel is the clearest case: A25
contributes the certificate panel from inside `packages/acme/`, declaring its
scope as `global`, and A05's settings shell renders it. A25 never opens a file
under `apps/<app>/app/(app)/settings/`, and A05 never learns what a certificate
is. **Registry, never a shared list** is the rule
that keeps the wave parallel.

## Database schema

Tables are owned, and migrations are namespaced by owner so two agents never
produce a conflicting migration ordinal:

`db/migrations/<agent-id>/<timestamp>__<slug>.sql`

| Table group | Owner |
|-------------|-------|
| `tenants`, `roles`, `permissions`, `role_permissions`, `user_roles`, RLS policies | A04 |
| `users`, `credentials`, `mfa_factors`, `recovery_codes`, `sessions`, `oidc_providers`, `identity_links` | A03 |
| `audit_events`, `audit_chain`, `log_sinks` | A13 |
| `api_keys`, `api_key_scopes` | A11 |
| `push_subscriptions`, `notification_preferences`, `notification_events` | A09 / A12 (A09 owns subscriptions, A12 owns events & preferences) |
| `mail_outbox`, `mail_templates` | A12 |
| `canonical_*`, `mapping_descriptors`, `quarantine`, `provenance` | A10 |
| `collector_agents`, `agent_credentials` | A15 |
| `user_grid_prefs` | A07 |
| `user_preferences` (theme, locale, timezone, format) | A05 |
| `help_topics` | A16 |
| `setup_state`, `setup_steps` | A24 |
| `acme_accounts`, `certificates`, `cert_orders`, `cert_renewal_log`, `dns_providers` | A25 |

A04 owns the RLS policy for **every** tenant-scoped table, including tables it
does not own. A table owner declares `tenantScoped: true` in its contract entry;
A04 generates the policy. This is deliberate: one agent owning all isolation is
how REQ-RBA-04 and REQ-RBA-05 stay provable.

## Gate agents own nothing

C1, C2, S1 and S2 write only to `build/gates/`. They never edit product code —
they produce findings, and the owning agent fixes them (REQ-GAT-07).

`build/` as a whole is orchestrator-owned working state and it is **committed**,
not gitignored. `compliance/cra/obligations-matrix.md` cites
`build/gates/<gate>/<reviewer>-<dimension>-r<round>.json` as the Annex I II(3)
evidence, and `compliance/cra/technical-documentation.md` cites it again as the
Annex VII §6 test report. An auditor cannot check a path that is not in the
repository, so the path is in the repository. `node_modules/`, `.next/` and
`build/screenshots/*.tmp.png` are gitignored; `build/` is the record.

## Conflict resolution

If two agents both believe they own a path, that is a bug in **this file**, not
a negotiation between agents. The orchestrator amends the ownership map, states
the amendment in the build log, and reassigns. Agents never resolve ownership
between themselves.
