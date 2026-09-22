# The Expert Fleet

One part of the app, one expert agent, one owner. Agent IDs are stable and are
the only way to refer to an agent — prompts, gates, ownership and traceability
cite `B00`…`B18`, `D1`, `D2`, `T1`, `T2`.

Full prompts live in `.claude/agents/<id>-<slug>.md`. This file is the index and
the contract between agents: who owns what, who publishes what, who consumes
what.

Gates in this boilerplate are `H0`–`H8`. The other boilerplate in this
repository uses `G0`–`G8`; the namespaces are deliberately different so a
verdict file can never be read against the wrong ladder.

---

## Wave 0 — Intake

| ID | Agent | Owns | Publishes | Consumes |
|----|-------|------|-----------|----------|
| B00 | `intake-analyst` | `build/intake.md`, `build/scope.md`, `build/waivers.md` | resolved scope | the user's description |

B00 resolves the app's purpose, whether service mode is needed (REQ-SVC-01 is
`OPT`), the UI framework, the forge endpoints, the support period, and the cost
ceiling. It asks only the questions whose answers change the build.

## Wave 1 — Design first, and it blocks everything

| ID | Agent | Owns | Publishes | Consumes |
|----|-------|------|-----------|----------|
| B03 | `design-system` | `crates/design/**`, `design/**` | `design-tokens` | scope |
| B04 | `mockup-builder` | `mockups/**` | 3–5 compiled mockups | `design-tokens` |
| B15 | `visual-qa` | `tests/visual/**`, `build/screenshots/**` | screenshot sets | anything that runs |

This wave is why this boilerplate exists in the shape it does. **No feature work
begins until a human approves a design direction** (REQ-GAT-08, REQ-MOC-01), and
the mockups are **compiled programs, not pictures** (REQ-MOC-02): each is a small
binary that builds and runs, proving the styling is achievable in the chosen
stack rather than achievable in an image editor.

B04 produces between three and five, differentiated by design *direction* —
density, typographic scale, chrome weight, accent strategy — not by accent
colour. Each states in its own source header what it is testing and what it gives
up. B15 screenshots each in light and dark, and they are presented in chat.

**Gate H1 stops the build until a human names the winner.** The token module is
then derived from that mockup, and the mockup stays in-tree as the reference the
design is checked against.

## Wave 2 — Foundation & contract freeze (sequential)

| ID | Agent | Owns | Publishes | Consumes |
|----|-------|------|-----------|----------|
| B16 | `version-validator` | `versions/**` | `manifest.json` | crates.io, the Rust release channel |
| B01 | `arch-foundation` | workspace, `rust-toolchain.toml`, `crates/app/` scaffold, `crates/ffi/**`, build scripts, app manifest | `env-config`, `ffi-boundary`, `paths` | `manifest.json` |
| B02 | `contract-steward` | `crates/contracts/**` | the whole contract surface, `config`, `errors`, `version` | every agent's declared members |

B16 runs first — nothing is added to `Cargo.toml` against a remembered version.
B01 scaffolds and owns the `unsafe`/FFI boundary policy (REQ-FND-06). B02
assembles every crate's declaration into one frozen `crates/contracts`.
**Gate H3 freezes it**; after that, change is CCR-only and additive.

## Wave 3 — Parallel build

Nine agents start together against the frozen contract. None blocks another.

| ID | Agent | Owns | Publishes | Consumes |
|----|-------|------|-----------|----------|
| B05 | `ui-shell` | `crates/ui/**` | `view-registry`, `settings-registry` | `design-tokens`, `config`, `version` |
| B06 | `systray` | `crates/tray/**` | `tray-state` | `design-tokens`, `view-registry`, `config` |
| B07 | `installer` | `crates/install/**`, `packaging/wix/**` | `install-mode`, `exit-codes` | `paths`, `version`, `signing-keys` |
| B08 | `service-autostart` | `crates/service/**`, `crates/autostart/**` | `service-state`, `ipc-contract` | `config`, `paths`, `version` |
| B09 | `updater` | `crates/update/**` | `update-manifest`, `channel` | `version`, `signing-keys`, `paths` |
| B10 | `release-publisher` | `.github/workflows/release.yml`, `ci/publish/**` | `release-artifacts` | `update-manifest`, SBOM, `version` |
| B11 | `supply-chain` | `deny.toml`, `security/supply-chain/**` | SBOM, advisory report | `Cargo.lock` |
| B12 | `observability` | `crates/obs/**` | `log-record`, `diagnostics` | `config`, `paths`, `version` |
| B14 | `test-engineer` | `tests/**` except `tests/visual/**`, `crates/fixtures/**` | fixtures, interface tests | every contract member |

### The seam that matters most

`B07 installer`, `B08 service-autostart` and `B09 updater` all touch
installation state, and all three can leave a machine broken. They are separated
by **who owns the state transition**, not by which file is convenient:

- B07 owns putting files on disk and registering the app.
- B08 owns the service and the autostart entry as *registrations*.
- B09 owns replacing files that B07 put there.

An update of a service installation therefore crosses all three, and it crosses
them through the contract: B09 reads `service-state` and calls the stop/start
transition B08 published, rather than shelling out to `sc.exe` itself
(REQ-UPD-10). An agent that reaches for `sc.exe` has bypassed a contract.

## Wave 4 — Narrative & release

| ID | Agent | Owns | Publishes | Consumes |
|----|-------|------|-----------|----------|
| B13 | `compliance-cra-cer` | `compliance/**` | CRA + CER document set | SBOM, signing posture, update chain, support period |
| B17 | `release-manager` | `CHANGELOG.md`, `README.md`, `SECURITY.md`, `TODO.md`, `VERSION`, version fields | the release record | gate verdicts, cost summary |

B13 runs last on purpose: it documents what was built. This product is squarely
a product with digital elements placed on the market, so Annex I applies directly
rather than by analogy — and the auto-updater is the mechanism that satisfies the
security-update obligation, which makes REQ-UPD-02's signature verification a
compliance control as well as a security one.

## Cross-wave

| ID | Agent | Runs | Why it is not in a wave |
|----|-------|------|------------------------|
| B15 | `visual-qa` | H1 and H5 | It screenshots anything that renders, including the 3–5 mockups and the DPI matrix (REQ-TST-08) |
| B18 | `cost-accountant` | every gate | Arithmetic over structured input; it runs on the cheapest model in the fleet on purpose (REQ-COST-03) |

## Gate agents — never in a wave, never self-approving

| ID | Agent | Lens | Votes on |
|----|-------|------|----------|
| D1 | `critic-design` | Design system, states, DPI, theme honesty, accessibility | design **and** functions |
| D2 | `critic-function` | Completeness and edge cases across install, update, service, tray | design **and** functions |
| T1 | `security-alpha` | Privilege boundaries: elevation, service account, IPC, ACLs, DLL search order | code |
| T2 | `security-beta` | The trust chain: update signing, artefact verification, secrets at rest, supply chain | code |

D1 and D2 both vote on both dimensions (REQ-GAT-01). T1 and T2 are launched
together with no shared context and do not see each other's findings before
submitting (REQ-GAT-02).

**No gate agent may have written any of the code it reviews (REQ-GAT-07).**

## Fleet summary

| | Count | Who |
|---|---|---|
| Intake | 1 | `B00` |
| Wave 1 (design, blocking) | 3 | `B03` `B04` `B15` |
| Wave 2 (foundation, sequential) | 3 | `B16` `B01` `B02` |
| Wave 3 (parallel) | **9** | `B05` `B06` `B07` `B08` `B09` `B10` `B11` `B12` `B14` |
| Wave 4 | 2 | `B13` `B17` |
| Cross-wave | 1 | `B18` |
| **Build agents** | **19** | `B00`–`B18` |
| Gate agents | 4 | `D1` `D2` `T1` `T2` |
| **Total** | **23** | |

A smaller fleet than the admin panel's, and deliberately so: a single-binary
desktop app has fewer genuinely independent domains, and an agent per file is
the proliferation the Karpathy lens catches (`gates/karpathy-lens.md`).

The critical path is
`B00 → B03 → B04/B15 → human → B16 → B01 → B02 → [Wave 3] → [Wave 4] → D1/D2 → T1/T2 → B17`.

Wave 3 is 9-wide. The design gate before it is the one that cannot be
parallelised and should not be rushed, because everything downstream is styled
against its output.
