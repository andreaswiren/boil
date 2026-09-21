---
name: supply-chain-audit
description: Runs the three separate supply-chain passes for the monorepo — a known-vulnerability pass (inventory with licence and provenance, CycloneDX SBOM, advisory matching, critical or known-exploited blocks the build), a first-party suspicious-code pass that greps node_modules and the lockfile for install scripts, obfuscation, credential reads, dynamic evaluation and typosquat names, and a telemetry kill pass asserted by test — then checks lockfile integrity, self-hosted assets and documented egress. Load at gate G7 or whenever a dependency is added, a lockfile changes, or you are asked about "audit the dependencies", "SBOM", "CVE", "malicious package", "postinstall script", "typosquat", "telemetry" or "phone home".
---

# Supply Chain Audit

A19 owns `security/supply-chain/**` and `.github/workflows/supply-chain.yml`.
Requirements REQ-SUP-01 … REQ-SUP-08. A19 must be clean in the same round as the
S1/S2 verdicts for G7 to pass (`gates/gate-ladder.md` §G7.5).

**Three passes, and they are not the same pass.** Pass 1 asks "does anyone already
know this package is bad?". Pass 2 asks "does this code do things a dependency has
no business doing?" — it finds what no advisory database has heard of, the class
that matters for a fresh compromise. Pass 3 asks "is anything phoning home?".
Running pass 1 and calling the audit done is the failure mode this skill prevents.

## Pass 1 — Known vulnerabilities

**1.1 Inventory, licence and provenance (REQ-SUP-01).**

```bash
pnpm ls -r --depth Infinity --json > security/supply-chain/inventory.json
pnpm licenses list --json --long   > security/supply-chain/licences.json
```

Direct **and** transitive — a top-level-only inventory is not an inventory.
Provenance is the lockfile's resolved URL and integrity hash; anything from a git
URL, a tarball or a non-default registry is a finding until justified (REQ-SUP-04):

```bash
grep -E '^\s+(resolution|tarball):' pnpm-lock.yaml | grep -v 'registry.npmjs.org' | head -50
```

**1.2 CycloneDX SBOM (REQ-CRA-03).**

```bash
npx --yes @cyclonedx/cdxgen@latest -t pnpm -o security/supply-chain/sbom.cdx.json .
jq -r '.bomFormat, .specVersion, (.components|length)' security/supply-chain/sbom.cdx.json
```

Check `cdxgen --help` before trusting a flag beyond `-t/-o` — its options move
between majors. The SBOM is retained per release, not regenerated on demand.

**1.3 Advisory matching (REQ-SUP-02).**

```bash
pnpm audit --json > security/supply-chain/audit.json
jq -r '.advisories // {} | to_entries[] | "\(.value.severity)\t\(.value.module_name)"' security/supply-chain/audit.json | sort
pnpm audit --audit-level high     # non-zero exit = the build stops
# second source, when egress allows:
curl -s -X POST -d '{"package":{"name":"<pkg>","ecosystem":"npm"},"version":"<ver>"}' \
  https://api.osv.dev/v1/query | jq -r '.vulns[]?.id'
```

**When this fails:** `api.osv.dev` is refused by this environment's egress proxy
(403 on CONNECT). Never record "no advisories" from a blocked call — record the
block, rely on `pnpm audit` plus the SBOM, and name the missing source.

**A critical advisory, or one on a known-exploited vulnerability, blocks the
build** — not a warning, not a ticket. Upgrade, remove the dependency, or get a
human-signed waiver in `build/waivers.md`; a `MUST` is never waived (REQ-REL-07).

## Pass 2 — First-party suspicious-code scan (REQ-SUP-03)

Your own scan of the code on disk. Every finding needs either a **recorded
justification** in `security/supply-chain/justifications.md` or the **removal** of
the package (REQ-SUP-04). "It is popular" is not a justification.

```bash
# install-time lifecycle scripts — the primary execution vector
jq -r 'select(.scripts) | .name as $n | .scripts
        | to_entries[] | select(.key|test("^(pre|post)?install$|^prepare$"))
        | "\($n)\t\(.key)\t\(.value)"' node_modules/*/package.json node_modules/@*/*/package.json 2>/dev/null
pnpm config get ignore-scripts    # expect true in CI; scripts allowlisted per package
# obfuscated or minified source shipped as a source package
find node_modules -name '*.js' -size +200k -not -path '*/dist/*' -not -path '*/build/*' | head -20
grep -rlE '\\x[0-9a-f]{2}\\x[0-9a-f]{2}\\x[0-9a-f]{2}|_0x[0-9a-f]{4,}|atob\(' node_modules --include='*.js' | head -20
# network calls inside the packages that run at install time
grep -rlE 'https?://|net\.(connect|Socket)|dns\.' $(jq -r 'select(.scripts.postinstall or .scripts.install or .scripts.preinstall) | .name' node_modules/*/package.json 2>/dev/null | sed 's|^|node_modules/|') 2>/dev/null | head
# credential and environment reads
grep -rlE 'process\.env\[[^]]|\.npmrc|\.ssh/|\.aws/credentials|\.config/gcloud|GOOGLE_APPLICATION_CREDENTIALS|id_rsa' node_modules --include='*js' | head -20
# dynamic evaluation and process spawning in a library with no business doing it
grep -rlE '\beval\(|new Function\(|child_process|execSync\(' node_modules --include='*.js' | grep -vE '/(typescript|esbuild|turbo|next|vite|playwright)/' | head -20
# unexpected binaries and wasm blobs
find node_modules -type f \( -name '*.node' -o -name '*.wasm' -o -name '*.so' -o -name '*.sh' \) | grep -vE '/(esbuild|sharp|@swc|lightningcss|@napi-rs)/' | head -20
```

**Typosquat check — against what is actually imported, not against a blocklist:**

```bash
grep -rhoE "from '(@?[a-z0-9@/._-]+)'" apps packages services --include='*.ts' --include='*.tsx' \
  | sed "s/from '//;s/'$//" | grep -v '^[.@]app' | cut -d/ -f1-2 | sort -u > /tmp/imported.txt
jq -r '.dependencies?, .devDependencies? | select(.) | keys[]' package.json apps/*/package.json packages/*/package.json \
  | sort -u > /tmp/declared.txt
comm -13 /tmp/imported.txt /tmp/declared.txt    # declared, never imported — why is it here?
```

Then read the near-misses: a name one edit from something you do import
(`react-dom` vs `react-domm`, `@types/node` vs `types-node`) is a finding, and so is
a declared package nothing imports.

**Maintainer and age anomalies:**

```bash
for p in $(jq -r '.dependencies | keys[]' package.json); do
  curl -s "https://registry.npmjs.org/$(printf '%s' "$p" | sed 's|/|%2F|')" \
    | jq -r --arg p "$p" '"\($p)\t\(."dist-tags".latest)\t\(.time[."dist-tags".latest])\t\(.maintainers|length) maint"'
done
```

A version published in the last few days, a maintainer set that changed since the
last build, or a long-dormant package suddenly releasing — each holds the upgrade
until a human looks (REQ-SUP-04). Diff the maintainer list against the last run.

**When this fails:** the greps return hundreds of hits and skimming starts. Do not
widen the exclusions to quiet the output — narrow the scope: run each check against
the packages the lockfile diff added or changed, and sweep fully on a clean checkout.

## Pass 3 — Telemetry kill (REQ-SUP-06)

Disabled **and asserted by test**. A variable that happens to default off today
is not compliance.

```bash
# set in compose, the Dockerfile and CI — build time and run time
NEXT_TELEMETRY_DISABLED=1
TURBO_TELEMETRY_DISABLED=1
DO_NOT_TRACK=1
npx next telemetry disable && npx next telemetry status   # persisted flag
```

For everything else in `versions/manifest.json`: find its documented switch, set
it, and list it in `security/supply-chain/telemetry-kill-list.md` with the setting
and the source. A tool with no switch passes only if the egress check below shows
it makes no outbound call. The assertion belongs in the suite, not a comment:

```ts
// tests/security/telemetry.spec.ts
for (const k of ['NEXT_TELEMETRY_DISABLED', 'TURBO_TELEMETRY_DISABLED', 'DO_NOT_TRACK'])
  expect(process.env[k], `${k} must be set`).toBe('1');
expect(readFileSync('.next/telemetry.json', 'utf8')).toContain('"enabled":false');  // REQ-SUP-06
```

## Standing checks

**Lockfile integrity (REQ-SUP-05).** A changed lockfile with no matching
`package.json` change fails CI — the signature of an injected or drifted dependency.

```bash
base=${GITHUB_BASE_REF:-origin/main}
lock=$(git diff --name-only "$base"... -- pnpm-lock.yaml | wc -l)
pkgs=$(git diff --name-only "$base"... -- '**/package.json' 'package.json' | wc -l)
[ "$lock" -gt 0 ] && [ "$pkgs" -eq 0 ] && { echo "LOCKFILE CHANGED WITHOUT MANIFEST CHANGE — REQ-SUP-05"; exit 1; }
pnpm install --frozen-lockfile --ignore-scripts   # must succeed unchanged
```

**Self-hosted assets (REQ-SUP-07).** No remote font, script or asset at runtime.
These find the reference:

```bash
grep -rnE "https?://(fonts\.googleapis|fonts\.gstatic|cdn\.|unpkg\.com|jsdelivr|cdnjs|googletagmanager|google-analytics)" \
  apps packages --include='*.ts' --include='*.tsx' --include='*.css' --include='*.html'
grep -rnE '<(script|link)[^>]+(src|href)="https?://|@import url\("http' apps packages --include='*.tsx' --include='*.html' --include='*.css'
```

Any hit is a finding for the owning agent: vendor the asset. Add a CSP
`font-src`/`script-src`/`connect-src` assertion to the e2e run so the next one fails
a test rather than a review.

**Documented egress (REQ-SUP-08).** Every destination the container may reach is in
`security/supply-chain/egress.md` with the REQ ID justifying it; A01's egress client
is the only path out.

```bash
grep -rhoE 'https?://[a-z0-9.-]+' apps packages services --include='*.ts' \
  | grep -vE 'localhost|127\.0\.0\.1|example\.(com|org)|w3\.org|json-schema' \
  | awk -F'//' '{print $2}' | sort -u > /tmp/found-egress.txt
comm -13 <(sort security/supply-chain/egress-allowlist.txt) /tmp/found-egress.txt
```

Anything `comm` prints is an undocumented destination and fails G7. Destinations
that appear only at run time — a config webhook, an OIDC discovery URL — go in the
same list with their REQ ID.
