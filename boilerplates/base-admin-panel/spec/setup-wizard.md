# First-Run Setup Wizard

Five steps between a freshly started container and an admin panel with a real
owner. Owned by **A24** (`setup-wizard`): `packages/setup/**`,
`apps/<app>/app/(setup)/**`, and the tables `setup_state`, `setup_steps`. A24
publishes `wizard-state` and `setup-step`; it consumes `session`, `auth-policy`,
`mfa`, `rbac`, `mail-template`, `env-schema`. A24 defines no role (A04), writes
no audit row (A13), sends no mail (A12) and runs no ACME order (A25) — it records
decisions and emits events.

## Requirements covered

REQ-WIZ-01 … REQ-WIZ-14, REQ-PROX-03, REQ-PROX-08, REQ-ACME-03, REQ-AUT-05,
REQ-AUT-06, REQ-SEC-07, REQ-SEC-11, REQ-MAIL-04, REQ-MAIL-06, REQ-FND-04,
REQ-FND-07, REQ-AUD-04, REQ-SET-08, REQ-I18N-01, REQ-UI-07.

## 1. The step machine (REQ-WIZ-01)

Strictly ordered. A step is reachable only when every earlier step has a
`complete` record — no skip, no re-entry, no deep-link past the cursor. A step
whose entry condition is unmet returns `setup.step_out_of_order` (409).

| # | Step id | Entry condition | Writes | Complete when | On failure |
|---|---------|-----------------|--------|---------------|------------|
| 1 | `welcome-preflight` | bootstrap session valid, `setup_state.completed_at IS NULL` | `setup_steps` row with the preflight snapshot; chosen locale into `setup_state.draft` | every blocking check green | nothing recorded; re-check action; failed checks listed with their REQ ID |
| 2 | `create-admin` | step 1 complete | real global admin via `identity.provisionGlobalAdmin`; `setup_state.real_admin_actor_id`; bootstrap credential destroyed (§4) | the admin exists **with** an MFA factor enrolled and 10 recovery codes issued (REQ-AUT-05, REQ-AUT-06) | bootstrap credential still works, no admin half-exists, no record; retry idempotent on the same email |
| 3 | `smtp` | step 2 complete | `SenderIdentity` through A12's interface; verification token in `setup_state.draft` | a real message was **delivered** and its code entered (REQ-WIZ-06) | sender config not persisted, email-based password/OTP recovery stays disabled, relay error shown credential-free (REQ-MAIL-06) |
| 4 | `edge-environment` | step 3 complete | topology mode and certificate plan into the settings registry; environment report snapshot | a mode is chosen and every `blocking` environment row is cleared | mode unchanged, no partial write; an `insecure_default` row cannot be waived |
| 5 | `review-complete` | steps 1–4 complete | `setup_state.completed_at`, `completed_by`, `required_steps`, `steps_digest` | completion record committed and the operator is at `/sign-in` | no completion record; the wizard is still the only surface |

Step 2 precedes step 3 deliberately: step 3's verification send goes to the real
admin's address, so one action satisfies REQ-WIZ-06 and that address's
verification (REQ-MAIL-05). Step 1's preflight, all blocking: database over
`sslmode=verify-full` with a pinned CA (REQ-SEC-03), migrations at head, a KEK
`seal`/`open` round-trip (REQ-SEC-06), audit chain writable with a verifying head
(REQ-AUD-06), `edge` reachable over TLS internally (REQ-PROX-08), clock UTC with
drift under 5 s (REQ-TIM-03), `en` and `sv` loaded (REQ-I18N-06). Syslog
reachability is non-blocking — a down collector spools.

## 2. The bootstrap credential (REQ-WIZ-02)

`admin@example.invalid`. The password is generated on the first boot that finds
no `setup_state` row: 160 bits from the kernel CSPRNG through `packages/crypto`'s
`randomBytes(20)` — never `Math.random`, never a timestamp-derived seed —
Crockford base32 to 32 characters in four groups of eight. It is written **once**
to stdout, which is the container log, and stored only as an Argon2id hash with
A01's parameters (REQ-SEC-07). It is never a fixed default and never in the repo,
the image, `.env.example`, an audit payload or the ready probe, and it is not
recoverable server-side. Its length is fixed in code, not an env var.

**A second boot does not regenerate it.** With `bootstrap_password_hash`
non-null, boot generates nothing and prints nothing: restarts are routine, so
regeneration would invalidate the log line an operator scrolled back to, and each
boot would add one more record holding a live credential (REQ-FND-08). Lost
password, one path — boot once with `SETUP_BOOTSTRAP_ROTATE=1`, which rotates,
prints, emits `setup.bootstrap.rotated` and refuses when `completed_at` is set.
Rotation is not a way back into a finished install (REQ-WIZ-04).

## 3. What the bootstrap account may do (REQ-WIZ-03)

The failure mode this prevents is a global admin with a temporary password, so we
do not build one. **The bootstrap credential cannot produce an
`identity.Session`**: no `users` row, no `credentials` row, no role grant, no row
in A03's session store. Signing in mints an opaque 256-bit id in a `__Host-setup`
cookie (`HttpOnly`, `Secure`, `SameSite=Strict`) on the `setup_state` singleton,
one at a time — a second sign-in supersedes the first, so two operators cannot
race the wizard.

| Capability | Bootstrap principal |
|---|---|
| Read wizard state, step cursor, environment report | yes |
| Write step drafts, complete steps 1–5 | yes |
| Create the real global admin, once (§4) | yes |
| Trigger the SMTP verification send | yes, rate-limited (§5) |
| `/api/v1/**` outside `/api/v1/setup/**`; any `(app)`, `(auth)`, settings route | no |
| Any tenant-scoped read or write; another account, role grant or API key | no |
| Hold any permission string | no — it holds none |

Three enforcement layers, all server-side. The route kit resolves an actor from
the session cookie only, and a `__Host-setup` cookie is not a session, so every
check is deny-by-default against an empty permission set (REQ-RBA-02). The tenant
GUC is never set on a bootstrap request, so forced RLS denies every tenant-scoped
row (REQ-RBA-04). And `/api/v1/setup/**` is the only subtree whose guard accepts
this principal, by an allowlist in my own package. The `setup.*` permission
strings exist for the re-run surface (§10); nobody holds them during a first run.

## 4. Irreversible teardown (REQ-WIZ-04)

Step 2 is one transaction over `setup_state` and `setup_steps`:

```sql
BEGIN;   -- provisionGlobalAdmin has already returned an actor id, atomically,
         -- under idempotency key (setup_state.id, lower(email)).
  UPDATE setup_state
     SET real_admin_actor_id = $1, bootstrap_password_hash = NULL,  -- destroyed
         bootstrap_disabled_at = now(), bootstrap_session_id = NULL
   WHERE completed_at IS NULL AND bootstrap_disabled_at IS NULL;
  INSERT INTO setup_steps (step, run_ordinal, state, result, completed_at) ...;
COMMIT;
```

The ordering is the safety property: **create, verify, then destroy — never the
reverse.** The credential dies only after an admin exists holding an MFA factor
and issued recovery codes. One transaction makes "an admin exists" and "the
bootstrap credential is gone" inseparable in the record; two commits leave a
window where a crash bricks the install with no reachable account. A partial
failure must leave it usable: credential intact, no half-created admin, step 2
not recorded. A retry with the same email returns the same actor and re-attempts
the teardown, and the `WHERE` clause makes the update a no-op once it has run. No
re-enable path exists and nothing recreates the account — asserted by test.

## 5. Resumability (REQ-WIZ-09)

Two tables, one rule. `setup_state` is a singleton row holding the cursor, the
bootstrap fields, the completion record and `draft jsonb`. `setup_steps` is
**append-only**, keyed `(step, run_ordinal)`: a row exists only for a step that
completed, so after a crash there is no partial record to interpret. `draft` holds
only re-derivable, echo-safe values — locale, SMTP host, port, from-address, the
pending verification token — never a credential: the relay password arrives in
the request that completes step 3 and goes into A12's envelope-encrypted
`credentialRef` (REQ-SEC-06).

Three steps have effects outside my tables and are made idempotent one by one:

| Step | External effect | Idempotency mechanism |
|---|---|---|
| 2 `create-admin` | rows in A03's identity tables | idempotency key `(setup_state.id, lower(email))` on `provisionGlobalAdmin`; a replay returns the same actor and writes nothing new |
| 3 `smtp` | **a real email leaves the building** | a 128-bit token generated once per `(step, sha256(sender_config))`; the enqueue carries `idempotencyKey = "setup.smtp." + config_hash + "." + token` (REQ-MAIL-04), so a crash-and-resume re-enqueues nothing. Editing the config changes the hash, voids the token and forces a new send. Max 5 sends per hour per config hash (REQ-SEC-11) |
| 4 `edge-environment` | settings-registry values A25 and A01 read | a keyed upsert of one value per key, not an append — replaying it is a no-op |

Step 3 completes on **confirmation of delivery**, not on a `250` from the relay:
a relay accepting a message is not a delivered message. The operator enters the
8-character code from the received mail; a wrong code returns
`setup.verification_not_confirmed` (409) and does not consume the token.

## 6. Lockout semantics (REQ-WIZ-13)

While `completed_at IS NULL` the wizard is the only surface. Codes follow
`contracts/types/errors.md` §3: one status per code, never a generic 403.

| Caller | Response |
|---|---|
| Any route outside `(setup)` | `307` to `/setup`. The gate is the contract member `wizard-state` (`readSetupGate()`), implemented by `packages/setup` and registered at boot — the pattern A13 uses for `emitAuditEvent`. A01's `middleware.ts` and A05's `(app)` layout call the contract, never my package (REQ-CTR-01) |
| Any `/api/v1` call outside `/api/v1/setup/**` | `setup.incomplete` → **503**, `retryable: true`. Not `common.forbidden`: the caller's authorisation is not what is wrong, and a 403 sends an integrator hunting permissions for a condition that clears on its own |
| `/api/health/live`, `/api/health/ready` | 200, with `setup: "pending"` (REQ-FND-10). A load balancer must not see a redirect |
| A first-run route after completion | `setup.already_complete` (409) |
| A bootstrap cookie after teardown | `setup.bootstrap_disabled` (401), audited as `setup.bootstrap.rejected` |

## 7. Environment guidance (REQ-WIZ-07)

Generated from the **live parsed configuration** — A01's assembled `AppEnvSchema`
and its refinement results — not from a checklist in a document. One row per
declared key, classified `ok` / `missing` / `insecure_default`, with its owner and
REQ ID; the live value never appears (REQ-FND-08) and the copy-paste block carries
a placeholder. A key whose absence fails boot (REQ-FND-07) cannot appear as
`missing` — an app missing it is not running — so the report covers keys optional
at boot and load-bearing for a step.

| Key | Owner | REQ | State | Severity | Row renders |
|---|---|---|---|---|---|
| `DATABASE_URL` | A01 | REQ-SEC-03 | `ok` | info | `setup.env.tls_verified`; the `sslmode=verify-full` and `sslrootcert` refinements both passed |
| `MAIL_RELAY_PASSWORD` | A12 | REQ-MAIL-02 | `missing` | blocking for step 3 | `setup.env.missing_blocks_step`, `copyPaste: "MAIL_RELAY_PASSWORD=<relay password>"` |
| `CRYPTO_KEK` | A01 | REQ-SEC-06 | `insecure_default` | blocking, not waivable | `setup.env.dev_value_in_use`, `copyPaste: "CRYPTO_KEK=<openssl rand -base64 32>"` |

`insecure_default` is a constant-time match against the digests of the values
shipped in `compose.dev.yml` and the dev CA — a known-value comparison, not a
heuristic about how the string looks. Rules live in `packages/setup/env-rules.ts`,
each citing its REQ ID; a key another domain wants classified gets an
`insecureWhen` predicate on its own env declaration, which is a CCR, not a patch
to my table.

## 8. Step 4: edge topology, certificates, environment

Docker Compose is the deployment target (REQ-FND-04), and the path step 4 walks
by default is `docker compose up` on a clean host with DNS pointed at it: our
HAProxy edge terminates TLS, our ACME client provisions the certificate, nothing
else installed. That is REQ-PROX-03 `self` mode and it is pre-selected. HAProxy
is ours and always in the path (REQ-PROX-01); the question is which of three
topologies this deployment is, asked explicitly, never inferred (REQ-ACME-03):

| Mode | Path | Public certificate | Internal ACME | Challenges for the public name |
|---|---|---|---|---|
| `self` (**default**) | client → our HAProxy → app | ours | enabled, all four paths (REQ-ACME-01) | HTTP-01, TLS-ALPN-01, DNS-01, DNS-PERSIST-01 |
| `behind-proxy` | client → an upstream proxy → our HAProxy → app | the upstream's | disabled **for the public hostname only** | DNS-01, DNS-PERSIST-01 |
| `delegated` | client → external proxy → app | the external proxy's | fully disabled | none — the app orders no certificate |

`behind-proxy` is the generic case where something upstream already terminates
public TLS: a PaaS, a corporate load balancer, a CDN, a hand-rolled nginx. That
upstream answers on port 80 and owns the 443 handshake, so **HTTP-01 and
TLS-ALPN-01 for the public name cannot succeed**; they are refused at selection
rather than at issuance (REQ-ACME-02) and the step steers the operator to DNS-01
or DNS-PERSIST-01, with the reason stated. A25's `spec/acme-tls.md` holds the
authoritative availability matrix; step 4 reads it and does not restate it. The
HAProxy↔app hop is TLS in `self` and `behind-proxy` alike — REQ-SEC-01 and
REQ-PROX-08 have no exemption for traffic inside the compose network — so
`behind-proxy` means the upstream owns the public certificate, not that our proxy
stops doing TLS.

The step then shows the environment report (§7), the DNS records the chosen
challenge needs (name, type, value, TTL — REQ-ACME-04), and what to verify: a
certificate loaded at `edge`, HTTPS answering on the public name, an SSE stream
surviving the proxy (REQ-PROX-05).

### If a PaaS already fronts your containers (REQ-WIZ-08)

Shown when the mode is `behind-proxy`, one worked example per platform the intake
names. Dokploy is the shipped example:

| What | Dokploy |
|---|---|
| Where variables are set | The **Environment editor** in project settings. Dokploy writes the `.env`; values are referenced as `${VAR_NAME}`. Do not hand-edit `.env` inside the container |
| After changing a variable | **A container rebuild is required.** Changes are not picked up automatically. Every copy-paste block in this panel repeats that line, because this is what trips people |
| Where the domain is set | The **Domains tab**, not the compose file — Dokploy injects the Traefik labels at deploy time, so hand-written labels are the wrong layer. The domain points at **our `edge` service**, not the app container (REQ-PROX-02) |
| Networking | Every service is attached to the `dokploy-network` network |
| Why the mode is `behind-proxy` | Dokploy's Traefik does HTTP-01 itself, so the challenge here is DNS-based |

## 9. Completion and the first real login (REQ-WIZ-11)

Step 5 commits the completion record — `completed_at`, `completed_by` (the real
admin's `ActorRef`), `required_steps` (the step ids this version demanded),
`steps_digest` (SHA-256 over the ordered `(step, run_ordinal, completed_at,
result_digest)` tuples), `app_version`, `contract_version` — then destroys the
`__Host-setup` cookie and its row and redirects to `/sign-in`. The first login is
a **real login**, not a continuation: the wizard principal was never an
`identity.Session`, so it has no `amr`, no `mfaSatisfied` and no step-up, and
nothing about this account's authentication has been exercised. One forced login
proves password and TOTP work against the factor enrolled minutes earlier, while
the operator is present and holding the recovery codes. Continuing into `(app)`
on the wizard's cookie ships an install whose MFA has never been tested, and the
discovery happens later, from outside, with nobody able to fix it.

## 10. Re-running setup (REQ-WIZ-12)

`completed_at` is never cleared and no `setup_steps` row is ever mutated. A
re-run appends a row with `run_ordinal = n+1` and emits `setup.step.rerun` —
never `setup.step.completed`, so no query over the trail can mistake a re-run for
a first run. It requires `global.setup-step.run`, step-up within 300 s
(REQ-AUT-07, `contracts/types/rbac.md` §3) and typed confirmation naming the step
(REQ-SET-10). The surface is a global-scope settings panel contributed from inside
`packages/setup` through `settings-registry` (REQ-SET-08); A24 never opens a file
under `apps/<app>/app/(app)/settings/`.

| Step | Re-runnable | Why |
|---|---|---|
| 1 `welcome-preflight` | yes, read-only | a diagnostic; it writes only a snapshot |
| 2 `create-admin` | **never** | REQ-WIZ-04: no path recreates the bootstrap account. Further admins are ordinary user administration (A03/A04) |
| 3 `smtp` | yes | re-verification is how you change relays; recovery-by-email reverts to disabled until a new send is confirmed |
| 4 `edge-environment` | yes | the topology changes when the deployment moves |
| 5 `review-complete` | **never** | the completion record is immutable |

## 11. Audit events (REQ-WIZ-10)

Each step emits on completion, plus the lifecycle events below. All carry actor,
correlation id, result and a before/after diff where a value changed (REQ-AUD-04);
secrets are redacted at the source (REQ-AUD-05). Bootstrap-era events have no
tenant, so they join the global hash chain (REQ-AUD-06) — A13 owns the chain.

| Event | Severity | Payload notes |
|---|---|---|
| `setup.bootstrap.generated` / `.rotated` | warning | actor `{kind: "system"}`; the password is not in the payload |
| `setup.wizard.entered` | info | one per bootstrap sign-in, with the superseded session id |
| `setup.preflight.completed` | info | the check table with per-check results |
| `setup.admin.created` | **critical** | the new `ActorRef`, factor kind, recovery-code count |
| `setup.bootstrap.disabled` | **critical** | same transaction as the above (§4) |
| `setup.smtp.verification_sent` / `_confirmed` | info | config hash, never the credential |
| `setup.smtp.configured` | warning | diff with `credentialRef` redacted |
| `setup.topology.set` | warning | diff: mode, challenge plan, platform, and the environment-report state counts per class — never a value |
| `setup.wizard.completed` | **critical** | the completion-record digest |
| `setup.step.rerun` | warning | step id, `run_ordinal`, actor, reason |
| `setup.bootstrap.rejected` | warning | a bootstrap cookie presented after teardown |

## 12. Localisation and 390px (REQ-WIZ-14)

Namespace `setup`, ICU, `en` and `sv` at ship (REQ-I18N-03, REQ-I18N-06), no
user-visible literal in a rendered path (REQ-I18N-02) — platform notes and error
details included. With no user preference and no tenant yet, locale resolves
`Accept-Language` → system default (REQ-I18N-04); step 1 offers a switcher whose
choice persists in `setup_state.draft`, so a resume keeps the operator's language.
At 390px: one step per screen, single column, 44px targets (REQ-UI-07), copy-paste
blocks scrolling inside their own container so the page never scrolls
horizontally, and the ten recovery codes fitting at 390×664 with no truncation and
no hidden scroll region — a code the operator cannot see is a code they did not
save. The `setup.wizard` surface budget is asserted at every breakpoint
(REQ-UI-10); every timestamp goes through `packages/contracts/time` (REQ-TIM-04).

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Bootstrap identity | Not a `users` row, not a session | A constrained global admin is still a global admin (REQ-WIZ-03) | No |
| Bootstrap password | 160 bits, kernel CSPRNG, printed once, not regenerated on restart | Survives a log leak being the only exposure; a moving password is worse than a stable one | No |
| Teardown | One transaction, create-verify-destroy | A crash between two commits bricks the install (REQ-WIZ-04) | No |
| SMTP step completion | Operator confirms a delivered code; 5 sends/hour per config hash | A `250` is not a delivery (REQ-WIZ-06, REQ-SEC-11) | Rate, lower only |
| Lockout API code | `setup.incomplete` → 503, retryable; health routes stay 200 | Not an authorisation failure (REQ-WIZ-13, REQ-FND-10) | No |
| Primary deployment path | `docker compose up`, topology `self` | REQ-FND-04; one command must yield working HTTPS | Yes, per deployment |
| Platform guidance | A subsection under `behind-proxy`, Dokploy as the worked example | A PaaS is one instance of "an upstream terminates TLS", not the expected case | Yes, more examples |
| Challenges in `behind-proxy` | DNS-01 or DNS-PERSIST-01, refused at selection | Port 80 and the 443 handshake belong to the upstream (REQ-ACME-02) | No |
| Setup-state tenancy | Not tenant-scoped (`contracts/types/wizard-state.md`) | No tenant exists yet, and the tenant comes from a session (REQ-RBA-03) | No |
| Completion | Forced sign-out, real login; `create-admin` never re-runnable | Proves the new factor works while the operator is present (REQ-WIZ-11, REQ-WIZ-04) | No |

## How this is verified

| Command | What it proves |
|---|---|
| `pnpm --filter @app/setup test` | Every out-of-order transition refused; the preflight table; the env classifier against a fixture config with one `ok`, one `missing` and one known dev value; challenge availability per topology mode |
| `pnpm test:integration` | A crash injected after `provisionGlobalAdmin` and before the teardown commit leaves the credential working and no step-2 record; the retry is idempotent; a second boot neither regenerates nor reprints; `SETUP_BOOTSTRAP_ROTATE=1` refuses on a completed install |
| `pnpm test:setup-lockout` | Every route group redirects; every non-setup `/api/v1` operation returns `setup.incomplete`, 503, `application/problem+json`; `/api/health/*` returns 200; a bootstrap cookie against 20 sampled tenant-scoped operations returns zero rows or raises |
| `pnpm test:e2e` (`tests/e2e/setup/**`, CDP, REQ-TST-02) | The five steps through `edge` in `self` mode against the compose relay, reading the delivered code from its mailbox, the forced sign-out, the first TOTP login; then the same run in `behind-proxy`, asserting HTTP-01 is refused at selection |
| `pnpm test:audit` | Every event row of §11 fires exactly once with actor and result; no payload holds the bootstrap password, the relay credential or a live env value (seeded sentinels) |
| `pnpm test:visual`; `pnpm i18n:check`; `grep -rn "toLocaleString\|Intl.DateTimeFormat" packages/setup apps/*/app/\(setup\)` | Five steps at 390/834/1440, light and dark, axe AA (REQ-TST-06); recovery codes fully visible at 390×664; no horizontal scroll; no hardcoded literal and no local date formatting (REQ-I18N-02, REQ-TIM-04) |
| `pnpm test:contract`; `GET /api/v1/setup/_selftest` | `packages/contracts/tests/wizard-state.spec.ts` passes both sides (REQ-CTR-10) and the domain asserts its own contract (REQ-CTR-08) |

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| Topology pre-selected in step 4 | `self` — plain Docker Compose with our edge owning TLS |
| Platform notes to ship | Dokploy only; another platform is a panel, not a code path |
| May the first admin skip MFA | No. Not overridable — REQ-WIZ-05, REQ-AUT-05 |
| SMTP step when no relay exists yet | Setup cannot complete. A panel without email cannot reset a password |
| Extra first-run steps (branding, a first tenant) | None. Everything optional belongs in settings, not in the lockout |
