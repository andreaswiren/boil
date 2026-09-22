# base-windows-rust-app — operating instructions

You have been pointed at a boilerplate. It builds a Windows desktop application
in Rust — tray-resident, self-installing, self-updating, optionally a service —
using a 23-agent fleet (19 builders, 4 reviewers) across 5 waves behind 9
gates.

> **`CLAUDE.md` and `AGENTS.md` in this directory are byte-identical.** Some
> runtimes read one, some read the other, and Muse Code reads `AGENTS.md` and
> prints a warning that it is ignoring `CLAUDE.md`. That warning is expected and
> costs nothing here, because there is nothing in the ignored file that is not
> in the one being read. Do not "fix" it by deleting either file — that breaks
> the other runtime. `scripts/check-boilerplate.sh` fails if the two drift.

## Start here

**If the user has described what they want** — even in a sentence — read
`prompts/00-master-orchestrator.md` and follow it. That file is the process of
record and it is the entry point on every runtime, because it is a file rather
than a feature.

On Claude Code you can load the same procedure as a skill, which is a shortcut
and not a prerequisite:

```
/build-orchestrate
```

If a slash command does nothing in your runtime, or the skill does not load, you
have lost nothing: read `.claude/skills/build-orchestrate/SKILL.md` as an
ordinary file. A skill is a procedure, and a procedure can always be read.

**If the user has not described anything yet** — ask for a paragraph. What the
app does, who runs it, whether it needs to run when nobody is logged in, and
where releases go. `B00` resolves the rest.

**If the user is asking a question about this boilerplate** rather than asking
you to run it — answer from `spec/requirements.md` and the relevant `spec/`
document. Do not start a build to answer a question.

## The map

| File | What it is |
|------|------------|
| `prompts/00-master-orchestrator.md` | How the build runs. Read this first. |
| `spec/requirements.md` | 177 requirements with stable IDs. The source of truth. |
| `spec/agents.md` | The fleet: `B00`–`B18`, `D1`, `D2`, `T1`, `T2`, and the waves. |
| `contracts/ownership.md` | Who owns which path. The routing table for tasks and findings. |
| `gates/gate-ladder.md` | `H0`–`H8`. |
| `versions/manifest.json` | Externally validated crate and toolchain versions. |
| `.claude/agents/` | The 23 agent prompts themselves. |
| `.claude/skills/` | `build-orchestrate` — the orchestration procedure, loadable or readable. |
| `design/` | The design system, once `B03` has written it. |
| `mockups/` | The compiled styling proofs. |

## Rules that are not negotiable

1. **Design first, and it blocks.** No feature work begins before a human
   approves a design direction at `H1` (REQ-GAT-08, REQ-MOC-01). This is the
   rule most likely to feel like a delay and most likely to save a rebuild.
2. **Mockups are compiled programs, not pictures** (REQ-MOC-02). Each builds
   with `cargo build -p mockup-<n>` from a clean checkout. A mockup that cannot
   be compiled has proven nothing about whether the styling is achievable.
3. **Cite requirement IDs.** It is `REQ-UPD-02`, not "the update signing thing".
4. **No version from memory.** Validated against crates.io and the Rust release
   channel, recorded with source URL and timestamp (REQ-VER-02). crates.io
   rejects a request without a `User-Agent`, which reads like a missing crate.
5. **`windows-rs` is called from one crate only.** `crates/ffi` is the FFI
   boundary (REQ-FND-03). Nine agents writing their own `unsafe` Win32 calls
   produce nine different assumptions about handle lifetime and string encoding,
   and those bugs are memory-unsafe rather than merely wrong.
6. **The app runs as a normal user.** `asInvoker`. Only the installer path
   elevates, and only when it must (REQ-FND-11, REQ-INST-04).
7. **The updater verifies a signature before it swaps anything** (REQ-UPD-02).
   An auto-updater without verification is a remote code execution channel that
   ships enabled and turned on.
8. **Single ownership.** Write only inside your owned paths. Writing outside them
   is a build defect, not a merge conflict.
9. **Nothing self-approves.** The agent that wrote it never votes on it
   (REQ-GAT-07).
10. **Commit, push, bump, log.** Every build bumps the semver and updates
    `CHANGELOG.md`, `README.md`, `SECURITY.md` and `TODO.md` — and only `B17`
    may touch those files.

## This folder is self-contained

Nothing here reaches outside `boilerplates/base-windows-rust-app/`. If you want
a file from a sibling directory, that is a bug — someone will clone this folder
on its own.

## Style

Decide. "Consider using X" is a failed spec; write "we use X, because Y". Prefer
a crate version, a Win32 API name or a number over an adjective. State failure
modes bluntly: what breaks, and what to do instead.
