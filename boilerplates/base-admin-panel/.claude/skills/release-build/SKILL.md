---
name: release-build
description: Closes a build as A22 — derives the semver bump level from the change set and records the reason, bumps VERSION and every version field, writes the Keep a Changelog entry citing REQ IDs, refreshes README.md, SECURITY.md (CVD policy and CRA reporting posture) and TODO.md as live status, commits with the gate outcomes and bump reason in the message, and pushes with backoff on network failure only. Load at gate G8, or when asked to "cut the release", "bump the version", "update the changelog", "commit and push the build", "is this a release candidate" or "what bump level is this".
---

# Release Build

**This procedure is A22's and nobody else's.** `CHANGELOG.md`, `README.md`,
`SECURITY.md`, `TODO.md`, `VERSION` and every `version` field belong to A22 in
`contracts/ownership.md` — "No other agent edits these, ever". If you are not A22
you do not touch them; you hand A22 the facts. REQ-REL-01 … REQ-REL-08. Entry
condition: G6 and G7 both passed.

## 1. Derive the bump level from the change set — and record why

REQ-REL-02. The level is derived, not chosen by feel, and the derivation is written
down where the next build can read it.

| The change set contains | Level | Because |
|---|---|---|
| A breaking contract change (rename, removal, optional→required, retype, semantic change), or a removed capability | **major** | a consumer must change to keep working |
| A new capability, a newly-satisfied `REQ`, a new `/api/v1` operation, an additive contract member | **minor** | consumers keep working; the surface grew |
| A fix, a doc change, a test, the remediation of a gate finding | **patch** | no surface change |

```bash
git log --oneline --stat "v$(cat VERSION)"..HEAD
grep -l 'Kind: breaking' build/ccr/*.md 2>/dev/null   # any hit ⇒ major
```

Take the **highest** level any single change earns; mixed sets do not average. Write
the reason as one line naming the change, not the level: "major — `Session.tenantId`
optional→required under CCR-004" (REQ-REL-08).

**When this fails:** two levels look defensible. Ask which consumer breaks — if any
must change, major; if none must but the surface grew, minor; otherwise patch. A
breaking change shipped as a minor is a build incident, and the contract detector
already flagged it at G3.

## 2. Bump VERSION and every version field

```bash
new=1.4.0; echo "$new" > VERSION
grep -rln '"version":' package.json apps/*/package.json packages/*/package.json services/*/package.json
grep -rn '^version' agents/collector/Cargo.toml
grep -rn 'APP_VERSION\|NEXT_PUBLIC_APP_VERSION' .env.example compose*.yml
# after editing: nothing may still carry the old number
git grep -nE '"version": *"[0-9]+\.[0-9]+\.[0-9]+"' | grep -v "\"$new\"" && echo "VERSION FIELD DRIFT"
```

One version, everywhere: a field left behind makes the running app lie about itself
in the footer, in the API's `info.version` and in the SBOM.

## 3. CHANGELOG.md (REQ-REL-03)

Keep a Changelog form, every entry citing the REQ IDs it affects, so a reader can
trace the change back to the requirement that motivated it.

```markdown
## [1.4.0] — 2026-09-21

### Added
- Read/view logging on every entity detail view (REQ-AUD-02, REQ-TST-08).
- Grid preference round-trip persisted per user (REQ-GRD-08).

### Fixed
- Surface budget exceeded on the tablet console at 834px (REQ-UI-10, G6/C1-design-r2).

### Security
- `@types/node` pinned to the Node LTS major (REQ-VER-05, VER-TRAP-001).
```

Only sections with content — an empty `### Added` is noise. A remediated gate
finding cites the verdict file that raised it, as in `### Fixed` above.

## 4. README.md (REQ-REL-04)

Update what the thing **now is** and how to run it: resolved app name, entity list,
the integrations actually wired, the compose commands, required env vars from
`packages/config`, the first-run credentials story. Delete what the build removed —
a stale README is a defect, not cosmetic.

## 5. SECURITY.md (REQ-REL-05)

Four things, all current:

1. **Supported versions** — the table, the support period, the end-of-support date
   (REQ-CRA-08).
2. **CVD policy** — how to report, the single point of contact, acknowledgement and
   triage SLAs, the disclosure window, where advisories are published (REQ-CRA-04,
   REQ-CRA-05).
3. **CRA reporting posture** — both dates, plainly: Article 14 reporting obligations
   have been **in force since 11 September 2026** (actively exploited vulnerabilities
   and severe incidents — 24-hour early warning, 72-hour notification, 14-day/1-month
   final report, to ENISA and the national CSIRT), and **full CRA application, CE
   marking and Annex I conformity included, lands 11 December 2027**. Link
   `compliance/cra/reporting-runbook.md` (REQ-CRA-06). The reporting duty is live
   today; the CE-marking duty is not.
4. **Security updates** — separable from feature updates, and signed (REQ-CRA-07).

Never write a conformity claim here: `compliance/README.md` sets the posture —
conformity is determined by a notified body or authority, never by this repo.

## 6. TODO.md as live status (REQ-REL-06)

Not a wish list. Four states, a REQ ID on every line, gate state where one applies.

```markdown
# TODO — status at 1.4.0 (2026-09-21)

## Done
- [x] Read/view logging on detail views — REQ-AUD-02 — G5 ✓, G6 ✓, G7 ✓

## In progress
- [ ] Service-worker update prompt — REQ-PWA-05 — A09 — G4 self-test red

## Planned
- [ ] Collector mTLS rotation — REQ-OBS-02 — A15 — after the 1.5 contract minor

## Blocked
- [ ] SSO metadata refresh — REQ-AUT-09 — on the tenant's IdP contact; escalation
      in build/gates/escalations/sso-metadata.md
```

A line without a REQ ID does not belong in this file. A `MUST` not in Done means
there is no release candidate (REQ-REL-07).

## 7. Commit (REQ-REL-01, REQ-REL-08)

The message records the gate outcomes and the bump reason — both, every time.

```
release: 1.4.0 — read/view logging and grid preference persistence

Bump: minor — new capability: read/view logging on entity detail views
      (REQ-AUD-02); no contract member changed, no consumer must change.
Gates:
  G5 integration     pass  (A23, A21 — 42 screenshots, budgets met)
  G6 design/function pass  (C1 design r2, C1 function r1, C2 design r1, C2 function r2)
  G7 security        pass  (S1 r1, S2 r2, A19 clean: SBOM, 0 critical, telemetry asserted)
  G8 release candidate     human accepted 2026-09-21
REQ: REQ-AUD-02, REQ-AUT-07, REQ-GRD-08, REQ-TST-08, REQ-UI-10, REQ-VER-05
Waivers: none (build/waivers.md empty; no MUST waived — REQ-REL-07)
```

Write it to `build/commit-message.txt`, then
`git add -A && git commit -F build/commit-message.txt`.

## 8. Push (REQ-REL-01)

Work left only in a container is lost work.

```bash
branch=$(git rev-parse --abbrev-ref HEAD)
for delay in 2 4 8 16 stop; do
  git push -u origin "$branch" && break
  [ "$delay" = stop ] && { echo "PUSH FAILED after 4 retries — report, do not rewrite history"; exit 1; }
  echo "push failed; retrying in ${delay}s"; sleep "$delay"
done
```

**Retry only on network failure** — timeout, reset connection, DNS failure, a 5xx
from the remote. A rejected push is **not** a network failure: a non-fast-forward,
a protected-branch refusal, a hook rejection or an auth failure is answered by
reading the message, not by retrying and never by `--force`. Never push to the
default branch directly; branch first.

## 9. Is it a release candidate? (REQ-REL-07)

All of these, or the answer is no. There is no partial RC.

- [ ] Every `MUST` green. A `MUST` is never waived; only a `SHOULD` may be, with its
      entry in `build/waivers.md` citing the intake answer.
- [ ] C1 and C2 each approved **both** dimensions — four verdicts in `build/gates/G6/`, all `blocking: false` (REQ-GAT-01).
- [ ] S1 and S2 both approved independently, plus A19's report clean (REQ-GAT-02).
- [ ] Docs current: a help topic per shipped feature, charts regenerated from the real code, compliance set from repository state (REQ-CRA-10).
- [ ] `VERSION`, `CHANGELOG.md`, `README.md`, `SECURITY.md` and `TODO.md` all updated in **this** commit.

```bash
ls build/gates/G6/*.json | wc -l     # expect 4
jq -s '[.[]|select(.blocking == true)]|length' build/gates/G{6,7}/*.json   # expect 0
```

**When this fails:** one box is red and the work looks finished. It is not a release
candidate and A22 does not declare one — name the red box, name the owning agent
from `contracts/ownership.md`, and hand it back to the orchestrator.
