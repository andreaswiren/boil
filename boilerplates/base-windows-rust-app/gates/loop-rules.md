# Loop Rules

What happens after a gate fails. `README.md` gives the short form; this is the
binding version. Requirements: REQ-GAT-05, REQ-GAT-07, REQ-CTR-04.

A failed gate is a routing problem, not a repair problem. The reviewer names a
defect, somebody else fixes it, the same reviewer checks it — at most three
times.

## 1. Routing: the owner, never the nearest

Every finding carries an `owner` (`verdict-schema.md`). The orchestrator resolves
it from the finding's evidence path against `contracts/ownership.md`
(`grep -n "crates/update" contracts/ownership.md`) and dispatches to that agent.

- The owner of the **path in the evidence**, not the author of the last commit
  and not the agent that is already awake.
- A finding whose evidence spans two owners is **split by the orchestrator** into
  one finding per owner. It is never handed to one agent to coordinate.
- Registrations route by **state transition**, not by which file the symptom
  appeared in: a service that comes back after an update is B08's even when the
  finding was read in `crates/update`, and a file left in the install directory
  after uninstall is B07's even when B09 wrote it there.
- A `windows` call found outside `crates/ffi` routes **twice**: the offending
  crate's owner removes it, and B01 publishes the wrapper it needed
  (`contracts/README.md` §6).
- Version and changelog files are B17's, always. No other agent edits them.
- A path no row matches, or two rows match, is a bug in `contracts/ownership.md`.
  The orchestrator amends the map, logs the amendment, then dispatches. Agents
  never negotiate ownership between themselves.

## 2. The fix is bounded by the finding

The owner fixes **only what the finding names**, and reports with the evidence the
reviewer asked for.

- A fix that grows into a refactor stops being a fix. The owner reports what it
  found, the orchestrator opens a separate task, and the round closes on the
  narrow fix.
- A finding the owner believes is wrong is answered with
  `ownerResponse: "disputed"`, a reason and evidence — not a silent no-op and not
  a different change. A dispute is a legitimate move; silence is not.
- A finding the owner believes is a requirement problem is a CCR or a waiver
  request (`ownerResponse: "waiver-requested"`), decided by the orchestrator and
  the human (REQ-CTR-02, REQ-CTR-03). A `MUST` is never waived, and all but one
  requirement in this register is a `MUST`.
- The owner never edits a verdict file. Verdicts are reviewer-owned.
- A fix that needs a new contract member is a CCR first and a fix second. Editing
  `crates/contracts` to make your own crate compile is an ownership violation,
  not a fix (`contracts/README.md` §3).

## 3. Re-review: same reviewer, round N+1, same scope

- The reviewer that raised the finding re-reviews it — not the other critic, not
  the orchestrator, not the owner — carrying `carriedFrom` forward so the round
  count survives a rewording.
- **A reviewer may not widen scope between rounds.** `scope.paths` and
  `scope.reqIds` are set at round 1 and copied verbatim. New territory noticed in
  round 2 is a round-1 finding in the **next** cycle, not an extra condition on
  this one. Widening is how a two-round loop becomes permanent.
- A new defect the fix itself created is in scope, as a new finding id at the
  current round with `carriedFrom` set to that round.
- H6 and H7 are independent. An H7 fix re-opens H6 only if it changed a surface
  D1 or D2 voted on, and the orchestrator makes and records that call.
- Evidence is re-collected, never reused. A round-2 verdict citing a round-1
  screenshot or a round-1 ACL dump has not re-reviewed anything.

## 4. The bounded loop (REQ-GAT-05)

Rounds are counted **per defect**, keyed on REQ ID plus evidence path — not on
the reviewer's wording, which changes, and not per gate. Round 1: finding raised,
owner fixes, same reviewer re-reviews. Round 2: the same. Round 3 failing on the
same defect: **stop.** There is no fourth round.

On the third failure the reviewer sets `decision.escalate: true` and writes
`decision.disagreement`, and the orchestrator writes
`build/gates/escalations/<defect-slug>.md` stating plainly:

- **what the reviewer wants**, with the measurement or the reproduction,
- **what the owner did** in each of the three rounds,
- **why they disagree** — the actual point of difference — and **what each would
  need** to change its mind.

The human rules. **The orchestrator does not break the tie** and does not pick the
cheaper side. The ruling is recorded and the gate closes on it — including a
ruling of "ship as is", which becomes a documented accepted risk rather than a
silent pass. The failure mode to watch for is a defect that mutates between
rounds so that nothing looks like a repeat, which is why the count keys on REQ ID
plus evidence path.

## 5. No self-approval (REQ-GAT-07)

The agent that wrote the code never votes on it, enforced mechanically rather
than by trust:

- The orchestrator **never assigns a build task to D1, D2, T1 or T2**. Those IDs
  appear in no wave in `spec/agents.md` and own nothing in
  `contracts/ownership.md`. A dispatch handing a gate agent a fix is an
  orchestrator defect, and the gate agent refuses it.
- Gate agents hold `Write` to reach `build/gates/` and nowhere else. A gate-agent
  diff touching product code invalidates its verdict for that round.
- A build agent's report is a claim. Claims are what reviewers test.
- At H7, T1 and T2 launch in the same message with no shared context
  (REQ-GAT-02). A finding both raise is a stronger signal, not a duplicate to
  suppress.

## 6. The record

```
build/gates/H7/T2-code-r1.json         round 1 verdict
build/gates/H7/T2-code-r2.json         round 2, same scope, carriedFrom set
build/gates/escalations/updater-unsigned-manifest.md
```

Nothing is overwritten. Round 2 is a new file; round 1 stays as written, wrong
predictions included. A build whose gate history cannot be reconstructed has no
evidence, and evidence is the point of the ladder. `build/` is gitignored working
state, so what survives is the commit, the changelog, and the verdict outcomes
B17 carries into the release record.

## 7. Worked example — three rounds to escalation

**Round 1.** T2 raises `F-002` against REQ-UPD-02, `critical`. Evidence:
`crates/update/src/apply.rs` L204-L217 — the staged artefact's SHA-256 is compared
to the value in the manifest, then `self_replace::self_replace(&staged)` runs. The
manifest itself is never verified, so an attacker who can answer the update
request supplies both the artefact and the hash it is checked against. Owner
resolved from `crates/update/**` → **B09**. Fix direction: verify the manifest's
detached signature against the embedded public key (REQ-UPD-03) **before** the
artefact is hashed, and refuse on any verification error. B09 adds
`verify_manifest()` and reports `"fixed"`.

**Round 2.** T2 re-reviews the same scope. `verify_manifest()` exists, but the key
comes from `GET /updates/pubkey.pem` at run time (`fetch.rs` L88) — so the trust
anchor is supplied by the same server as the payload, which is REQ-UPD-03 unmet
and leaves REQ-UPD-02 unmet in substance. `F-002` carries `carriedFrom: 1`. B09
responds `"disputed"`: a fetched key is needed for key rotation.

The orchestrator does not rule on it. Rotation is a release concern belonging to
B10 and B17, and a rotation mechanism that removes the trust anchor is not a
rotation mechanism. B09 is told to embed the key as the finding named.

**Round 3.** B09 embeds the key, and adds `allow_unsigned` — set when the manifest
carries no `signature` field — so that the previous release's unsigned manifests
still upgrade (REQ-TST-02). `F-002` fails a third time: an attacker omits the
field and the check is skipped, which is REQ-UPD-02 unmet through a different
door. T2 sets `escalate: true`; the orchestrator writes
`build/gates/escalations/updater-unsigned-manifest.md`:

- **Reviewer (T2) wants:** no code path in which an artefact is swapped without a
  signature verified against the embedded key. An absent signature is a hard
  refusal, not a compatibility branch.
- **Owner (B09) did:** round 1 added hash-then-swap verification; round 2 fetched
  the key and disputed; round 3 embedded the key but added `allow_unsigned`.
- **Why they disagree:** B09 holds that refusing unsigned manifests breaks the
  upgrade path from the previous released version, which H5 requires. T2 holds
  that an updater accepting an unsigned manifest is a remote code execution
  channel and that the upgrade path is a release problem, not an updater problem.
- **Each would change its mind if:** T2 — the historical manifests cannot be
  re-signed **and** the unsigned path is restricted to one pinned version with a
  known hash compiled into the binary. B09 — a re-signed manifest is published
  for the previous release, which removes the need for the branch.

No fourth round runs. The human rules — re-sign the historical manifests, or
accept a single pinned-hash exception with the reason recorded. The ruling goes in
the escalation file, the gate closes on it, and B17 carries it into the release
record.
