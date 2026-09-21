# Versions

`manifest.json` is the only place a version is allowed to come from. Agents read
it; they never write a version from memory (REQ-VER-02).

Owned by **A20 version-validator**. Regenerated and re-validated at gate **G2**
of every build, before anything is installed. A manifest older than
`policy.staleAfterDays` fails the gate.

## Entry shape

```json
"next": {
  "latestStable": "16.3.5",
  "pin": "^16.3.5",
  "source": "https://registry.npmjs.org/next/latest",
  "checkedAt": "2026-09-21T00:00:00Z"
}
```

`source` and `checkedAt` are the point of the file. A version without them is a
version someone remembered, and this manifest exists because remembered versions
are wrong (REQ-VER-03).

Where `pin` differs from `latestStable`, a `note` says why. Those notes are the
accumulated compatibility traps (REQ-VER-05) — they exist so the same mistake is
not rediscovered on the next build.

## Re-validating

```bash
# npm — scoped packages need the slash URL-encoded as %2F
curl -s https://registry.npmjs.org/next/latest | jq -r .version
curl -s https://registry.npmjs.org/@tanstack%2Freact-table/latest | jq -r .version

# Node LTS — not the newest release (REQ-VER-06)
curl -s https://nodejs.org/dist/index.json | jq -r '[.[]|select(.lts)][0].version'

# crates.io — requires a User-Agent
curl -s -H 'User-Agent: boil-version-guard' \
  https://crates.io/api/v1/crates/tokio | jq -r .crate.max_stable_version

# PyPI
curl -s https://pypi.org/pypi/fastapi/json | jq -r .info.version

# Docker images
curl -s 'https://hub.docker.com/v2/repositories/library/postgres/tags?page_size=100&ordering=last_updated' \
  | jq -r '.results[].name' | grep -E '^[0-9]+\.[0-9]+$' | sort -Vr | head -3

# Rust stable
curl -s https://static.rust-lang.org/dist/channel-rust-stable.toml | grep -A1 '^\[pkg.rust\]'
```

`endoflife.date` is blocked by this environment's egress proxy. Use the
registries above.

## Traps currently recorded

| Package | Trap |
|---------|------|
| `@types/node` | npm `latest` tracks a Node major we do not run. The pin follows the Node **LTS** major. Bumping it to match npm latest is a regression, not an upgrade. |
| `typescript` | Latest stable is the 7.x native rewrite. A major jump needs the reviewed-decision note (REQ-VER-04) and external confirmation that Next.js, Biome and drizzle-kit support it. |
| `syslog-pro` | Low release activity. Verify RFC 5424 structured data and RFC 5425 TLS against the actual package before adopting it, or implement the framing over a `tls.TLSSocket` directly. |
| `shadcn` | A CLI, run via `npx`/`pnpm dlx`, not a dependency. Preset codes are decoded with `npx shadcn@latest preset decode` — never by hand. |
| `@tanstack/react-table` | Major 9. Do not carry v8 patterns across. |

## When a major jumps

1. Do not bump automatically (REQ-VER-04).
2. Write `build/versions-review.md`: what moved, what the breaking changes are,
   what in this stack touches them.
3. Confirm the rest of the stack supports it — externally, from the dependency's
   own release notes, not by assumption.
4. Bump, or pin the previous line with the reason recorded. Either outcome is
   acceptable; an unrecorded one is not.
