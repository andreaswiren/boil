# First-Run Setup Wizard

Five steps between a freshly started container and an admin panel with a real
owner. Owned by **A24** (`setup-wizard`): `packages/setup/**`,
`apps/<app>/app/(setup)/**`, and the tables `setup_state`, `setup_steps`. A24
publishes `wizard-state` and `setup-step`; it consumes `session`, `auth-policy`,
`mfa`, `rbac`, `mail-template`, `env-schema`. A24 defines no role (A04), writes
no audit row (A13), sends no mail itself (A12) and runs no ACME order (A25) — it
records decisions and emits events.

## Requirements covered

REQ-WIZ-01 … REQ-WIZ-14, REQ-PROX-03, REQ-PROX-08, REQ-ACME-03, REQ-AUT-05,
REQ-AUT-06, REQ-SEC-07, REQ-SEC-11, REQ-MAIL-04, REQ-MAIL-06, REQ-FND-07,
REQ-AUD-01, REQ-AUD-04, REQ-SET-08, REQ-I18N-01, REQ-UI-07, REQ-TIM-04.

## 1. The step machine (REQ-WIZ-01)

Strictly ordered. A step is reachable only when every earlier step has a
`complete` record. No skip, no re-entry into a completed step, no deep-link past
the cursor: a step whose entry condition is unmet returns
`setup.step_out_of_order` (409) and the UI renders the cursor's step.

| # | Step id | Entry condition | Writes | Complete when | On failure |
|---|---------|-----------------|--------|---------------|------------|
| 1 | `welcome-preflight` | bootstrap session valid, `setup_state.completed_at IS NULL` | `setup_steps` row with the preflight snapshot; chosen locale into `setup_state.draft` | every blocking check green | nothing recorded; re-check action; failed checks listed with their REQ ID |
| 2 | `create-admin` | step 1 complete | real global admin via `identity.provisionGlobalAdmin`; `setup_state.real_admin_actor_id`; bootstrap credential destroyed (§4) | the admin exists **with** an MFA factor enrolled and 10 recovery codes issued (REQ-AUT-05, REQ-AUT-06) | bootstrap credential still works, no admin half-exists, no record; retry idempotent on the same email |
| 3 | `smtp` | step 2 complete | `SenderIdentity` through A12's interface; verification token in `setup_state.draft` | a real message was **delivered** and its code entered (REQ-WIZ-06) | sender config not persisted, email-based password/OTP recovery stays disabled, relay error shown credential-free (REQ-MAIL-06) |
| 4 | `edge-environment` | step 3 complete | topology mode and certificate plan into the settings registry; environment report snapshot | a topology mode is chosen and every `blocking` environment row is cleared | mode unchanged, no partial write; an `insecure_default` row cannot be waived |
| 5 | `review-complete` | steps 1–4 complete | `setup_state.completed_at`, `completed_by`, `required_steps`, `steps_digest` | completion record committed and the operator is at `/sign-in` | no completion record; the wizard is still the only surface |

Step 2 precedes step 3 deliberately: step 3's verification send goes to the real
admin's address, so confirming it also proves that address is reachable — one
action satisfies REQ-WIZ-06 and the admin's email verification (REQ-MAIL-05).

Step 1's preflight checks, all blocking: database reachable with
`sslmode=verify-full` and a pinned CA (REQ-SEC-03); migrations at head; a KEK
`seal`/`open` round-trip (REQ-SEC-06); audit chain writable with a verifying
head (REQ-AUD-03, REQ-AUD-06); `edge` reachable over TLS on the internal hop
(REQ-PROX-08); clock UTC, drift under 5 s (REQ-TIM-03); `en` and `sv` catalogues
loaded (REQ-I18N-06). Syslog reachability is non-blocking — a down collector
spools, it does not stop setup.

## 2. The bootstrap credential (REQ-WIZ-02)

`admin@example.invalid`. The password is generated on the first boot that finds
no `setup_state` row: 160 bits from the kernel CSPRNG through
`packages/crypto`'s `randomBytes(20)` — never `Math.random`, never a
timestamp-derived seed — Crockford base32 to 32 characters in four groups of
eight. It is written **once** to stdout, which is the container log, and stored
only as an Argon2id hash with A01's parameters (REQ-SEC-07). It is not in the
repo, the image, `.env.example`, an audit payload or the ready probe, and it is
not recoverable server-side. Its length is fixed in code, not an env var: a knob
that weakens a credential is not a knob.

**A second boot does not regenerate it.** With `bootstrap_password_hash`
non-null, boot generates nothing and prints nothing. Restarts are routine — a
Dokploy environment change forces a rebuild (REQ-WIZ-08) — so regeneration would
hand an operator scrolling back to an older log line a password that a restart
had silently invalidated, and every boot would add one more log record holding a
live credential (REQ-FND-08). Lost password, one path: boot once with
`SETUP_BOOTSTRAP_ROTATE=1`, which rotates, prints, emits
`setup.bootstrap.rotated`, and refuses when `completed_at` is set — rotation is
not a way back into a finished install (REQ-WIZ-04).

## 3. What the bootstrap account may do (REQ-WIZ-03)

The failure mode this requirement exists to prevent is a global admin with a
temporary password. We do not build a weak global admin. **The bootstrap
credential cannot produce an `identity.Session`**: no `users` row, no
`credentials` row, no role grant, no row in A03's session store. Signing in
mints an opaque 256-bit id in a `__Host-setup` cookie (`HttpOnly`, `Secure`,
`SameSite=Strict`) recorded on the `setup_state` singleton. Exactly one
bootstrap session exists at a time; a second sign-in supersedes the first, so
two operators cannot race the wizard.

| Capability | Bootstrap principal |
|---|---|
| Read wizard state, step cursor, environment report | yes |
| Write step drafts, complete steps 1–5 | yes |
| Create the real global admin, once (§4) | yes |
| Trigger the SMTP verification send | yes, rate-limited (§5) |
| `/api/v1/**` outside `/api/v1/setup/**`; any `(app)`, `(auth)` or settings route | no |
| Any tenant-scoped read or write | no |
| Create another account, grant a role, mint an API key | no |
| Hold any permission string | no — it holds none |

Enforcement is server-side and structural, in three layers. The route kit
resolves an actor from the session cookie only, and a `__Host-setup` cookie is
not a session, so every permission check is deny-by-default against an empty
permission set (REQ-RBA-02). The tenant GUC is never set on a bootstrap request,
so forced RLS denies every tenant-scoped row (REQ-RBA-04). And
`/api/v1/setup/**` is the only subtree whose guard accepts this principal, by an
allowlist in my own package rather than an exclusion in someone else's. The
`setup.*` permission strings exist for the **re-run** surface (§10), reached by a
real global-tier session; during a first run nobody holds them.

## 4. Irreversible teardown (REQ-WIZ-04)

Step 2 is one transaction over `setup_state` and `setup_steps`:

```sql
BEGIN;                          -- provisionGlobalAdmin has already returned an
                                -- actor id, atomically, under idempotency key
                                -- (setup_state.id, lower(email)).
  UPDATE setup_state
     SET real_admin_actor_id = $1, bootstrap_password_hash = NULL,  -- destroyed
         bootstrap_disabled_at = now(), bootstrap_session_id = NULL,
         draft = draft - 'admin'
   WHERE completed_at IS NULL AND bootstrap_disabled_at IS NULL;
  INSERT INTO setup_steps (step, run_ordinal, state, result, completed_at) ...;
COMMIT;
```

The ordering is the safety property: **create, verify, then destroy — never the
reverse.** The credential dies only after an admin exists holding an MFA factor
and issued recovery codes. One transaction is what makes "an admin exists" and
"the bootstrap credential is gone" inseparable in the record; two commits leave a
window in which a crash bricks the install with no reachable account.

A partial failure must leave the install **usable**: credential intact, no
half-created admin, step 2 not recorded. A retry with the same email returns the
same actor and re-attempts the teardown; the `WHERE` clause makes the update a
no-op once it has run, so a duplicate retry resurrects nothing. There is no
re-enable path and no code path that recreates the account — asserted by test,
because a future convenience helper is how this requirement gets violated.

## 5. Resumability (REQ-WIZ-09)

Two tables, one rule. `setup_state` is a singleton row holding the cursor, the
bootstrap fields, the completion record and `draft jsonb`. `setup_steps` is
**append-only**, keyed `(step, run_ordinal)`: a row exists only for a step that
completed, so after a crash there is no partial record to interpret. `draft`
holds only re-derivable, echo-safe values — locale, SMTP host, port,
from-address, the pending verification token. Never a credential: the relay
password arrives in the request that completes step 3 and goes straight into
A12's envelope-encrypted `credentialRef` (REQ-SEC-06). A crash mid-step loses a
form, never a secret.

Three steps have effects outside my tables and are made idempotent one by one:

| Step | External effect | Idempotency mechanism |
|---|---|---|
| 2 `create-admin` | rows in A03's identity tables | idempotency key `(setup_state.id, lower(email))` on `provisionGlobalAdmin`; a replay returns the same actor and writes nothing new |
| 3 `smtp` | **a real email leaves the building** | a 128-bit token generated once per `(step, sha256(sender_config))`; the enqueue carries `idempotencyKey = "setup.smtp." + config_hash + "." + token` (REQ-MAIL-04), so a crash-and-resume re-enqueues nothing. Editing the config changes the hash, voids the token and forces a new send. Max 5 sends per hour per config hash (REQ-SEC-11) |
| 4 `edge-environment` | settings-registry values A25 and A01 read | a keyed upsert of one value per key, not an append — replaying it is a no-op |

Step 3 completes on **confirmation of delivery**, not on a `250` from the relay:
a relay accepting a message is not a delivered message, and REQ-WIZ-06 says
delivered and confirmed. The operator enters the 8-character Crockford code from
the received mail; a wrong code returns `setup.verification_not_confirmed` (409)
and does not consume the token.

## 6. Lockout semantics (REQ-WIZ-13)

While `completed_at IS NULL`:

- **Every route** outside `(setup)` answers `307` to `/setup`. The gate is read
  through the contract member `wizard-state` (`readSetupGate()`), whose
  implementation `packages/setup` registers at boot — the pattern A13 uses for
  `emitAuditEvent`. A01's `middleware.ts` and A05's `(app)` layout call the
  contract, never my package (REQ-CTR-01).
- **Every API call** outside `/api/v1/setup/**` is refused with
  `setup.incomplete` → **503**, `retryable: true`, per the taxonomy in
  `contracts/types/errors.md` §3. Not `common.forbidden`: nothing about the
  caller's authorisation is wrong, and a 403 sends an integrator hunting
  permissions for a condition that clears on its own.
- `/api/health/live` and `/api/health/ready` stay reachable and `ready` reports
  `setup: "pending"` (REQ-FND-10). A load balancer must not see a redirect.
- After completion, a first-run route answers `setup.already_complete` (409) and
  a presented bootstrap cookie `setup.bootstrap_disabled` (401), audited as
  `setup.bootstrap.rejected`.

## 7. Environment guidance (REQ-WIZ-07)

The report is generated from the **live parsed configuration** — A01's assembled
`AppEnvSchema` and its refinement results — not from a checklist in a document.
One row per declared key, classified `ok` / `missing` / `insecure_default`, with
its owning agent and REQ ID. The live value never appears (REQ-FND-08); the
copy-paste block carries a placeholder. A key whose absence fails boot
(REQ-FND-07) cannot appear as `missing`, because an app missing that key is not
running and there is no wizard to ask; the report covers keys that are optional
at boot and load-bearing for a step.

```ts
{ key: "DATABASE_URL", owner: "A01", req: "REQ-SEC-03", state: "ok",
  severity: "info", detailKey: "setup.env.tls_verified" }
{ key: "MAIL_RELAY_PASSWORD", owner: "A12", req: "REQ-MAIL-02", state: "missing",
  severity: "blocking", detailKey: "setup.env.missing_blocks_step",
  detailParams: { step: "smtp" }, copyPaste: "MAIL_RELAY_PASSWORD=<relay password>" }
{ key: "CRYPTO_KEK", owner: "A01", req: "REQ-SEC-06", state: "insecure_default",
  severity: "blocking", detailKey: "setup.env.dev_value_in_use",
  copyPaste: "CRYPTO_KEK=<openssl rand -base64 32>" }
```

`insecure_default` is a constant-time match against the digests of the values
shipped in `compose.dev.yml` and the dev CA — a known-value comparison, not a
heuristic about how the string looks. Such a row is blocking and not waivable; a
`missing` row blocks only the step that needs it. Rules live in
`packages/setup/env-rules.ts`, each citing its REQ ID. A key another domain wants
classified gets an `insecureWhen` predicate on its own env declaration, which is
a CCR against the declaration shape, not a patch to my table.

## 8. Edge topology and TLS termination (REQ-PROX-03, REQ-ACME-03, REQ-WIZ-08)

HAProxy is ours and always in the path (REQ-PROX-01). Step 4 does not ask whether
there is a proxy; it asks **which of the three topologies this deployment is**,
explicitly, never inferred silently (REQ-ACME-03).

| Mode | Path | Public certificate | Internal ACME | Challenges for the public name |
|---|---|---|---|---|
| `self` (**default**) | client → our HAProxy → app | ours | enabled, all four paths (REQ-ACME-01) | HTTP-01, TLS-ALPN-01, DNS-01, DNS-PERSIST-01 |
| `behind-proxy` (**the Dokploy case**) | client → upstream proxy → our HAProxy → app | the upstream's | disabled **for the public hostname only** | DNS-01, DNS-PERSIST-01 |
| `delegated` | client → external proxy → app | the external proxy's | fully disabled | none — the app orders no certificate |

The HAProxy↔app hop is TLS in `self` and `behind-proxy` alike: REQ-SEC-01 and
REQ-PROX-08 have no exemption for traffic that stays inside the compose network.
`behind-proxy` does not mean our proxy stops doing TLS — it means the upstream
owns the public certificate while our edge keeps terminating the internal hop
with its own.

In `behind-proxy` the upstream already answers on port 80 and owns the 443
handshake, so **HTTP-01 and TLS-ALPN-01 for the public name cannot succeed**.
They are refused at selection rather than at issuance (REQ-ACME-02) and the step
steers the operator to DNS-01 or DNS-PERSIST-01, with the reason stated. The
authoritative availability matrix is A25's, in `spec/acme-tls.md`; step 4 reads
it and does not restate it. Two ACME clients competing for one hostname and port
80 is the failure REQ-ACME-03 exists to prevent.

`behind-proxy` is pre-selected when `SETUP_DEPLOY_TARGET=dokploy`, `self`
otherwise. The Dokploy panel states, in the operator's locale:

1. Environment variables are set in the Dokploy **Environment editor** in
   project settings. Dokploy writes the `.env`; values are referenced as
   `${VAR_NAME}`. Do not hand-edit `.env` inside the container.
2. **A container rebuild is required after changing an environment variable.**
   Changes are not picked up automatically. Every copy-paste block in step 4
   repeats this line, because this is what trips people.
3. Domains are configured in the Dokploy **Domains tab**, not in the compose
   file — Dokploy injects the Traefik labels at deploy time, so hand-written
   labels are the wrong layer. The domain points at **our `edge` service**, not
   at the app container (REQ-PROX-02).
4. Every service is attached to the `dokploy-network` network.
5. The topology is `behind-proxy`, with the challenge consequence above.

## 9. Completion and the first real login (REQ-WIZ-11)

Step 5 commits the completion record — `completed_at`, `completed_by` (the real
admin's `ActorRef`), `required_steps` (the step ids this version demanded),
`steps_digest` (SHA-256 over the ordered `(step, run_ordinal, completed_at,
result_digest)` tuples), `app_version` and `contract_version` — then destroys
the `__Host-setup` cookie and its row and redirects to `/sign-in`.

The first login is a **real login**, not a continuation. The wizard principal was
never an `identity.Session`: no `amr`, no `mfaSatisfied`, no step-up, so nothing
about this account's authentication has been exercised. Forcing one login proves
password and TOTP work against the factor enrolled minutes earlier, while the
operator is present and still holding the recovery codes. Handing them a working
`(app)` on the wizard's cookie ships an install whose MFA has never been tested,
and the discovery happens later, from outside, with nobody able to fix it.

## 10. Re-running setup (REQ-WIZ-12)

`completed_at` is never cleared and no `setup_steps` row is ever mutated. A
re-run appends a row with `run_ordinal = n+1` and emits `setup.step.rerun` —
never `setup.step.completed`, so no query over the trail can mistake a re-run for
a first run. It requires `global.setup-step.run`, step-up within 300 s
(REQ-AUT-07, `contracts/types/rbac.md` §3) and typed confirmation naming the step
(REQ-SET-10).

| Step | Re-runnable | Why |
|---|---|---|
| 1 `welcome-preflight` | yes, read-only | a diagnostic; it writes only a snapshot |
| 2 `create-admin` | **never** | REQ-WIZ-04: no path recreates the bootstrap account. Further admins are ordinary user administration (A03/A04) |
| 3 `smtp` | yes | re-verification is the supported way to change relays; recovery-by-email reverts to disabled until a new send is confirmed |
| 4 `edge-environment` | yes | the topology changes when the deployment moves |
| 5 `review-complete` | **never** | the completion record is immutable |

The re-run surface is a global-scope settings panel contributed from inside
`packages/setup` through `settings-registry` (REQ-SET-08). A24 never opens a file
under `apps/<app>/app/(app)/settings/`.

## 11. Audit events (REQ-WIZ-10)

Every step emits on completion, plus the lifecycle events below. All carry actor,
correlation id, result and a before/after diff where a value changed
(REQ-AUD-04); secrets are redacted at the source (REQ-AUD-05).

| Event | Severity | Notes |
|---|---|---|
| `setup.bootstrap.generated` | warning | actor `{kind: "system"}`; the password is not in the payload |
| `setup.bootstrap.rotated` | warning | the `SETUP_BOOTSTRAP_ROTATE=1` path only |
| `setup.wizard.entered` | info | one per bootstrap sign-in, with the superseded session id |
| `setup.preflight.completed` | info | the check table with per-check results |
| `setup.admin.created` | **critical** | the new `ActorRef`, factor kind, recovery-code count |
| `setup.bootstrap.disabled` | **critical** | same transaction as the above (§4) |
| `setup.smtp.verification_sent` / `_confirmed` | info | config hash, never the credential |
| `setup.smtp.configured` | warning | diff with `credentialRef` redacted |
| `setup.topology.set` | warning | diff: mode, challenge plan, deploy target |
| `setup.environment.reviewed` | info | state counts per class, no values |
| `setup.wizard.completed` | **critical** | the completion-record digest |
| `setup.step.rerun` | warning | step id, `run_ordinal`, actor, reason |
| `setup.bootstrap.rejected` | warning | a bootstrap cookie presented after teardown |

Bootstrap-era events have no tenant, so they join the global hash chain
(REQ-AUD-06); A13 owns the chain and A24 only emits.

## 12. Localisation and 390px (REQ-WIZ-14)

Namespace `setup`, ICU, `en` and `sv` at ship (REQ-I18N-03, REQ-I18N-06), no
user-visible literal in a rendered path (REQ-I18N-02) — including the Dokploy
guidance and every error detail. With no user preference and no tenant yet,
locale resolves `Accept-Language` → system default (REQ-I18N-04); step 1 offers a
switcher and the choice persists in `setup_state.draft`, so a resume keeps the
operator's language. At 390px: one step per screen, single column, 44px minimum
targets (REQ-UI-07), copy-paste blocks scrolling inside their own container so
the page never scrolls horizontally, and the ten recovery codes fitting at
390×664 with no truncation and no hidden scroll region — a code the operator
cannot see is a code they did not save. A `setup.wizard` surface budget is
declared and asserted at every breakpoint (REQ-UI-10). Every timestamp goes
through `packages/contracts/time` (REQ-TIM-04).

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Bootstrap identity | Not a `users` row, not a session | A constrained global admin is still a global admin (REQ-WIZ-03) | No |
| Bootstrap entropy | 160 bits, kernel CSPRNG, Crockford base32 | Survives a log leak being the only exposure | No |
| Regenerate on restart | No, unless `SETUP_BOOTSTRAP_ROTATE=1` | Restarts are routine; a moving password is worse than a stable one | No |
| Bootstrap sessions | One at a time, second supersedes first | Two operators racing the wizard is unrecoverable | No |
| Step order | preflight → admin → SMTP → edge/env → complete | The verification send doubles as the admin's email proof | No |
| Teardown | One transaction, create-verify-destroy | A crash between two commits bricks the install (REQ-WIZ-04) | No |
| `setup_steps` | Append-only, `(step, run_ordinal)` | No partial row means no partial state to interpret (REQ-WIZ-09) | No |
| SMTP step completion | Operator confirms a delivered code | A `250` is not a delivery (REQ-WIZ-06) | No |
| Verification send rate | 5 per hour per config hash | REQ-SEC-11 without blocking a legitimate retry | Yes, lower only |
| Lockout API code | `setup.incomplete` → 503, retryable | Not an authorisation failure (REQ-WIZ-13) | No |
| Health routes during lockout | Reachable, `setup: "pending"` | A redirect to a load balancer is an outage (REQ-FND-10) | No |
| Default topology | `self` — our HAProxy is the edge | REQ-PROX-01, REQ-PROX-03; HAProxy ships in every stack | Yes, per deployment |
| Topology under Dokploy | `behind-proxy`, HAProxy still ours, internal hop still TLS | Traefik owns the public certificate only (REQ-PROX-08) | Yes, per deployment |
| Challenges in `behind-proxy` | DNS-01 or DNS-PERSIST-01, refused at selection | Port 80 and the 443 handshake belong to the upstream (REQ-ACME-02) | No |
| `insecure_default` rows | Blocking, not waivable | REQ-FND-08; a dev KEK in production is not a warning | No |
| Setup-state tenancy | Not tenant-scoped (`contracts/types/wizard-state.md`) | No tenant exists yet, and the tenant comes from a session (REQ-RBA-03) | No |
| Completion | Forced sign-out, real login | Proves the new factor works while the operator is present (REQ-WIZ-11) | No |
| Re-run of `create-admin` | Never | REQ-WIZ-04 has no exception | No |

## How this is verified

- `pnpm --filter @app/setup test` — the step machine refuses every out-of-order
  transition; the preflight table; the env classifier against a fixture config
  holding one `ok`, one `missing` and one known dev value; challenge
  availability per topology mode.
- `pnpm test:integration` — a crash injected after `provisionGlobalAdmin` and
  before the teardown commit leaves the bootstrap credential working and no
  step-2 record; the retry is idempotent; a second boot neither regenerates nor
  reprints; `SETUP_BOOTSTRAP_ROTATE=1` refuses on a completed install.
- `pnpm test:setup-lockout` — every route group redirects; every non-setup
  `/api/v1` operation returns `setup.incomplete` with status 503 and
  `application/problem+json`; `/api/health/*` returns 200; a bootstrap cookie
  against 20 sampled tenant-scoped operations returns zero rows or raises.
- `pnpm test:e2e` — `tests/e2e/setup/**` (Playwright over CDP, REQ-TST-02): the
  five-step journey through `edge` against the compose relay, reading the
  delivered code from its mailbox, the forced sign-out, the first TOTP login.
- `pnpm test:audit` — the thirteen events of §11 fire exactly once with actor and
  result; no payload holds the bootstrap password, the relay credential or a live
  env value (searched for seeded sentinels).
- `pnpm test:visual` — five steps at 390/834/1440, light and dark, axe AA
  (REQ-TST-06); recovery codes fully visible at 390×664; no horizontal scroll.
- `pnpm i18n:check`, and `grep -rn "toLocaleString\|Intl.DateTimeFormat"` over
  `packages/setup` and `app/(setup)` returns nothing (REQ-I18N-02, REQ-TIM-04).
- `pnpm test:contract` — `packages/contracts/tests/wizard-state.spec.ts` plus
  `GET /api/v1/setup/_selftest` (REQ-CTR-08, REQ-CTR-10).

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| Deployment target | `dokploy` — it is the documented target (REQ-WIZ-08) |
| Topology pre-selected in step 4 | `behind-proxy` when the target is `dokploy`, `self` otherwise |
| Bootstrap email address | `admin@example.invalid`, fixed by REQ-WIZ-02 |
| May the first admin skip MFA | No. Not overridable — REQ-WIZ-05, REQ-AUT-05 |
| SMTP step when no relay exists yet | Setup cannot complete. A panel without email cannot reset a password |
| Extra first-run steps (branding, a first tenant) | None. Everything optional belongs in settings, not in the lockout |
