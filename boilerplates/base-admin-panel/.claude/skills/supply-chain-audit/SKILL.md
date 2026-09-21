---
name: supply-chain-audit
description: Runs the three separate supply-chain passes for the monorepo — a known-vulnerability pass (inventory with licence and provenance, CycloneDX SBOM, advisory matching, critical or known-exploited blocks the build), a first-party suspicious-code pass that greps node_modules and the lockfile for install scripts, obfuscation, credential reads, dynamic evaluation and typosquat names, and a telemetry kill pass asserted by test — then checks lockfile integrity, self-hosted assets and documented egress. Load at gate G7 or whenever a dependency is added, a lockfile changes, or you are asked about "audit the dependencies", "SBOM", "CVE", "malicious package", "postinstall script", "typosquat", "telemetry" or "phone home".
---

# Supply Chain Audit

A19 owns `security/supply-chain/**` and `.github/workflows/supply-chain.yml`.
Requirements: REQ-SUP-01 … REQ-SUP-08. A19 must be clean in the same round as the
S1/S2 verdicts for G7 to pass (`gates/gate-ladder.md` §G7.5).

**There are three passes and they are not the same pass.** Pass 1 asks "does
anyone already know this package is bad?". Pass 2 asks "does this code do things
a dependency has no business doing?" — it finds what no advisory database has
ever heard of, which is exactly the class that matters for a fresh compromise.
Pass 3 asks "is anything phoning home?". Running pass 1 and calling the audit
done is the failure mode this skill exists to prevent.

## Pass 1 — Known vulnerabilities

### 1.1 Inventory with licence and provenance (REQ-SUP-01)

```bash
mkdir -p security/supply-chain/$(date -u +%Y%m%d)
pnpm ls -r --depth Infinity --json > security/supply-chain/inventory.json
pnpm licenses list --json --long   > security/supply-chain/licences.json
jq -r '.[] | .versions[]? as $v | "\(.name)@\($v) \(.license) \(.homepage // "-")"' \
  security/supply-chain/licences.json | sort -u | wc -l
```

Direct **and** transitive. A top-level-only inventory is not an inventory.
Provenance is the resolved registry URL and integrity hash from the lockfile:

```bash
grep -E '^\s+(resolution|tarball):' pnpm-lock.yaml | grep -v 'registry.npmjs.org' | head -50
```

Anything resolved from a git URL, a tarball URL or a non-default registry is a
finding until it has a recorded justification (REQ-SUP-04).

### 1.2 CycloneDX SBOM (REQ-CRA-03)

```bash
npx --yes @cyclonedx/cdxgen@latest -t pnpm -o security/supply-chain/sbom.cdx.json .
jq -r '.bomFormat, .specVersion, (.components | length)' security/supply-chain/sbom.cdx.json
```

Check `--help` before trusting any flag beyond `-t/-o`; cdxgen's options move
between majors. The SBOM is retained per release, not regenerated on demand.

### 1.3 Advisory matching (REQ-SUP-02)

```bash
pnpm audit --json > security/supply-chain/audit.json; echo "exit=$?"
jq -r '.advisories // {} | to_entries[] | "\(.value.severity)\t\(.value.module_name)\t\(.value.title)"' \
  security/supply-chain/audit.json | sort
pnpm audit --audit-level high          # non-zero exit = the build stops
```

Cross-check against a second source (OSV, GitHub advisories) when egress allows:

```bash
curl -s -X POST -d '{"package":{"name":"<pkg>","ecosystem":"npm"},"version":"<ver>"}' \
  https://api.osv.dev/v1/query | jq -r '.vulns[]?.id'
```

**When this fails:** `api.osv.dev` is refused by this environment's egress proxy
(403 on CONNECT). Do not record "no advisories" from a blocked call. Record the
block, rely on `pnpm audit` plus the retained SBOM, and note in the report which
source was unavailable.

**A critical advisory, or any advisory on a known-exploited vulnerability, blocks
the build.** Not a warning, not a follow-up ticket. The choices are: upgrade,
remove the dependency, or a human-signed waiver in `build/waivers.md` — and a
`MUST` is never waived (REQ-REL-07).

## Pass 2 — First-party suspicious-code scan (REQ-SUP-03)

This is **your own** scan of the code on disk. Every check below produces a
finding that needs either a **recorded justification** in
`security/supply-chain/justifications.md` or the **removal** of the package
(REQ-SUP-04). "It is a popular package" is not a justification.

```bash
# install-time lifecycle scripts — the primary execution vector
jq -r 'select(.scripts) | .name as $n | .scripts
        | to_entries[] | select(.key|test("^(pre|post)?install$|^prepare$"))
        | "\($n)\t\(.key)\t\(.value)"' node_modules/*/package.json node_modules/@*/*/package.json 2>/dev/null
pnpm config get ignore-scripts        # expect true in CI; scripts are allowlisted per package

# obfuscated or minified source shipped as a source package
find node_modules -name '*.js' -size +200k -not -path '*/dist/*' -not -path '*/build/*' | head -20
grep -rlE '\\x[0-9a-f]{2}\\x[0-9a-f]{2}\\x[0-9a-f]{2}|_0x[0-9a-f]{4,}|atob\(' node_modules --include='*.js' | head -20

# network calls at install time
grep -rlE 'https?://|net\.(connect|Socket)|dns\.' $(jq -r 'select(.scripts.postinstall or .scripts.install or .scripts.preinstall) | .name' node_modules/*/package.json 2>/dev/null | sed 's|^|node_modules/|') 2>/dev/null | head

# credential and environment reads
grep -rnE 'process\.env\[[^]]|\.npmrc|\.ssh/|\.aws/credentials|\.config/gcloud|GOOGLE_APPLICATION_CREDENTIALS|AZURE_CLIENT_SECRET|id_rsa' \
  node_modules --include='*.js' --include='*.cjs' --include='*.mjs' -l | head -20

# dynamic evaluation and process spawning in a library with no business doing it
grep -rnE '\beval\(|new Function\(|child_process|execSync\(|spawnSync\(' \
  node_modules --include='*.js' -l | grep -vE 'node_modules/(typescript|esbuild|turbo|next|vite|playwright)/' | head -20

# unexpected binaries and wasm blobs
find node_modules -type f \( -name '*.node' -o -name '*.wasm' -o -name '*.so' -o -perm -u+x -name '*.sh' \) \
  | grep -vE '/(esbuild|sharp|@swc|lightningcss|@napi-rs)/' | head -20
```

**Typosquat check — against what is actually imported, not against a blocklist:**

```bash
# every package the source actually imports
grep -rhoE "from '(@?[a-z0-9@/._-]+)'" apps packages services --include='*.ts' --include='*.tsx' \
  | sed "s/from '//;s/'$//" | grep -v '^[.@]app' | cut -d/ -f1-2 | sort -u > /tmp/imported.txt
# every installed direct dependency
jq -r '.dependencies?, .devDependencies? | select(.) | keys[]' package.json apps/*/package.json packages/*/package.json \
  | sort -u > /tmp/declared.txt
comm -13 /tmp/imported.txt /tmp/declared.txt    # declared but never imported — why is it here?
```

Then eyeball the near-misses: a name one edit away from a package you do import
(`react-dom` vs `react-domm`, `@types/node` vs `types-node`) is a finding, and an
installed package nothing imports is a finding of its own.

**Maintainer and age anomalies:**

```bash
for p in $(jq -r '.dependencies | keys[]' package.json); do
  enc=$(printf '%s' "$p" | sed 's|/|%2F|')
  curl -s "https://registry.npmjs.org/$enc" | jq -r --arg p "$p" \
    '"\($p)\t\(."dist-tags".latest)\t\(.time[."dist-tags".latest])\t\(.maintainers|length) maintainers"'
done
```

A version published within the last few days, a maintainer set that changed since
the last build, or a long-dormant package suddenly releasing — each is a finding
that holds the upgrade until a human looks (REQ-SUP-04).

**When this fails:** the greps return hundreds of hits and the temptation is to
skim. Do not widen the exclusions to quiet the output — narrow the scope instead:
run each check against the packages the lockfile shows as *added or changed* in
this build's diff, and run the full sweep on a clean checkout.

## Pass 3 — Telemetry kill (REQ-SUP-06)

Disabled **and asserted by test**. An unset variable that happens to default off
today is not compliance.

```bash
# build- and run-time environment, set in compose, Dockerfile and CI
NEXT_TELEMETRY_DISABLED=1
TURBO_TELEMETRY_DISABLED=1
DO_NOT_TRACK=1

npx next telemetry disable && npx next telemetry status   # writes the persisted flag
```

For anything else in `versions/manifest.json`: read its docs for a telemetry
switch, set it, and add it to `security/supply-chain/telemetry-kill-list.md` with
the setting and the source. A tool with no documented switch is only acceptable
if the egress check (below) shows it makes no outbound call.

The assertion belongs in the test suite, not in a comment:

```ts
// tests/security/telemetry.spec.ts
for (const k of ['NEXT_TELEMETRY_DISABLED', 'TURBO_TELEMETRY_DISABLED', 'DO_NOT_TRACK'])
  expect(process.env[k], `${k} must be set`).toBe('1');
expect(readFileSync('.next/telemetry.json', 'utf8')).toContain('"enabled":false');
```

## Lockfile integrity (REQ-SUP-05)

A changed lockfile with no matching `package.json` change fails CI — it is the
signature of an injected or drifted dependency.

```bash
base=${GITHUB_BASE_REF:-origin/main}
lock=$(git diff --name-only "$base"... -- pnpm-lock.yaml | wc -l)
pkgs=$(git diff --name-only "$base"... -- '**/package.json' 'package.json' | wc -l)
[ "$lock" -gt 0 ] && [ "$pkgs" -eq 0 ] && { echo "LOCKFILE CHANGED WITHOUT MANIFEST CHANGE — REQ-SUP-05"; exit 1; }
pnpm install --frozen-lockfile --ignore-scripts   # must succeed unchanged
```

## Self-hosted assets (REQ-SUP-07)

No remote font, script or asset at runtime. This check finds the reference:

```bash
grep -rnE "https?://(fonts\.googleapis|fonts\.gstatic|cdn\.|unpkg\.com|jsdelivr|cdnjs|googletagmanager|google-analytics)" \
  apps packages --include='*.ts' --include='*.tsx' --include='*.css' --include='*.html'
grep -rnE '<(script|link)[^>]+(src|href)="https?://' apps --include='*.tsx' --include='*.html'
grep -rn '@import url("http' apps packages --include='*.css'
```

Any hit is a finding for the owning agent: vendor the asset into the repo. Add a
CSP `connect-src`/`font-src`/`script-src` assertion in the e2e run so a new
remote reference fails a test rather than a review.

## Documented egress (REQ-SUP-08)

Every outbound destination the container may reach is listed in
`security/supply-chain/egress.md` with the REQ ID that justifies it. The egress
client A01 owns is the only path out.

```bash
grep -rnoE 'https?://[a-z0-9.-]+' apps packages services --include='*.ts' \
  | grep -vE 'localhost|127\.0\.0\.1|example\.(com|org)|schema|w3\.org|json-schema' \
  | awk -F'//' '{print $2}' | cut -d/ -f1 | sort -u > /tmp/found-egress.txt
comm -13 <(sort security/supply-chain/egress-allowlist.txt) /tmp/found-egress.txt
```

Anything the second command prints is an undocumented destination and fails G7.
Confirm at runtime too: a destination that only appears at run time (a webhook
from config, an OIDC discovery URL) belongs in the same list with its REQ ID.
