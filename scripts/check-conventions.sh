#!/usr/bin/env bash
# Verifies every boilerplate against CONVENTIONS.md.
# Exits non-zero on any violation. Run from the repository root.
set -uo pipefail

fail=0
note() { printf '  %s\n' "$*"; }
bad()  { printf '  FAIL: %s\n' "$*"; fail=1; }

for dir in boilerplates/*/; do
  name=$(basename "$dir")
  printf '\n== %s ==\n' "$name"

  # CONVENTIONS.md §1 — self-containment. A boilerplate must work cloned alone.
  if grep -rqn '\.\./\.\.' "$dir" --include='*.md' --include='*.json' --include='*.yaml' 2>/dev/null; then
    bad "path escapes the boilerplate folder:"
    grep -rn '\.\./\.\.' "$dir" --include='*.md' --include='*.json' --include='*.yaml' | sed 's/^/    /'
  else
    note "self-contained: no escaping relative paths"
  fi
  if find "$dir" -type l 2>/dev/null | while read -r l; do readlink "$l"; done | grep -qF '../'; then
    bad "symlink points outside the boilerplate"
  fi

  # CONVENTIONS.md §2 — required structure.
  for f in README.md CLAUDE.md AGENTS.md spec/requirements.md prompts/00-master-orchestrator.md; do
    [ -f "$dir$f" ] || bad "missing required file: $f"
  done
  [ -d "$dir.claude/agents" ] || note "no .claude/agents (single-agent boilerplate?)"

  # CONVENTIONS.md §3 — every cited requirement ID is defined.
  if [ -f "$dir/spec/requirements.md" ]; then
    defined=$(grep -oE '^\| REQ-[A-Z0-9]+-[0-9]+' "$dir/spec/requirements.md" | sed 's/^| //' | sort -u)
    used=$(grep -rhoE 'REQ-[A-Z0-9]+-[0-9]+' "$dir" \
             --include='*.md' --include='*.csv' --include='*.yaml' --include='*.json' | sort -u)
    dangling=$(comm -13 <(echo "$defined") <(echo "$used"))
    if [ -n "$dangling" ]; then
      bad "requirement IDs cited but not defined:"; echo "$dangling" | sed 's/^/    /'
    else
      note "requirement IDs: $(echo "$defined" | wc -l | tr -d ' ') defined, none dangling"
    fi
    # Every requirement must carry a status.
    missing_status=$(grep -cE '^\| REQ-[A-Z0-9]+-[0-9]+ \| (MUST|SHOULD|OPT) \|' "$dir/spec/requirements.md")
    total=$(echo "$defined" | wc -l | tr -d ' ')
    [ "$missing_status" -eq "$total" ] || bad "some requirements lack a MUST/SHOULD/OPT status"
  fi

  # The traceability matrix is generated, so it must still match the register.
  if [ -f "$dir/spec/traceability.csv" ] && [ -f scripts/gen-traceability.py ]; then
    tmp=$(mktemp -d)
    cp "$dir/spec/traceability.csv" "$tmp/before.csv"
    ( cd "$dir" && python3 "$OLDPWD/scripts/gen-traceability.py" >/dev/null 2>&1 ) || true
    if diff -q "$tmp/before.csv" "$dir/spec/traceability.csv" >/dev/null 2>&1; then
      note "traceability matrix is in sync with the register"
    else
      bad "traceability.csv is stale — regenerate with scripts/gen-traceability.py"
      cp "$tmp/before.csv" "$dir/spec/traceability.csv"
    fi
    rm -rf "$tmp"
  fi

  # CONVENTIONS.md §5 — ownership before parallelism.
  if [ -f "$dir/contracts/ownership.md" ]; then
    for a in $(grep -oE '\b[AC][0-9]{2}\b|\bS[12]\b|\bC[12]\b' "$dir/contracts/ownership.md" | sort -u); do
      ls "$dir/.claude/agents/" 2>/dev/null | grep -q "^${a}-" \
        || bad "ownership map names $a but .claude/agents/${a}-*.md is missing"
    done
    note "ownership map present, named agents resolve"
  fi

  # Internal document links must resolve. Paths under build/ are per-build
  # working state and are expected to be absent -- that is why every reference
  # to one must carry its build/ prefix.
  while read -r p; do
    case "$p" in build/*) continue ;; esac
    [ -e "$dir$p" ] || bad "broken internal reference: $p"
  # The lookbehind keeps this from matching a path fragment inside a longer path
  # (packages/contracts/... is the generated app's package, not this folder) or
  # inside a URL (a JSON Schema $id is not a file reference).
  done < <(grep -rhoP '(?<![\w/.-])(build|spec|contracts|gates|prompts|compliance|versions|normalizers)/[A-Za-z0-9._/-]+\.(md|csv|json|yaml)' \
             "$dir" --include='*.md' 2>/dev/null | sort -u)

  # CONVENTIONS.md §4 — no versions from memory.
  if [ -f "$dir/versions/manifest.json" ]; then
    python3 - "$dir/versions/manifest.json" <<'PY'
import json,sys
m=json.load(open(sys.argv[1])); missing=[]
def walk(node,path):
    if isinstance(node,dict):
        if "latestStable" in node:
            for k in ("source","checkedAt"):
                if k not in node: missing.append(f"{path}.{k}")
        else:
            for k,v in node.items(): walk(v,f"{path}.{k}")
for k in ("platform","npm","crates","pypi"): walk(m.get(k,{}),k)
print("  FAIL: manifest entries missing source/checkedAt: "+", ".join(missing[:8]) if missing
      else "  version manifest: every entry carries source and checkedAt")
sys.exit(1 if missing else 0)
PY
    [ $? -eq 0 ] || fail=1
  fi
done

printf '\n'
if [ "$fail" -eq 0 ]; then echo "All boilerplates conform to CONVENTIONS.md."; else echo "Violations found."; fi
exit "$fail"
