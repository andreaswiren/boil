#!/usr/bin/env bash
# Verifies THIS boilerplate against the conventions it ships with.
#
# It lives inside the boilerplate on purpose. An agent handed this folder alone
# -- which is the whole point of the folder -- cannot run a script in a parent
# directory that was not cloned. Every check here reads only paths under $root.
#
#   ./scripts/check-boilerplate.sh
#
# Exits non-zero on any violation.
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
fail=0
note() { printf '  %s\n' "$*"; }
bad()  { printf '  FAIL: %s\n' "$*"; fail=1; }

printf '\n== %s ==\n' "$(basename "$root")"


# CONVENTIONS.md §1 — self-containment. A boilerplate must work cloned alone.
#
# Every relative path containing ../ is resolved against the directory of the
# file that holds it, and fails only if the result lands outside this folder.
# Pattern-matching on "../.." missed the case hard rule 1 names explicitly: a
# single ../ to a sibling boilerplate. Resolving also avoids failing the
# legitimate ones -- contracts/../spec/x.md stays inside, and so does a Rust
# include_str! or an ellipsis in a URL.
python3 - "$root" <<'PYSELF'
import os,re,sys
root=os.path.realpath(sys.argv[1])
pat=re.compile(r'(?:\.\./)+[A-Za-z0-9._/-]*')
bad=[]
for r,_,fs in os.walk(root):
    if os.sep+'.git' in r or os.sep+'resources' in r: continue
    for n in fs:
        if not n.endswith(('.md','.json','.yaml','.yml')): continue
        p=os.path.join(r,n)
        for i,line in enumerate(open(p,encoding='utf-8',errors='replace'),1):
            for m in pat.finditer(line):
                target=os.path.realpath(os.path.join(r,m.group(0)))
                if not (target==root or target.startswith(root+os.sep)):
                    bad.append(f'{os.path.relpath(p,root)}:{i}: {m.group(0)}')
if bad:
    for b in bad[:8]: print('  FAIL: path escapes the boilerplate folder: '+b)
else:
    print('  self-contained: no path resolves outside this folder')
sys.exit(1 if bad else 0)
PYSELF
[ $? -eq 0 ] || fail=1
if find "$root" -type l 2>/dev/null | while read -r l; do readlink "$l"; done | grep -qF '../'; then
  bad "symlink points outside the boilerplate"
fi

# CONVENTIONS.md §2 — required structure.
for f in README.md CLAUDE.md AGENTS.md spec/requirements.md prompts/00-master-orchestrator.md; do
  [ -f "$root/$f" ] || bad "missing required file: $f"
done
[ -d "$root/.claude/agents" ] || note "no .claude/agents (single-agent boilerplate?)"

# The two entry points must be byte-identical. Runtimes disagree about which one
# wins, and some ignore the loser outright -- Muse Code 1.3.0 gives AGENTS.md
# precedence and prints "rules file at CLAUDE.md is ignored this session". A
# pointer file is therefore the one thing neither file may be: on the runtime
# that ignores its target, the agent gets a note telling it to read a file the
# tool has just refused to read, and every hard rule, the map and the gate
# ladder silently fail to load.
if [ -f "$root/CLAUDE.md" ] && [ -f "$root/AGENTS.md" ]; then
  if diff -q "$root/CLAUDE.md" "$root/AGENTS.md" >/dev/null 2>&1; then
    note "entry points: CLAUDE.md and AGENTS.md are identical"
  else
    bad "CLAUDE.md and AGENTS.md differ -- a runtime that reads only one would miss what is in the other"
    diff "$root/CLAUDE.md" "$root/AGENTS.md" | head -12 | sed 's/^/    /'
  fi
fi

# A slash command named in a document must resolve to a skill the folder ships.
# CLAUDE.md told the agent to run /build-orchestrate in a boilerplate whose
# .claude/skills/ was empty, so the documented entry point resolved to nothing
# in every runtime, Claude Code included.
#
# Only a whole line that is nothing but the command counts -- that is how a
# fenced invocation block reads, and it is the shape that tells an agent to run
# something. A backticked mention in prose is documentation about syntax and may
# legitimately be a placeholder, so matching those produces false failures.
cited=$(grep -rhoE '^/[a-z][a-z0-9-]{3,}$' "$root" --include='*.md' --exclude-dir=resources 2>/dev/null \
          | tr -d '/' | sort -u)
if [ -n "$cited" ]; then
  missing=0
  for cmd in $cited; do
    [ -f "$root/.claude/skills/$cmd/SKILL.md" ] \
      || { bad "/$cmd is cited as a command but .claude/skills/$cmd/SKILL.md is missing"; missing=1; }
  done
  [ "$missing" -eq 0 ] && note "slash commands: $(echo "$cited" | wc -w | tr -d ' ') cited, every one resolves to a skill"
fi
for d in "$root"/.claude/skills/*/; do
  [ -d "$d" ] || continue
  [ -f "$d/SKILL.md" ] || bad "skill $(basename "$d") has no SKILL.md"
done

# Stated counts must match the register and the roster. Every "N requirements"
# and "N-agent fleet" in a document is a number a human typed and nobody
# re-derived when the register grew, and it is read by an agent as fact. This
# check exists because the same defect was fixed by hand seven times in one
# session: 165 against 175, 215 and 272 against 337, 24 and 26 against 32, 19
# against 23, and "Thirteen expert agents" against sixteen.
if [ -f "$root/spec/requirements.md" ] && [ -d "$root/.claude/agents" ]; then
  python3 - "$root" <<'PYCOUNT'
import os,re,sys
d=sys.argv[1]
reqs=len(set(re.findall(r'^\| (REQ-[A-Z0-9]+-[0-9]+)',
      open(os.path.join(d,'spec','requirements.md'),encoding='utf-8').read(),re.M)))
agents=len([n for n in os.listdir(os.path.join(d,'.claude','agents')) if n.endswith('.md')])
bad=[]
for r,_,fs in os.walk(d):
    if os.sep+'.git' in r or os.sep+'resources' in r: continue
    for n in fs:
        if not n.endswith('.md'): continue
        p=os.path.join(r,n); rel=os.path.relpath(p,d)
        for line in open(p,encoding='utf-8',errors='replace').read().split('\n'):
            for m in re.finditer(r'(\d{2,4})\s+requirements?\b', line):
                if int(m.group(1))!=reqs:
                    bad.append(f'{rel}: "{m.group(0)}" but the register defines {reqs}')
            for m in re.finditer(r'(\d{1,3})[- ]agent (?:fleet|build fleet)\b', line):
                if int(m.group(1))!=agents:
                    bad.append(f'{rel}: "{m.group(0)}" but .claude/agents holds {agents}')
if bad:
    for b in sorted(set(bad))[:8]: print('  FAIL: stated count: '+b)
else:
    print(f'  stated counts agree with the register ({reqs} requirements, {agents} agents)')
sys.exit(1 if bad else 0)
PYCOUNT
  [ $? -eq 0 ] || fail=1
fi

# Vendored third-party resources carry an integrity pin, and our conventions do
# not apply to them. Without the pin the copy is a comment: a file edited in
# place still reads as "upstream at commit X" while being an undeclared fork,
# and every gate that measures against it is measuring against something else.
if [ -f "$root/resources/pin.json" ]; then
  python3 - "$root/resources" <<'PYPIN'
import hashlib,json,os,sys
d=sys.argv[1]
m=json.load(open(os.path.join(d,'pin.json')))
bad=[]
for rel,want in m.get('files',{}).items():
    p=os.path.join(d,'next-shadcn-admin-dashboard',rel)
    if not os.path.exists(p): bad.append(f'{rel}: missing'); continue
    if hashlib.sha256(open(p,'rb').read()).hexdigest()!=want:
        bad.append(f'{rel}: edited since it was pinned')
lic=os.path.join(d,m.get('upstream',{}).get('licenseFile',''))
if not os.path.exists(lic): bad.append('the upstream licence notice is missing, which the vendoring depends on')
if bad:
    for b in bad[:6]: print('  FAIL: vendored resource: '+b)
    if len(bad)>6: print(f'  FAIL: vendored resource: ... and {len(bad)-6} more')
else:
    print(f"  vendored resources intact ({m['fileCount']} files at {m['upstream']['commit'][:12]})")
sys.exit(1 if bad else 0)
PYPIN
  [ $? -eq 0 ] || fail=1
fi

# CONVENTIONS.md §3 — every cited requirement ID is defined.
if [ -f "$root/spec/requirements.md" ]; then
  defined=$(grep -oE '^\| REQ-[A-Z0-9]+-[0-9]+' "$root/spec/requirements.md" | sed 's/^| //' | sort -u)
  used=$(grep -rhoE 'REQ-[A-Z0-9]+-[0-9]+' "$root" \
           --include='*.md' --include='*.csv' --include='*.yaml' --include='*.json' --exclude-dir=resources | sort -u)
  dangling=$(comm -13 <(echo "$defined") <(echo "$used"))
  if [ -n "$dangling" ]; then
    bad "requirement IDs cited but not defined:"; echo "$dangling" | sed 's/^/    /'
  else
    note "requirement IDs: $(echo "$defined" | wc -l | tr -d ' ') defined, none dangling"
  fi
  # Every requirement must carry a status.
  missing_status=$(grep -cE '^\| REQ-[A-Z0-9]+-[0-9]+ \| (MUST|SHOULD|OPT) \|' "$root/spec/requirements.md")
  total=$(echo "$defined" | wc -l | tr -d ' ')
  [ "$missing_status" -eq "$total" ] || bad "some requirements lack a MUST/SHOULD/OPT status"
fi

# The traceability matrix is generated, so it must still match the register.
if [ -f "$root/spec/traceability.csv" ] && [ -f "$root/scripts/gen-traceability.py" ]; then
  tmp=$(mktemp -d)
  cp "$root/spec/traceability.csv" "$tmp/before.csv"
  ( cd "$root" && python3 scripts/gen-traceability.py >/dev/null 2>&1 ) || true
  if diff -q "$tmp/before.csv" "$root/spec/traceability.csv" >/dev/null 2>&1; then
    note "traceability matrix is in sync with the register"
  else
    bad "traceability.csv is stale — regenerate with scripts/gen-traceability.py"
    cp "$tmp/before.csv" "$root/spec/traceability.csv"
  fi
  rm -rf "$tmp"
fi

# CONVENTIONS.md §5 — ownership before parallelism.
# The roster is the source of truth for agent ids, so this works for any
# naming scheme. Deriving the ids from a hardcoded pattern silently passed a
# boilerplate whose agents are B01/D1/T1 rather than A01/C1/S1.
if [ -f "$root/spec/agents.md" ] && [ -d "$root/.claude/agents" ]; then
  ids=$(grep -oE '^\| *`?[A-Z]{1,2}[0-9]{1,2}`? *\|' "$root/spec/agents.md" \
          | tr -d '|` ' | sort -u)
  if [ -z "$ids" ]; then
    bad "spec/agents.md has no recognisable agent-id rows — the roster is the source of truth for ids"
  else
    missing=0
    for a in $ids; do
      ls "$root/.claude/agents/" 2>/dev/null | grep -q "^${a}-" \
        || { bad "roster names $a but .claude/agents/${a}-*.md is missing"; missing=1; }
    done
    [ "$missing" -eq 0 ] && note "roster: $(echo "$ids" | wc -w | tr -d ' ') agents, every one has a definition"
  fi
fi
if [ -f "$root/contracts/ownership.md" ] && [ -f "$root/spec/agents.md" ] && [ -n "${ids:-}" ]; then
  # An agent that owns a path but is not in the roster is the inverse error.
  # Only tokens sharing a roster prefix are considered: gate ids (G3, H3) fit
  # a generic letter+digit pattern and are not agents.
  prefixes=$(echo "$ids" | sed 's/[0-9].*//' | sort -u | tr -d '\n' | sed 's/./&|/g; s/|$//')
  for a in $(grep -oE "\b(${prefixes})[0-9]{1,2}\b" "$root/contracts/ownership.md" | sort -u); do
    echo "$ids" | grep -qx "$a" \
      || bad "ownership map names $a, which is not in spec/agents.md"
  done
fi

# Internal document links must resolve. Paths under build/ are per-build
# working state and are expected to be absent -- that is why every reference
# to one must carry its build/ prefix.
while read -r p; do
  case "$p" in build/*) continue ;; esac
  [ -e "$root/$p" ] || bad "broken internal reference: $p"
# The lookbehind keeps this from matching a path fragment inside a longer path
# (packages/contracts/... is the generated app's package, not this folder) or
# inside a URL (a JSON Schema $id is not a file reference).
done < <(grep -rhoP '(?<![\w/.-])(build|spec|contracts|gates|prompts|compliance|versions|normalizers)/[A-Za-z0-9._/-]+\.(md|csv|json|yaml)' \
           "$root" --include='*.md' --exclude-dir=resources 2>/dev/null | sort -u)

# CONVENTIONS.md §4 — no versions from memory.
if [ -f "$root/versions/manifest.json" ]; then
  python3 - "$root/versions/manifest.json" <<'PY'
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

  # The manifest being well-formed is not the same as the prose agreeing with
  # it. Every "`crate` X.Y.Z" written anywhere in the boilerplate must match
  # the validated entry, because a version drifts in a spec long before anyone
  # re-reads the manifest -- and an agent builds against the spec it was given.
  python3 - "$root" <<'PYVER'
import json,os,re,sys
d=sys.argv[1]
known={}
def walk(n,path=""):
  if isinstance(n,dict):
      if "latestStable" in n: known[n.get("name") or path.split(".")[-1]]=n["latestStable"]
      for k,v in n.items(): walk(v,f"{path}.{k}")
  elif isinstance(n,list):
      for v in n: walk(v,path)
walk(json.load(open(os.path.join(d,"versions","manifest.json"))))
pat=re.compile(r"`([a-z0-9@][a-z0-9@/_.-]{1,40})`\s+(\d+\.\d+(?:\.\d+)?)")
bad=[]
for r,_,fs in os.walk(d):
  if os.sep+".git" in r or os.sep+"resources" in r: continue
  for n in fs:
      if not n.endswith(".md"): continue
      p=os.path.join(r,n)
      for cr,ver in pat.findall(open(p,encoding="utf-8",errors="replace").read()):
          if cr in known and known[cr]!=ver:
              bad.append(f"{os.path.relpath(p,d)}: {cr} {ver} != manifest {known[cr]}")
if bad:
  for b in bad[:8]: print("  FAIL: version drift: "+b)
else:
  print(f"  prose versions agree with the manifest ({len(known)} validated entries)")
sys.exit(1 if bad else 0)
PYVER
  [ $? -eq 0 ] || fail=1

  # REQ-VER-06's failure is silent: a dependency raises its rust_version, the
  # workspace no longer builds on the pinned toolchain, and nobody decided it.
  # Where a manifest records an MSRV per entry, the highest one must be at or
  # below the pinned toolchain.
  python3 - "$root/versions/manifest.json" <<'PYMSRV'
import json,re,sys
m=json.load(open(sys.argv[1]))
def ver(s):
  return tuple(int(x) for x in re.findall(r"\d+", str(s))[:3]) if s else None
worst=(None,None)
def walk(n,name="?"):
  global worst
  if isinstance(n,dict):
      if "latestStable" in n and n.get("msrv") and ver(n["msrv"]):
          v=ver(n["msrv"])
          if worst[0] is None or v>worst[0]:
              worst=(v,f'{n.get("name",name)} {n["latestStable"]} needs {n["msrv"]}')
      for k,v in n.items(): walk(v,k)
  elif isinstance(n,list):
      for v in n: walk(v,name)
walk(m.get("crates",{}))
pin=ver(((m.get("toolchain") or {}).get("rust") or {}).get("pin"))
if worst[0] is None:
  print("  no per-entry MSRV recorded, nothing to check")
elif pin is None:
  print("  FAIL: entries record an MSRV but toolchain.rust.pin is absent")
  sys.exit(1)
elif worst[0] > pin:
  print(f"  FAIL: MSRV {'.'.join(map(str,worst[0]))} exceeds pinned toolchain {'.'.join(map(str,pin))}: {worst[1]}")
  sys.exit(1)
else:
  print(f"  MSRV floor {'.'.join(map(str,worst[0]))} fits the pinned toolchain {'.'.join(map(str,pin))}")
PYMSRV
  [ $? -eq 0 ] || fail=1
fi

printf '\n'
if [ "$fail" -eq 0 ]; then
  echo "$(basename "$root") conforms."
else
  echo "$(basename "$root"): violations found."
fi
exit "$fail"
