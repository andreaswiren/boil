# Certificates & TLS Automation

The ACME client, the four validation paths, the ARI-driven renewal scheduler and
the HAProxy certificate store. Owned by **A25** (`acme-tls`): `packages/acme/**`,
`packages/tls/**`, and the tables `acme_accounts`, `certificates`, `cert_orders`,
`cert_renewal_log`, `dns_providers`. A25 publishes `acme-account`, `certificate`,
`cert-renewal` and `dns-provider`; it consumes `crypto`, `egress-client` and
`edge-topology` (A01), `notification-event` (A12), `audit-event` and
`console-stream` (A13), `grid-def` (A07) and `settings-registry` (A05). A25
contributes its panels to the **global** settings scope from inside
`packages/acme/` and never opens a file under `apps/<app>/app/(app)/settings/`
(REQ-SET-08). Docker Compose is the deployment target (REQ-FND-04), so the
primary path is the complete one: `docker compose up` on a clean host with DNS
pointed at it provisions a certificate and serves HTTPS with nothing else
installed. HAProxy — the `edge` service A01 owns — is our own edge, and A25
drives it.

## Requirements covered

REQ-ACME-01 … REQ-ACME-18, REQ-SEC-01, REQ-SEC-06, REQ-SEC-12, REQ-AUD-01,
REQ-AUD-05, REQ-AUD-12, REQ-FND-04, REQ-FND-05, REQ-FND-07, REQ-SET-05,
REQ-SET-08, REQ-SET-10, REQ-RBA-01, REQ-RBA-06, REQ-TIM-04, REQ-CTR-08.

## 1. Termination mode: who owns the edge (REQ-ACME-03)

Two ACME clients competing for one domain and one challenge port is the failure
this requirement exists to prevent. Three modes, not two, because "an upstream
already terminates public TLS" is a different situation from "there is no edge of
ours at all".

| Mode | Topology | What A25 does |
|---|---|---|
| **`self`** (default) | `client → HAProxy (ours) → app` | Owns ACME end to end. HAProxy serves the HTTP-01 path and holds `bind :443`, so all four paths are available. |
| `behind-proxy` | `client → upstream proxy → HAProxy (ours) → app` | Public TLS is terminated upstream, so the public certificate is not ours: internal ACME for that name is **disabled**. A25 still runs the internal leaf for the HAProxy↔app hop. |
| `delegated` | `client → external proxy → app` | No edge of ours. The internal client is fully disabled. |

We front the app with HAProxy even when something else sits in front of that, because HAProxy is dumb and scriptable: it makes REQ-ACME-13's atomic install achievable through its Runtime API (§8), which is not true of an edge we do not control.

**The mode lives in `TLS_TERMINATION_MODE`, not a database row.** It decides which ports are bound and which HAProxy config is rendered at boot, so it is an env value in A01's single Zod schema with no default (REQ-FND-07). A DB-stored mode would be changeable by a request but effective only after a rebuild, so the settings screen would show a value the running stack is not using. The screen shows the parsed env value and the detection result beneath it. A24 asks one wizard question — "is anything else terminating TLS for this hostname?" — and defaults to `self` when detection finds nothing in front of us.

**Detection.** Four probes, at boot and on demand, all outbound HTTP through A01's egress client (REQ-SEC-12):

| Probe | Method | Conclusion |
|---|---|---|
| TLS | `https://<domain>:443` with SNI; compare the leaf's SPKI SHA-256 to our pin | A leaf we did not install → an upstream terminates |
| Marker | `GET http://<domain>/.well-known/acme-challenge/<random>`; HAProxy answers 404 with `X-Acme-Responder: edge` | A 404 without the marker, someone else's error page, or a 308 we did not emit → an upstream owns port 80 |
| Bind | Does the `edge` service hold `:80`/`:443`? | Bound while the marker probe misses → `behind-proxy`. `EADDRINUSE`, or no `edge` in `edge-topology` → `delegated` |
| Hop count | `Via` / `Forwarded` / `X-Forwarded-For` arriving with more hops than HAProxy adds | An upstream exists even when the first two are inconclusive |

A **`conflict`** — mode `self` but another responder answers — blocks ordering. Ordering anyway means racing the upstream for the same token path, losing, and spending the failed-validation budget (§9) on a race we cannot win.

**`behind-proxy` and `delegated` are not blank screens.** The panel states which component owns the public certificate, why the internal client is off for that name, what the upstream is serving — issuer, SAN list, `notAfter`, SPKI pin, from the TLS probe — as an `observed` inventory row (§12), and which paths remain available (§2.5). Silently doing nothing is the failure REQ-ACME-03 names.

**The internal hop is never cleartext.** REQ-SEC-01 has no exemption for "inside the compose network", so the HAProxy↔app hop runs TLS in all three modes, on a leaf A25 issues from the compose CA A01 ships (REQ-SEC-03's CA pattern). That leaf carries `issuerKind: "internal"`, involves no ACME, and rotates on a fixed 30-day cadence because no CA advises us about it.

**Worked example: Dokploy.** One platform on top of Compose, and the clearest `behind-proxy` case: its Traefik is the internet-facing edge, already does Let's Encrypt HTTP-01, needs port 80 for it, and takes domains in its Domains tab rather than the compose file — so the app cannot see its own routing. Set `TLS_TERMINATION_MODE=behind-proxy` in the Dokploy Environment editor, which writes the `.env`; a container rebuild is required before it takes effect. Any other PaaS, corporate load balancer, CDN or hand-rolled nginx in front of the stack is the same case and takes the same setting.

## 2. The four validation paths (REQ-ACME-01, REQ-ACME-02, REQ-ACME-15)

Challenge type is per certificate, on the `certificates` row. The offered set is the intersection of what the CA directory advertises and what the mode permits, both read at runtime, neither hardcoded.

**HTTP-01 (RFC 8555 §8.3).** *Proves* control of the HTTP server on port 80 for the name, right now. *Prerequisite:* inbound TCP/80 reaches **our** HAProxy — mode `self`. *The user does nothing:* HAProxy answers `/.well-known/acme-challenge/` from an `http-request return` rule over a map file A25 writes, so the token is served at the edge with no round trip to the app. *Goes wrong when:* an upstream proxy owns port 80 and is already answering that path for its own certificates; the firewall allows 443 but not 80; the CA follows a 308 to HTTPS and lands on a not-yet-valid certificate (permitted — a redirect to a *different host* is not); a CDN caches the 404 from before the token existed. *Choose it when* the mode is `self` and the names are concrete.

**DNS-01 (RFC 8555 §8.4).** *Proves* write access to the zone, right now, via a TXT at `_acme-challenge.<name>` holding the base64url SHA-256 of `<token>.<accountKeyThumbprint>`. *Prerequisite:* a `dns_providers` credential for the zone (§11), or a human who will create the record. It never touches the data path, so it works in every mode. *The user does nothing* when a provider is configured; otherwise §3 guides them. *Goes wrong when:* the record lands in the apex zone though the name is delegated to a child zone; `_acme-challenge` is CNAME'd and the operator edits the CNAME's target instead of the target zone; a long TTL on the previous value means the CA reads a stale answer; a wildcard and its base name need two TXT RRs at the *same* `_acme-challenge.example.com` and the second write replaces the first. *Choose it when* the name is a wildcard, port 80 is unreachable, or an upstream owns the edge.

**TLS-ALPN-01 (RFC 8737).** *Proves* control of the TLS server on port 443, via a self-signed certificate carrying the key authorization in an `acmeIdentifier` extension, served only under the `acme-tls/1` ALPN protocol. *Prerequisite:* we own the public handshake — mode `self` only. *The user does nothing.* *Goes wrong when:* anything terminates TLS in front of us, which breaks it completely; an L7 load balancer strips the ALPN; an inexact ALPN match leaks the challenge certificate into normal traffic. *Choose it when* port 80 is firewalled but 443 is ours — the one case it wins.

**DNS-PERSIST-01 (draft-ietf-acme-dns-persist).** *Proves* that the domain holder has authorised **this ACME account at this CA** to issue for the name, indefinitely. It does **not** prove control right now — both the point and the risk (§4). *Prerequisite:* the CA directory advertises `dns-persist-01` and one persistent TXT exists per name. *The user must* publish that record once, guided by §3, and then never again. *Goes wrong when:* the ACME account changes (§4). It never touches the data path, so it works in every mode.

### 2.5 Availability by mode, and wildcards

| Path | `self` | `behind-proxy` | `delegated` | Wildcard |
|---|---|---|---|---|
| HTTP-01 | **Yes** | No — the upstream owns port 80 | No | No |
| DNS-01 | **Yes** | **Yes** | **Yes** | **Yes** |
| TLS-ALPN-01 | **Yes** | No — the upstream owns the handshake | No | No |
| DNS-PERSIST-01 | **Yes** | **Yes** (recommended) | **Yes** | **Yes** |

All four support a multi-name SAN list, one authorization per name.

**Only DNS-01 and DNS-PERSIST-01 support wildcards, and the UI enforces that rather than letting the order fail (REQ-ACME-15).** A SAN list containing a `*.` entry disables HTTP-01 and TLS-ALPN-01 in the picker with the reason inline; so does a mode of `behind-proxy`, which additionally names DNS-01 and DNS-PERSIST-01 as the answer rather than leaving a greyed-out form. Typing a wildcard while HTTP-01 is selected switches the picker and says why. An order is never submitted to fail — REQ-ACME-02 and REQ-ACME-15 are enforced in the form. DNS-PERSIST-01 is recommended for `behind-proxy` because it is indifferent to who owns the data path and removes the per-renewal DNS write, the last moving part in DNS-01.

## 3. Guided DNS setup and the authoritative check (REQ-ACME-04)

The record is four discrete copyable fields, because a single pasted string is where the mistakes live: **Name** `_acme-challenge.app.example.com.` (fully qualified, trailing dot shown), **Type** `TXT`, **Value** the 43-character base64url digest, **TTL** `60` — short, so a corrected value is visible in a minute rather than an hour.

**The propagation check queries the domain's authoritative nameservers, not a recursive resolver.** Walk from the FQDN up to the registrable-domain boundary, take the `NS` set, resolve each nameserver, and query each one directly with `RD=0`.

This distinction is the whole feature. A recursive resolver asked for `_acme-challenge.app.example.com` *before* the record existed caches the negative answer for the zone's SOA `MINIMUM` — routinely 300 to 3600 seconds. A correct record then reads as missing for up to an hour. The operator deletes it, re-creates it, switches provider, and never finds the real fault, because there was none. Querying authoritative cannot see a cached negative, and it is what the CA does.

- Results are **per nameserver**, listed. A zone with one lagging secondary is visible instead of a coin flip, and the CA may query any of them.
- A `CNAME` at `_acme-challenge` is followed and the chain shown — that is the supported way to delegate validation to a separate zone.
- Ordering is refused while any authoritative nameserver disagrees, and the refusal names the nameserver and quotes what it returned.
- Re-check polls for 10 minutes with the remaining time shown, then stops. A spinner that never ends is not a diagnostic.

**The named cleartext exception (REQ-SEC-01).** These queries go to arbitrary authoritative nameservers, most of which do not speak DNS-over-TLS, so they are UDP/53 in the clear where DoT (RFC 7858) is unavailable. This is the only cleartext egress in A25, it is deliberate, and A18 records it: the query carries no secret, and the answer is compared against a value we published, so a forged answer can only make a correct record look wrong — it cannot cause a wrong certificate. **DNS provider API calls carry credentials and have no exception:** HTTPS through A01's egress client, always (REQ-SEC-12).

## 4. DNS-PERSIST-01 and the account-key trap (REQ-ACME-05)

A TXT at `_validation-persist.<domain>`, valued in the CAA `issue` property syntax of RFC 8659 §4.2 with RFC 8657's `accounturi` parameter:

```
_validation-persist.example.com. 300 IN TXT "letsencrypt.org; accounturi=https://acme-v02.api.letsencrypt.org/acme/acct/1234567890"
```

Two optional parameters: `persistUntil=<unix seconds, UTC>`, after which the CA refuses to validate against the record, and `policy=wildcard`, which broadens the authorization to the wildcard and to subdomains of the validated name. **We publish no `persistUntil` by default** — an expiry the operator has forgotten is a scheduled outage with a one-year fuse. One that is set appears in the inventory beside the certificate expiry, under §10's ladder.

**The account key thumbprint is displayed next to the record** — RFC 7638 JWK SHA-256, base64url, with a copy action. The account URI alone does not say *which key* the record trusts, so an account restored from backup under a different key looks identical in DNS and stays invisible until a renewal fails.

**The trap, plainly.** With DNS-01 the secret that matters is DNS write access, needed for thirty seconds per renewal. With DNS-PERSIST-01 the record lives in the zone indefinitely and the ACME **account key** becomes the entire security boundary for every name it authorises.

- A **new account** means a new account URI. Every persistent record in every zone silently stops authorising us. Nothing breaks that day — the first symptom is a failed renewal on a certificate that has worked for a year.
- **Deactivating** the account is immediate, irreversible, and takes down every domain under it at once.
- A **key change** (RFC 8555 §7.3.5) keeps the account URI, so the record should survive. **We do not rely on that.** A25 treats any account key change as invalidating every persistent record, because the draft permits a CA to bind more tightly than the URI, because another CA's behaviour is not ours to assume, and because being wrong means every certificate in the fleet failing to renew at the same moment. Assume a rotation breaks every record and re-publish.

So `global.acme-account.rotate` is refused while any certificate uses DNS-PERSIST-01 unless the operator passes a typed confirmation naming every zone whose record must be re-published (REQ-SET-10). The rotation writes `persistState: "needs_republish"` onto every affected certificate, raises one `acme.persist-record-invalid` at `critical` per zone, and the inventory shows each as blocked until §3's check sees the new account URI.

**Availability is probed, never assumed.** Let's Encrypt announced DNS-PERSIST-01 on 2026-02-18 with staging late Q1 2026 and production *targeted* for Q2 2026; CA/Browser Forum ballot SC-088v3 defining BR §3.2.2.4.22 passed in October 2025 and the IETF ACME working group adopted the draft the same month. **No source confirms production availability as of 2026-09-21.** The picker offers `dns-persist-01` only when the CA directory advertises it, and otherwise says "not offered by this CA directory".

## 5. The renewal scheduler (REQ-ACME-06 … REQ-ACME-09)

Renewal is ARI-driven (RFC 9773, ACME Renewal Information — REQ-ACME-07) and needs no future user intervention ever (REQ-ACME-06). A deployment left alone for a year keeps working because the scheduler asks the CA when to renew instead of guessing. The ARI resource id is the base64url `keyIdentifier` of the leaf's Authority Key Identifier, a `.`, and the base64url DER serial, trailing `=` stripped. The response carries `suggestedWindow: { start, end }` and an optional `explanationURL`. Every renewal order sends `replaces`, which lets the CA retire the predecessor and — under Let's Encrypt policy — exempts the renewal from the duplicate-certificate limit (§9).

```
every ACME_CHECK_INTERVAL_MINUTES, per certificate where installed_at is not null:

  1. GET <directory.renewalInfo>/<certID>      # A01 egress client, TLS verified
  2. on 200:
       lower  = max(window.start, now)
       upper  = window.end - ACME_RENEWAL_SAFETY_MARGIN_HOURS
       target = upper <= lower ? now                    # window tighter than the margin
                               : lower + random() * (upper - lower)
       persist ari_window_start, ari_window_end, next_attempt_at = target
  3. if target <= now + interval: run the attempt at target
  4. on 404 / 410 / 5xx / timeout / malformed: fall back (below), count it, and
     surface "ARI unavailable" on the inventory row
  5. sleep min(Retry-After, interval)
```

**The jitter is the random draw itself** — uniform across `[lower, upper]`, which is RFC 9773's own recommendation. Every deployment of this boilerplate renewing the same profile against the same CA would otherwise converge on one instant. No separate jitter constant exists; a second randomness source on a random draw is noise.

**Fallback when ARI is unavailable: renew at 50% of lifetime.** `target = notBefore + (notAfter − notBefore) / 2`, clamped to no later than `notAfter − margin`. One rule, correct at both scales: a 160-hour certificate is attempted at 80 hours with 80 hours of failure budget left — a ~3.3-day cadence, inside Let's Encrypt's 2–3 day recommendation — and a 90-day certificate at day 45. The fallback is deliberately earlier than ARI would advise, because a client that has lost contact with the CA's advice should spend margin, not hoard it.

**Shipped defaults, correct for a 160-hour certificate (REQ-ACME-08, REQ-ACME-09).** Let's Encrypt's `shortlived` profile is exactly 160 hours, selected by `ACME_CERT_PROFILE`, and it is opt-in — `classic` stays the default because 6-day certificates demand automation this app provides but the operator's DNS and upstream proxy may not.

| Knob | Default | Range | Why |
|---|---|---|---|
| `ACME_CHECK_INTERVAL_MINUTES` | `360` (6 h) | 60 … 1440 | 27 ARI checks across a 160-hour lifetime, four times the "at least daily" floor. 1 h is the minimum REQ-ACME-08 names; above 1440 is refused, as it would break REQ-ACME-09 |
| `ACME_RENEWAL_SAFETY_MARGIN_HOURS` | `8` | ≥ 1 and **≥ the check interval** | One missed check plus a full retry ladder inside the window. 5% of a 160-hour lifetime, 0.4% of a 90-day one |
| `ACME_CERT_PROFILE` | `classic` | `classic` \| `shortlived` | Opt-in, not default |

The boot schema rejects `margin < interval` (REQ-FND-07): a margin shorter than the poll interval lets the scheduler sleep straight past the window's end.

**As the margin shrinks** the behaviour tightens rather than staying linear. Once `now >= upper` the target is `now` and every tick attempts. Retry backoff is exponential from 2 minutes, capped at 1 hour — except after a *validation* failure, where the floor is 15 minutes, because the failed-validation budget refills at one per 12 minutes per identifier (§9) and a tighter retry burns the budget the next real attempt needs. Notifications escalate on §10's ladder.

**Why "renew at 2/3 of the lifetime" is wrong here.** Two reasons, the second decisive. A fixed fraction cannot know what the CA knows: a mass revocation, a load spike, a compliance-driven early replacement. ARI exists because in 2020 there was no way for a CA to say "renew now". And the arithmetic fails at 160 hours: 2/3 elapsed means renewing every 107 hours, about 1.6 certificates per week per name — one failed attempt with a retry doubles that and walks into the 5-duplicate-certificates-per-week limit. The ARI path escapes it because `replaces` exempts the renewal; a fixed-fraction client sends no `replaces` and has nothing to fall back on.

## 6. The ACME debug log (REQ-ACME-10)

Every protocol step, request, response, challenge state transition, DNS lookup and error, with millisecond timestamps, surfaced **in the certificate renewal settings screen** — not in a separate console the operator must correlate by hand.

**It reuses `console-stream` rather than inventing a second protocol.** Same `ConsoleFrameSchema`, same `gap` and `hello` control events, same SSE transport with `Last-Event-ID` resume and a `: ping` every 15 s, same compact-mode column widths (time 12, level 3, domain 14, event 24, message rest, two spaces between), same six levels with their three-letter tags and `--console-*` theme tokens, same ANSI rules. A25 files one **additive CCR** adding `"acme"` to the frozen `domain` enum, which `contracts/events/console-stream.md` §9 lists as additive. Nothing else in that contract changes.

```
HH:mm:ss.SSS  LVL  domain........  event...................  message
09:14:02.118  INF  acme            order.new                 names=app.example.com profile=shortlived
09:14:02.402  DBG  acme            authz.challenge           type=dns-01 status=pending
09:14:02.611  INF  acme            dns.record-write          provider=cloudflare zone=example.com ttl=60
09:14:33.905  DBG  acme            dns.authoritative-check   ns=ns1.example.net result=match
09:14:34.010  WRN  acme            dns.authoritative-check   ns=ns2.example.net result=nxdomain attempt=1
09:15:06.744  INF  acme            authz.valid               type=dns-01 elapsed=184s
09:15:07.301  INF  acme            edge.commit               store=app.example.com.pem contexts=2
09:15:07.902  ERR  acme            order.failed              code=urn:ietf:params:acme:error:rateLimited retryAfter=3600
```

**Redaction (REQ-ACME-12, REQ-AUD-05, REQ-AUD-12).** The frame passes through A13's single redactor at emit, before the frame exists — not at render, not at download. On top of that:

- The **account key**, every **certificate private key** and every **DNS provider credential** never appear, in any mode. They are not declared `mask`; they are absent.
- **JWS payloads are scrubbed, not dumped.** A protocol frame records the method, URL, HTTP status, `nonce` length, `kid`, the decoded `protected` header's `alg` and `url`, and the payload's *field names*. The `signature`, the raw `payload` and any `jwk` are dropped. A base64url blob in a log is an unreadable diagnostic and a readable key.
- HAProxy Runtime API frames record the command, the store filename and the result — **never the payload**, which is a PEM containing the private key (§8).
- `fields` values are scalars capped at 200 characters, so a PEM chain or a response body cannot be attached to a frame at all.
- The contract's secret-shaped detector (PEM blocks, 32+ character high-entropy strings, JWT shapes) drops any frame that slips, emits a `gap` with `reason: "redaction_failure"`, and raises a `system` audit event.

Durable copy: `cert_renewal_log`, retained `ACME_DEBUG_LOG_RETENTION_DAYS` (default 30), so the panel can show the *last* failure after the ring rotated. The stream is a tail; the table is the record. Both are redacted by the same function. Timestamps are UTC `timestamptz`, formatted only at the edge by `packages/contracts/time` (REQ-TIM-04).

## 7. Key custody (REQ-ACME-12)

| Material | Where it lives | Form |
|---|---|---|
| ACME account key | `acme_accounts.private_key_enc` | Envelope ciphertext, rotatable KEK (REQ-SEC-06) |
| Certificate private key | `certificates.private_key_enc` | Envelope ciphertext |
| Chain and leaf | `certificates.chain_pem`, `leaf_pem` | Cleartext — it is public |
| DNS provider credentials | `dns_providers.credentials_enc` | Envelope ciphertext, per field |
| SPKI pin | `certificates.spki_sha256` | Cleartext digest, used by §1's probe |

Keys are generated in-process. **Postgres is the datastore of record** (REQ-FND-05); the PEM files HAProxy loads are a cache materialised from the row at boot (§8), never the truth and never the only copy. There is **no export route for any private key** — not permission-gated, not step-up, not for a superadmin. An operator who needs the key off the box wants a different product.

The rule, absolutely: **a private key never enters a log, a debug stream, an export or an audit diff.** A diff records that the material changed — `{ before: { accountKey: "[redacted]" }, after: { accountKey: "[redacted:changed]" } }` — preserving "the key was rotated" without the key (`spec/observability.md` §4). The registry entries enforcing this are generated from the `secret: true` flags in §11's descriptors, so a new secret-bearing field cannot be added without its redaction declaration.

## 8. Atomic install and hot reload (REQ-ACME-13)

HAProxy's Runtime API replaces a certificate in memory, transactionally, with no reload and no dropped connections. The commands are exact, verified against HAProxy's management guide rather than written from memory:

```
# Once, for a store filename HAProxy does not yet know:
new ssl cert /etc/haproxy/certs/app.example.com.pem

# Every install, including the first:
set ssl cert /etc/haproxy/certs/app.example.com.pem <<
<leaf PEM><intermediate chain PEM><private key PEM>
                                  # an EMPTY LINE terminates the payload
commit ssl cert /etc/haproxy/certs/app.example.com.pem

# Only for a store not yet referenced by a bind line:
add ssl crt-list /etc/haproxy/crt-list.txt /etc/haproxy/certs/app.example.com.pem
```

`set ssl cert` opens a transaction holding the new material; nothing serves it yet. `commit ssl cert` generates every SSL context and SNI the store needs, inserts them, and removes the previous ones — and in HAProxy's own words, **"upon failure it doesn't remove or insert anything."** That sentence is the whole of REQ-ACME-13: a bad certificate leaves the old one serving, because the commit is all-or-nothing inside HAProxy. On any error we issue `abort ssl cert <filename>`, so no transaction is left dangling to be committed by a later, unrelated install.

**We validate before committing anyway**, because a refused install is a better diagnostic than a rejected commit: (1) the private key's public half equals the leaf's SPKI; (2) the chain builds to a trusted root, leaf first, no gaps; (3) `notBefore <= now <= notAfter`, with the clock cross-checked against the CA's `Date` header, skew being the failure mode RFC 9773 §9 names; (4) every configured name is covered by the leaf's `subjectAltName`, wildcards matched by label and never by substring; (5) the signature algorithm is in the allowed set; (6) the PEM is sanitised — the Runtime API ends a payload at the first empty line, so blank lines between PEM blocks are stripped before the command is written, and an unsanitised PEM truncates the payload and commits a partial certificate.

**If a check fails the swap does not happen.** The old certificate keeps serving, the order is marked `install_failed`, the debug log names the failed check, and a `critical` notification fires. A half-installed certificate is worse than an expiring one: an expiring certificate still serves traffic for the rest of its margin. The rejected material stays in the row with `installed_at: null` so it can be inspected rather than silently re-fetched.

**Runtime API changes are memory-only and die when HAProxy restarts.** So every install also writes the PEM to the crt-list directory, and a boot-time materialiser rewrites that directory from `certificates` before the `edge` service starts. The row is the truth; the file exists so a restart does not serve yesterday's certificate. Writing only to memory is the classic Runtime API mistake and it fails on the next `docker compose up`.

**The reload fallback.** If the Runtime API socket is unavailable — an older HAProxy, a socket permission problem — A25 falls back to a socket-handover reload: HAProxy runs in master-worker mode (`-W`), the master reloads on `SIGUSR2` and spawns a new worker with `-sf <old pid>`, handing the listening sockets over with `-x sockpair@`, so the old worker finishes its in-flight connections and nothing is dropped. It is the fallback, not the default, because it re-reads the entire configuration and that is a larger blast radius than replacing one certificate.

Multi-instance deployments learn of an install through `NOTIFY acme_cert_installed, '<certificate id>'` and each runs the commit against its own edge socket. Polling would mean an instance serving a revoked certificate for one poll interval, and LISTEN/NOTIFY costs nothing because Postgres is already the only datastore. In `delegated` mode there is no store and nothing to reload.

## 9. Staging first, and rate limits (REQ-ACME-14)

`ACME_DIRECTORY_URL` defaults to the Let's Encrypt **staging** directory, and a production order for a name is refused until a staging order for that same name has succeeded. The precondition is a row in `cert_orders`, not a checkbox the operator can click past. Staging leaves are never committed to the edge and are labelled `staging` in the inventory — they are not browser-trusted, and nobody should spend an afternoon wondering why the padlock is broken.

**Rate limits are read, not remembered.** Let's Encrypt restructured its limits in 2025 and the numbers move, so `packages/acme/rate-limits.json` records them with a source URL and a fetch timestamp, refreshed at build time under the same rule as every dependency version (REQ-VER-02 — a limit you remember is wrong). Confirmed at the time of writing, from Let's Encrypt's rate-limit documentation: **50 new certificates per registered domain per week**, **5 duplicate certificates per exact name set per week**, and **5 failed validations per account per identifier per hour, refilling one per 12 minutes**. ARI-driven renewals carrying `replaces` are exempt from the duplicate-certificate limit under Let's Encrypt policy, the second reason §5 always sends it.

Two layers, because the recorded numbers can be stale. **Pre-flight**, from the recorded limits: before an order the panel states the issuances for this registrable domain in the last 7 days, the duplicate count for this exact name set, and the failed-validation budget left; an order the recorded limits say would be refused is blocked, with an audited override (`acme.rate-limit.override`) for when the recorded numbers are the thing that is wrong. **In-flight**, from the CA: a `urn:ietf:params:acme:error:rateLimited` problem is obeyed exactly, `Retry-After` honoured to the second, no earlier retry. The CA's answer always outranks our copy of its documentation.

## 10. Failure alerting (REQ-ACME-11)

Silent failure until an outage is not acceptable. A25 emits through A12's `notification-event` and never sends mail itself. Thresholds are **fractions of the certificate's own lifetime, not absolute hours** — an absolute "7 days remaining" threshold never fires at all on a 160-hour certificate, being already past by the time the certificate exists. With `r = (notAfter − now) / (notAfter − notBefore)`:

| Condition | Category | Severity | Channels |
|---|---|---|---|
| Attempt failed, `r > 0.5` | — | — | Debug log only. One failure with most of the lifetime left is noise |
| ≥ 3 consecutive failures, or `r <= 0.5` | `acme.renewal-failing` | `warning` | in_app, email (digestable) |
| `r <= 0.25` and a failure | `acme.renewal-failing` | `warning` | Every failure, no digest |
| `now >= windowEnd − 2 × margin` | `acme.renewal-critical` | `critical` | in_app, push, email to global operators |
| `now > notAfter` | `acme.certificate-expired` | `critical` | in_app, push, email |
| Persistent record no longer authorises us | `acme.persist-record-invalid` | `critical` | in_app, push, email, per zone |
| Recorded limit 80% consumed | `acme.rate-limit-approaching` | `warning` | in_app, email (digestable) |
| Commit succeeded | `acme.certificate-installed` | `info` | in_app (digestable) |

Every category declares `permission: "global.certificate.read"`, so it is invisible to and undeliverable for anyone who cannot see certificates. Payloads carry a `ref` and i18n keys under the `acme` namespace, never a rendered sentence and never key material (REQ-PWA-04).

## 11. The DNS provider registry (REQ-ACME-18)

Adding a provider is **data**: one descriptor in `packages/acme/providers/<id>.ts` plus a fixture. No new branch in a switch, no change to the challenge code. The descriptor drives the credential form, the egress allowlist entry, the redaction declarations and the audit target, so the four cannot disagree.

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
      hintKey: "acme.provider.cloudflare.tokenHint" },  // "Zone → DNS → Edit. Not a Global API Key."
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

- **Credentials are scoped to the minimum the provider allows**, and `minimumScope` is shown in the form as required reading, not buried in help. Cloudflare gets a zone-scoped `Zone:DNS:Edit` token, never a Global API Key, and the hint says so at the point of entry.
- `secret: true` fields are envelope-encrypted (REQ-SEC-06), write-only through the API — never returned, not even masked with a length — and they **generate** their redaction declarations. A new provider cannot forget to redact.
- Every call goes through A01's egress client against `apiBase`, which is the allowlist entry (REQ-SEC-12). A descriptor whose `apiBase` is not HTTPS fails the assembly lint.
- A `manual` provider always exists: the operator creates the record by hand and presses re-check. DNS-01 must work for a zone hosted anywhere, including a registrar with no API.
- **The bounded escape hatch:** a provider needing request signing, pagination or a custom auth dance declares `adapter: "./adapters/<id>"`. The descriptor is still the registry entry, so the panel, the form, the redaction rules and the audit target come from one place. An adapter *without* a descriptor is a defect.

## 12. Inventory and audit (REQ-ACME-16, REQ-ACME-17)

The inventory is an A07 grid (`grid-def`) over `certificates`: SAN list, issuer CN, profile, challenge type, `notBefore`/`notAfter`, remaining lifetime, status, last renewal result, next scheduled check, next attempt target, ARI window start and end, and termination mode. Every instant is UTC in the column data and formatted at the edge by `packages/contracts/time` (REQ-TIM-04) — a certificate that reads as valid in one operator's timezone and expired in another's is exactly the bug that formatter prevents. The detail view adds the full issuance history from `cert_renewal_log`, the account URI and key thumbprint, the DNS record state per name with §3's per-nameserver results, the chain, the SPKI pin, and the edge store filename with its `show ssl cert` state. An `observed` row (§1) shows issuer, SAN list and `notAfter` from the live TLS probe with an empty history, marked observed rather than managed.

Audit events, permission-shaped, all first-class (REQ-ACME-17, REQ-AUD-01): `acme.account.register`, `acme.account.rotate`, `acme.account.deactivate`, `acme.certificate.order`, `acme.certificate.issue`, `acme.certificate.install`, `acme.certificate.revoke`, `acme.certificate.delete`, `acme.challenge.start`, `acme.challenge.fail`, `acme.renewal.attempt`, `acme.renewal.fail`, `acme.dns-record.write`, `acme.dns-record.delete`, `acme.dns-provider.write`, `acme.renewal-policy.write`, `acme.rate-limit.override`, `global.tls-mode.detect`. A challenge failure is an audit event, not a log line, because "who tried to issue for which name, and why did the CA refuse" is a security question.

**Tenant scoping, justified explicitly.** All five tables are `tenantScoped: false`. A certificate terminates the connection *before* a session exists, so when `packages/tls` materialises the row there is no tenant to scope by; an RLS policy on that path would either refuse the read or need a bypass, and a bypass on an isolation-critical table is worse than declaring the table global. Access control is the `global.*` permission set plus step-up (REQ-RBA-06), which no tenant role may hold. A future per-tenant custom-domain feature gets a **new** table, `tenant_domains`, declared `tenantScoped: true` — not a retroactive scoping of `certificates`, which would be a silent semantic change of the worst kind (REQ-CTR-03).

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Our own edge | HAProxy (`edge`), in compose, in `self` and `behind-proxy` | Dumb and scriptable, so REQ-ACME-13 is achievable via its Runtime API | No |
| Default mode | `self` — `docker compose up` provisions and serves HTTPS unaided | Compose is the deployment target (REQ-FND-04) | Yes |
| Where the mode lives | `TLS_TERMINATION_MODE` env, no default; `conflict` blocks ordering | It decides which ports are bound at boot; racing the upstream burns the failed-validation budget | No |
| Non-`self` panel | Names the owner of the public certificate, shows the observed leaf and the available paths | Silently doing nothing is the failure REQ-ACME-03 names | No |
| Internal HAProxy↔app hop | Always TLS, internal leaf, 30-day rotation | REQ-SEC-01 has no exemption for "internal" | No |
| HTTP-01 / TLS-ALPN-01 outside `self`, or with a wildcard | Refused in the form, DNS-01 and DNS-PERSIST-01 named instead | REQ-ACME-15 enforced, not discovered at the CA | No |
| Propagation check target | The zone's authoritative nameservers, `RD=0`, per-NS results | A cached negative makes a correct record look wrong | No |
| DNS verification transport | UDP/53 where DoT is unavailable — the one named cleartext exception | No secret in the query; the answer is compared to what we published | No |
| `persistUntil` | Not published | An expiry the operator forgot is a scheduled outage | Yes |
| Account key rotation with persistent records | Refused without typed confirmation naming every zone | Assume a rotation breaks every record; the blast radius is the fleet | No |
| DNS-PERSIST-01 availability | Probed from the CA directory, never assumed | Production not confirmed as of 2026-09-21 | No |
| Renewal timing | ARI (RFC 9773), uniform draw in `[windowStart, windowEnd − margin]`, which is also the jitter | The CA knows about mass revocation; a second randomness source is noise | No |
| ARI unavailable | Renew at 50% of lifetime, clamped to `notAfter − margin` | One rule, correct at 160 h and at 90 days | No |
| Check interval / safety margin | 360 min / 8 h, `margin >= interval` enforced at boot | 27 checks per 160 h lifetime; a shorter margin sleeps past the window | Yes |
| Certificate profile | `classic`; `shortlived` (160 h) opt-in | 6-day certs demand automation the operator's DNS may not have | Yes |
| Validation-failure retry floor | 15 min | The failed-validation budget refills at 1 per 12 min | No |
| Debug log protocol | `console-stream` verbatim plus one additive CCR for `domain: "acme"` | A second SSE protocol is a second redaction bug | No |
| JWS in the log | Method, URL, status, `kid`, `alg`, payload *field names* | A base64url blob is an unreadable diagnostic and a readable key | No |
| Private key export | No route exists, at any permission | Envelope-encrypted material that leaves is not encrypted at rest | No |
| Install mechanism | `set ssl cert` → validate → `commit ssl cert`; `abort ssl cert` on error | The commit inserts nothing on failure — that is the atomicity | No |
| Install persistence | Runtime API **and** a PEM on disk, rematerialised from the row at boot | Runtime API changes are memory-only and die on restart | No |
| Reload path | Fallback only: master-worker, `SIGUSR2`, `-sf` + `-x sockpair@` | A reload re-reads everything; replacing one certificate should not | No |
| Multi-instance install | `NOTIFY acme_cert_installed` | Polling serves a revoked certificate for one interval | No |
| First issuance | Staging, and staging success gates the production order | Rate limits are per week; mistakes are cheap in staging | Yes |
| Rate-limit numbers | Recorded with source URL and timestamp; the CA's `Retry-After` outranks them | Let's Encrypt restructured its limits in 2025 | No |
| Alert thresholds | Fractions of lifetime, not absolute hours | "7 days remaining" never fires on a 160-hour certificate | Yes |
| Provider registry | Declarative descriptor, minimum credential scope shown in the form; adapters only with a descriptor | Adding a provider is data (REQ-ACME-18); a Global API Key in a container is a zone takeover | No |
| Table scoping | All five `tenantScoped: false`; a future `tenant_domains` is scoped | The TLS handshake has no session to scope by | No |

## How this is verified

- `pnpm --filter @app/acme test` — ARI target calculation over a table of windows including one wholly in the past, one narrower than the margin and one with a skewed clock; the 50%-of-lifetime fallback at 160 h and 90 days; the `margin < interval` boot rejection; §10's ladder at `r` = 0.6, 0.5, 0.25, 0.01 for both profiles (REQ-ACME-06 … REQ-ACME-09, REQ-ACME-11). Plus §2.5 exhaustively: every (mode × challenge type × wildcard) triple, asserting the picker offers exactly the permitted set and names the alternative when it refuses (REQ-ACME-02, REQ-ACME-03, REQ-ACME-15).
- `pnpm test:integration` — `tests/integration/acme/**` against **Pebble** with a stub DNS server: issuance on all four paths in `self` mode; an authoritative check where one of two nameservers lags; a `dns-persist-01` record whose `accounturi` no longer matches; an order refused by a rate-limit problem whose `Retry-After` is obeyed to the second (REQ-ACME-01, REQ-ACME-04, REQ-ACME-05, REQ-ACME-14).
- `pnpm test:integration` — the primary path end to end: `docker compose up` on a clean network in mode `self`, a real issuance against the **Let's Encrypt staging directory**, HAProxy serving it, and a production order refused before the staging order exists (REQ-FND-04, REQ-ACME-14).
- `pnpm test:integration` — install atomicity against a real HAProxy: 200 concurrent keep-alive requests plus one WebSocket across a `set`/`commit ssl cert` cycle, zero dropped connections and zero handshake errors; a certificate failing each of §8's six checks in turn leaves the old one serving and the order `install_failed`; an unsanitised PEM is rejected before the command is written; after `docker compose restart edge` the materialised file serves the same SPKI (REQ-ACME-13).
- `pnpm test:unit` — the JWS scrubber over a real signed request: `signature`, `payload` and `jwk` absent, `alg`/`url`/`kid` present. The load-bearing one: a full issuance with a planted key sentinel, grepped across the SSE stream, the compact-mode copy, the download, `cert_renewal_log`, every audit diff and every Runtime API frame. One hit fails the build (REQ-ACME-10, REQ-ACME-12, REQ-AUD-12). Plus: every descriptor parses, `apiBase` is HTTPS, every `secret: true` field has a generated redaction declaration, and a planted descriptor with an unredacted secret field fails assembly (REQ-ACME-18).
- `pnpm test:e2e` — `tests/e2e/certificates/**`: the guided DNS screen shows all four fields and the per-nameserver results; the debug log streams a live frame within 2 s in compact mode at the contract's column widths; `behind-proxy` renders the observed certificate, the owner of the public certificate and the two available paths rather than an empty panel; 403 without `global.certificate.read` (REQ-ACME-03, REQ-ACME-04, REQ-ACME-10).
- `grep -rn "toLocaleString\|Intl.DateTimeFormat\|new Date(" packages/acme/src packages/tls/src` returns nothing (REQ-TIM-04). `grep -rn "http://" packages/acme/src` returns only the HTTP-01 responder path and §3's exception, each commented with its requirement ID (REQ-SEC-01, REQ-SEC-12).
- `GET /api/v1/acme/_selftest` — schemas parse, all eleven `global.*` permissions resolve, the CA directory is reachable through the egress client with its advertised challenge types and `renewalInfo` endpoint reported, the termination mode and detection result reported, every env var present, the edge Runtime API socket answering `show ssl cert`, and every installed certificate's SPKI matching what HAProxy serves (REQ-CTR-08).

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| Termination mode | `self` — our HAProxy is the edge and we own ACME. Detection contradicting the env is a hard block |
| ACME directory | Let's Encrypt **staging**; production needs a successful staging order for the same name |
| Certificate profile | `classic`. `shortlived` (160 h) is opt-in and the defaults are already correct for it |
| Default challenge type | `http-01` in `self`; `dns-01` where a provider credential exists or the mode is `behind-proxy`; `dns-persist-01` never by default |
| DNS provider | `manual`. A credentialled provider is configured in the panel |
| Check interval / safety margin | 360 min / 8 h, with `margin >= interval` enforced |
| Who may see and change certificates | `global.certificate.read` / `global.certificate.write`, step-up, global tier only |
| Debug log retention | 30 days in `cert_renewal_log`; the live stream is a tail, not a record |
| Wildcard certificate | Not created unless asked; it forces `dns-01` or `dns-persist-01` |
