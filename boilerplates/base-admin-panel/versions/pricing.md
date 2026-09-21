# Pricing

`pricing.json` is the only place a price is allowed to come from. A26 reads it;
it never writes a rate from memory (REQ-COST-05). This file is what that file's
`$schema` points at: the entry shape, what a `confidence` level permits, how to
re-validate, and the traps already recorded.

Owned by **A26 cost-accountant**. Re-validated at gate **G2**, alongside A20's
`manifest.json`, before anything is derived from it. Same gate, same discipline:
a remembered price is wrong for the same reason a remembered version is
(REQ-VER-02).

`manifest.json` decides what gets installed. This file decides nothing — it only
prices what already happened. That is why a wrong entry is quiet: nothing fails,
a column just reads low.

## Entry shape

A provider carries the provenance; a model carries the rates.

```json
"anthropic": {
  "source": "https://docs.claude.com/en/docs/about-claude/pricing",
  "checkedAt": "2026-09-21T22:18:53Z",
  "confidence": "secondary",
  "provenance": "Bundled claude-api skill's cached model table, dated 2026-06-24.",
  "models": {
    "claude-opus-5": {
      "input": 5.0,
      "output": 25.0,
      "note": "Default build model. Fast mode is billed at 10.00/50.00 and is a separate decision."
    }
  }
}
```

- `unit` is fixed at the top of the file: **USD per 1,000,000 tokens**. Every
  rate is in that unit; no entry carries its own unit.
- `input` and `output` are required. `cacheRead` and `cacheWrite` are optional,
  and **absent means unpriced, not free** — A26 reports the token count and
  leaves the money cell `unpriced` (REQ-COST-08, REQ-COST-12).
- `source` is the URL that would confirm the figure. `checkedAt` is when it was
  last attempted, whether or not the attempt succeeded.
- `provenance` says where the number actually came from. When `confidence` is
  `secondary`, this field is the only thing standing between a reader and a
  figure they would otherwise assume was fetched.
- A field may carry its own marker: `cacheReadConfidence: "unconfirmed"` means
  that one rate is weaker than the entry's `confidence` and is not usable for a
  money cell until it is confirmed. The narrower marker always wins.
- `note`, `warning` and `defaultTierWarning` are free text. A `warning` means
  the rate is real but using it has a consequence — see the contributor tier.

## Confidence levels

| Level | Means | What it permits |
|-------|-------|-----------------|
| `verified` | This build fetched `source`, got HTTP `200`, and read the rate out of that body | Money columns without an estimate label |
| `secondary` | The figure came from a cache, a search snippet or an aggregator, and was not confirmed against the provider this build | Money columns **labelled an estimate**, with the price shown (REQ-COST-04) |
| rate absent | No `cacheRead`/`cacheWrite` entry, or the model is not in the file | `unpriced` cell; the token count is still reported (REQ-COST-12) |

There is no third level and no "probably current". A figure is either confirmed
this build or it is an estimate.

**Never upgrade `secondary` to `verified` without a successful fetch.** The gate
is the HTTP status code plus the rate read out of the response body. A fetched
figure that matches the stored one is not evidence of anything — that is the
number being checked.

Every entry in this repository is `secondary` today. The pricing pages are
unreachable through this environment's egress proxy (`egressNote` in
`pricing.json`, 2026-09-21), so every money column the build produces is an
estimate and says so.

## Re-validating

Always with the status code visible. A bare `curl -s` makes a proxy block look
like an empty page, which is how a 403 becomes a silent zero.

```bash
# Status first, body second. 000 means curl never got an HTTP response at all.
curl -sS -o /dev/null -w '%{http_code}\n' --max-time 20 \
  https://docs.claude.com/en/docs/about-claude/pricing
curl -sS -o /dev/null -w '%{http_code}\n' --max-time 20 \
  https://www.anthropic.com/pricing
curl -sS -o /dev/null -w '%{http_code}\n' --max-time 20 \
  https://dev.meta.ai/docs/pricing-rate-limits

# Only on 200: keep the body and read the rate out of it.
curl -sS -o /tmp/pricing.html -w '%{http_code}\n' --max-time 20 \
  https://docs.claude.com/en/docs/about-claude/pricing
grep -Eo '\$[0-9]+(\.[0-9]+)?[^<]*(input|output)' /tmp/pricing.html | head

# The proxy's own view, when a code makes no sense.
curl -sS "$HTTPS_PROXY/__agentproxy/status"
```

| Code | What it means here | What you write |
|------|--------------------|----------------|
| `200` | Fetched. Read the rate from the body | `verified`, new `checkedAt` |
| `301`, `302` | Redirected — the recorded `source` is stale. Follow it manually and record the destination | stays `secondary`; fix `source` |
| `403`, `407` | Blocked, usually by the proxy | stays `secondary`; note the code in `egressNote` |
| `404` | The page moved. Find the new one; do not guess a rate | stays `secondary`; `source` needs fixing |
| `000` | No HTTP response: TLS failure, refusal, timeout | stays `secondary`; note it in `egressNote` |

A re-validation that changed nothing still updates `checkedAt` and records which
URL returned what. The record of a failed check is the useful part.

## Staleness

`policy.staleAfterDays` is **14**. A `checkedAt` older than that makes every
money column an estimate, whatever the `confidence` says. Prices move without a
changelog, so an old `verified` and a fresh `secondary` deserve the same label.

Staleness never invalidates a token count. Counts are measured; only the money
derived from them degrades.

## Traps currently recorded

| Entry | Trap |
|-------|------|
| Every Anthropic figure | Traces to the bundled `claude-api` skill's cached model table dated **2026-06-24**, not to the live pricing page. The page returned 302 through this proxy. Treat the whole provider block as one unconfirmed source, not nine independent ones. |
| `claude-opus-5` cache rates | No `cacheRead` or `cacheWrite` rate is recorded. Cache-read tokens are the majority of input in this build (~65%), so the unpriced share of the total is large. Do not substitute another model's ratio to close it — report `unpriced` (REQ-COST-08). |
| `claude-opus-5` fast mode | Billed at 10.00/50.00, double the standard rate. Running a wave in fast mode is a separate decision with a separate line in the cost table, not a hidden 2x. |
| Every Meta figure | Came from search snippets citing `dev.meta.ai` and third-party write-ups, retrieved 2026-09-21. Meta's own hosts (`dev.meta.ai`, `developer.meta.com`) are blocked by this proxy, so **nothing in this block was read from the vendor**. Aggregators copy each other, so three agreeing sources are frequently one source. |
| `muse-spark-1.3` | The quoted 1.25/4.25 is for the **xhigh tier on the standard endpoint**. Tier and endpoint both change the rate. Confirm the tier matches how the build actually runs before deriving money from it — the figure is right for a configuration that may not be yours. |
| `muse-spark-1.3-contributor` | Roughly 10-20x cheaper **because Meta may train on the prompts and outputs**. That is the trade, not a discount. This build handles security posture, credentials guidance and compliance evidence, so using this tier is an explicitly recorded decision (REQ-PORT-08), never a default and never a cost optimisation A26 applies on its own. Its `cacheRead` of 0.002 is marked `unconfirmed` and is not usable for a money cell. |
| Muse Code's default tier | Secondary sources report that Muse Code **defaults to the contributor tier after install**, making opt-out an active step rather than an offered choice (`defaultTierWarning` in `pricing.json`, unconfirmed). Verify before the first build with `cat ~/.config/muse/settings.json` and by checking which model id the session reports. If it holds, a build on a fresh install has already sent its prompts to a training-eligible tier, so REQ-PORT-08's recorded decision has to be made **before** the first run. |
| `batch` modifier | 0.5x, asynchronous. It cannot serve an interactive wave, so it never appears in a wave estimate. It is available for bulk analysis, and the multiplier is recorded so nobody re-derives it. |

## When a price moves

1. Do not edit the rate alone. Update `input`/`output`, `checkedAt`,
   `confidence` and `provenance` in one pass, so the figure and its evidence
   never disagree.
2. Record the previous value in the entry's `note` with the date it changed.
   Two builds compared under REQ-COST-10 may straddle the change, and a
   comparison across a silent price change is worse than no comparison.
3. Do not retro-price an earlier build. Its table states the rate it used; that
   is what makes it reproducible.
4. If the fetch failed, change nothing but `checkedAt` and `egressNote`. A
   failed check is recorded, never rounded into a guess.
