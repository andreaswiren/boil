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
| [`base-admin-panel`](boilerplates/base-admin-panel/) | A multi-tenant Next.js admin panel that deploys with `docker compose up`: RBAC with full user impersonation, MFA (password+OTP, passkeys, OIDC), a skip-proof setup wizard, HAProxy edge with built-in Let's Encrypt across all four challenge types, full audit including read logging, PWA with push, SMTP, syslog forwarding, an advanced TanStack datagrid, Monaco editing surfaces, a dedicated mobile UX layer, personal/tenant/global settings, EU CRA + CER compliance documentation. 337 requirements driven by a 32-agent fleet — 28 builders and 4 reviewers — across 5 waves behind 9 quality gates, with per-gate token-cost reporting and a portability adapter for non-Claude runtimes. | Prompt structure complete, unbuilt |
| [`base-windows-rust-app`](boilerplates/base-windows-rust-app/) | A Windows desktop app in Rust with `windows-rs`: tray-resident, self-installing with scoped elevation, optional service mode and login autostart, signature-verified auto-update, SBOM embedded in the binary, signed releases published to both GitHub and Gitea from one tag, EU CRA + CER documentation. **Design comes first and blocks:** 3-5 mockups that are compiled programs rather than pictures, approved by a human before any feature work. 177 requirements driven by a 23-agent fleet — 19 builders and 4 reviewers — across 5 waves behind 9 gates, with per-gate token-cost reporting and the same portability adapter. | Prompt structure complete, unbuilt |

More boilerplates will be added alongside it. Each one is independent.

---

## Using a boilerplate

**A boilerplate becomes your project. It is not a folder you add to one.**

Each boilerplate's `contracts/ownership.md` opens with a *Workspace root*
section that assigns the workspace manifest, the lockfile, `.github/workflows/`
and `README.md` / `CHANGELOG.md` / `VERSION` to agents. The build writes the
application beside `spec/`, `contracts/` and `gates/`, at those paths with no
prefix. So the folder you start in is the root of the thing you end up with.

### The command

Copy the one boilerplate to where the new project should live, and start there:

```bash
npx degit andreaswiren/boil/boilerplates/base-windows-rust-app my-app
cd my-app
git init && git add -A && git commit -m "Vendor base-windows-rust-app"
claude          # or: muse, or any agent pointed at this directory
```

`degit` takes the folder without the collection's git history, which is what you
want: the boilerplate is a vendored input, and the commit above records the
version you vendored. Swap `base-windows-rust-app` for `base-admin-panel` for
the other one.

No Node? Sparse checkout does the same thing:

```bash
git clone --filter=blob:none --no-checkout https://github.com/andreaswiren/boil.git
cd boil
git sparse-checkout init --cone
git sparse-checkout set boilerplates/base-windows-rust-app
git checkout main
mv boilerplates/base-windows-rust-app ../my-app && cd ../my-app
```

Then describe what you want in a paragraph. The orchestrator handles the rest:

```
Build me a panel for managing customer firewall estates across ~40 tenants.
Techs need to see devices, config backups and change history. Entra ID login.
```

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
   two domains share. Thirteen expert agents then build simultaneously without
   merging, waiting or negotiating.
2. **Additive-only change.** After the contract freeze, nothing is renamed,
   removed or retyped. A breaking change needs arbitration and a version. This
   is what keeps a 13-wide wave from collapsing.
3. **Single ownership.** Every file and every table has exactly one owning
   agent. Two agents writing the same file is treated as a build defect, not a
   merge conflict.
4. **Gates that actually block.** Two harsh critics must approve the design and
   the functions. Two independent security reviewers must approve the code.
   Nothing self-approves.

---

## Adding a boilerplate

Use the repo skill:

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
