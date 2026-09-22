#!/usr/bin/env bash
# Repo-level conformance: runs every boilerplate's own check, then the checks
# that only make sense from outside one.
#
# The per-boilerplate checks live in boilerplates/<name>/scripts/ because a
# boilerplate has to work cloned alone (CONVENTIONS.md §1). A checker that only
# exists at the repository root is a checker the person who cloned one folder
# cannot run, and six agent briefs used to tell them to run it.
#
#   ./scripts/check-conventions.sh
set -uo pipefail

fail=0
bad() { printf '  FAIL: %s\n' "$*"; fail=1; }

for dir in boilerplates/*/; do
  name=$(basename "$dir")
  if [ -x "$dir/scripts/check-boilerplate.sh" ]; then
    "$dir/scripts/check-boilerplate.sh" || fail=1
  else
    printf '\n== %s ==\n' "$name"
    bad "no scripts/check-boilerplate.sh — the boilerplate cannot verify itself when cloned alone"
  fi
done

printf '\n== repository ==\n'

# A boilerplate must not instruct anyone to run something outside itself. This is
# the check that would have caught six agent briefs saying "run
# ./scripts/check-conventions.sh from the repository root", which is a file that
# is not in the folder those briefs ship in.
for dir in boilerplates/*/; do
  name=$(basename "$dir")
  # Test that the cited script EXISTS, rather than that it is one of a hardcoded
  # pair. The allowlist version failed a boilerplate for citing scripts/harden.sh
  # -- which it ships. The rule is "cites a file it does not ship", so check that.
  # The lookbehind keeps this from matching a scripts/ fragment inside a longer
  # path: packages/theme/scripts/generate-presets.ts is the GENERATED app's
  # script, not this folder's. Same trap the broken-reference check already hit.
  for sref in $(grep -rhoP '(?<![\w/.-])(\./)?scripts/[A-Za-z0-9_-]+\.(sh|py|ts)' "$dir" \
                  --include='*.md' --include='*.json' 2>/dev/null \
                | sed 's|^\./||' | sort -u); do
    [ -f "$dir/$sref" ] || bad "$name cites $sref, which it does not ship"
  done
done

# Hard rule 1: no boilerplate depends on a sibling. Naming one is the dependency
# -- the reader follows the name. This is a repo-level check because only from
# here are the sibling names known. It catches what path resolution cannot: a
# ../ written as if from the boilerplate root resolves to a path that is inside
# the folder and simply does not exist, so a self-containment check based on
# resolving paths passes it while the reference is still a sibling dependency.
for dir in boilerplates/*/; do
  name=$(basename "$dir")
  for other in boilerplates/*/; do
    o=$(basename "$other")
    [ "$o" = "$name" ] && continue
    # A full https:// URL naming a sibling resolves for anyone from anywhere, so
    # it is a citation, not a dependency. A path is the dependency rule 1 forbids.
    hits=$(grep -rn "$o" "$dir" --include='*.md' --include='*.json' --include='*.yaml' 2>/dev/null \
             | grep -v 'https\?://' || true)
    if [ -n "$hits" ]; then
      bad "$name names the sibling boilerplate $o:"
      printf '%s\n' "$hits" | head -4 | sed 's/^/    /'
    fi
  done
done

# Every boilerplate in the tree must be listed in the README table, or nobody
# finds it.
for dir in boilerplates/*/; do
  name=$(basename "$dir")
  grep -q "$name" README.md || bad "$name is not listed in the repository README"
done

# The two shipped copies of the generator must not drift from the repo's.
for dir in boilerplates/*/; do
  name=$(basename "$dir")
  if [ -f "$dir/scripts/gen-traceability.py" ] && [ -f scripts/gen-traceability.py ]; then
    diff -q scripts/gen-traceability.py "$dir/scripts/gen-traceability.py" >/dev/null \
      || bad "$name/scripts/gen-traceability.py has drifted from scripts/gen-traceability.py"
  fi
done

[ "$fail" -eq 0 ] && printf '  repository-level checks pass\n'

printf '\n'
if [ "$fail" -eq 0 ]; then echo "All boilerplates conform to CONVENTIONS.md."; else echo "Violations found."; fi
exit "$fail"
