# base-windows-rust-app

A Windows desktop application in Rust that is finished rather than started:
tray-resident, self-installing, self-updating, signed, and shipped to two forges
from one tag.

## Starting a build

**There is no command to run.** Point an agent at this directory and describe
what you want. It reads `AGENTS.md` (or `CLAUDE.md` — they are identical),
which sends it to `prompts/00-master-orchestrator.md`.

```bash
cd my-app        # this directory: the project root, not a folder inside it
claude           # or muse, or any agent pointed here
```

> A small utility that sits in the tray, watches a folder for incoming exports,
> normalises them and drops them on a share. Needs to keep running when nobody
> is logged in. Releases go to our Gitea and to GitHub.

That paragraph is the trigger. `B00` asks the handful of questions whose answers
change the build and defaults the rest loudly. Then `H1` stops and waits for you
to name a design direction — see below.

On Claude Code, `/build-orchestrate` loads the same procedure as a shortcut. It
is not a prerequisite: if slash commands or skills do nothing in your runtime,
read `.claude/skills/build-orchestrate/SKILL.md` as an ordinary file.

**This directory is the project root.** If you copied it into a subfolder of an
existing project, stop and read *Where this folder sits* in `AGENTS.md` first —
the ownership map's paths are relative to here, and nested they are ambiguous.

---

## Design comes first, and it blocks

Most of this structure is ordinary. This part is not.

**No feature work begins until a human approves a design direction**
(REQ-GAT-08). Before that, the build produces three to five mockups — and the
mockups are **compiled programs, not pictures** (REQ-MOC-02). Each is a small
Rust binary that builds and runs, so it proves the styling is achievable in the
chosen stack rather than achievable in a design tool.

Each mockup states in its own source header the direction it is testing and what
it gives up to get there. Each runs in light and dark, and both are screenshotted
and presented in chat. You name the winner; the token module is derived from it,
and the mockup stays in-tree as the reference the design is checked against.

The reason is narrow and practical: a desktop design that cannot be expressed in
the framework's styling model is discovered late, and by then every view has
been built against it.

## What it produces

**The app** — a single self-contained executable with no runtime prerequisite.
Native window behaviour, persisted window placement that survives a monitor
disappearing, keyboard-complete, screen-reader accessible through UI Automation,
and a UI thread that never blocks.

**Design system** — tokens as compiled Rust, full light and dark themes both
designed rather than one inverted, following the Windows system preference and
switching live. Contrast asserted at AA in both themes by a test over the token
table, not by eye. Correct from 100% to 250% DPI, including a window dragged
between monitors with different scale factors.

**Tray** — icon with light, dark and high-contrast variants, a context menu
reflecting live state, and re-registration after an Explorer restart, which is
the defect users actually report. Single-instance, so launching again focuses the
running window instead of adding a second icon.

**Install** — `app.exe --install` installs itself, per-user without elevation by
default, machine-wide when asked. An MSI is produced as well for GPO deployment.
Install, upgrade, repair and uninstall are idempotent and transactional, and
uninstall is honest: service, scheduled task, autostart entry, shortcuts and
registry all removed, with an explicit prompt about user data.

**Service and autostart** — optional service mode from the same binary under the
least-privileged account that works, with an access-controlled local IPC channel
that authenticates its caller. Autostart at login is offered, default off,
visible in settings rather than discovered in Task Manager, and launches
minimised to tray instead of stealing focus during login.

**Auto-update** — automatic, staggered to avoid a release-day thundering herd,
atomic across power loss, refusing downgrades, and **verifying a signature
against an embedded public key before anything is swapped in**. Security updates
are distinguishable from feature updates so an operator can take one without the
other.

**Release** — one pipeline, one tag, both GitHub and Gitea. Signed binaries for
x64 and ARM64, the MSI, the SBOM, checksums, and the signed update manifest —
published atomically and last, after every artefact it references is retrievable.

**Compliance** — EU CRA and CER documentation. This product is squarely a product
with digital elements placed on the market, so Annex I applies directly rather
than by analogy, and the auto-updater is the mechanism that satisfies the
security-update obligation.

All of it under [`spec/requirements.md`](spec/requirements.md) — 177
requirements with stable IDs, each owned by an agent and checked by a gate.

## How it builds

```
H0 intake        B00 resolves scope from your paragraph
H1 design        B03 tokens -> B04 compiles 3-5 mockups -> YOU PICK ONE   [BLOCKS]
H2 versions      B16 validates every crate against crates.io
H3 freeze        B02 assembles and freezes crates/contracts
H4 self-test     ┌- 9 agents build simultaneously -┐
H5 integration   └- ui tray install service update -┘
H6 critique      D1 and D2 must both approve design AND functions
H7 security      T1 and T2 review independently; both must approve
H8 release       signed, SBOM'd, published to both forges
```

## Layout

| Path | What |
|------|------|
| [`prompts/`](prompts/) | The orchestrator and phase prompts |
| [`.claude/agents/`](.claude/agents/) | 19 build agents plus 4 gate agents |
| [`.claude/skills/`](.claude/skills/) | Orchestration, version guard, release, supply chain |
| [`spec/`](spec/) | 177 requirements and a spec per domain |
| [`contracts/`](contracts/) | Contract law, the ownership map, typed members |
| [`gates/`](gates/) | The H0–H8 ladder, verdict schema, loop rules |
| [`design/`](design/) | The design system, once approved |
| [`mockups/`](mockups/) | Compiled styling proofs, kept in-tree |
| [`versions/`](versions/) | Externally validated crate and toolchain versions |
| [`compliance/`](compliance/) | EU CRA and CER documentation |
| `build/` | Per-build working state. Gitignored. |

## Design principles

**One FFI boundary.** `crates/ffi` is the only crate that calls `windows-rs`.
Nine agents each writing their own `unsafe` Win32 calls produce nine different
assumptions about handle lifetime and string encoding, and those bugs are
memory-unsafe rather than merely wrong.

**Registrations have one owner each.** Three agents can change what a machine
looks like after install, split by state transition rather than by file: files on
disk are the installer's, the service and autostart entries are the service
agent's, and replacing installed files is the updater's. Updating a service
installation crosses all three, and it crosses them through the contract — an
agent reaching for `sc.exe` has bypassed one.

**Nobody owns a signing key.** The updater embeds a public key; the publisher
consumes a CI credential it never reads or logs. An agent that needs a private
key has been asked to do the wrong job.

**Every dependency is shipped.** In a Rust binary a dependency is compiled into
the product, so adding one is a shipping decision rather than a development
convenience.
