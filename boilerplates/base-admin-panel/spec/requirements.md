# Base Admin Panel — Requirement Register

Every requirement has a stable ID. **Nothing in this boilerplate may reference a
requirement by prose alone** — agents cite `REQ-xxx-nn`, gates verify by ID, and
`spec/traceability.csv` maps every ID to an owner agent, a contract, and a gate.

Status values: `MUST` (release-candidate blocking), `SHOULD` (blocking unless the
intake explicitly waives it), `OPT` (enabled per intake answer).

Waivers are recorded in `build/waivers.md` with the intake answer that granted
them. A `MUST` cannot be waived; the build fails instead.

---

## FND — Foundation & platform

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-FND-01 | MUST | Monorepo layout even for a single app. Apps live at `apps/<app-name>/`, shared code at `packages/<name>/`. |
| REQ-FND-02 | MUST | pnpm workspaces + Turborepo task graph. One lockfile at the root. |
| REQ-FND-03 | MUST | Next.js App Router, React Server Components, TypeScript `strict` with `noUncheckedIndexedAccess`. |
| REQ-FND-04 | MUST | Docker Compose is the run target: `app`, `db` (PostgreSQL), `smtp-relay`, `edge` (HAProxy — REQ-PROX-01). Dev and prod compose files share a base. |
| REQ-FND-05 | MUST | PostgreSQL is the only datastore. No secondary state store that survives a restart. |
| REQ-FND-06 | MUST | All dependency versions come from `versions/manifest.json`, externally validated (REQ-VER-01). |
| REQ-FND-07 | MUST | Config is env-var driven, parsed and validated at boot by a single Zod schema. Boot fails loudly on a missing or malformed value — never a silent default for a security-relevant key. |
| REQ-FND-08 | MUST | No secret in the image, the repo, or a client bundle. Secrets arrive via env or a mounted file and are redacted from every log sink. |
| REQ-FND-09 | MUST | Reproducible build: pinned base images by digest, `--frozen-lockfile`, deterministic `NEXT_BUILD_ID`. |
| REQ-FND-10 | MUST | Health endpoints: `/api/health/live`, `/api/health/ready` (checks DB, migrations, SMTP, syslog sink). |
| REQ-FND-11 | MUST | The stack is **self-sufficient**. On a clean host with a domain pointed at it, `docker compose up` alone yields a working HTTPS deployment — edge terminating TLS, certificate provisioned, migrations applied, app serving. No PaaS, no external orchestrator, no reverse proxy installed by hand, no manual step between the command and a login page. A deployment platform may sit on top of this, and several are documented, but none is required. |

## CTR — Contracts & parallel-build discipline

These are the requirements that make the multi-agent build possible. They are
about the *process* as much as the product, and they are `MUST` because breaking
one of them stalls every agent at once.

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-CTR-01 | MUST | A single contract package, `packages/contracts`, is the only cross-domain coupling. Two domains never import each other directly. |
| REQ-CTR-02 | MUST | The contract package is frozen at gate G3 before parallel work begins. After the freeze it changes only through a Contract Change Request (CCR). |
| REQ-CTR-03 | MUST | Contract changes are **additive only**. A shipped type, field, permission string, error code, event name, i18n namespace or API operation is never edited or removed in place — a new one is added and the old one deprecated with a removal version. |
| REQ-CTR-04 | MUST | Every file in the repository has exactly one owning agent, declared in `contracts/ownership.md`. An agent writing outside its ownership is a build defect, not a merge conflict. |
| REQ-CTR-05 | MUST | Domains consume each other through generated clients and contract fixtures, never through a running instance of the other domain. No agent waits for another agent to finish. |
| REQ-CTR-06 | MUST | Contract fixtures are generated from the contract, so a fixture cannot drift from the schema it stands in for. |
| REQ-CTR-07 | MUST | A breaking-change detector runs on the contract package on every commit and fails the build on a removed or narrowed member. |
| REQ-CTR-08 | MUST | Every domain publishes a health/self-test route proving it satisfies its side of the contract, so integration failures localise to one owner. |
| REQ-CTR-09 | MUST | A CCR that genuinely needs a breaking change is arbitrated by the orchestrator, versioned (`v1` → `v2`), and both versions are served through a stated deprecation window. |
| REQ-CTR-10 | MUST | Interface tests belong to the contract, not to either side, and both the producer and the consumer run them. |

## SEC — Encryption, transport & hardening

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-SEC-01 | MUST | Every byte that enters or leaves the server is encrypted in transit. No cleartext ingress or egress on any interface, including inside the compose network. |
| REQ-SEC-02 | MUST | TLS 1.3 preferred, TLS 1.2 floor with an AEAD-only cipher list. HSTS with `includeSubDomains; preload`. HTTP exists only to 308 to HTTPS. |
| REQ-SEC-03 | MUST | Postgres connections use `sslmode=verify-full` with a pinned CA. The compose stack ships its own dev CA and refuses to start the app against a non-TLS database. |
| REQ-SEC-04 | MUST | SMTP egress requires implicit TLS (465) or mandatory STARTTLS with certificate verification. `STARTTLS optional` is not a supported configuration. |
| REQ-SEC-05 | MUST | Syslog forwarding uses RFC 5425 TLS (or DTLS). Plain UDP/514 is not a supported configuration. |
| REQ-SEC-06 | MUST | Application-level encryption at rest for sensitive columns (TOTP seeds, recovery codes, OIDC client secrets, API key material, SMTP credentials) via an envelope scheme with a rotatable KEK. |
| REQ-SEC-07 | MUST | Secrets are stored as hashes where verification is enough: Argon2id for passwords, SHA-256 of a high-entropy token for API keys, Argon2id for recovery codes. |
| REQ-SEC-08 | MUST | Strict CSP with per-request nonces and no `unsafe-inline`/`unsafe-eval`. Plus `Referrer-Policy`, `X-Content-Type-Options`, `Permissions-Policy`, `Cross-Origin-Opener-Policy`, `Cross-Origin-Resource-Policy`. |
| REQ-SEC-09 | MUST | Session cookies: `HttpOnly`, `Secure`, `SameSite=Lax` (session) / `Strict` (privileged), `__Host-` prefix, rotated on privilege change. |
| REQ-SEC-10 | MUST | Origin-checked double-submit CSRF protection on every state-changing route, including Server Actions. |
| REQ-SEC-11 | MUST | Per-identity and per-IP rate limits on auth, API-key, password-reset and export routes, with lockout backoff and an audit event per trip. |
| REQ-SEC-12 | MUST | Every external outbound call goes through one egress client that enforces TLS verification, a timeout, an allowlist, and SSRF guards (no link-local, no loopback, no private ranges unless allowlisted). |

## AUT — Authentication & MFA

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-AUT-01 | MUST | Username + password + OTP (TOTP, RFC 6238) as a first-class method. |
| REQ-AUT-02 | MUST | Passkeys (WebAuthn level 2, resident keys, user verification required) as a first-class method. |
| REQ-AUT-03 | MUST | OIDC federation with three validated providers: Microsoft Entra ID, Authentik, Keycloak. Authorization Code + PKCE, `state` and `nonce` enforced, discovery-document driven. |
| REQ-AUT-04 | MUST | Per-tenant and global policy to enable/disable each method independently. A tenant admin cannot enable a method the global tier has disabled. |
| REQ-AUT-05 | MUST | MFA is required by default. Turning it off is an explicit, audited, global-tier-only policy change with a typed confirmation. |
| REQ-AUT-06 | MUST | Recovery codes are generated at the moment a user enrols any MFA factor: 10 single-use codes, shown exactly once, stored Argon2id-hashed, with a regenerate flow and a consumed-code audit event. |
| REQ-AUT-07 | MUST | Step-up re-authentication for privileged actions (role change, tenant creation, API key mint, policy change, export). |
| REQ-AUT-08 | MUST | Login screen is built from the shadcn `login-02` block (REQ-UI-02). |
| REQ-AUT-09 | MUST | Account linking: one identity may hold several methods; unlinking the last factor that satisfies policy is refused. |
| REQ-AUT-10 | MUST | Sessions are server-side and revocable. A user sees their active sessions and can kill them; an admin can kill a tenant's. |

## RBA — RBAC, tenancy & the global tier

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-RBA-01 | MUST | Role-based access control with roles composed of fine-grained permissions, expressed as `<domain>.<resource>.<action>` strings in `packages/contracts`. |
| REQ-RBA-02 | MUST | Permission checks are deny-by-default and evaluated server-side. Client-side gating is presentation only and never the enforcement point. |
| REQ-RBA-03 | MUST | Multi-tenant. Every tenant-scoped row carries `tenant_id`, and the tenant is derived from the session server-side — never from a request parameter. |
| REQ-RBA-04 | MUST | PostgreSQL Row Level Security is enabled and `FORCE`d on every tenant-scoped table. The app connects as a non-owner role that cannot bypass RLS. |
| REQ-RBA-05 | MUST | Tenant isolation is proven by test, not by inspection: a cross-tenant read/write attempt per table returns zero rows / raises. |
| REQ-RBA-06 | MUST | A global tier above tenants — MSP operators, global admins, superadmins — with system-wide administration, its own permission namespace, and mandatory step-up auth. |
| REQ-RBA-07 | MUST | Global-tier impersonation or tenant-entry is time-boxed, reason-required, banner-visible to the operator, and audited on both entry and exit. |
| REQ-RBA-08 | MUST | Role and permission changes are versioned and audited with a before/after diff. |
| REQ-RBA-09 | MUST | Where an actor has access to more than one tenant, they can switch between them. Switching **changes the session**, server-side. It never becomes a request parameter, a query string or a header — REQ-RBA-03 holds during and after a switch, and a chooser that passes a tenant id to the API is the exact bug that requirement exists to prevent. |
| REQ-RBA-10 | MUST | The tenant list offered is derived server-side from the actor's own grants. A tenant the actor cannot reach is never in the list, and asking for one anyway is denied and audited, not merely absent from the UI. |
| REQ-RBA-11 | MUST | A switch rotates the session, invalidates cached tenant-scoped data in the client, and is audited with both the previous and new tenant. Data from the previous tenant must not survive the switch in any cache, store or open stream. |
| REQ-RBA-12 | MUST | With exactly one accessible tenant there is no chooser and no switch path, because a control that cannot do anything is a control that teaches people to ignore controls. |

## IMP — Impersonation

A global operator can enter a user's session and see what that user sees. This
is the most dangerous capability in the product: it is, by construction, an
authorized account takeover. These requirements exist so it is auditable,
bounded, and cannot quietly become privilege escalation.

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-IMP-01 | MUST | A global-tier operator with the impersonation permission can enter the session of a specific user and see the application exactly as that user sees it — their tenant, their navigation, their data, their permitted actions. |
| REQ-IMP-02 | MUST | The effective permission set during impersonation is the **target's, exactly** — not the operator's, and never the union of the two. The union is the defect this requirement exists to prevent: it silently grants the operator's powers inside the target's account and makes every audit record a lie about what was possible. |
| REQ-IMP-03 | MUST | The audit trail records both identities on every event: the operator as actor, the target as on-behalf-of (REQ-AUD-04). No action taken while impersonating is attributable to the target alone. |
| REQ-IMP-04 | MUST | Impersonation is time-boxed with a stated maximum, requires a typed reason at entry, and is audited on entry **and** exit (REQ-RBA-07). Expiry ends the session rather than extending it silently. |
| REQ-IMP-05 | MUST | A persistent, unmissable banner is visible on every screen for the whole session, naming the target, the remaining time, and carrying the exit control. It is not dismissible, and it is not a toast. |
| REQ-IMP-06 | MUST | Exit is always one action from anywhere, and returns the operator to their own session — never to a logged-out state, which is how operators end up re-authenticating and losing the audit thread. |
| REQ-IMP-07 | MUST | Actions that would escalate or conceal are refused during impersonation, with a stated reason rather than a silent failure: changing the target's password or email, enrolling or removing their MFA factors, generating recovery codes, minting an API key as them, changing their roles, or starting a nested impersonation. Impersonation is for seeing what they see, not for becoming them permanently. |
| REQ-IMP-08 | MUST | Impersonating another global-tier operator is refused by default. Where an intake explicitly enables it, it requires a second operator's approval, because a tier that can enter its peers' sessions has no separation of duties left. |
| REQ-IMP-09 | MUST | The impersonated session is a distinct, revocable session object. It appears in the operator's session list, is revocable by another global operator mid-flight, and never merges with or replaces the operator's own session. |
| REQ-IMP-10 | MUST | The target can see that they were impersonated: their own security/activity view shows who entered their account, when, for how long, and the stated reason. A capability the subject cannot see is one they cannot challenge. |
| REQ-IMP-11 | MUST | Impersonation is disabled by default and enabled per deployment, and enabling it is an audited global-tier policy change. Some operators are contractually unable to allow it at all. |
| REQ-IMP-12 | MUST | A dedicated test suite proves the hard parts rather than the easy one: that the effective permission set equals the target's and excludes the operator's, that each refusal in REQ-IMP-07 actually refuses, that expiry ends the session, that exit restores the operator's own permissions, and that every action carries both identities. |



## ENT — Entity conventions

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-ENT-01 | MUST | Almost every entity extends the base envelope: `comment`, `created_at`, `created_by`, `updated_at`, `updated_by`, `deleted_at`, `deleted_by`. Exemptions are enumerated in `contracts/types/entity-base.md` and justified there. |
| REQ-ENT-02 | MUST | Deletion is soft by default. Hard delete is a separate, global-tier permission with its own audit event. |
| REQ-ENT-03 | MUST | The envelope is enforced by migration lint, not by convention: CI fails on a table lacking the columns and not listed as exempt. |
| REQ-ENT-04 | MUST | `created_by`/`updated_by`/`deleted_by` are set from the request's actor context by a single data-access layer, never passed in by a caller. |
| REQ-ENT-05 | MUST | Every list and detail read filters `deleted_at IS NULL` unless the caller holds the permission to see deleted rows. |

## UI — Interface, layout & space

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-UI-01 | MUST | shadcn/ui, `dashboard-01` block as the dashboard baseline. |
| REQ-UI-02 | MUST | shadcn `login-02` block as the login baseline. |
| REQ-UI-03 | MUST | Layout and navigation conventions follow `arhamkhnz/next-shadcn-admin-dashboard` as the reference implementation (see `spec/baseline.md`). |
| REQ-UI-16 | MUST | The baseline is **pinned and vendored**, never fetched: `spec/baseline-ref/` holds the convention-bearing files verbatim at one recorded commit, with a SHA-256 per file and the upstream MIT notice. A reference that can change is not a reference — the live demo is redeployed and `main` advances, so a build measured against a URL is measured against something the register never described. Moving the pin is a recorded decision with a reason in `CHANGELOG.md`, and `src/` is never edited: editing it turns the reference into a fork and silently changes what every gate compares to. |
| REQ-UI-04 | MUST | Theme preset `b2CjxkL2O` with base `radix`: style `mira`, baseColor `mist`, theme `emerald`, chart `emerald`, font `montserrat`, radius `small`, menuAccent `bold`. |
| REQ-UI-05 | MUST | Full in-app theming at parity with the shadcn theme generator: every knob the generator exposes (style, base colour, theme colour, chart colour, icon library, font, heading font, radius, menu accent, menu colour) is editable, previewable and persistable in-app. |
| REQ-UI-06 | MUST | Dark, light and system theme modes, with no flash of wrong theme on first paint. |
| REQ-UI-07 | MUST | A genuine mobile design — not a narrowed desktop. Bottom navigation, sheet-based detail, thumb-reachable primary actions, 44px minimum touch targets. |
| REQ-UI-08 | MUST | A genuine desktop design — density-first, keyboard-first, multi-pane where it earns the space. |
| REQ-UI-09 | MUST | Screenspace is measured, not assumed: a runtime measurement layer reports viewport, safe-area insets, visual-viewport (keyboard) offset, container sizes and available content height. |
| REQ-UI-10 | MUST | Declared space budgets per surface (chrome vs content) are asserted in visual tests at each named breakpoint; a surface spending more chrome than its budget fails the gate. |
| REQ-UI-11 | MUST | Keyboard-complete and screen-reader-sane: visible focus, logical order, labelled controls, WCAG 2.2 AA contrast in both themes. |
| REQ-UI-12 | MUST | Command palette (⌘K) covering navigation, entity search and permitted actions. |
| REQ-UI-13 | MUST | The tenant chooser sits in the **top-left, directly beneath the logotype**, and appears only when the actor can reach more than one tenant (REQ-RBA-12). Position is part of the requirement: it is where a multi-tenant operator looks to answer "whose data am I about to change". |
| REQ-UI-14 | MUST | The chooser states the current tenant at a glance without being opened, is keyboard-reachable and type-ahead searchable, and stays usable at a few hundred tenants — a plain `<select>` of 400 options is not a chooser. |
| REQ-UI-15 | MUST | On mobile the chooser keeps its meaning without keeping its geometry: the current tenant stays visible in the header and switching is reachable within the thumb zone (REQ-MOB-04). It is not hidden behind a nested menu, because it answers a question the user needs before acting. |

## MON — Code & text editing surfaces

Anywhere the app lets a human edit text that has a grammar — a mapping
descriptor, an email template, a policy document, a config value — it is the
same editor, behaving the same way. A second editor with different keybindings
and no validation is how a product teaches people not to trust it.

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-MON-01 | MUST | Monaco is the base for every text-editing surface in the app. There is one editor component; a `<textarea>` for structured content is a defect, not a simplification. |
| REQ-MON-02 | MUST | Syntax highlighting, bracket matching, folding and a diff view for every supported language, driven by a declared language id rather than guessed from content. |
| REQ-MON-03 | MUST | **Formatting is active for every supported file type** — format on demand, format on save, and a stated default for format-on-type per language. The supported set and its formatter are declared in one registry, not spread across call sites. |
| REQ-MON-04 | MUST | Initial supported languages: JSON, YAML, SQL, Markdown, TypeScript/JavaScript, HTML, CSS, XML, and plain text. Adding a language is a registry entry plus its formatter, never a new editor. |
| REQ-MON-05 | MUST | Schema-aware validation where a schema exists — mapping descriptors validate against `normalizers/descriptor.schema.json` (REQ-DAT-07) and surface errors inline with the offending line, not as a toast after save. |
| REQ-MON-06 | MUST | Monaco and its workers are **self-hosted**. No CDN loader, no remote worker fetch, no remote font (REQ-SUP-07). The editor works with the container offline from the public internet. |
| REQ-MON-07 | MUST | Lazy-loaded and code-split. Monaco is large, and a route that does not edit text does not pay for it. Its weight is asserted in the bundle budget, not assumed. |
| REQ-MON-08 | MUST | The editor theme is derived from the app's design tokens (REQ-UI-04, REQ-UI-05) for both light and dark, and follows a theme change without a reload. A Monaco default theme beside a themed app is a visible seam. |
| REQ-MON-09 | MUST | Accessible: keyboard-complete, screen-reader mode available and discoverable, visible focus, and a documented way out of the editor's tab trap. An editor that swallows Tab with no escape fails REQ-UI-11. |
| REQ-MON-10 | MUST | **Monaco is not used on touch-primary viewports.** Below the declared breakpoint the same surface renders a reduced editor — syntax-highlighted, validated, scrollable, but not Monaco — or is read-only with a stated reason. Shipping a desktop code editor to a phone and calling it responsive is the failure REQ-UI-07 exists to prevent. |
| REQ-MON-11 | MUST | Editor content is subject to the same redaction and permission rules as any other surface (REQ-AUD-05, REQ-RBA-02). A secret does not become visible because it is inside a config document. |
| REQ-MON-12 | MUST | Every edit through the editor emits an audit event with a before/after diff (REQ-AUD-01, REQ-AUD-04). The diff is the editor's natural output, so there is no excuse for a weaker record here than anywhere else. |

## MOB — Mobile experience

`REQ-UI-07` demands a genuine mobile design rather than a narrowed desktop. That
requirement has been in the register since 0.1.0 and has had no dedicated owner:
the shell agent owned desktop and mobile together, which is precisely the
arrangement that produces a narrowed desktop. These requirements and agent A27
exist to fix that.

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-MOB-01 | MUST | Mobile has a dedicated owner (A27) who owns the mobile primitives and the mobile half of every surface budget. Mobile is not a breakpoint someone gets to at the end. |
| REQ-MOB-02 | MUST | A published set of mobile primitives every domain consumes: bottom navigation, sheet, action bar, thumb-reach zones, safe-area insets, pull-to-refresh where it is meaningful, and the keyboard-avoidance container. Domains compose these; they do not invent their own. |
| REQ-MOB-03 | MUST | Touch targets are at least 44×44 CSS px with at least 8px between adjacent targets, asserted by test at every mobile breakpoint rather than eyeballed. |
| REQ-MOB-04 | MUST | Primary actions sit in the thumb-reachable zone. A destructive action does not sit adjacent to a frequent one, because on a phone the miss distance is a thumb width. |
| REQ-MOB-05 | MUST | The on-screen keyboard is treated as a first-class layout event via `visualViewport` (REQ-UI-09): the focused field stays visible, the submit action stays reachable, and no fixed element covers the input. |
| REQ-MOB-06 | MUST | Correct input affordances per field — `inputmode`, `enterkeyhint`, `autocomplete`, `type` — so the right keyboard appears and autofill works. A numeric field that opens a QWERTY keyboard is a defect. |
| REQ-MOB-07 | MUST | Gestures never conflict with the platform's own. No horizontal swipe that fights the browser's back gesture at a screen edge, no pull-to-refresh that fires mid-scroll, and every gesture has a visible non-gesture equivalent. |
| REQ-MOB-08 | MUST | Navigation depth is bounded and every screen states where it is. A phone has no breadcrumb bar to fall back on, so a user four levels deep must still be able to get out in one action. |
| REQ-MOB-09 | MUST | Long-running and offline states are designed, not defaulted: an action started on a flaky connection shows its state, survives a backgrounded tab, and never silently double-submits (REQ-PWA-01). |
| REQ-MOB-10 | MUST | Orientation and small-height viewports are supported, including landscape phones where vertical space is scarce and a keyboard leaves very little of it. |
| REQ-MOB-11 | MUST | The mobile surfaces are verified on a real engine at the declared viewports with touch emulation enabled, in both themes (REQ-TST-02, REQ-TST-03). A desktop browser narrowed to 390px does not exercise touch targets, the on-screen keyboard, or safe-area insets. |
| REQ-MOB-12 | MUST | Where a surface is genuinely unsuitable for a phone — a dense editor (REQ-MON-10), a wide comparison view — the mobile experience says so and offers the useful subset, rather than shipping an unusable rendering and calling it responsive. |

## ORC — Fleet supervision

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-ORC-01 | MUST | The orchestrator checks in on every dispatched agent on a fixed interval of **at most 5 minutes**, and never simply waits for a wave to return. A wave dispatched and then left alone is a wave whose failures are all discovered at the end, at the cost of the whole wave. |
| REQ-ORC-02 | MUST | A dedicated supervisor agent (`A28`) runs for the duration of every wave alongside the orchestrator. It writes no product code, owns no product path and votes at no gate (REQ-GAT-07). Its only job is to keep the wave alive: watch each agent, classify what went wrong, revive it, and escalate when reviving stops working. |
| REQ-ORC-03 | MUST | A non-responding agent is **classified before it is retried**, because retry is the correct remedy for only one of the classes: `hard-stop` (rate limit, spend limit, auth failure — the runtime refused, so wait and re-dispatch), `stall` (dispatched, no output for two consecutive check-ins — re-dispatch), `partial` (files written, no hand-off — reconcile, see REQ-ORC-04), `malformed` (hand-off returned but missing required artefacts — re-dispatch with the gap named). A retry loop that does not classify turns a spend limit into ten spend limits. |
| REQ-ORC-04 | MUST | **A partial landing is reconciled, never accepted.** An agent that dies after writing some of its files leaves a tree that looks like progress and reads like completion. The supervisor diffs what landed against the agent's declared file list, and either resumes from the gap or re-dispatches the whole agent. It never marks a partial result done, and never lets the next wave consume it. |
| REQ-ORC-05 | MUST | Re-dispatch is idempotent. Every agent brief states its complete file list, so a re-run overwrites its own outputs and touches nothing else (REQ-CTR-04). An agent whose second run would append, duplicate or half-merge is a build defect to fix in the brief, not a hazard to work around. |
| REQ-ORC-06 | MUST | Every check-in is appended to `build/supervision.md` with its timestamp, each in-flight agent's state, and the action taken. A wave that "went fine" with no record is indistinguishable from a wave nobody watched, and the second one is what actually happened most of the time. |
| REQ-ORC-07 | MUST | After three failed revivals of the same agent the supervisor escalates to the human with the classification, what was tried and what it recommends, rather than looping (the bound in REQ-GAT-05 applies to revival as it does to critique). |
| REQ-ORC-08 | MUST | The check-in carries the running token cost per agent, so the cost table is current at every gate rather than reconstructed at the end (REQ-COST-01, REQ-COST-03). An agent that died is also an agent that spent. |


## MOC — Mockup & approval phase

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-MOC-01 | MUST | The first build phase produces mockups and screenshots for human approval before production code is written. |
| REQ-MOC-02 | MUST | Exactly 10 mockup designs, differentiated by **layout**, not by palette. Each names the layout thesis it is testing. |
| REQ-MOC-03 | MUST | Each of the 10 is rendered at mobile (390px), tablet (834px) and desktop (1440px) and screenshotted. |
| REQ-MOC-04 | MUST | Screenshots are presented in the chat response, not only written to disk. |
| REQ-MOC-05 | MUST | No production UI code is written until a human names the winning layout (or a hybrid of named ones). The approval is recorded in `build/approvals.md`. |
| REQ-MOC-06 | MUST | Mockups are real rendered HTML at the chosen theme, not drawings — they must be honest about typography, density and control sizes. |
| REQ-MOC-07 | MUST | **Mockups are built in the shipping stack**: a runnable Next.js workspace with Tailwind and shadcn/ui at the configured preset, one route per thesis. Not standalone `index.html`. A page that only links the token stylesheet proves the colours are reachable and nothing about whether the component library can express the layout, which is the only question this phase asks. |
| REQ-MOC-08 | MUST | Where a thesis shows the dashboard or the login surface it composes the shadcn `dashboard-01` and `login-02` blocks (REQ-UI-01, REQ-UI-02), and any tabular surface is TanStack Table (REQ-GRD-01) — never a hand-written `<table>`. A layout approved against a hand-rolled table is approved against a control that will not ship. |
| REQ-MOC-09 | MUST | Layout and navigation conventions follow `arhamkhnz/next-shadcn-admin-dashboard` (REQ-UI-03). The ten theses vary the **layout**; they do not each invent their own navigation conventions. |
| REQ-MOC-10 | MUST | The design system is published and frozen **before the first mockup is built**. A06 completes and publishes `theme-tokens` before A08 starts — they do not run concurrently. No mockup declares a colour, radius, font, spacing step or shadow of its own; every value resolves to a token (REQ-UI-04, REQ-UI-05). |
| REQ-MOC-11 | MUST | Two independent design reviewers — C1 for design and A27 for the mobile renderings — pass every mockup round **before the human is asked to choose**. Neither wrote the mockups (REQ-GAT-07). A set that reaches the human unreviewed spends the one irreplaceable resource in the build, the human's attention, on defects a reviewer would have caught. |
| REQ-MOC-12 | MUST | A thesis that shows a grid shows the **real grid with its real chrome**: fuzzy search top-left and column chooser top-right above the table (REQ-GRD-02, REQ-GRD-03), a sort indicator, at least one type-aware column filter, and pagination at the bottom (REQ-GRD-04, REQ-GRD-05, REQ-GRD-09). A grid drawn as rows with no toolbar hides precisely the chrome the layout has to accommodate, so it is the one surface where a simplified mockup invalidates the choice the human is making (REQ-UI-10). |
| REQ-MOC-13 | MUST | **The navigation model is resolved and published before the first mockup.** A00 derives it from the entity list, the settings sections (REQ-SET-01) and the tenant model, and writes `build/navigation.md`: every top-level group and item, the nesting depth, the real labels, the icons and the permission that gates each one. All ten theses render **that** menu — same items, same depth, same labels. A05 later formalises it as the `nav-registry` contract (REQ-UI-03); this is its input, not a second source of truth. |
| REQ-MOC-14 | MUST | The published menu is sized honestly: the longest real label, the deepest real nesting, and the item count a tenant with every module enabled actually sees. Sidebar width, the collapse breakpoint and the chrome budget (REQ-UI-10) are all consequences of the menu, so a thesis that invents a three-item menu is not comparable with one that invents fifteen — and the human comparing them is choosing between measurements of different things. |

## GRD — Advanced datagrid

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-GRD-01 | MUST | Built on TanStack Table as the headless base. |
| REQ-GRD-02 | MUST | Fuzzy search in the **top-left**, above the table. |
| REQ-GRD-03 | MUST | Column chooser in the **top-right**, above the table. |
| REQ-GRD-04 | MUST | Column sorting, including multi-column with a visible precedence indicator. |
| REQ-GRD-05 | MUST | Per-column filtering with a type-aware filter control (text, enum, number range, date range, boolean). |
| REQ-GRD-06 | MUST | Column reordering by drag. |
| REQ-GRD-07 | MUST | Column resizing with a persisted width. |
| REQ-GRD-08 | MUST | Every grid interaction that expresses a preference — visibility, order, width, sort, filters, density, page size — is persisted to the **user profile**, per grid key, and survives device change. |
| REQ-GRD-09 | MUST | Pagination at the **bottom**. |
| REQ-GRD-10 | MUST | Page-size ranges are a per-grid setting, not a global constant: a small grid can declare `[10, 20, 50, all]`, a large one `[20, 50, 100, 200, 500, all]`. |
| REQ-GRD-11 | MUST | `all` is guarded: above a declared row ceiling it streams or refuses with an explainable message rather than hanging the tab. |
| REQ-GRD-12 | MUST | Server-side sort/filter/paginate for grids over a declared row threshold; the client contract is identical either way. |
| REQ-GRD-13 | MUST | Row selection, bulk actions gated by permission, and an export that is itself audited. |
| REQ-GRD-14 | MUST | Mobile rendering of the same grid definition as a card/stack list with the same filter and sort state. |
| REQ-GRD-15 | MUST | Grid state is URL-shareable; the URL wins over the stored profile for that visit. |

## AUD — Audit, logging & the debug console

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-AUD-01 | MUST | Full audit trail: create, update, delete, restore, login, logout, failed auth, policy change, permission change, impersonation, export, API key lifecycle. |
| REQ-AUD-02 | MUST | **Read/view logging** — successful reads and detail views are audited too, with a sampling/aggregation policy for list reads so the trail stays affordable and honest. |
| REQ-AUD-03 | MUST | Audit records are append-only: no `UPDATE`/`DELETE` grant to the app role, enforced by database privileges and a trigger. |
| REQ-AUD-04 | MUST | Every audit record carries actor, tenant, on-behalf-of (impersonation), permission used, target, before/after diff for writes, request correlation id, source IP, user agent, and result. |
| REQ-AUD-05 | MUST | Field-level redaction: secrets and declared PII never reach the audit diff in cleartext. |
| REQ-AUD-06 | MUST | Tamper evidence: a per-tenant hash chain over audit rows with a verify job. |
| REQ-AUD-07 | MUST | Syslog forwarding over TLS in RFC 5424 structured-data format, with local spooling and backpressure when the collector is down. |
| REQ-AUD-08 | MUST | An in-app debug console that streams live application events (SSE), for permitted operators only. |
| REQ-AUD-09 | MUST | Debug console **compact mode** — one event per line, aligned columns, collapsed metadata — toggleable. |
| REQ-AUD-10 | MUST | Debug console uses a monospace console font with coloured level/severity formatting and ANSI-faithful rendering, legible in both themes. |
| REQ-AUD-11 | MUST | Stream controls: level filter, domain filter, text filter, pause/resume, follow-tail, ring-buffer size, copy, download. |
| REQ-AUD-12 | MUST | Console output is redacted by the same rules as the audit diff — the console is not a secret-exfiltration channel. |
| REQ-AUD-13 | MUST | Audit retention and export per tenant, with a legal-hold flag that blocks purge. |

## TIM — Time & formatting

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-TIM-01 | MUST | Default display timezone `Europe/Stockholm`, with correct CET/CEST DST handling including the ambiguous and non-existent local hours. |
| REQ-TIM-02 | MUST | Default date-time format `YYYY-MM-DD HH:mm:ss`, with `YYYY-MM-DD HH:mm` where seconds carry no meaning. Seconds are shown only when they matter. |
| REQ-TIM-03 | MUST | Storage is always UTC (`timestamptz`); the timezone is a presentation concern resolved per user, falling back to tenant, then system default. |
| REQ-TIM-04 | MUST | One formatting module. No ad-hoc `toLocaleString`, no per-component format strings. |
| REQ-TIM-05 | MUST | User-selectable timezone and format profile, including 24h/12h, with `YYYY-MM-DD HH:mm:ss` as the shipped default. |
| REQ-TIM-06 | MUST | Relative times ("3 min ago") always carry the absolute value in a tooltip or title. |

## I18N — Language & translation

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-I18N-01 | MUST | Multi-language support across the whole app including emails, PDFs, audit reason templates and error messages. |
| REQ-I18N-02 | MUST | No user-visible literal outside a message catalogue. CI fails on a hardcoded string in a rendered path. |
| REQ-I18N-03 | MUST | ICU message format for plurals, gender and interpolation. |
| REQ-I18N-04 | MUST | Locale resolution: user preference → tenant default → `Accept-Language` → system default. |
| REQ-I18N-05 | MUST | Namespaced keys owned per domain, registered in `packages/contracts` so two agents cannot collide on a key. |
| REQ-I18N-06 | MUST | Shipped locales `en`, `sv`. Adding a locale is a data change, never a code change. |
| REQ-I18N-07 | MUST | Untranslated keys fall back visibly in development and silently to the base locale in production, and are reported by a coverage check. |
| REQ-I18N-08 | SHOULD | RTL-ready layout primitives (logical CSS properties) even before an RTL locale ships. |

## API — API surface, docs & keys

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-API-01 | MUST | OpenAPI 3.1 document covering **every** endpoint, generated from the same Zod schemas the runtime validates with — never hand-maintained. |
| REQ-API-02 | MUST | Interactive API documentation served in-app, behind auth, reflecting the caller's own permissions. |
| REQ-API-03 | MUST | CI fails if a route exists without an OpenAPI operation, or an operation without a route. |
| REQ-API-04 | MUST | Users can generate API keys bound to themselves, inheriting their permissions, never exceeding them. |
| REQ-API-05 | MUST | Admins can generate API keys — service keys with an explicitly chosen permission set and an owner of record. |
| REQ-API-06 | MUST | Key material is shown exactly once. Storage is a hash plus a non-secret prefix for identification. |
| REQ-API-07 | MUST | Keys carry scopes, an expiry (mandatory, with a maximum), optional IP allowlist, last-used timestamp, and immediate revocation. |
| REQ-API-08 | MUST | Full API key lifecycle auditing: mint, use-first, rotate, revoke, expire. |
| REQ-API-09 | MUST | Versioned paths `/api/v1/...`. Breaking a shipped operation requires a new version, never an edit (REQ-CTR-03). |
| REQ-API-10 | MUST | Uniform error envelope (RFC 9457 `application/problem+json`) with a stable error code taxonomy. |
| REQ-API-11 | MUST | Machine-readable pagination, filtering and sorting conventions shared with the datagrid contract. |

## PWA — Progressive web app

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-PWA-01 | MUST | Installable PWA: manifest, maskable icons, splash, standalone display, offline shell. |
| REQ-PWA-02 | MUST | Web Push notifications (VAPID) with per-user, per-category subscription management and a graceful iOS/Safari path. |
| REQ-PWA-03 | MUST | Service worker never caches an authenticated response or a tenant-scoped payload. |
| REQ-PWA-04 | MUST | Push payloads carry no sensitive content — a reference the client resolves over TLS after authenticating. |
| REQ-PWA-05 | MUST | A deterministic update path: new version detected, user prompted, no stale-shell lock-in. |
| REQ-PWA-06 | MUST | Notification preferences are per-category and per-channel (in-app, push, email) with a digest option. |

## MAIL — SMTP & messaging

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-MAIL-01 | MUST | SMTP sending with per-tenant sender identity and a global fallback. |
| REQ-MAIL-02 | MUST | Mandatory TLS on submission (REQ-SEC-04) with verified certificates. |
| REQ-MAIL-03 | MUST | Templated, localised, themed emails with a plain-text alternative, rendered from the same design tokens as the app. |
| REQ-MAIL-04 | MUST | A durable outbox with retry, backoff, dead-letter and a delivery audit event. No send from a request path. |
| REQ-MAIL-05 | MUST | Email address verification, and no enumeration through differential responses or timing. |
| REQ-MAIL-06 | MUST | Operator-facing SMTP diagnostics: test send, last errors, connection probe — without revealing credentials. |

## DAT — Common data models & normalization

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-DAT-01 | MUST | Canonical, product-agnostic and integration-agnostic core models (identity, organisation, asset, ticket, event, metric, location — as the intake requires) defined once in `packages/contracts`. |
| REQ-DAT-02 | MUST | Integration payloads are normalised into canonical models. No vendor field name reaches a canonical table. |
| REQ-DAT-03 | MUST | Mapping is **declarative data, not code**: a versioned mapping descriptor per source, executed by a generic engine. Adding a source ships no TypeScript. |
| REQ-DAT-04 | MUST | The normalization engine is a lightweight Python service (`services/normalizer/`) exposing an HTTP contract, so mappings are authored and hot-reloaded without rebuilding the app. |
| REQ-DAT-05 | MUST | Every normalised record keeps provenance: source system, source id, source payload hash, mapping descriptor version, normalised-at. |
| REQ-DAT-06 | MUST | Unmappable input is quarantined with a reason, never dropped and never coerced into a wrong shape. |
| REQ-DAT-07 | MUST | Mapping descriptors are validated against the canonical schema in CI; a descriptor that would write an unknown field fails the build. |
| REQ-DAT-08 | MUST | The engine is deterministic and side-effect free: same input plus same descriptor equals same output, and it is fuzz-tested as an untrusted-input parser. |

## OBS — Remote agents (Rust)

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-OBS-01 | OPT | Where the intake requires remote agents (collectors running outside the server), they are implemented in Rust. |
| REQ-OBS-02 | MUST | Agent↔server transport is mutually authenticated TLS with per-agent identity and short-lived credentials. |
| REQ-OBS-03 | MUST | Agents are least-privilege, config-declared, and cannot receive arbitrary code or shell commands from the server. |
| REQ-OBS-04 | MUST | Agent enrolment, heartbeat, version, and revocation are first-class audited entities. |
| REQ-OBS-05 | MUST | Agents buffer locally and resume without loss or duplication (idempotent ingest keys). |

## DOC — Help, documentation & architecture charts

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-DOC-01 | MUST | An in-app help section, always current, owned by the documentation expert agent (A16). |
| REQ-DOC-02 | MUST | Help content is organised and navigable: task-oriented guides, per-feature reference, glossary, search, deep links from the feature to its help topic. |
| REQ-DOC-03 | MUST | A shipped feature without a help topic fails the documentation gate. Help is not a follow-up. |
| REQ-DOC-04 | MUST | Help is localised (REQ-I18N-01) and permission-aware — an operator sees the global-tier topics, a tenant user does not. |
| REQ-DOC-05 | MUST | The help section contains architecture and high-level design visualisations. |
| REQ-DOC-06 | MUST | Those visualisations are proper charts authored by the architecture-chart agent (A17): C4-style context/container/component views, an auth-and-MFA sequence, a request-to-audit dataflow, an RLS/tenancy boundary diagram, a deployment topology, and the normalization pipeline. |
| REQ-DOC-07 | MUST | Charts are version-controlled source (Mermaid or authored SVG), theme-aware in light and dark, and legible on mobile. A chart is not a screenshot of a whiteboard. |
| REQ-DOC-08 | MUST | Charts are regenerated and re-reviewed when the thing they describe changes; a stale diagram fails the documentation gate. |

## CRA — EU Cyber Resilience Act compliance

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-CRA-01 | MUST | Documented conformity posture against Regulation (EU) 2024/2847, Annex I Part I (product security properties) and Part II (vulnerability handling). |
| REQ-CRA-02 | MUST | Secure-by-default configuration, documented, with the ability to reset to a secure state. |
| REQ-CRA-03 | MUST | A machine-readable SBOM (CycloneDX) covering at least top-level dependencies, produced per build and retained per release. |
| REQ-CRA-04 | MUST | A coordinated vulnerability disclosure policy and a documented single point of contact, published in `SECURITY.md`. |
| REQ-CRA-05 | MUST | A vulnerability handling process: intake, triage SLA, remediation, security update distribution, and advisory publication. |
| REQ-CRA-06 | MUST | Reporting readiness for the obligations in force since 11 September 2026 — actively exploited vulnerabilities and severe incidents to ENISA and the national CSIRT, 24-hour early warning, 72-hour notification, 14-day/1-month final report — as a rehearsed runbook with named roles. |
| REQ-CRA-07 | MUST | Security updates are separable from feature updates, and signed/verifiable. |
| REQ-CRA-08 | MUST | A declared support period, with the end-of-support date stated in the documentation. |
| REQ-CRA-09 | MUST | Annex II user information, Annex V EU declaration of conformity, and Annex VII technical documentation kept as templates completed at release. |
| REQ-CRA-10 | MUST | Compliance documentation is generated from the repository state, not written by hand, so it cannot drift from the product. |

## CER — EU Critical Entities Resilience compliance

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-CER-01 | MUST | Documented resilience posture supporting an operator's obligations under Directive (EU) 2022/2557 — the product is a supplier artefact in a critical entity's resilience plan. |
| REQ-CER-02 | MUST | A criticality and dependency assessment: which essential service the panel supports, what it depends on, and what fails if each dependency fails. |
| REQ-CER-03 | MUST | A resilience plan covering prevention, protection, response, and recovery, with documented RTO/RPO and the backup/restore procedure that meets them. |
| REQ-CER-04 | MUST | A tested restore — the documentation records the date and result of the last restore rehearsal, not just the procedure. |
| REQ-CER-05 | MUST | Business continuity for the declared dependencies: database, identity provider, SMTP, syslog collector, push service — including degraded-mode behaviour for each. |
| REQ-CER-06 | MUST | Incident response and notification procedures with named roles and escalation paths, aligned with the CRA reporting runbook (REQ-CRA-06). |
| REQ-CER-07 | MUST | Personnel security and access control documentation: background-check posture, joiner/mover/leaver, and privileged-access review cadence. |
| REQ-CER-08 | MUST | Physical and environmental assumptions stated explicitly, since they are the deploying operator's responsibility, not the product's. |
| REQ-CER-09 | MUST | A four-yearly reassessment cadence recorded, with the next due date in the document. |

## WIZ — First-run setup wizard

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-WIZ-01 | MUST | A setup wizard launches automatically at the first login and cannot be dismissed, skipped or navigated around until it is complete. |
| REQ-WIZ-02 | MUST | The shipped initial account is `admin@example.invalid` with a temporary password **generated at first boot** — never a fixed default, never a value in the repo or the image. It is written once to the container log and stored only as an Argon2id hash. |
| REQ-WIZ-03 | MUST | The initial account is constrained to completing the wizard. It holds no tenant-data permission, cannot call the API, and cannot create another account except the real admin in REQ-WIZ-05. |
| REQ-WIZ-04 | MUST | The initial account is disabled and its credential destroyed the moment the real admin is created. It cannot be re-enabled, and no code path recreates it after setup completes. |
| REQ-WIZ-05 | MUST | Step: create the real global admin — email, display name, a password meeting policy, and **mandatory MFA enrolment with recovery codes issued** before the step can complete (REQ-AUT-05, REQ-AUT-06). |
| REQ-WIZ-06 | MUST | Step: SMTP configuration with a **live verification send that must succeed** before the step completes. Email-based password and OTP recovery stays disabled until a real message has been delivered and confirmed. |
| REQ-WIZ-07 | MUST | Step: environment guidance — the wizard states which environment variables are required, which are missing, and which currently hold an insecure development default, each with a copy-paste block. It reads actual runtime config, not a static list. |
| REQ-WIZ-08 | MUST | Deployment guidance for the **plain Docker Compose** path first: the topology choice of REQ-PROX-03, the DNS records the chosen ACME challenge needs, and what to verify afterwards. Platform-specific notes are a clearly separated subsection for the case where a PaaS or load balancer already fronts the containers — of which one worked example is carried, not a required integration. |
| REQ-WIZ-09 | MUST | The wizard is resumable. Each step's progress persists, a crash or closed tab resumes at the same step, and no step half-applies — a step either completes and is recorded or leaves nothing behind. |
| REQ-WIZ-10 | MUST | Every step emits an audit event (REQ-AUD-01), including the initial-account disablement, the first real admin creation, and each configuration write. |
| REQ-WIZ-11 | MUST | Completion is explicit: the wizard writes a completion record, signs the session out, and the user performs their first real login with the account they just created. |
| REQ-WIZ-12 | MUST | Once complete the wizard cannot be re-entered. Re-running any part of setup requires a global-tier permission and is audited as a distinct event, never as a first run. |
| REQ-WIZ-13 | MUST | While setup is incomplete the wizard is the only reachable surface: every other route redirects to it, and the API refuses non-wizard calls with a distinct error code rather than a generic 403. |
| REQ-WIZ-14 | MUST | The wizard is localised (REQ-I18N-01), follows the approved layout and theme, and is usable at 390px — it is the first thing anyone sees. |

## PROX — Edge proxy & long-lived connections

The app is always fronted by its own HAProxy, even when that HAProxy is itself
behind someone else's proxy. This exists because long-lived connections are
load-bearing here — the debug console streams over SSE (REQ-AUD-08), and a proxy
that buffers, coalesces or idle-times those streams breaks a feature that looks
fine in every short-request test.

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-PROX-01 | MUST | HAProxy is the default and only shipped edge proxy, running as the `edge` service in the compose stack (REQ-FND-04). It is present even when the stack sits behind an external proxy. |
| REQ-PROX-02 | MUST | The app container is never directly internet-facing and never published to the host except through `edge`. |
| REQ-PROX-03 | MUST | Three supported topologies, declared explicitly at setup and stored as configuration: `self` (HAProxy is the internet-facing edge — the default), `behind-proxy` (HAProxy sits behind an upstream that already terminates public TLS — a PaaS, a corporate load balancer, a CDN, or a hand-rolled proxy), and `delegated` (no HAProxy; an external proxy fronts the app directly, which is supported but unsupported for the ACME paths in REQ-ACME-03). |
| REQ-PROX-04 | MUST | HAProxy configuration is generated from the same validated config source as the app (REQ-FND-07), not hand-maintained alongside it. A hostname or port that exists in one and not the other is a boot failure, not a runtime surprise. |
| REQ-PROX-05 | MUST | Long-lived connections are explicitly configured and verified: SSE and WebSocket upgrades pass through without response buffering, without chunk coalescing, and with timeouts long enough for an idle stream to survive. The configured values are stated, not left to defaults. |
| REQ-PROX-06 | MUST | A test proves an SSE stream stays open and delivers events promptly through `edge` — not merely that the endpoint returns 200. This is the requirement that catches the buffering class of bug, and it must fail if buffering is reintroduced. |
| REQ-PROX-07 | MUST | WebSocket upgrade is supported end to end through every topology, including `behind-proxy`, and is covered by the same style of test as REQ-PROX-06. |
| REQ-PROX-08 | MUST | The HAProxy↔app hop is TLS, in every topology. REQ-SEC-01 has no exemption for traffic that stays inside the compose network. |
| REQ-PROX-09 | MUST | HAProxy reloads without dropping established connections, and the reload path is the one the certificate installer uses (REQ-ACME-13). |
| REQ-PROX-10 | MUST | The real client address survives to the application through every topology — `X-Forwarded-For` / `Forwarded` handling is configured with an explicit trusted-proxy list, and the app never trusts a forwarded address from an untrusted hop. The audit trail records source IP (REQ-AUD-04), so a wrong client address is an integrity defect in the audit record, not a cosmetic one. |
| REQ-PROX-11 | MUST | Security headers and TLS policy (REQ-SEC-02, REQ-SEC-08) are asserted at `edge` and by the app, so removing the proxy cannot silently remove the headers. |
| REQ-PROX-12 | MUST | HAProxy's own runtime state — connection counts, reload history, certificate load status, error rates — is visible to permitted operators and emitted to the audit and log sinks like any other component (REQ-AUD-07). |

## ACME — Certificates & TLS automation

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-ACME-01 | MUST | A built-in ACME client supporting all four validation paths: HTTP-01, DNS-01, TLS-ALPN-01 and DNS-PERSIST-01. |
| REQ-ACME-02 | MUST | Challenge type is selectable per certificate. The UI states each type's prerequisite and refuses a selection whose prerequisite is unmet rather than failing at issuance. |
| REQ-ACME-03 | MUST | An explicit TLS-termination mode with three values, matching the three topologies of REQ-PROX-03: `self` (our HAProxy is the internet-facing edge and we own ACME end to end — the default), `behind-proxy` (our HAProxy is in the path but an upstream — a PaaS, a load balancer, a CDN — terminates public TLS, so internal ACME is disabled for the public hostname only), and `delegated` (no HAProxy; internal ACME fully disabled). The mode is chosen explicitly, never inferred silently. Two ACME clients competing for the same hostname and port 80 is the failure this prevents. |
| REQ-ACME-04 | MUST | Guided DNS setup: the exact record name, type, value and TTL to create, with a re-check action and a propagation check against the domain's **authoritative** nameservers before issuance is requested. |
| REQ-ACME-05 | MUST | DNS-PERSIST-01 support: the persistent TXT record at `_validation-persist.<domain>` binding this ACME account and CA, with the account key thumbprint displayed and the consequence of rotating that key stated plainly. |
| REQ-ACME-06 | MUST | Renewal is automatic and requires no future user intervention, ever. A deployment left alone for a year keeps working. |
| REQ-ACME-07 | MUST | Renewal timing is **ARI-driven** (RFC 9773, ACME Renewal Information): the client polls the CA's suggested renewal window and obeys it, rather than assuming a fixed fraction of the certificate lifetime. |
| REQ-ACME-08 | MUST | The check frequency is configurable down to every 1 hour, and the safety margin before the window closes is configurable. These two are the only renewal knobs a user should ever need. |
| REQ-ACME-09 | MUST | Short-lived certificate profiles are supported — Let's Encrypt's 160-hour (6-day) profile — where the expected cadence is renewal every 2–3 days with ARI checks at least daily. The shipped defaults must be correct for this case, not only for 90-day certificates. |
| REQ-ACME-10 | MUST | Full debug logs in the certificate renewal settings screen: every ACME protocol step, request, response, challenge state transition, DNS lookup and error, with timestamps — subject to the same redaction rules as every other sink (REQ-AUD-05, REQ-AUD-12). |
| REQ-ACME-11 | MUST | Renewal failure raises a notification before expiry, escalating as the remaining margin shrinks. Silent failure until an outage is not acceptable. |
| REQ-ACME-12 | MUST | The ACME account key and all certificate private keys are stored under envelope encryption (REQ-SEC-06), never leave the server, and never appear in a log, a debug stream, an export or an audit diff. |
| REQ-ACME-13 | MUST | Certificate installation is atomic and hot-reloaded without dropping connections or requiring a restart. |
| REQ-ACME-14 | MUST | Staging and production ACME directories are both selectable, staging is the default for a first issuance, and rate-limit state is surfaced before a request that would exceed it. |
| REQ-ACME-15 | MUST | Multiple certificates, SAN lists and wildcards are supported. A wildcard requires DNS-01 or DNS-PERSIST-01, and the UI enforces that rather than letting the order fail. |
| REQ-ACME-16 | MUST | A certificate inventory showing, per certificate: names, issuer, challenge type, validity window, last renewal, next scheduled check, ARI window, and full issuance history. |
| REQ-ACME-17 | MUST | Every ACME operation is audited. Issuance, renewal, revocation and challenge failure are first-class audit events (REQ-AUD-01). |
| REQ-ACME-18 | MUST | DNS provider credentials for DNS-01 are stored encrypted, scoped to the minimum the provider allows, and the supported provider set is a declarative registry — adding a provider is data, not a new branch in a switch statement. |

## SET — Settings surfaces

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-SET-01 | MUST | A settings section is always present in the navigation. It is not an afterthought reachable only from an avatar menu. |
| REQ-SET-02 | MUST | Three scopes, always distinguishable: **personal**, **tenant**, **global**. |
| REQ-SET-03 | MUST | Personal settings cover: profile, theme, locale, timezone and date format (REQ-TIM-05), notification preferences, MFA factors, recovery codes, active sessions, and the user's own API keys. |
| REQ-SET-04 | MUST | Tenant settings cover: tenant identity and branding, enabled auth methods within global policy (REQ-AUT-04), SMTP sender identity, audit retention, grid defaults, and tenant-scoped API keys. |
| REQ-SET-05 | MUST | Global settings cover: system-wide auth policy, tenant administration, global roles, SMTP, syslog forwarding, certificates (REQ-ACME-*), normalizer mappings, telemetry posture, declared support and end-of-support dates, and backup/restore. |
| REQ-SET-06 | MUST | Scope is unambiguous on every panel **before** a change is saved, not explained after. A global change must read as global while the user is making it. |
| REQ-SET-07 | MUST | Every scope and every panel is permission-gated. A scope with no panel the actor may see is not rendered at all, rather than rendered empty. |
| REQ-SET-08 | MUST | Panels are contributed by their owning domain through a settings registry, never a shared list — the same rule that keeps the parallel wave safe (REQ-CTR-04). |
| REQ-SET-09 | MUST | Every settings change is audited with a before/after diff (REQ-AUD-01, REQ-AUD-04), including which scope it was made at. |
| REQ-SET-10 | MUST | A global or tenant change with blast radius requires typed confirmation naming what will change and for whom. |
| REQ-SET-11 | MUST | Precedence is documented and visible in-app: personal overrides tenant overrides global, except where a policy is declared non-overridable — and where it is, the panel says so and shows the effective value with its source. |
| REQ-SET-12 | MUST | Settings are searchable, deep-linkable, and every panel has a help topic (REQ-DOC-03). |

## SUP — Supply chain & telemetry

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-SUP-01 | MUST | A complete dependency inventory per build — direct and transitive, with licence and provenance. |
| REQ-SUP-02 | MUST | Every dependency checked against known-vulnerability sources on every build; a known-exploited or critical advisory blocks the build. |
| REQ-SUP-03 | MUST | An independent, first-party scan for suspicious code beyond CVE matching: install scripts, obfuscation, network calls at install time, credential/env access, dynamic evaluation, typosquat-shaped names, and maintainer-change/age anomalies. |
| REQ-SUP-04 | MUST | A new dependency is a reviewed decision with a recorded justification, not a side effect of an agent's convenience. |
| REQ-SUP-05 | MUST | Lockfile integrity enforced; a changed lockfile without a matching `package.json` change fails CI. |
| REQ-SUP-06 | MUST | Telemetry, analytics and phone-home are disabled for every framework and tool in the stack — build-time and run-time — and the settings are asserted by test, not assumed. |
| REQ-SUP-07 | MUST | No third-party script, font or asset is loaded from a remote origin at runtime. Fonts and assets are self-hosted. |
| REQ-SUP-08 | MUST | Egress from the built container is documented and minimal; an unexpected outbound destination fails the security gate. |

## COST — Token accounting & cost reporting

The build spends real money. A structure that cannot say what a wave cost cannot
tell you whether the parallelism paid for itself, and cannot tell you what a
gate loop cost you in rework.

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-COST-01 | MUST | Every agent's hand-off reports its own token usage: input, output, cache-read and cache-write tokens, plus the model and effort it ran at. An agent that finishes without reporting usage has not finished. |
| REQ-COST-02 | MUST | The orchestrator maintains a running cost table at `build/costs.md`, updated every time an agent hands off or a gate returns a verdict. |
| REQ-COST-03 | MUST | The table is **presented to the user at each gate**, not saved for the end. A cost you learn at G8 is a cost you could not have acted on. |
| REQ-COST-04 | MUST | Two kinds of number, never conflated: **measured** token counts and **derived** money. A derived figure is always labelled as derived and always shows the unit price it used. |
| REQ-COST-05 | MUST | Prices come from `versions/pricing.json`, validated against the provider's published pricing with the source URL and check timestamp recorded — never from a model's memory. This is REQ-VER-02's discipline applied to money, and for the same reason: a remembered price is wrong. |
| REQ-COST-06 | MUST | Breakdown by agent, by wave, by gate and by round. A gate that loops three times cost three times, and the table shows each round separately. |
| REQ-COST-07 | MUST | Rework is attributed to its cause. Tokens spent fixing a gate finding are attributed to that finding, so the cost of a defect is visible rather than absorbed into the domain that had to fix it. |
| REQ-COST-08 | MUST | Cache reads are reported separately from fresh input tokens, because they are priced differently and the ratio between them is the main cost lever the structure controls. |
| REQ-COST-09 | MUST | A cost ceiling may be declared at intake. Crossing it pauses the build and asks, rather than continuing silently or aborting. |
| REQ-COST-10 | MUST | The release record carries the build's total (REQ-REL-08), so cost is part of a build's history and two builds can be compared. |
| REQ-COST-11 | MUST | An estimate is published before each wave and the actual after it, with the variance shown. An estimator that is consistently wrong is a finding about the estimate, not about the wave. |
| REQ-COST-12 | MUST | Where the runtime does not expose token usage, the cell reads `unreported` and the total is marked incomplete. A fabricated number is worse than a visible gap, because it will be trusted. |

## PORT — Runtime portability

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-PORT-01 | MUST | The prompt structure runs on more than one agent runtime. Claude Code is the reference implementation, not a dependency. |
| REQ-PORT-02 | MUST | Portability is expressed as a **capability map**: what the structure needs a runtime to be able to do, not which product provides it. |
| REQ-PORT-03 | MUST | No requirement and no spec names a runtime-specific tool. Tool names appear only in agent frontmatter and in the capability map, which is the one place a translation happens. |
| REQ-PORT-04 | MUST | An adapter ships for Muse Code with Muse Spark 1.3, as a paste-ready prompt rather than a fork of the structure. Two copies of a prompt structure diverge; one structure plus an adapter does not. |
| REQ-PORT-05 | MUST | An adapter corrects only what its target would otherwise misread. It never restates a requirement, because a restated requirement is a second source of truth that will drift. |
| REQ-PORT-06 | MUST | Where a target runtime cannot satisfy a capability, the adapter names the requirements that become unverifiable on it. An unverifiable requirement is reported, never quietly dropped. |
| REQ-PORT-07 | MUST | Telemetry is disabled in the **agent runtime** as well as in the generated app. REQ-SUP-06 applies to the tool doing the building, not only to the thing built. |
| REQ-PORT-08 | MUST | Where a runtime offers a cheaper tier in exchange for training on the traffic, using it for a build is an explicitly recorded decision — this build handles security posture, credentials guidance and compliance evidence. |
| REQ-PORT-09 | MUST | An adapter is verified by running one wave on the target and comparing the artefacts, not by reading it. |
| REQ-PORT-10 | MUST | Adding a runtime adds an adapter and a capability-map column. It never edits a requirement, a spec, or an agent's mission. |

## VER — Version currency

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-VER-01 | MUST | Latest stable releases of every language, runtime, framework and library — no prereleases, no release candidates. |
| REQ-VER-02 | MUST | Every version is validated **externally** against the authoritative source (npm registry, crates.io, PyPI, Docker Hub, nodejs.org, postgresql.org) at build time. No version is taken from training memory. |
| REQ-VER-03 | MUST | The validation result is written to `versions/manifest.json` with the source URL and the timestamp of the check. |
| REQ-VER-04 | MUST | A major-version jump in the manifest is a reviewed decision with a migration note, not an automatic bump. |
| REQ-VER-05 | MUST | Compatibility traps are recorded in the manifest, not rediscovered: e.g. `@types/node` tracks the **Node LTS** major, not the newest published major. |
| REQ-VER-06 | MUST | The stack runs on the current Node LTS and the current PostgreSQL stable, both externally confirmed. |

## TST — Testing & visual verification

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-TST-01 | MUST | Unit tests on domain logic, integration tests on data access and RLS, end-to-end tests on the critical journeys. |
| REQ-TST-02 | MUST | End-to-end and visual testing via Playwright driving Chromium over CDP. |
| REQ-TST-03 | MUST | Screenshots are captured at multiple points during a run — not just at failure — across mobile, tablet and desktop, in light and dark. |
| REQ-TST-04 | MUST | Screenshots are presented in the chat response to the user for every build that touches the UI. |
| REQ-TST-05 | MUST | Tenant isolation, permission denial, MFA enforcement and audit emission each have a dedicated test suite. |
| REQ-TST-06 | MUST | Accessibility assertions in the e2e run (axe) at AA, in both themes. |
| REQ-TST-07 | MUST | Seeded, deterministic fixtures: two tenants, a global operator, and a user per role. |
| REQ-TST-08 | MUST | The debug console, the grid preference round-trip and the read-audit emission are verified by test, since all three are easy to fake visually. |

## GAT — Quality gates & critique loops

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-GAT-01 | MUST | Two harsh critique agents (C1, C2) must **both** approve the design **and** the functions. Either rejection loops the work back with named defects. |
| REQ-GAT-02 | MUST | Two independent security expert agents (S1, S2) review the code. They do not see each other's findings before submitting. |
| REQ-GAT-03 | MUST | For a larger change, each security reviewer first establishes and states a review plan covering common best practice, RLS, endpoints, authentication, and privacy/integrity leakage — then executes it. |
| REQ-GAT-04 | MUST | Critique and security verdicts are structured, per-REQ, and written to `build/gates/`. "Looks good" is not a verdict. |
| REQ-GAT-05 | MUST | A loop is bounded: three failed rounds on the same defect escalate to the human with the disagreement stated, rather than looping forever. |
| REQ-GAT-06 | MUST | Karpathy guidelines are applied as a standing review lens on every build: no overcomplication, surgical changes, surfaced assumptions, verifiable success criteria. |
| REQ-GAT-07 | MUST | No gate may be self-approved. The agent that wrote the code never votes on it. |

## REL — Release, versioning & records

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-REL-01 | MUST | Every build commits and pushes. Work in progress is not left only in a container. |
| REQ-REL-02 | MUST | Semantic version bumped at every build, with the bump level derived from the change set and recorded. |
| REQ-REL-03 | MUST | `CHANGELOG.md` updated every build in Keep a Changelog form, with REQ IDs cited. |
| REQ-REL-04 | MUST | `README.md` kept current with what the thing now is and how to run it. |
| REQ-REL-05 | MUST | `SECURITY.md` kept current: supported versions, the CVD policy, the contact, and the CRA reporting posture. |
| REQ-REL-06 | MUST | `TODO.md` maintained as live status: done, in progress, planned, blocked — with REQ IDs and gate state. |
| REQ-REL-07 | MUST | A release candidate is only declared when every `MUST` is green, both critics approve, both security reviewers approve, and the version/changelog/docs are updated. |
| REQ-REL-08 | MUST | The commit message records the gate outcomes and the version bump reason. |
