# Supply Chain

Owner: `B11 supply-chain`. Owned paths: `deny.toml`,
`security/supply-chain/**`, and the supply-chain workflow in
`.github/workflows/` (`contracts/ownership.md`; every other workflow is `B10`'s).

Requirements: REQ-SBM-01..08, REQ-FND-10, REQ-CRA-03, REQ-VER-01.

---

## 0. Why this is stricter in Rust than it looks

**Every dependency is compiled into the shipped binary.** There is no runtime
package manager on the user's machine, no separate `node_modules` to audit after
the fact, no dynamic library the operator can patch independently. The crate
graph at build time *is* the product.

So adding a dependency is a **shipping decision, not a development convenience**
(REQ-SBM-05). A crate added to save an afternoon is code the product carries for
its whole support period (REQ-CRA-08), signed by our certificate (REQ-REL-04),
and reported as ours when it has a vulnerability (REQ-CRA-06).

The other side of that is the leverage: because the graph is fixed at build time,
`cargo-auditable` 0.7.6 (`versions/manifest.json`) can embed the exact dependency
list **in the binary** (REQ-SBM-02). An `app.exe` found on a machine two years
from now can be audited with `cargo audit bin app.exe` without the release page,
the build server, or anyone remembering which release it came from. That is
exactly the evidence a CRA audit asks for, and it is why the embedded list is a
requirement rather than a nicety (`compliance/cra/obligations-matrix.md`).

## 1. Three passes, and they are not the same pass

| Pass | Question it answers | Mechanism | REQ |
|------|--------------------|-----------|-----|
| 1. Known-vulnerability | Has someone already published an advisory against what we ship? | Inventory + CycloneDX SBOM + advisory matching | REQ-SBM-01, REQ-SBM-02, REQ-SBM-03 |
| 2. First-party behaviour review | What does this dependency actually *do* in our build and in our process? | Human review against a fixed checklist, with mechanical pre-filters | REQ-SBM-04 |
| 3. Telemetry kill | Does anything phone home, at run time or at build time? | Assertion by test | REQ-SBM-06, REQ-FND-10 |

Pass 2 exists because pass 1 has a blind spot that is not a gap in its data: an
advisory database tells you what has been **reported**. It cannot tell you that a
crate gained a `build.rs` that downloads a binary blob last month, or that
maintainership moved to an account created in March. Treating pass 1 as coverage
of pass 2 is the most common way this gate is quietly skipped.

---

## 2. Pass 1 — known-vulnerability

### Inventory and SBOM

`cargo-cyclonedx` 0.5.9 generates a CycloneDX SBOM per target per build, and it
is published per release (REQ-SBM-01, REQ-CRA-03, REQ-REL-03):

```bash
cargo cyclonedx --all --format json --target x86_64-pc-windows-msvc
# -> app-<version>-x86_64.cdx.json
```

The SBOM covers the full resolved graph from `Cargo.lock`, not only direct
dependencies. Annex I Part II point 1 requires at least top-level dependencies;
the full graph is what `Cargo.lock` already knows, so publishing less would be a
deliberate reduction in evidence.

The same graph is embedded in the binary by `cargo auditable build` (REQ-SBM-02).
The SBOM beside the release and the list inside the binary are generated from one
`Cargo.lock` in one job. If they can disagree, the pipeline is wrong.

### Advisory matching

`cargo deny check advisories` against the RustSec advisory database, plus the
CycloneDX SBOM retained for matching against sources that arrive later. The
matching runs on every build, not only on release (REQ-SBM-03).

### The blocking rule

A **critical** advisory, or any advisory marked known-exploited, **blocks the
release**. Not a warning, not a follow-up issue (REQ-SBM-03). High and below are
recorded in `security/supply-chain/advisory-report.json` with a decision and an
owner, and an unresolved entry older than one release cycle escalates.

The report is a build output, not prose. It is the evidence row for Annex I
Part I "no known exploitable vulnerabilities" in the obligations matrix, and a
prose assertion there would be marked **weak** (REQ-CRA-10).

---

## 3. Pass 2 — first-party review of dependency behaviour

An independent review of what the dependency does, beyond advisory matching
(REQ-SBM-04). It runs on every **new** dependency and on every version bump that
changes any of the signals below. Output:
`security/supply-chain/dependency-review.md`, one section per crate, with a
verdict of `accept`, `accept with note`, or `reject`.

| Signal | What is checked | How | Why it matters here |
|--------|----------------|-----|--------------------|
| Build scripts | Does the crate have a `build.rs`, and what does it do? | Enumerate `build.rs` in the vendored graph; read each one | A build script runs with the builder's privileges, before any of our code |
| `proc-macro` crates | Which crates are `proc-macro`, and what do they generate? | `cargo metadata` filter on `proc-macro = true` | A proc macro executes at compile time and can read the filesystem |
| Build-time network | Does any build script or proc macro reach the network? | Pass 3's offline build (§4) | A download at build time defeats `--locked` and reproducibility (REQ-FND-09) |
| `unsafe` volume | How much `unsafe`, and where? | Count and locate per crate; compare against the previous accepted version | Our own `unsafe` is confined to `crates/ffi` (REQ-FND-06); a dependency's is not |
| Ownership and activity | Did owners, publishers or release cadence change recently? | crates.io owners and version history, with the source URL recorded | A transferred crate with a fresh publisher is the supply-chain attack that actually happens |

Mechanical pre-filters narrow the reading; they do not replace it. The
enumeration of `build.rs` files is a script. Deciding whether a given `build.rs`
that links a system library is acceptable is a judgement, and it is recorded with
a name against it.

### Scope discipline

The review is over crates that enter the shipped binary or run during its build.
A dev-dependency used only by `tests/**` is reviewed at a lower bar and the
distinction is stated in the record — but note that a proc macro in a
dev-dependency still executes on a developer's machine, so "dev-only" is not
"unreviewed".

### New dependency = recorded decision

A new dependency needs a record before it is merged (REQ-SBM-05):

```markdown
### <crate> <version>
- Purpose: <the one thing it does for us>
- Alternative considered: <crate or "write it ourselves — N lines">
- Graph cost: <n> new transitive crates, <n> new `unsafe` sites
- Signals: build.rs <yes/no> · proc-macro <yes/no> · build-time network <no>
- Licence: <SPDX id>, allowed by deny.toml
- Verdict: accept | accept with note | reject — <name>, <date>
```

"We needed an HTTP client" is not a purpose; `ureq` for the update fetch
(REQ-UPD-04) is. `T2` reviews these records at H7 (REQ-GAT-02) — the agent that
added the dependency does not vote on it (REQ-GAT-07).

---

## 4. Pass 3 — telemetry kill, asserted by test

No telemetry, no phone-home, no third-party crash reporting, from the app or from
any dependency (REQ-FND-10) — and it is **asserted by test**, including
**build-time network access by any crate** (REQ-SBM-06).

Three assertions, all in CI, all failing the build:

1. **Build-time network.** Vendor the graph, then build with the network
   unavailable to the build process:

   ```bash
   cargo vendor --locked vendor/
   cargo build --release --locked --offline        # any network need fails here
   ```

   A crate whose build script needs the network cannot be built this way, and
   that is the finding. Such a crate is rejected, not accommodated with a
   proxy allowance: a build that fetches is not reproducible from its tag
   (REQ-FND-09) and cannot be audited from `Cargo.lock`.

2. **Runtime destinations.** An integration test drives the app through startup,
   an update check, and a support-bundle export with an outbound allowlist of
   exactly the configured update endpoint. Any other connection attempt fails the
   test. The allowlist is a single value read from config, so a hard-coded second
   endpoint anywhere in the graph shows up as a test failure rather than as a
   packet someone happens to notice.

3. **Source-level check.** A scan for known telemetry and crash-reporting crates
   and for HTTP destination literals outside `crates/update`. It is the weakest of
   the three and it is kept because it names the offending crate, which the other
   two do not.

`DO_NOT_TRACK=1` is set in the build environment (`versions/manifest.json`,
`telemetry`) and in the agent runtime (REQ-PORT-04). Setting an environment
variable is a courtesy to a well-behaved dependency; assertions 1 and 2 are the
control.

Crash output stays local (REQ-OBS-05). Nothing leaves the machine without an
explicit, per-incident user action, and the support bundle is a file the user
chooses (REQ-OBS-04).

---

## 5. `cargo deny` policy

`deny.toml` is committed, reviewed, and gates licences, duplicate versions and
advisories (REQ-SBM-07). Sections and what each one is for:

| Section | Policy | Why |
|---------|--------|-----|
| `[advisories]` | `vulnerability = "deny"`, `unmaintained = "warn"`, `yanked = "deny"`, no blanket `ignore` without an expiry and an owner | A permanent ignore is an accepted vulnerability nobody re-reads |
| `[licenses]` | An explicit SPDX allowlist; `unlicensed = "deny"`; `copyleft = "deny"` unless intake accepted it in writing | We ship a signed binary; a licence we cannot comply with is a legal defect in the artefact |
| `[bans]` | `multiple-versions = "deny"` with named, justified exceptions; `wildcards = "deny"` | Two versions of one crate in the binary means two behaviours and two advisory surfaces |
| `[sources]` | Only the crates.io registry; `unknown-git = "deny"` | No git dependency in a release build (REQ-VER-01) |

`cargo-deny`'s version is recorded as **unresolved** in
`versions/manifest.json` and `B16` resolves it at gate H2 (REQ-VER-02,
REQ-VER-03). `B11` reads the resolved value from the manifest. It does not write
a version into a workflow from memory, and it does not pin `latest` — an
unpinned gate tool changes the gate without a commit.

A `deny.toml` change is reviewed like code: it is the file that decides what the
gate lets through.

## 6. `--locked`, always

`Cargo.lock` is committed and every release build passes `--locked`
(REQ-SBM-08). An unlocked release build resolves a graph that was never tested,
never reviewed under pass 2, and never matched under pass 1 — it is a different
product with the same version number.

`--locked` also carries the reproducibility claim in `spec/release.md` §6 and the
SBOM's accuracy: an SBOM generated from a graph that the build then re-resolved
describes something else.

## 7. Where this runs

| Trigger | Passes | Blocking |
|---------|--------|----------|
| Pull request | 1, 3, `cargo deny`, `--locked` check | Yes |
| Push to the default branch | 1, 3, `cargo deny` | Yes |
| Scheduled daily | 1 (advisory data moves without our code moving) | Opens a blocking issue |
| Dependency added or bumped | 2, then 1 and 3 | Yes |
| Release tag | all three, before `B10` builds anything | Yes (REQ-SBM-03) |

The daily run matters because the advisory database changes when nothing in the
repository does. A supply chain that is only checked when someone commits is
checked least when it is most exposed.

## 8. Failure modes

| Symptom | Cause | What happens |
|---------|-------|--------------|
| Advisory gate green, crate is malicious | Pass 2 was skipped as "already covered" | Pass 2 is separately recorded; a missing record for a new crate fails CI (REQ-SBM-04) |
| `--offline` build fails after a bump | A build script wants the network | Reject the bump; record it in `dependency-review.md` (REQ-SBM-06) |
| Duplicate versions accumulate | `multiple-versions` demoted to warn | Blocking; exceptions are named and justified in `deny.toml` (REQ-SBM-07) |
| SBOM and embedded list disagree | Two jobs, two resolutions | Blocking pipeline defect; both come from one `Cargo.lock` (REQ-SBM-02) |
| An `ignore` entry hides a live advisory | Expiry-less ignore | `deny.toml` rejects an `ignore` without an expiry and an owner |
| `cargo-deny` version drifts | Tool installed as `latest` in CI | Read the resolved pin from `versions/manifest.json` (REQ-VER-02) |

## 9. Definition of done

- [ ] CycloneDX SBOM per target, published per release, retained (REQ-SBM-01, REQ-CRA-03).
- [ ] Dependency list embedded in every shipped binary and verified by auditing
      the released artefact, not the build tree (REQ-SBM-02).
- [ ] Advisory matching on every build; critical or known-exploited blocks
      (REQ-SBM-03).
- [ ] A `dependency-review.md` section exists for every crate added or bumped in
      this release, with a named verdict (REQ-SBM-04, REQ-SBM-05).
- [ ] Offline vendored build passes; runtime destination test passes; source scan
      clean (REQ-SBM-06, REQ-FND-10).
- [ ] `deny.toml` committed, reviewed, and running on the pinned `cargo-deny`
      from `versions/manifest.json` (REQ-SBM-07).
- [ ] Every release build ran `--locked` against a committed `Cargo.lock`
      (REQ-SBM-08).
