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
  hits=$(grep -rn '\(\./\)\?scripts/[a-z-]*\.\(sh\|py\)' "$dir" \
           --include='*.md' --include='*.json' 2>/dev/null \
         | grep -v "$name/scripts/" \
         | grep -vE '`?(\./)?scripts/(check-boilerplate\.sh|gen-traceability\.py)`?' || true)
  if [ -n "$hits" ]; then
    bad "$name cites a script it does not ship:"
    printf '%s\n' "$hits" | sed 's/^/    /'
  fi
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
