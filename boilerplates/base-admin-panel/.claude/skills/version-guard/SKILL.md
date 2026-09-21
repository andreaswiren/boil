---
name: version-guard
description: Resolves every language, runtime, framework, library and base-image version from its authoritative registry — npm, nodejs.org, crates.io, PyPI, Docker Hub — rejects prereleases and RCs, writes versions/manifest.json with a source URL and check timestamp per entry, holds major jumps for a reviewed migration note, and records compatibility traps such as @types/node tracking the Node LTS major. Load at gate G2, before any pnpm add, Dockerfile FROM or Cargo.toml dependency line, when a new dependency is requested mid-build, or when asked about "latest stable", "version manifest", "is this version current", "major bump" or "@types/node mismatch".
---

# Version Guard

Gate G2 (`gates/gate-ladder.md`). A20 owns `versions/**` and nothing else.
Requirements: REQ-VER-01 … REQ-VER-06, REQ-FND-06, REQ-SUP-04.

**Core rule: never take a version from memory. Always from the registry. Always
write down where you looked and when.** A version you remember was current on
some day you cannot name. A lookup that cannot be completed is a hard fail, never
a fallback to memory (G2, "Fail → A20").

## 1. Collect the request list

Read `build/scope.md` for the live ecosystems: `remoteAgents: false` means no
crates.io lookups; PyPI always runs, because `services/normalizer/` is a MUST
(REQ-DAT-04). Group by ecosystem and record `requestedBy` (agent ID) and `why`
(REQ IDs) per request — a package with neither is convenience, not a dependency
(REQ-SUP-04).

## 2. Resolve the anchors first

Other entries pin *to* these, so they are not resolved in parallel with them.

```bash
# Node LTS — .lts is false on non-LTS lines, so select(.lts) keeps only LTS
curl -s https://nodejs.org/dist/index.json | jq -r '[.[] | select(.lts)][0] | "\(.version) \(.lts)"'

# PostgreSQL stable — Docker Hub tag list, with the digest A01 pins by (REQ-FND-09)
curl -s 'https://hub.docker.com/v2/repositories/library/postgres/tags?page_size=100' \
  | jq -r '.results[] | select(.name | test("^[0-9]+(\\.[0-9]+)?$")) | "\(.name)\t\(.digest)"' \
  | sort -rV | head -5
```

Record the specific tag (`18.6`), not the bare major: the bare tag moves.

**When this fails:** `postgresql.org/versions.json` and `endoflife.date` are both
refused by this environment's egress proxy (403 on CONNECT). Do not retry them and
do not read the refusal as "no such version" — use the Docker Hub tag list as the
source of record and note the blocked cross-check in `versions/check-log.txt`.

## 3. Registry lookups

```bash
# npm, unscoped
curl -s https://registry.npmjs.org/next/latest | jq -r .version

# npm, SCOPED — the / in @scope/name must be URL-encoded as %2F
curl -s https://registry.npmjs.org/@playwright%2Ftest/latest | jq -r .version

# npm, when the latest dist-tag may be a prerelease or you need a specific major:
# sort numerically by component — a lexicographic sort puts 5.9.2 above 10.0.0
curl -s https://registry.npmjs.org/typescript \
  | jq -r '[.versions | keys[] | select(test("-") | not)] | sort_by(split(".") | map(tonumber)) | last'

# crates.io — it rejects requests without a User-Agent, so always send one
curl -s -H 'User-Agent: boil-version-guard' https://crates.io/api/v1/crates/tokio | jq -r .crate.max_stable_version

# PyPI
curl -s https://pypi.org/pypi/pydantic/json | jq -r .info.version
curl -s https://pypi.org/pypi/pydantic/json | jq -r '.info.yanked'   # must be false
```

Tee every raw response into `versions/check-log.txt` as you go — that log is the
evidence the check was external (REQ-VER-02). S1, S2 and A19 read it.

**When this fails:** a lookup returns `null`, `{}` or an HTML error page — that is
a wrong name, a missing `%2F`, or a blocked host, not a missing package. Check the
status with `curl -s -o /dev/null -w '%{http_code}'` before concluding anything,
and never substitute a remembered number for a failed lookup.

## 4. Reject prereleases — explicitly and loudly

REQ-VER-01. A registry's `latest` tag is not a promise of stability.

```bash
jq -r '.entries | to_entries[] | "\(.key) \(.value.version)"' versions/manifest.json \
  | grep -E -- '-(alpha|beta|rc|next|canary|dev|insiders|pre)' && echo "PRERELEASE IN MANIFEST — REQ-VER-01"
```

Log each rejection with the string it rejected. A silent filter hides the case
where a package publishes *only* prereleases — a decision for the human.

## 5. Write the manifest

REQ-VER-03. Four fields per entry are mandatory: `version`, `ecosystem`,
`source`, `checkedAt`. An entry missing any of them is invalid and G2 fails.

```jsonc
{
  "generatedAt": "2026-09-21T21:04:11Z",
  "entries": {
    "node": { "ecosystem": "runtime", "version": "24.21.0", "channel": "lts", "lts": "Krypton",
      "source": "https://nodejs.org/dist/index.json", "checkedAt": "2026-09-21T21:03:52Z",
      "requestedBy": "A01", "why": "REQ-FND-03, REQ-VER-06" },
    "@types/node": { "ecosystem": "npm", "version": "24.13.6", "pinnedMajor": 24,
      "trap": "VER-TRAP-001", "source": "https://registry.npmjs.org/@types%2Fnode",
      "checkedAt": "2026-09-21T21:03:58Z", "requestedBy": "A01",
      "why": "REQ-VER-05 — tracks the Node LTS major, not latest (26.6.2)" },
    "postgres": { "ecosystem": "docker", "version": "18.6", "digest": "sha256:…",
      "source": "https://hub.docker.com/v2/repositories/library/postgres/tags?page_size=100",
      "checkedAt": "2026-09-21T21:04:03Z", "requestedBy": "A01", "why": "REQ-FND-05, REQ-VER-06",
      "crossCheckBlocked": "postgresql.org/versions.json — 403 at the egress proxy" }
  },
  "majorJumps": [
    { "name": "typescript", "from": 6, "to": 7,
      "migrationNote": "versions/notes/typescript-7.md", "acknowledgedBy": "human" }
  ],
  "traps": [
    { "id": "VER-TRAP-001", "applies": "@types/node",
      "rule": "major must equal entries.node.version major",
      "symptom": "type errors on built-in modules that only appear in CI" }
  ]
}
```

`checkedAt` is the lookup's timestamp, not the write's — capture
`date -u +%Y-%m-%dT%H:%M:%SZ` per entry as you make the call.

## 6. A major jump is a decision, never an automatic bump

REQ-VER-04. Diff each entry's major against the previous manifest:

```bash
jq -r '.entries | to_entries[] | "\(.key) \(.value.version | split(".")[0])"' versions/manifest.json.prev | sort > /tmp/prev.txt
jq -r '.entries | to_entries[] | "\(.key) \(.value.version | split(".")[0])"' versions/manifest.json      | sort > /tmp/head.txt
join /tmp/prev.txt /tmp/head.txt -o 0,1.2,2.2 | awk '$2 != $3 { print "MAJOR JUMP:", $1, $2, "->", $3 }'
```

For each jump write `versions/notes/<name>-<major>.md` — breaking changes from
the release notes, affected agents, work each one owes — then **stop and ask the
human**. An unacknowledged major does not enter the manifest; `acknowledgedBy:
"human"` is a recorded answer, not a placeholder.

## 7. Record the traps instead of rediscovering them

REQ-VER-05. Every trap you hit becomes an entry the next build inherits from
`versions/traps.json`. Apply every inherited rule before finalising.

- **`VER-TRAP-001` — `@types/node` tracks the Node **LTS** major.** Verified
  today: `@types/node` `latest` is `26.6.2` while Node LTS is `24.21.0`. Taking
  `latest` gives type definitions for a runtime the app does not run on, and the
  errors surface in CI, not locally. Resolve it against the LTS major:
  ```bash
  lts=$(curl -s https://nodejs.org/dist/index.json | jq -r '[.[]|select(.lts)][0].version' | sed 's/^v//;s/\..*//')
  curl -s https://registry.npmjs.org/@types%2Fnode \
    | jq -r --arg m "$lts." '[.versions|keys[]|select(startswith($m))|select(test("-")|not)]
            | sort_by(split(".")|map(tonumber)) | last'
  ```
- **`typescript` has the same *shape* of trap** when a new major is a rewrite
  rather than an increment (TypeScript 7 is the native port; `latest` is already
  on it). The newest stable is not automatically installable — the constraint is
  what the toolchain accepts. Read the consumers' `peerDependencies` first:
  ```bash
  curl -s https://registry.npmjs.org/typescript-eslint/latest | jq -c '.peerDependencies'
  ```
  If a consumer range excludes the new major, pin the highest major every
  consumer accepts and write that reason into the entry as a trap.

**When this fails:** an agent "fixes" a type error by bumping `@types/node` past
the LTS major. That is the trap re-entered, not a fix. The manifest wins; the
error belongs to whoever wrote code against a non-LTS API.

## 8. Verify before handing off

```bash
jq -e '[.entries[] | select((.source|not) or (.checkedAt|not) or (.version|not) or (.ecosystem|not))] | length == 0' versions/manifest.json
jq -e '.entries.node.channel == "lts"' versions/manifest.json
jq -e '.entries["@types/node"].pinnedMajor == (.entries.node.version|split(".")[0]|tonumber)' versions/manifest.json
jq -e '[.majorJumps[] | select(.acknowledgedBy != "human")] | length == 0' versions/manifest.json
jq -e '[.entries[] | select((.requestedBy|not) or (.why|not))] | length == 0' versions/manifest.json
git status --porcelain | grep -v '^.. versions/' && echo "WROTE OUTSIDE versions/ — build defect"
```

G2 passes on: zero entries without a source URL and timestamp, zero prereleases,
one acknowledged migration note per major jump. Until it passes there is no
`pnpm add`, no Dockerfile `FROM`, no `Cargo.toml` dependency line (REQ-FND-06).
