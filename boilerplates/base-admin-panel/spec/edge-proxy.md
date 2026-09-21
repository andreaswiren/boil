# Edge Proxy

HAProxy is the app's own edge, always present, even when it sits behind someone
else's proxy. Owned by **A01 arch-foundation**, which already owns `docker/**`
and the validated config source the HAProxy config is generated from
(REQ-PROX-04). **A25 acme-tls** owns exactly one seam into it: the certificate
install and reload path (REQ-PROX-09, REQ-ACME-13).

## Requirements covered

REQ-PROX-01 … REQ-PROX-12, REQ-FND-04, REQ-SEC-01, REQ-SEC-02, REQ-SEC-08,
REQ-AUD-04, REQ-AUD-07, REQ-ACME-03, REQ-ACME-13.

## 1. Why HAProxy and not the thing already in front of us

Long-lived connections are load-bearing in this app, not incidental. The debug
console streams over SSE (REQ-AUD-08) with compact-mode frames arriving inside
the same second. A proxy that buffers responses, coalesces chunks, or applies a
short idle timeout breaks that feature while passing every short-request test —
the endpoint returns 200, the stream just never delivers.

We front the app with our own HAProxy so that behaviour is **ours to configure
and ours to test**, rather than a property of whatever proxy the operator
happens to deploy behind. This holds even when the stack runs behind Dokploy's
Traefik: our HAProxy stays in the path (REQ-PROX-01).

The secondary benefit is certificates. HAProxy is deliberately simple to drive
from outside, which is what makes REQ-ACME-13's "atomic install, hot reload, no
dropped connections" actually achievable rather than aspirational.

## 2. The three topologies (REQ-PROX-03)

Declared explicitly at setup by A24 and stored as configuration. Never inferred
silently — a wrong guess here produces two ACME clients fighting over one
hostname.

| Mode | Shape | Who owns the public certificate | Default |
|------|-------|--------------------------------|---------|
| `self` | `client → HAProxy → app` | Us, end to end via A25 | **Yes** |
| `behind-proxy` | `client → upstream proxy → HAProxy → app` | The upstream. Ours is disabled for the public hostname only | The Dokploy case |
| `delegated` | `client → external proxy → app` | The external proxy. Internal ACME fully off | Supported, not recommended |

In `behind-proxy` the upstream is Dokploy's Traefik, a corporate load balancer,
or a CDN. Our HAProxy is still ours and still terminates TLS on its hop to the
app — **REQ-SEC-01 has no exemption for traffic that stays inside the compose
network** (REQ-PROX-08).

`delegated` exists because some operators will insist. It is supported, and the
documentation states plainly which requirements it weakens: the app can no
longer guarantee REQ-PROX-05 through REQ-PROX-07, because the component that
would guarantee them is not in the path.

### Challenge-type availability follows from the mode

This is the practical consequence, and the reason the mode is a setup question
rather than a config file nobody reads. A25's `spec/acme-tls.md` carries the
authoritative matrix; the short version:

| Mode | HTTP-01 | TLS-ALPN-01 | DNS-01 | DNS-PERSIST-01 |
|------|---------|-------------|--------|----------------|
| `self` | Yes | Yes | Yes | Yes |
| `behind-proxy` | No — upstream owns port 80 | No — upstream owns the 443 handshake | Yes | Yes |
| `delegated` | n/a | n/a | Yes | Yes |

DNS-01 and DNS-PERSIST-01 never touch the data path, which is why they work
everywhere and why DNS-PERSIST-01 is the recommendation for `behind-proxy`
(REQ-ACME-05).

## 3. Config generation, not config maintenance (REQ-PROX-04)

The HAProxy config is generated at boot from the same Zod-validated config source
as the app (REQ-FND-07). There is no hand-maintained `haproxy.cfg` in the repo
that could drift from the app's view of its own hostnames and ports.

A hostname or port present in one and absent from the other is a **boot
failure**, with the mismatch named. The alternative — starting successfully and
serving 503s for one vhost — is the failure mode this requirement exists to
prevent.

```
packages/config (Zod)  ──┬──▶  app runtime config
                         └──▶  docker/haproxy/haproxy.cfg  (generated, gitignored)
```

## 4. Long-lived connections (REQ-PROX-05)

The values below are the shipped defaults. They are stated here because
"whatever HAProxy defaults to" is not a specification, and the defaults are
wrong for an SSE stream that may sit idle between events.

| Setting | Value | Why |
|---------|-------|-----|
| `timeout tunnel` | `1h` | Governs an upgraded WebSocket connection and a long-lived stream after the initial exchange. The default is far too short for an idle console. |
| `timeout client` / `timeout server` | `60s` | Normal request timeouts. `timeout tunnel` supersedes these once a connection is upgraded, which is precisely why both are needed. |
| `timeout http-keep-alive` | `10s` | Short on purpose; it is not the stream timeout. |
| `option http-no-delay` | enabled on the SSE and WebSocket paths | Stops HAProxy holding small frames back for coalescing. This is the single directive whose absence produces "the stream works but arrives in bursts". |
| Response buffering | not enabled | HAProxy streams by default. The requirement is that nothing in the config turns it off — no compression filter, no body-rewriting filter on the stream paths. |

Two things that look like tuning but are correctness:

- **A compression filter on an SSE path will buffer it.** Compression is
  configured per-path and excluded from `text/event-stream`.
- **WebSocket upgrade is native in HTTP mode**, so it needs no `mode tcp`
  backend. A `mode tcp` shortcut would lose the forwarded-address handling of
  REQ-PROX-10, which the audit trail depends on.

A01 must confirm the current directive names and defaults against the HAProxy
version pinned in `versions/manifest.json` before writing the config. Do not
carry these values across a major HAProxy version without re-reading its
documentation.

## 5. Certificate install and reload (REQ-PROX-09, REQ-ACME-13)

A25 installs certificates through HAProxy's Runtime API, which applies a new
certificate **without a reload**:

```
set ssl cert /etc/haproxy/certs/<name>.pem <<\n<pem payload>\n
commit ssl cert /etc/haproxy/certs/<name>.pem
```

`set ssl cert` opens a transaction and loads the material into memory;
`commit ssl cert` applies it. Nothing takes effect until the commit, which is
what makes the swap atomic.

**The trap, and it is a real one: Runtime API changes live in memory only and are
lost when the process stops.** So the installer must do both, in this order:

1. Write the new certificate to its path on disk.
2. `set ssl cert` + `commit ssl cert` to apply it live.

Doing only step 2 produces a deployment that serves the new certificate happily
until the next restart, then silently reverts to the expired one. Doing only
step 1 produces a correct file nobody is serving. A25's definition of done must
include a test that restarts `edge` and asserts the certificate survives.

Where a genuine reload is unavoidable (a config change, not a certificate),
HAProxy's master-worker mode with `expose-fd listeners` and `-sf` hands the
listening sockets to the new worker, so established connections are not dropped.

## 6. Client address integrity (REQ-PROX-10)

The audit trail records source IP (REQ-AUD-04). A wrong client address is
therefore an **integrity defect in the audit record**, not a cosmetic one — it
is a record that says a different person did the thing.

- HAProxy sets `X-Forwarded-For` with `option forwardfor`.
- The app trusts a forwarded address **only** from a configured trusted-proxy
  list, never because the header is present.
- In `behind-proxy` mode the trusted list includes the upstream, and the app
  takes the correct element of the chain rather than the leftmost or rightmost by
  habit. Which element is correct depends on how many trusted hops precede it, so
  this is derived from the declared topology, not hardcoded.
- In `delegated` mode the app cannot verify the chain and says so in the audit
  record rather than recording a value it cannot vouch for.

## 7. Headers in two places on purpose (REQ-PROX-11)

TLS policy and security headers (REQ-SEC-02, REQ-SEC-08) are set by the app
**and** asserted at the edge. The duplication is deliberate: if someone removes
the proxy, or runs the app directly in `delegated` mode, the headers must not
silently disappear with it. Where the two disagree, the stricter wins and the
mismatch is logged.

## 8. Observability (REQ-PROX-12)

HAProxy's stats and runtime state — connection counts, reload history,
certificate load status and expiry, error rates, backend health — are exposed to
permitted operators and forwarded to the same sinks as everything else
(REQ-AUD-07). The stats socket is never reachable from outside the compose
network.

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|----------|--------|-----|---------------------|
| Edge proxy | HAProxy | Long-lived-connection behaviour must be ours to configure and test; scriptable certificate installation (REQ-PROX-01) | No |
| Edge present behind an external proxy | Yes | Otherwise SSE and WebSocket behaviour becomes a property of someone else's config | No |
| Default topology | `self` | The app owns its edge end to end unless told otherwise | Yes — A24 asks |
| HAProxy↔app hop | TLS | REQ-SEC-01 has no internal exemption | No |
| `timeout tunnel` | `1h` | An idle console stream must survive | Yes |
| Certificate install | Runtime API + disk write | Hitless, and survives restart | No |
| Reload mechanism | master-worker, `expose-fd listeners`, `-sf` | Established connections are not dropped | No |
| Forwarded-address trust | Explicit trusted-proxy list | An unverified source IP is an audit-integrity defect | No |
| WebSocket backend mode | HTTP mode, native upgrade | `mode tcp` would lose forwarded-address handling | No |

## How this is verified

| Requirement | Test |
|-------------|------|
| REQ-PROX-06 | `tests/integration/edge/sse-stream.spec.ts` — open the console SSE stream through `edge`, assert the first event arrives inside a stated budget, assert events emitted 5s apart arrive ~5s apart rather than batched, and hold the stream idle past `timeout http-keep-alive` to prove it survives. Fails if buffering or coalescing is reintroduced. |
| REQ-PROX-07 | `tests/integration/edge/websocket.spec.ts` — upgrade, echo, and hold idle, run against every topology fixture. |
| REQ-PROX-04 | `tests/integration/edge/config-parity.spec.ts` — a hostname in the app config but not the generated HAProxy config fails the boot, and the error names the mismatch. |
| REQ-PROX-08 | `tests/integration/edge/tls-hop.spec.ts` — assert the app refuses a cleartext connection from `edge`. |
| REQ-PROX-09, REQ-ACME-13 | `tests/integration/edge/cert-swap.spec.ts` — install a new certificate under load, assert zero dropped connections, **then restart `edge` and assert the new certificate is still served** (the in-memory-only trap). |
| REQ-PROX-10 | `tests/integration/edge/forwarded-for.spec.ts` — per topology, assert the audit record's source IP equals the real client, and that a spoofed `X-Forwarded-For` from an untrusted hop is ignored. |
| REQ-PROX-11 | A21's visual/header assertions plus a direct-to-app request proving headers are present without the edge. |
| REQ-PROX-05 | Config assertion: the generated config contains the stated timeouts and `option http-no-delay` on the stream paths, and no compression filter matches `text/event-stream`. |

## Open to intake

| Question | Default if unanswered |
|----------|----------------------|
| Topology (`self` / `behind-proxy` / `delegated`) | `self`. A24 asks this explicitly at setup (REQ-WIZ-08) because it determines which ACME challenges are even possible. |
| Public hostname(s) and SAN list | Derived from the app name and the operator's domain; A24 confirms |
| `timeout tunnel` | `1h` |
| Trusted proxy CIDRs | The compose network only. In `behind-proxy` mode A24 requires the upstream's address before the step can complete — there is no safe default for trusting a hop. |
| Expose HAProxy stats to operators | Yes, permission-gated (REQ-PROX-12) |
