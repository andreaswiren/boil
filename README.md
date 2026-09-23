# boil

A collection of **boilerplates** and **skills** for starting projects that are
already at release-candidate quality, rather than at "hello world".

Two halves:

| Half | Path | What it is |
|------|------|------------|
| Boilerplates | `boilerplates/<name>/` | A self-contained, clonable starter. Not a template you fill in by hand — a prompt structure an AI agent fleet executes to produce the app. |
| Skills | `.claude/skills/` | Repo-level skills that work across boilerplates. Boilerplate-specific skills live inside their own boilerplate. |

## What is in here now

| Boilerplate | What it produces | Status |
|-------------|------------------|--------|
| [`base-admin-panel`](boilerplates/base-admin-panel/) | A multi-tenant Next.js admin panel that deploys with `docker compose up`: RBAC with full user impersonation, MFA (password+OTP, passkeys, OIDC), a skip-proof setup wizard, HAProxy edge with built-in Let's Encrypt across all four challenge types, full audit including read logging, PWA with push, SMTP, syslog forwarding, an advanced TanStack datagrid, Monaco editing surfaces, a dedicated mobile UX layer, personal/tenant/global settings, EU CRA + CER compliance documentation. 356 requirements driven by a 33-agent fleet — 29 builders and 4 reviewers — across 5 waves behind 9 quality gates, with per-gate token-cost reporting and a portability adapter for non-Claude runtimes. | Prompt structure complete, unbuilt |
| [`base-windows-rust-app`](boilerplates/base-windows-rust-app/) | A Windows desktop app in Rust with `windows-rs`: tray-resident, self-installing with scoped elevation, optional service mode and login autostart, signature-verified auto-update, SBOM embedded in the binary, signed releases published to both GitHub and Gitea from one tag, EU CRA + CER documentation. **Design comes first and blocks:** 3-5 mockups that are compiled programs rather than pictures, approved by a human before any feature work. 179 requirements driven by a 23-agent fleet — 19 builders and 4 reviewers — across 5 waves behind 9 gates, with per-gate token-cost reporting and the same portability adapter. | Prompt structure complete, unbuilt |
| [`base-hsm-signing-server`](boilerplates/base-hsm-signing-server/) | A hardened Debian code-signing appliance around a Nitrokey HSM 2 — **SignZone**. A Next.js admin surface that is unprivileged by construction, a Rust signer daemon holding the only path to the HSM, a typed allowlisted OS-control daemon in place of any shell, a REST signing API for CI, a PWA that approves with transaction binding rather than a push notification, DKEK ceremonies with a secondary HSM for disaster recovery, an append-only hash-chained audit log, and an ESXi-style local console on tty1. Authenticode and PowerShell signing on Linux with RFC3161 timestamps. 58 requirements with `SZ-*` IDs, 34 agents, 19 domain skills, and two independent reviewers — `security-reviewer` and `adversarial-reviewer` — on every security-critical change. | Contributed structure, unbuilt |

More boilerplates will be added alongside it. Each one is independent.

---

## Using a boilerplate

**A boilerplate becomes your project. It is not a folder you add to one.**

Each boilerplate's `contracts/ownership.md` opens with a *Workspace root*
section that assigns the workspace manifest, the lockfile, `.github/workflows/`
and `README.md` / `CHANGELOG.md` / `VERSION` to agents. The build writes the
application beside `spec/`, `contracts/` and `gates/`, at those paths with no
prefix. So the folder you start in is the root of the thing you end up with.

### The command — pick one

Copy the one boilerplate you want to where the new project should live, and
start there. Change `my-panel` / `my-app` to whatever the project is called.

**A multi-tenant Next.js admin panel:**

```bash
npx degit andreaswiren/boil/boilerplates/base-admin-panel my-panel
cd my-panel
git init && git add -A && git commit -m "Vendor base-admin-panel"
claude          # or: muse, or any agent pointed at this directory
```

**A Windows desktop app in Rust:**

```bash
npx degit andreaswiren/boil/boilerplates/base-windows-rust-app my-app
cd my-app
git init && git add -A && git commit -m "Vendor base-windows-rust-app"
claude          # or: muse, or any agent pointed at this directory
```

`degit` takes the folder without the collection's git history, which is what you
want: the boilerplate is a vendored input, and the commit records the version
you vendored.

No Node? Sparse checkout does the same thing — set `NAME` to either
`base-admin-panel` or `base-windows-rust-app`:

```bash
NAME=base-windows-rust-app
git clone --filter=blob:none --no-checkout https://github.com/andreaswiren/boil.git
cd boil
git sparse-checkout init --cone
git sparse-checkout set "boilerplates/$NAME"
git checkout main
mv "boilerplates/$NAME" ../my-app && cd ../my-app
```

On Windows PowerShell, replace `NAME=...` with `$NAME = "base-windows-rust-app"`
and `mv` with `Move-Item`.

### What triggers the build

**No command. You describe what you want.** The agent reads `AGENTS.md` (or
`CLAUDE.md` — they are identical), which tells it to read
`prompts/00-master-orchestrator.md` and start. That is deliberate: a file read
works on every runtime, where a slash command works on some.

```
Build me a panel for managing customer firewall estates across ~40 tenants.
Techs need to see devices, config backups and change history. Entra ID login.
```

That paragraph is the trigger. `A00` / `B00` resolves the rest and asks only the
questions whose answers change the build.

On Claude Code there is an optional shortcut that loads the same procedure:

```
/build-orchestrate
```

It is a shortcut, not a prerequisite. If it does nothing in your runtime —
Muse Code 1.3.0 does not load skills — read
`.claude/skills/build-orchestrate/SKILL.md` as an ordinary file instead.

**`/boil-new-boilerplate` is not this.** It authors a *new boilerplate into this
collection*, which is a contributor task; it lives in this repository's root
`.claude/skills/`, so a vendored project does not have it at all. If you typed
it expecting a build to start, you wanted the paragraph above.

### Running on Muse Code, or another non-Claude runtime

Both boilerplates are runtime-neutral by design: every spec, contract, gate and
agent file is plain Markdown that names no tool, and each ships a
`portability/` folder with a capability map. `base-admin-panel` also carries a
written Muse Code adapter; `base-windows-rust-app` does not yet, and its
`portability/README.md` says so rather than implying otherwise. Two things will
surprise you on either.

**The `AGENTS.md` warning is expected. Ignore it, and do not act on its
suggestion.** Muse Code 1.3.0 prints:

```
warning: rules file at ...\CLAUDE.md is ignored this session because AGENTS.md
takes precedence in that directory; merge still-applicable guidance into
AGENTS.md or remove one of the two files
```

Every `CLAUDE.md` and `AGENTS.md` in this repository is a **byte-identical
pair**, and the conformance check fails if they drift. So there is nothing in
the ignored file that is not in the file being read, and the warning costs you
nothing. **Do not remove either file** as the warning suggests — Claude Code
reads one, Muse Code reads the other, and deleting either breaks that runtime.
The duplication is deliberate: a pointer file is a behaviour that depends on the
agent following it, while two identical files are a fact the runtime cannot
misread.

**Skills may not load, and nothing depends on them.** In an observed Muse Code
1.3.0 run the skill did not load; where it looks for skills is recorded as
`unconfirmed` in `portability/capability-map.md` rather than guessed. It costs
nothing, because the entry point is a file read rather than a slash command, and
every skill is a plain `SKILL.md` you can read as a file. A skill is a
procedure, and a procedure can always be read.

Before a real build on a non-Claude runtime, read that boilerplate's
`portability/README.md`. It also covers two things that are easy to skip and are
requirements the build is held to: turning off the runtime's **own** telemetry,
and recording which tier the session bills to — a discounted tier is often
discounted because prompts and outputs may be used to improve the vendor's
products, and this build sends security design through the model.

### Two things not to do

**Do not build inside this collection.** Running an agent in
`boil/boilerplates/<name>/` has it overwrite that boilerplate's own `README.md`
with your project's, and drop a workspace manifest and CI workflows into the
collection. Copy it out first — that is what the command above does.

**Do not nest a boilerplate inside an existing project.** At
`yourproject/boilerplate/`, every path in the ownership map is ambiguous between
two roots and an agent will pick one silently. To add what a boilerplate
produces to an existing system, build it as its own repository and integrate at
the API or deployment boundary. Keeping the boilerplates in a central folder and
pulling them in through a skill has the same problem from the other direction,
plus two more: not every runtime loads skills — Muse Code 1.3.0 does not — and
the requirement register, the frozen contract and the CRA conformity evidence
have to live with the product. An auditor handed a path outside the repository
is in the same position as one handed a gitignored file.

### Reading a boilerplate without cloning

For a question rather than a build, the GitHub URL of
`boilerplates/<name>/` is enough context to hand an agent. Nothing in a
boilerplate reaches outside its own folder — that is enforced, not hoped for
(see [`CONVENTIONS.md`](CONVENTIONS.md)).

### Cloning the whole collection

```bash
git clone https://github.com/andreaswiren/boil.git
```

Use this when you want the shared skills or you are adding a boilerplate.

---

## Why a prompt structure instead of a code template

A code template rots. The moment it is committed, its dependency versions are
wrong, its patterns are a year behind, and every project that used it has
diverged in a different direction.

A prompt structure carries the *decisions* instead of the code: the requirements
with stable IDs, the contracts between the parts, the ownership map that lets
agents work in parallel, and the gates that refuse to let bad work through. The
code is generated fresh against externally-validated current versions, every
time.

The `base-admin-panel` structure is built around four ideas:

1. **Contract-first parallelism.** One frozen contract package is the only thing
   two domains share. Sixteen expert agents then build simultaneously without
   merging, waiting or negotiating.
2. **Additive-only change.** After the contract freeze, nothing is renamed,
   removed or retyped. A breaking change needs arbitration and a version. This
   is what keeps a 16-wide wave from collapsing.
3. **Single ownership.** Every file and every table has exactly one owning
   agent. Two agents writing the same file is treated as a build defect, not a
   merge conflict.
4. **Gates that actually block.** Two harsh critics must approve the design and
   the functions. Two independent security reviewers must approve the code.
   Nothing self-approves.

---

## Adding a new boilerplate to this collection

This is a contributor task — authoring a new boilerplate, not running one. It
only applies in a clone of this repository. To *run* a boilerplate, see
[What triggers the build](#what-triggers-the-build).

```
/boil-new-boilerplate
```

It scaffolds the required structure and checks the self-containment rule. The
rules a boilerplate must satisfy are in [`CONVENTIONS.md`](CONVENTIONS.md).

## Repo meta

- [`CHANGELOG.md`](CHANGELOG.md) — every change, semver-versioned
- [`SECURITY.md`](SECURITY.md) — vulnerability reporting for this repo
- [`TODO.md`](TODO.md) — live status and what is planned
- [`CONVENTIONS.md`](CONVENTIONS.md) — the rules every boilerplate follows
- [`CLAUDE.md`](CLAUDE.md) — operating instructions for agents working in this repo
- [`scripts/check-conventions.sh`](scripts/check-conventions.sh) — enforces `CONVENTIONS.md`; run it before every commit

Licensed under [MIT](LICENSE).
