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
  # The roster is the source of truth for agent ids, so this works for any
  # naming scheme. Deriving the ids from a hardcoded pattern silently passed a
  # boilerplate whose agents are B01/D1/T1 rather than A01/C1/S1.
  if [ -f "$dir/spec/agents.md" ] && [ -d "$dir/.claude/agents" ]; then
    ids=$(grep -oE '^\| *`?[A-Z]{1,2}[0-9]{1,2}`? *\|' "$dir/spec/agents.md" \
            | tr -d '|` ' | sort -u)
    if [ -z "$ids" ]; then
      bad "spec/agents.md has no recognisable agent-id rows — the roster is the source of truth for ids"
    else
      missing=0
      for a in $ids; do
        ls "$dir/.claude/agents/" 2>/dev/null | grep -q "^${a}-" \
          || { bad "roster names $a but .claude/agents/${a}-*.md is missing"; missing=1; }
      done
      [ "$missing" -eq 0 ] && note "roster: $(echo "$ids" | wc -w | tr -d ' ') agents, every one has a definition"
    fi
  fi
  if [ -f "$dir/contracts/ownership.md" ] && [ -f "$dir/spec/agents.md" ] && [ -n "${ids:-}" ]; then
    # An agent that owns a path but is not in the roster is the inverse error.
    # Only tokens sharing a roster prefix are considered: gate ids (G3, H3) fit
    # a generic letter+digit pattern and are not agents.
    prefixes=$(echo "$ids" | sed 's/[0-9].*//' | sort -u | tr -d '\n' | sed 's/./&|/g; s/|$//')
    for a in $(grep -oE "\b(${prefixes})[0-9]{1,2}\b" "$dir/contracts/ownership.md" | sort -u); do
      echo "$ids" | grep -qx "$a" \
        || bad "ownership map names $a, which is not in spec/agents.md"
    done
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
