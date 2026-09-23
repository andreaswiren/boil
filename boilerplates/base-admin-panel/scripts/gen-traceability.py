#!/usr/bin/env python3
"""Generate spec/traceability.csv from spec/requirements.md.

The matrix is generated, never hand-edited, so it cannot drift from the
register (CONVENTIONS.md §3). Run from a boilerplate directory:

    python3 ../../scripts/gen-traceability.py

The generator is generic. The ownership mapping lives in the boilerplate at
spec/traceability-map.json, because a boilerplate must work when it is the only
thing you have (CONVENTIONS.md §1) and because two boilerplates have different
requirement domains and different agent ids.

Map shape:

    {
      "domain":     { "FND": ["A01", "env-schema", "G4"], ... },
      "override":   { "REQ-FND-06": ["A20", "manifest.json", "G2"], ... },
      "spec":       { "FND": "spec/baseline.md", ... },
      "spec_by_id": { "REQ-UI-04": "spec/theming.md", ... }
    }

`domain` is the default (owner, contract member, gate) per requirement domain.
`override` is per-ID, for requirements whose owner genuinely differs from their
domain's — not a place to paper over a domain that was named wrongly.
"""
import csv
import collections
import json
import re
import sys
from pathlib import Path

# The ID prefix is not hardcoded. CONVENTIONS.md section 3 requires IDs that are
# stable and never renumbered; it does not require one spelling, and a
# boilerplate that arrives with a load-bearing prefix of its own keeps it rather
# than having every citation rewritten to satisfy this script.
REQ_ROW = re.compile(r'^\| ([A-Z][A-Z0-9]*-([A-Z0-9]+)-\d+) \| (MUST|SHOULD|OPT) \| (.+?) \|\s*$')
HEADER = ["req_id", "domain", "status", "owner_agent", "contract_member", "gate",
          "spec_document", "requirement"]


def die(msg: str) -> int:
    print(msg, file=sys.stderr)
    return 1


def main() -> int:
    src = Path("spec/requirements.md")
    mapfile = Path("spec/traceability-map.json")
    out = Path("spec/traceability.csv")

    if not src.exists():
        return die("run me from a boilerplate directory (no spec/requirements.md here)")
    if not mapfile.exists():
        return die(f"missing {mapfile} — the generator is generic; the mapping is the "
                   "boilerplate's. See this script's docstring for its shape.")

    m = json.loads(mapfile.read_text())
    domain = {k: tuple(v) for k, v in m.get("domain", {}).items()}
    override = {k: tuple(v) for k, v in m.get("override", {}).items()}
    spec_by_domain = m.get("spec", {})
    spec_by_id = m.get("spec_by_id", {})

    rows, unknown = [], set()
    for line in src.read_text().splitlines():
        hit = REQ_ROW.match(line)
        if not hit:
            continue
        rid, dom, status, text = hit.groups()
        if dom not in domain:
            unknown.add(dom)
            continue
        rows.append((rid, dom, status, text))

    if unknown:
        return die(f"unmapped requirement domains: {sorted(unknown)} — add them to "
                   f"{mapfile}'s \"domain\" table. Leaving them out would silently "
                   "produce requirements with no owner and no gate.")
    if not rows:
        return die("no requirement rows matched — check the register's table format")

    stale = sorted(set(override) - {r[0] for r in rows})
    if stale:
        print(f"note: {len(stale)} override(s) name requirements that no longer exist: "
              f"{', '.join(stale[:5])}{' …' if len(stale) > 5 else ''}", file=sys.stderr)

    with out.open("w", newline="\n") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(HEADER)
        for rid, dom, status, text in rows:
            owner, member, gate = override.get(rid, domain[dom])
            w.writerow([rid, dom, status, owner, member, gate,
                        spec_by_id.get(rid, spec_by_domain.get(dom, "")),
                        text.replace("**", "")])

    resolved = [override.get(r[0], domain[r[1]]) for r in rows]
    count = lambda i: dict(sorted(collections.Counter(x[i] for x in resolved).items()))
    print(f"{len(rows)} requirements, {len(set(r[1] for r in rows))} domains -> {out}")
    print("gates:", count(2))
    print("owners:", count(0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
