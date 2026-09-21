# Certificates & TLS Automation

The ACME client, the four validation paths, the renewal scheduler and the
certificate inventory. Owned by **A25** (`acme-tls`): `packages/acme/**`,
`packages/tls/**`, and the tables `acme_accounts`, `certificates`,
`cert_orders`, `cert_renewal_log`, `dns_providers`. A25 publishes
`acme-account`, `certificate`, `cert-renewal` and `dns-provider`; it consumes
`crypto` and `egress-client` (A01), `notification-event` (A12), `audit-event`
(A13), `console-stream` (A13), `grid-def` (A07) and `settings-registry` (A05).
A25 contributes its panels to the **global** settings scope from inside
`packages/acme/` and never opens a file under
`apps/<app>/app/(app)/settings/` (REQ-SET-08).

## Requirements covered

REQ-ACME-01 … REQ-ACME-18, REQ-SEC-01, REQ-SEC-06, REQ-SEC-12, REQ-AUD-01,
REQ-AUD-05, REQ-AUD-12, REQ-FND-05, REQ-FND-07, REQ-SET-05, REQ-SET-08,
REQ-SET-10, REQ-WIZ-08, REQ-RBA-01, REQ-RBA-06, REQ-TIM-04, REQ-CTR-08.

## 1. Termination mode: who owns port 80 (REQ-ACME-03)

Two ACME clients competing for the same domain and the same challenge port is
the most common deployment failure in this subsystem, and under Dokploy it is
the *default* situation: Dokploy's Traefik already performs Let's Encrypt
HTTP-01 and needs port 80 for it. So the mode is explicit, it is chosen before
anything is ordered, and under Dokploy the shipped default is **delegated**.

| Mode | What the app does |
|---|---|
| `self` | Binds `ACME_HTTP01_PORT` (80) and `ACME_ALPN_PORT` (443), registers an ACME account, orders, installs and hot-reloads (§8). Owns the certificate lifecycle end to end. |
| `delegated` | Binds neither. The internal client is **disabled**: no account, no orders, no scheduler tick. TLS is terminated by the reverse proxy, which renews on its own schedule. |

**The mode lives in `TLS_TERMINATION_MODE`, not in a database row.** It decides
whether a port is bound at boot, so it is an env value parsed by A01's single
Zod schema with no default (REQ-FND-07) — a security-relevant key never gets a
silent default. A DB-stored mode would be changeable by a request and would
take effect only after a restart, so the settings screen would be showing a
value the running process is not using. The screen shows the parsed env value,
the detection result below it, and how to change it: the Dokploy Environment
editor writes the `.env` and a container rebuild is required before it takes
effect (REQ-WIZ-08).

**Detection heuristic — "is something else already terminating TLS for this
domain?"** Four probes, run at boot and on demand, all outbound HTTP through
A01's egress client (REQ-SEC-12):

1. **TLS probe.** Connect to `https://<domain>:443` with SNI and read the leaf.
   Compare its SPKI SHA-256 against the pin of the certificate we installed. A
   leaf we did not install means another terminator.
2. **Marker probe.** `GET http://<domain>/.well-known/acme-challenge/<random>`.
   Our own responder answers 404 with `X-Acme-Responder: self`. A 404 without
   the marker, a Traefik error page, or a 308 to HTTPS we did not emit means
   another process holds port 80.
3. **Bind probe.** Try to bind `ACME_HTTP01_PORT` in-process. `EADDRINUSE` is
   conclusive. A *successful* bind while probe 2 still misses the marker is also
   conclusive, and it is the Dokploy case: we hold the port inside the container
   and Traefik holds it on the host.
4. **Platform probe.** `dokploy-network` attached to the service plus a
   `Server:` header we do not emit. Dokploy configures domains in its Domains
   tab, not in the compose file, so the app cannot see its own routing.

The result is three-state: `self`, `delegated`, or **`conflict`** — mode is
`self` but another responder answers. `conflict` blocks ordering. Ordering
anyway means racing Traefik for the same token path, losing, and spending the
failed-validation budget (§9) on a race we cannot win.

**Delegated mode is not a blank screen.** The panel renders with: the detected
responder, why the internal client is off, the proxy's own certificate read live
from probe 1 — issuer, SAN list, `notAfter`, SPKI pin — as an `observed`
inventory row (§12), and the Dokploy instructions. REQ-ACME-16 is satisfied in
delegated mode by observation. Silently doing nothing is the failure this
paragraph exists to prevent.

## 2. The four validation paths (REQ-ACME-01, REQ-ACME-02, REQ-ACME-15)

Challenge type is per certificate, stored on the `certificates` row, and the UI
refuses a selection whose prerequisite is unmet rather than letting the order
fail at the CA (REQ-ACME-02). The offered set is read from the CA directory and
the authorization object at runtime, never hardcoded — a CA that does not offer
a type does not show it.

### 2.1 HTTP-01 (RFC 8555 §8.3)

**Proves:** control of the HTTP server answering on port 80 for the name, right
now. **Prerequisite:** inbound TCP/80 reaches *this* process, and termination
mode is `self`. **The user does nothing** — we serve
`/.well-known/acme-challenge/<token>` ourselves.

**What goes wrong:** the reverse proxy answers first (§1); the firewall allows
443 but not 80; the CA follows a 308 to HTTPS and hits a certificate that is not
yet valid (permitted — the CA ignores certificate errors on the redirect target,
but a redirect to a *different host* fails); a CDN caches the 404 from before
the token existed. **Choose it when** the app is the only thing on port 80 and
the names are concrete, not wildcards. **No wildcard support.**

### 2.2 DNS-01 (RFC 8555 §8.4)

**Proves:** write access to the zone, right now, via a TXT record at
`_acme-challenge.<name>` holding the base64url SHA-256 of
`<token>.<accountKeyThumbprint>`. **Prerequisite:** either a `dns_providers`
credential for the zone (§11) or a human who will create the record.

**What the user must do:** nothing if a provider is configured; otherwise create
one TXT record per name, guided by §3. **What goes wrong:** the record is
created in the wrong zone (an apex zone when the name is delegated to a child);
`_acme-challenge` is CNAME'd and the operator edits the target of the CNAME
instead of the target zone; a long TTL on a *previous* value means the CA reads
a stale answer; a wildcard and its base name both need a record at the *same*
`_acme-challenge.example.com` and the second write replaces the first instead of
adding a second TXT RR. **Choose it when** the name is a wildcard, port 80 is
not reachable, or termination is delegated but we still want our own
certificate. **Wildcards: yes.**

### 2.3 TLS-ALPN-01 (RFC 8737)

**Proves:** control of the TLS server on port 443 for the name, via a
self-signed certificate carrying the key authorization in an
`acmeIdentifier` extension, served only under the `acme-tls/1` ALPN protocol.
**Prerequisite:** inbound TCP/443 reaches this process *and* we own the TLS
handshake — it cannot work behind a proxy that terminates TLS itself.

**The user does nothing.** **What goes wrong:** anything that terminates TLS in
front of us breaks it completely, which is most managed platforms including
Dokploy; an L7 load balancer strips the ALPN; the `acme-tls/1` handler leaks
into normal traffic if the ALPN match is not exact. **Choose it when** port 80
is firewalled but 443 is ours — that is the one case it wins. **No wildcard
support.**

### 2.4 DNS-PERSIST-01 (draft-ietf-acme-dns-persist)

**Proves:** that the domain holder has authorised *this ACME account at this CA*
to issue for the name, indefinitely. It does **not** prove control right now.
That is the whole point and the whole risk. Detailed in §4.

**Prerequisite:** the CA directory advertises `dns-persist-01`, and one
persistent TXT record exists per name. **Wildcards: yes**, with
`policy=wildcard`.

### Wildcard enforcement (REQ-ACME-15)

| Path | Wildcard | Multiple SANs |
|---|---|---|
| HTTP-01 | No | Yes, one challenge per name |
| DNS-01 | **Yes** | Yes |
| TLS-ALPN-01 | No | Yes, one handshake per name |
| DNS-PERSIST-01 | **Yes** (`policy=wildcard`) | Yes |

A SAN list containing a `*.` entry disables HTTP-01 and TLS-ALPN-01 in the
picker, with the reason shown inline. Typing a wildcard into a name field while
HTTP-01 is selected switches the picker and says why. The order is never
submitted to fail — REQ-ACME-15 is enforced in the form, not discovered at the
CA.

## 3. Guided DNS setup and the authoritative check (REQ-ACME-04)

The panel shows the record to create as four discrete, copyable fields, because
a single pasted string is where the mistakes live:

| Field | Value |
|---|---|
| Name | `_acme-challenge.app.example.com` (fully qualified, with the trailing dot shown) |
| Type | `TXT` |
| Value | the base64url key authorization digest, 43 characters |
| TTL | `60` — short, so a corrected value is visible in a minute rather than an hour |

**The propagation check queries the domain's authoritative nameservers, not a
recursive resolver.** Walk from the FQDN up to the registrable-domain boundary,
take the `NS` set, resolve each nameserver to an address, and query each one
directly with `RD=0`.

This distinction is the whole feature. A recursive resolver that was asked for
`_acme-challenge.app.example.com` *before* the record existed caches the
negative answer for the zone's SOA `MINIMUM` — routinely 300 to 3600 seconds. A
correct record then reads as missing for up to an hour. The operator deletes it,
re-creates it, changes provider, and never finds the real fault, because there
was none. Querying authoritative cannot see a cached negative, and it is also
what the CA does.

- Results are **per nameserver**, listed. A zone with one lagging secondary is
  visible instead of a coin flip, and the CA may query any of them.
- A `CNAME` at `_acme-challenge` is followed and the delegation chain is shown,
  because that is the supported way to delegate validation to a separate zone.
- Ordering is refused while any authoritative nameserver disagrees, and the
  refusal names the nameserver and quotes what it returned.
- Re-check polls for 10 minutes with the remaining time shown, then stops and
  waits for the operator. A spinner that never ends is not a diagnostic.

**The named cleartext exception (REQ-SEC-01).** These verification queries go to
arbitrary authoritative nameservers, most of which do not speak DNS-over-TLS, so
they are UDP/53 in the clear where DoT (RFC 7858) is unavailable. This is the
only cleartext egress in A25. It is acceptable and it is recorded in the
compliance set for A18: the query carries no secret, and the answer is compared
against a value we published ourselves, so a forged answer can only make a
correct record look wrong — it cannot cause a wrong certificate. **DNS provider
API calls carry credentials and have no exception**: HTTPS through A01's egress
client, always (REQ-SEC-12).

## 4. DNS-PERSIST-01 and the account-key trap (REQ-ACME-05)

The record is a TXT at `_validation-persist.<domain>`, whose value uses the CAA
`issue` property syntax of RFC 8659 §4.2 with RFC 8657's `accounturi`
parameter:

```
_validation-persist.example.com. 300 IN TXT "letsencrypt.org; accounturi=https://acme-v02.api.letsencrypt.org/acme/acct/1234567890"
```

Two optional parameters: `persistUntil=<unix seconds, UTC>`, after which the CA
refuses to validate against the record, and `policy=wildcard`, which broadens
the authorization to the wildcard and to subdomains of the validated name.

**We publish no `persistUntil` by default.** An expiry the operator has
forgotten is a scheduled outage with a one-year fuse. An operator who wants one
sets it, and the inventory then shows the record expiry beside the certificate
expiry under the same escalation ladder (§10).

**The account key thumbprint is displayed next to the record.** RFC 7638 JWK
SHA-256 thumbprint, base64url, with a copy action. The account URI alone does
not tell the operator *which key* the record is trusting, so an account restored
from a backup under a different key looks identical in DNS and is invisible
until a renewal fails.

**The trap, plainly.** With DNS-01, the secret that matters is DNS write access
and it is needed for 30 seconds per renewal. With DNS-PERSIST-01 the record
lives in the zone indefinitely, and the ACME **account key** becomes the entire
security boundary for every name it authorises.

- Creating a **new account** produces a new account URI. Every persistent record
  in every zone silently stops authorising us. Nothing breaks that day — the
  first symptom is a failed renewal on a certificate that has worked for a year.
- **Deactivating** the account is immediate, irreversible, and takes down every
  domain under it at once.
- A **key change** (RFC 8555 §7.3.5) keeps the account URI, so the record should
  remain valid. **We do not rely on that.** A25 treats any account key change as
  invalidating every persistent record, because the draft permits a CA to bind
  more tightly than the URI, because a second CA's behaviour is not ours to
  assume, and because being wrong means every certificate in the fleet failing
  to renew simultaneously. Assume a rotation breaks every record.

So `global.acme-account.rotate` is refused while any certificate uses
DNS-PERSIST-01, unless the operator passes a typed confirmation naming every
zone whose record must be re-published (REQ-SET-10). The rotation then writes
`persistState: "needs_republish"` onto every affected certificate, raises one
`acme.persist-record-invalid` notification per zone at `critical`, and the
inventory shows each one as blocked until the authoritative check (§3) sees the
new account URI.

**Availability is probed, never assumed.** Let's Encrypt announced
DNS-PERSIST-01 on 2026-02-18 with staging in late Q1 2026 and production
*targeted* for Q2 2026; CA/Browser Forum ballot SC-088v3 defining BR
§3.2.2.4.22 passed in October 2025 and the IETF ACME working group adopted the
draft the same month. **No source confirms production availability as of
2026-09-21.** The picker offers `dns-persist-01` only when the CA directory
advertises it, and shows "not offered by this CA directory" otherwise. Do not
ship it as a default until it is externally confirmed in production.

## 5. The renewal scheduler (REQ-ACME-06 … REQ-ACME-09)

Renewal is ARI-driven (RFC 9773) and requires no future user intervention ever
(REQ-ACME-06). A deployment left alone for a year keeps working because the
scheduler asks the CA when to renew instead of guessing.

The ARI resource id is the base64url `keyIdentifier` of the leaf's Authority Key
Identifier, a `.`, and the base64url DER serial, trailing `=` stripped. The
response carries `suggestedWindow: { start, end }` and an optional
`explanationURL`. Every renewal order sends `replaces`, which lets the CA retire
the predecessor and — under Let's Encrypt policy — exempts the renewal from the
duplicate-certificate limit (§9).

```
every ACME_CHECK_INTERVAL_MINUTES, per certificate where installed_at is not null:

  1. GET <directory.renewalInfo>/<certID>      # A01 egress client, TLS verified
  2. on 200:
       lower = max(window.start, now)
       upper = window.end - ACME_RENEWAL_SAFETY_MARGIN_HOURS
       target = upper <= lower ? now                       # window tighter than the margin
                               : lower + random() * (upper - lower)
       persist ari_window_start, ari_window_end, next_attempt_at = target
  3. if target <= now + interval: run the attempt at target
  4. on 404 / 410 / 5xx / timeout / malformed: fall back (below), count it,
     and surface "ARI unavailable" on the inventory row
  5. sleep min(Retry-After, interval)
```

**The jitter is the random selection itself** — a uniform draw across
`[lower, upper]`, which is RFC 9773's own recommendation. Every deployment of
this boilerplate renewing the same 160-hour profile against the same CA would
otherwise converge on the same instant. No separate jitter constant exists; a
second source of randomness on top of a random draw is noise.

**Fallback when ARI is unavailable: renew at 50% of the certificate's
lifetime.** `target = notBefore + (notAfter - notBefore) / 2`, clamped to no
later than `notAfter - margin`. One rule, correct at both scales: a 160-hour
certificate is attempted at 80 hours with 80 hours of failure budget left,
a ~3.3-day cadence that lands inside Let's Encrypt's 2–3 day recommendation; a
90-day certificate is attempted at day 45. The fallback is deliberately earlier
than ARI would advise, because a client that has lost contact with the CA's
advice should spend margin, not save it.

**Shipped defaults, correct for a 160-hour certificate (REQ-ACME-08,
REQ-ACME-09).** Let's Encrypt's `shortlived` profile is exactly 160 hours, it is
selected by the `ACME_CERT_PROFILE` value, and it is opt-in — `classic` remains
the default because 6-day certificates demand automation this app can provide
but the operator's DNS and proxy may not.

| Knob | Default | Range | Why |
|---|---|---|---|
| `ACME_CHECK_INTERVAL_MINUTES` | `360` (6 h) | 60 … 1440 | 27 ARI checks across a 160-hour lifetime; four times the "at least daily" floor. 1 h is the configurable minimum REQ-ACME-08 names. Above 1440 is refused — it would break REQ-ACME-09. |
| `ACME_RENEWAL_SAFETY_MARGIN_HOURS` | `8` | ≥ 1, and **≥ the check interval** | Room for one missed check plus a full retry ladder inside the window. 5% of a 160-hour lifetime, 0.4% of a 90-day one. |
| `ACME_CERT_PROFILE` | `classic` | `classic` \| `shortlived` | Opt-in, not default. |

The boot schema rejects `margin < interval` (REQ-FND-07): a margin shorter than
the poll interval lets the scheduler sleep straight past the window's end.

**As the margin shrinks**, behaviour tightens rather than staying linear. Once
`now >= upper`, the target is `now` and every tick attempts. Retry backoff is
exponential from 2 minutes, capped at 1 hour — except after a *validation*
failure, where the floor is 15 minutes, because the failed-validation budget
refills at one per 12 minutes per identifier (§9) and a tighter retry burns the
budget that the next real attempt needs. Notifications escalate on the ladder in
§10.

**Why "renew at 2/3 of the lifetime" is wrong here.** Two reasons, and the
second is the one that bites. First, a fixed fraction cannot know what the CA
knows: a mass revocation, a load spike, a compliance-driven early replacement.
ARI exists because in 2020 there was no way for a CA to say "renew now".
Second, the arithmetic fails at 160 hours: 2/3 elapsed means renewing every
107 hours, about 1.6 certificates per week per name — and a single failed
attempt with a retry doubles that, which walks straight into the
5-duplicate-certificates-per-week limit. The ARI path avoids this because
`replaces` exempts the renewal from that limit. A fixed-fraction client does not
send `replaces` and has nothing to fall back on.

## 6. The ACME debug log (REQ-ACME-10)

Every protocol step, request, response, challenge state transition, DNS lookup
and error, with millisecond timestamps, surfaced **in the certificate renewal
settings screen** — not in a separate console the operator has to correlate by
hand.

**It reuses `console-stream` rather than inventing a second protocol.** Same
`ConsoleFrameSchema`, same `gap` and `hello` control events, same SSE transport
with `Last-Event-ID` resume and a `: ping` every 15 s, same compact-mode column
widths (time 12, level 3, domain 14, event 24, message rest, two spaces
between), same six levels with their three-letter tags and `--console-*` theme
tokens, same ANSI rules. A25 files one **additive CCR** adding `"acme"` to the
frozen `domain` enum, which `contracts/events/console-stream.md` §9 lists as
additive. Nothing else in that contract changes.

```
HH:mm:ss.SSS  LVL  domain........  event...................  message
09:14:02.118  INF  acme            order.new                 names=app.example.com profile=shortlived
09:14:02.402  DBG  acme            authz.challenge           type=dns-01 status=pending
09:14:02.611  INF  acme            dns.record-write          provider=cloudflare zone=example.com ttl=60
09:14:33.905  DBG  acme            dns.authoritative-check   ns=ns1.example.net result=match
09:14:34.010  WRN  acme            dns.authoritative-check   ns=ns2.example.net result=nxdomain attempt=1
09:15:06.744  INF  acme            authz.valid               type=dns-01 elapsed=184s
09:15:07.220  ERR  acme            order.failed              code=urn:ietf:params:acme:error:rateLimited retryAfter=3600
```

**Redaction (REQ-ACME-12, REQ-AUD-05, REQ-AUD-12).** The frame passes through
A13's single redactor at emit, before the frame exists — not at render, not at
download. On top of that:

- The **account key**, every **certificate private key** and every **DNS
  provider credential** never appear, in any mode. They are not declared
  `mask`; they are absent.
- **JWS payloads are scrubbed, not dumped.** A protocol frame records the
  method, the URL, the HTTP status, the `nonce` length, the `kid`, the decoded
  `protected` header's `alg` and `url`, and the *field names* of the payload.
  The `signature`, the raw `payload` and any `jwk` are dropped. A base64url blob
  in a log is an unreadable diagnostic and a readable key.
- `fields` values are scalars capped at 200 characters, so a PEM chain or a
  response body cannot be attached to a frame at all.
- The secret-shaped detector already in the contract (PEM blocks, 32+ character
  high-entropy strings, JWT shapes) drops any frame that slips, emits a `gap`
  with `reason: "redaction_failure"`, and raises a `system` audit event.

Durable copy: `cert_renewal_log`, retained `ACME_DEBUG_LOG_RETENTION_DAYS`
(default 30), so the panel can show the *last* failure after the ring has
rotated. The stream is a tail; the table is the record. Both are redacted by the
same function. Timestamps are UTC `timestamptz` and are formatted only at the
edge by `packages/contracts/time` (REQ-TIM-04).

## 7. Key custody (REQ-ACME-12)

| Material | Where it lives | Form |
|---|---|---|
| ACME account key | `acme_accounts.private_key_enc` | Envelope ciphertext, rotatable KEK (REQ-SEC-06) |
| Certificate private key | `certificates.private_key_enc` | Envelope ciphertext |
| Certificate chain, leaf | `certificates.chain_pem`, `leaf_pem` | Cleartext — it is public |
| DNS provider credentials | `dns_providers.credentials_enc` | Envelope ciphertext, per-field |
| SPKI pin | `certificates.spki_sha256` | Cleartext digest, used by the §1 probe |

Keys are generated in-process and never written to a file: Postgres is the only
datastore (REQ-FND-05), and a key written into a container is gone on the next
Dokploy rebuild. There is **no export route for any private key**, not
permission-gated, not step-up, not for a superadmin. An operator who needs the
key off the box is asking for a different product.

The rule, absolutely: **a private key never enters a log, a debug stream, an
export or an audit diff.** An audit diff records that the material changed —
`{ before: { accountKey: "[redacted]" }, after: { accountKey: "[redacted:changed]" } }`
— which preserves "the key was rotated" without the key
(`spec/observability.md` §4). The registry entries that enforce this are
generated from the `secret: true` flags in the contract (§11), so a new
secret-bearing field cannot be added without its redaction declaration.

## 8. Atomic install and hot reload (REQ-ACME-13)

`packages/tls` holds one `Map<sniName, tls.SecureContext>`, and the HTTPS server
resolves it through `SNICallback`. A `SecureContext` is referenced by the socket
at handshake time and never re-looked-up, so replacing a map entry is invisible
to every connection already open. Install is therefore one assignment — and the
validation happens **before** it:

1. The private key's public half equals the leaf's SPKI.
2. The chain builds to a trusted root, leaf first, no gaps.
3. `notBefore <= now <= notAfter`, with the clock checked against the CA's
   `Date` header — a skewed clock is the failure mode RFC 9773 §9 names.
4. Every configured name is covered by the leaf's `subjectAltName`, wildcards
   matched by label, not by substring.
5. The signature algorithm is in the allowed set.
6. `tls.createSecureContext()` returns without throwing.

**If any check fails, the swap does not happen.** The old context keeps serving,
the order is marked `install_failed`, the debug log records which check failed
with the offending value, and a `critical` notification fires. A half-installed
certificate is worse than an expiring one: an expiring certificate still serves
traffic for the rest of its margin. The rejected material stays in the row with
`installed_at: null` so it can be inspected rather than silently re-fetched.

**No restart, and no dropped connections** — in-flight requests finish on the
old context and the next handshake gets the new one. Multi-instance deployments
learn about the swap through `NOTIFY acme_cert_installed, '<certificate id>'`;
each instance reloads that one context from the row. Polling would mean an
instance serving a revoked certificate for the length of the poll interval, and
LISTEN/NOTIFY costs nothing because Postgres is already the only datastore.

In `delegated` mode there is no context map and nothing to reload.

## 9. Staging first, and rate limits (REQ-ACME-14)

`ACME_DIRECTORY_URL` defaults to the Let's Encrypt **staging** directory, and a
production order for a name is refused until a staging order for that same name
has succeeded. The precondition is a row in `cert_orders`, not a checkbox the
operator can click past. Staging leaves are never installed into the SNI map and
are labelled `staging` in the inventory — they are not browser-trusted, and an
operator must not spend an afternoon wondering why the padlock is broken.

**Rate limits are read, not remembered.** Let's Encrypt restructured its limits
in 2025 and the numbers move, so `packages/acme/rate-limits.json` records them
with a source URL and a fetch timestamp, refreshed at build time under the same
rule as every dependency version (REQ-VER-02 — a limit you remember is wrong).
Confirmed at the time of writing, from Let's Encrypt's rate-limit documentation:
**50 new certificates per registered domain per week**, **5 duplicate
certificates per exact name set per week**, and **5 failed validations per
account per identifier per hour, refilling one per 12 minutes**. ARI-driven
renewals carrying `replaces` are exempt from the duplicate-certificate limit
under Let's Encrypt policy, which is the second reason §5 always sends it.

Two layers, because the recorded numbers can be stale:

- **Pre-flight**, from the recorded limits: before an order the panel states the
  issuances for this registrable domain in the last 7 days, the duplicate count
  for this exact name set, and the failed-validation budget remaining. An order
  that the recorded limits say would be refused is blocked, with an audited
  override (`acme.rate-limit.override`) for the case where the recorded numbers
  are the thing that is wrong.
- **In-flight**, from the CA: a `urn:ietf:params:acme:error:rateLimited` problem
  is obeyed exactly — `Retry-After` is honoured to the second and no retry is
  attempted before it. The CA's answer always outranks our copy of its docs.

## 10. Failure alerting (REQ-ACME-11)

Silent failure until an outage is not acceptable. A25 emits through A12's
`notification-event`; it never sends mail itself.

The thresholds are **fractions of the certificate's own lifetime, not absolute
hours.** An absolute "7 days remaining" threshold never fires at all on a
160-hour certificate — it is already past by the time the certificate exists.
With `r = (notAfter - now) / (notAfter - notBefore)`:

| Condition | Category | Severity | Channels |
|---|---|---|---|
| Attempt failed, `r > 0.5` | — | — | Debug log only. One failed attempt with most of the lifetime left is noise. |
| ≥ 3 consecutive failures, or `r <= 0.5` | `acme.renewal-failing` | `warning` | in_app, email (digestable) |
| `r <= 0.25` and a failure | `acme.renewal-failing` | `warning` | Every failure, no digest |
| `now >= windowEnd - 2 × margin` | `acme.renewal-critical` | `critical` | in_app, push, email to global operators |
| `now > notAfter` | `acme.certificate-expired` | `critical` | in_app, push, email |
| Persistent record no longer authorises us | `acme.persist-record-invalid` | `critical` | in_app, push, email, per zone |
| Recorded limit 80% consumed | `acme.rate-limit-approaching` | `warning` | in_app, email (digestable) |
| Install succeeded | `acme.certificate-installed` | `info` | in_app (digestable) |

Every category declares `permission: "global.certificate.read"`, so it is
invisible to and undeliverable for anyone who cannot see certificates. Payloads
carry a `ref` and i18n keys under the `acme` namespace, never a rendered
sentence and never key material (REQ-PWA-04).

## 11. The DNS provider registry (REQ-ACME-18)

Adding a provider is **data**: one descriptor file in
`packages/acme/providers/<id>.ts` plus a fixture. No new branch in a switch, no
change to the challenge code. The descriptor drives the credential form, the
egress allowlist entry, the redaction declarations and the audit target, so the
four cannot disagree.

```ts
// packages/acme/providers/cloudflare.ts
export const cloudflare: DnsProviderDescriptor = {
  id: "cloudflare",
  label: "Cloudflare",
  apiBase: "https://api.cloudflare.com/client/v4",
  minimumScope: "Zone:DNS:Edit, scoped to the single zone",   // REQ-ACME-18
  credentials: [
    { key: "apiToken", labelKey: "acme.provider.cloudflare.token", secret: true,
      pattern: "^[A-Za-z0-9_-]{40}$",
      hintKey: "acme.provider.cloudflare.tokenHint" },        // "Zone → DNS → Edit. Not a Global API Key."
  ],
  operations: {
    findZone:  { method: "GET",    path: "/zones?name={zone}", pick: "result[0].id" },
    listTxt:   { method: "GET",    path: "/zones/{zoneId}/dns_records?type=TXT&name={recordName}", pick: "result" },
    createTxt: { method: "POST",   path: "/zones/{zoneId}/dns_records",
                 body: { type: "TXT", name: "{recordName}", content: "{value}", ttl: 60 } },
    deleteTxt: { method: "DELETE", path: "/zones/{zoneId}/dns_records/{recordId}" },
  },
  propagationHintSeconds: 30,
  supportsWildcard: true,
};
```

- **Credentials are scoped to the minimum the provider allows**, and
  `minimumScope` is shown in the form as required reading, not buried in help.
  Cloudflare gets a zone-scoped `Zone:DNS:Edit` token, never a Global API Key,
  and the field hint says so at the point of entry.
- `secret: true` fields are envelope-encrypted (REQ-SEC-06), write-only through
  the API — never returned, not even masked with a length — and they **generate**
  their redaction declarations. A new provider cannot forget to redact.
- Every call goes through A01's egress client against `apiBase`, which is the
  allowlist entry (REQ-SEC-12). A descriptor whose `apiBase` is not HTTPS fails
  the assembly lint.
- A `manual` provider always exists: the operator creates the record by hand and
  presses re-check. DNS-01 must work for a zone hosted anywhere, including a
  registrar with no API.
- **The bounded escape hatch:** a provider needing request signing, pagination
  or a custom auth dance declares `adapter: "./adapters/<id>"`. The descriptor
  is still the registry entry, so the panel, the credential form, the redaction
  rules and the audit target come from the same place. A provider implemented as
  an adapter *without* a descriptor is a defect.

## 12. Inventory and audit (REQ-ACME-16, REQ-ACME-17)

The inventory is an A07 grid (`grid-def`) over `certificates`: SAN list, issuer
CN, profile, challenge type, `notBefore`/`notAfter`, remaining lifetime, status,
last renewal result, next scheduled check, next attempt target, ARI window start
and end, and termination mode. Every instant is UTC in the column data and
formatted at the edge by `packages/contracts/time` (REQ-TIM-04) — a certificate
that reads as valid in one operator's timezone and expired in another's is
exactly the bug that formatter exists to prevent.

The detail view adds the full issuance history from `cert_renewal_log`, the
account URI and its key thumbprint, the DNS record state per name with the
per-nameserver check results from §3, the chain, and the SPKI pin. An
`observed` row (delegated mode, §1) shows issuer, SAN list and `notAfter` from
the live TLS probe and an empty history, marked as observed rather than managed.

Audit events, permission-shaped, all first-class (REQ-ACME-17, REQ-AUD-01):
`acme.account.register`, `acme.account.rotate`, `acme.account.deactivate`,
`acme.certificate.order`, `acme.certificate.issue`, `acme.certificate.install`,
`acme.certificate.revoke`, `acme.certificate.delete`, `acme.challenge.start`,
`acme.challenge.fail`, `acme.renewal.attempt`, `acme.renewal.fail`,
`acme.dns-record.write`, `acme.dns-record.delete`, `acme.dns-provider.write`,
`acme.renewal-policy.write`, `acme.rate-limit.override`,
`global.tls-mode.detect`. A challenge failure is an audit event, not a log line,
because "who tried to issue for which name and why did the CA refuse" is a
security question.

**Tenant scoping, justified explicitly.** All five tables are
`tenantScoped: false`. A certificate terminates the connection *before* a
session exists, so at the moment `packages/tls` reads the row there is no tenant
to scope by; an RLS policy on that path would either refuse the read or need a
bypass, and a bypass on an isolation-critical table is worse than declaring the
table global. Access control is the `global.*` permission set plus step-up
(REQ-RBA-06), which no tenant role may hold. A future per-tenant custom-domain
feature gets a **new** table, `tenant_domains`, declared `tenantScoped: true` —
not a retroactive scoping of `certificates`, which would be a silent semantic
change of the worst kind (REQ-CTR-03).

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Termination mode under Dokploy | `delegated`, internal client disabled | Traefik already does HTTP-01 and needs port 80 | Yes, with the §1 conflict check |
| Where the mode lives | `TLS_TERMINATION_MODE` env, no default | It decides whether a port is bound at boot | No |
| Mode conflict detected | Ordering blocked, reason named | Racing Traefik burns the failed-validation budget | No |
| Delegated-mode panel | Renders the observed proxy certificate and the reason | Silently doing nothing is the failure REQ-ACME-03 names | No |
| Wildcard + HTTP-01 / TLS-ALPN-01 | Refused in the form | REQ-ACME-15 is enforced, not discovered at the CA | No |
| Propagation check target | The zone's authoritative nameservers, `RD=0`, per-NS results | A cached negative makes a correct record look wrong | No |
| DNS verification transport | UDP/53 where DoT is unavailable — the one named cleartext exception | No secret in the query; the answer is compared to what we published | No |
| Challenge TTL we ask for | 60 s | A corrected value is visible in a minute | Yes |
| `persistUntil` | Not published | An expiry the operator forgot is a scheduled outage | Yes |
| Account key rotation with persistent records | Refused without typed confirmation naming every zone | Assume a rotation breaks every record; the blast radius is the whole fleet | No |
| DNS-PERSIST-01 availability | Probed from the CA directory, never assumed | Production not confirmed as of 2026-09-21 | No |
| Renewal timing | ARI (RFC 9773), uniform draw in `[windowStart, windowEnd − margin]` | The CA knows about mass revocation; we do not | No |
| Jitter | The uniform draw itself | A second randomness source on a random draw is noise | No |
| ARI unavailable | Renew at 50% of lifetime, clamped to `notAfter − margin` | One rule, correct at 160 h and at 90 days | No |
| Check interval | 360 min, configurable 60 … 1440 | 27 checks per 160 h lifetime; 1 h is REQ-ACME-08's floor | Yes |
| Safety margin | 8 h, and `margin >= interval` enforced at boot | A shorter margin lets the scheduler sleep past the window | Yes |
| Certificate profile | `classic`; `shortlived` (160 h) opt-in | 6-day certs demand automation the operator's DNS may not have | Yes |
| Validation-failure retry floor | 15 min | The failed-validation budget refills at 1 per 12 min | No |
| Debug log protocol | `console-stream` verbatim plus one additive CCR for `domain: "acme"` | A second SSE protocol is a second redaction bug | No |
| JWS in the log | Method, URL, status, `kid`, `alg`, payload *field names* | A base64url blob is an unreadable diagnostic and a readable key | No |
| Private key export | No route exists, at any permission | Envelope-encrypted material that leaves is not encrypted at rest | No |
| Install | Validate six checks, then one map assignment; no swap on failure | A half-installed certificate is worse than an expiring one | No |
| Multi-instance reload | `NOTIFY acme_cert_installed` | Polling serves a revoked certificate for one interval | No |
| First issuance | Staging directory, and staging success is a precondition for production | Rate limits are per week and mistakes are cheap in staging | Yes |
| Rate-limit numbers | Recorded with source URL and timestamp; the CA's `Retry-After` outranks them | Let's Encrypt restructured its limits in 2025 | No |
| Alert thresholds | Fractions of lifetime, not absolute hours | "7 days remaining" never fires on a 160-hour certificate | Yes |
| Provider registry | Declarative descriptor; adapters only with a descriptor | Adding a provider is data (REQ-ACME-18) | No |
| Provider credential scope | The minimum the provider allows, shown in the form | A Global API Key in a container is a zone takeover | No |
| Table scoping | All five `tenantScoped: false`; a future `tenant_domains` is scoped | The TLS handshake has no session to scope by | No |

## How this is verified

- `pnpm --filter @app/acme test` — the ARI target calculation over a table of
  windows including one wholly in the past, one narrower than the margin and one
  with a skewed clock; the 50%-of-lifetime fallback at 160 h and at 90 days; the
  `margin < interval` boot rejection; the escalation ladder at `r` = 0.6, 0.5,
  0.25 and 0.01 for both profiles (REQ-ACME-06 … REQ-ACME-09, REQ-ACME-11).
- `pnpm --filter @app/acme test` — the wildcard matrix: every
  (challenge type × wildcard) pair, asserting the form refuses the four
  impossible combinations before submitting (REQ-ACME-15, REQ-ACME-02).
- `pnpm test:integration` — `tests/integration/acme/**` against **Pebble** with a
  stub DNS server: end-to-end issuance on all four paths, an authoritative check
  where one of two nameservers lags, a `dns-persist-01` record whose
  `accounturi` no longer matches, and an order refused by a rate-limit problem
  whose `Retry-After` is obeyed to the second (REQ-ACME-01, REQ-ACME-04,
  REQ-ACME-05, REQ-ACME-14).
- `pnpm test:integration` — a full end-to-end issuance against the **Let's
  Encrypt staging directory** for a real test name, proving the staging-first
  precondition and that a staging leaf is never installed into the SNI map
  (REQ-ACME-14).
- `pnpm test:integration` — install atomicity: 200 concurrent requests during a
  swap, zero dropped connections and zero handshake errors; a certificate that
  fails each of the six checks in turn leaves the old context serving and the
  order `install_failed` (REQ-ACME-13).
- `pnpm test:unit` — the JWS scrubber over a real signed request: `signature`,
  `payload` and `jwk` absent, `alg`/`url`/`kid` present. The load-bearing one:
  a full issuance run with a planted key sentinel, grepped across the SSE
  stream, the compact-mode copy, the download, `cert_renewal_log` and every
  audit diff. One hit fails the build (REQ-ACME-10, REQ-ACME-12, REQ-AUD-12).
- `pnpm test:unit` — every descriptor in `packages/acme/providers/` parses
  against `DnsProviderDescriptorSchema`, `apiBase` is HTTPS, every
  `secret: true` field has a generated redaction declaration, and a planted
  descriptor with an unredacted secret field fails assembly (REQ-ACME-18).
- `pnpm test:e2e` — `tests/e2e/certificates/**`: the guided DNS screen shows all
  four fields and the per-nameserver results; the debug log streams a live frame
  within 2 s in compact mode with the contract's column widths; delegated mode
  renders the observed certificate and the reason rather than an empty panel;
  403 without `global.certificate.read` (REQ-ACME-03, REQ-ACME-04, REQ-ACME-10).
- `grep -rn "toLocaleString\|Intl.DateTimeFormat\|new Date(" packages/acme/src packages/tls/src`
  returns nothing (REQ-TIM-04). `grep -rn "http://" packages/acme/src` returns
  only the HTTP-01 responder path and the §3 exception, both commented with
  their requirement ID (REQ-SEC-01, REQ-SEC-12).
- `GET /api/v1/acme/_selftest` — schemas parse, all eleven `global.*`
  permissions resolve, the CA directory is reachable through the egress client
  and its advertised challenge types and `renewalInfo` endpoint are reported,
  the termination mode and detection result are reported, every env var is
  present, and every installed certificate's SPKI matches what the TLS listener
  is serving (REQ-CTR-08).

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| Termination mode | `delegated` under Dokploy, `self` otherwise; the §1 detection contradicting the env is a hard block |
| ACME directory | Let's Encrypt **staging**; production requires a successful staging order for the same name |
| Certificate profile | `classic`. `shortlived` (160 h) is opt-in and the defaults are already correct for it |
| Default challenge type | `dns-01` where a provider credential exists, `http-01` otherwise, `dns-persist-01` never by default |
| DNS provider | `manual`. A credentialled provider is configured in the panel |
| Check interval / safety margin | 360 min / 8 h, with `margin >= interval` enforced |
| Who may see and change certificates | `global.certificate.read` / `global.certificate.write`, step-up, global tier only |
| Debug log retention | 30 days in `cert_renewal_log`; the live stream is a tail, not a record |
| Wildcard certificate | Not created unless asked; it forces `dns-01` or `dns-persist-01` |
