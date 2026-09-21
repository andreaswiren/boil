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
| REQ-FND-04 | MUST | Docker Compose is the only supported run target: `app`, `db` (PostgreSQL), `smtp-relay`, `reverse-proxy`. Dev and prod compose files share a base. |
| REQ-FND-05 | MUST | PostgreSQL is the only datastore. No secondary state store that survives a restart. |
| REQ-FND-06 | MUST | All dependency versions come from `versions/manifest.json`, externally validated (REQ-VER-01). |
| REQ-FND-07 | MUST | Config is env-var driven, parsed and validated at boot by a single Zod schema. Boot fails loudly on a missing or malformed value — never a silent default for a security-relevant key. |
| REQ-FND-08 | MUST | No secret in the image, the repo, or a client bundle. Secrets arrive via env or a mounted file and are redacted from every log sink. |
| REQ-FND-09 | MUST | Reproducible build: pinned base images by digest, `--frozen-lockfile`, deterministic `NEXT_BUILD_ID`. |
| REQ-FND-10 | MUST | Health endpoints: `/api/health/live`, `/api/health/ready` (checks DB, migrations, SMTP, syslog sink). |

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
| REQ-UI-04 | MUST | Theme preset `b2CjxkL2O` with base `radix`: style `mira`, baseColor `mist`, theme `emerald`, chart `emerald`, font `montserrat`, radius `small`, menuAccent `bold`. |
| REQ-UI-05 | MUST | Full in-app theming at parity with the shadcn theme generator: every knob the generator exposes (style, base colour, theme colour, chart colour, icon library, font, heading font, radius, menu accent, menu colour) is editable, previewable and persistable in-app. |
| REQ-UI-06 | MUST | Dark, light and system theme modes, with no flash of wrong theme on first paint. |
| REQ-UI-07 | MUST | A genuine mobile design — not a narrowed desktop. Bottom navigation, sheet-based detail, thumb-reachable primary actions, 44px minimum touch targets. |
| REQ-UI-08 | MUST | A genuine desktop design — density-first, keyboard-first, multi-pane where it earns the space. |
| REQ-UI-09 | MUST | Screenspace is measured, not assumed: a runtime measurement layer reports viewport, safe-area insets, visual-viewport (keyboard) offset, container sizes and available content height. |
| REQ-UI-10 | MUST | Declared space budgets per surface (chrome vs content) are asserted in visual tests at each named breakpoint; a surface spending more chrome than its budget fails the gate. |
| REQ-UI-11 | MUST | Keyboard-complete and screen-reader-sane: visible focus, logical order, labelled controls, WCAG 2.2 AA contrast in both themes. |
| REQ-UI-12 | MUST | Command palette (⌘K) covering navigation, entity search and permitted actions. |

## MOC — Mockup & approval phase

| ID | Status | Requirement |
|----|--------|-------------|
| REQ-MOC-01 | MUST | The first build phase produces mockups and screenshots for human approval before production code is written. |
| REQ-MOC-02 | MUST | Exactly 10 mockup designs, differentiated by **layout**, not by palette. Each names the layout thesis it is testing. |
| REQ-MOC-03 | MUST | Each of the 10 is rendered at mobile (390px), tablet (834px) and desktop (1440px) and screenshotted. |
| REQ-MOC-04 | MUST | Screenshots are presented in the chat response, not only written to disk. |
| REQ-MOC-05 | MUST | No production UI code is written until a human names the winning layout (or a hybrid of named ones). The approval is recorded in `build/approvals.md`. |
| REQ-MOC-06 | MUST | Mockups are real rendered HTML at the chosen theme, not drawings — they must be honest about typography, density and control sizes. |

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
