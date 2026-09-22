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
| [`base-admin-panel`](boilerplates/base-admin-panel/) | A multi-tenant Next.js admin panel that deploys with `docker compose up`: RBAC with full user impersonation, MFA (password+OTP, passkeys, OIDC), a skip-proof setup wizard, HAProxy edge with built-in Let's Encrypt across all four challenge types, full audit including read logging, PWA with push, SMTP, syslog forwarding, an advanced TanStack datagrid, Monaco editing surfaces, a dedicated mobile UX layer, personal/tenant/global settings, EU CRA + CER compliance documentation. 337 requirements driven by a 28-agent fleet across 5 waves behind 9 quality gates, with per-gate token-cost reporting and a portability adapter for non-Claude runtimes. | Prompt structure complete, unbuilt |

More boilerplates will be added alongside it. Each one is independent.

---

## Using a boilerplate

### Option A — point an agent at the folder

The fastest path. Each boilerplate folder is self-describing: it carries its own
`CLAUDE.md`, its own `.claude/agents/` fleet and its own `.claude/skills/`.

```bash
cd boilerplates/base-admin-panel
claude
```

Then describe what you want in a paragraph. The orchestrator handles the rest:

```
Build me a panel for managing customer firewall estates across ~40 tenants.
Techs need to see devices, config backups and change history. Entra ID login.
```

You can also hand an agent the folder without cloning anything — the path or the
GitHub URL of `boilerplates/base-admin-panel/` is enough context to start.

### Option B — clone just the one boilerplate

You do not need the rest of the repo. Sparse checkout pulls one folder:

```bash
git clone --filter=blob:none --no-checkout https://github.com/andreaswiren/boil.git
cd boil
git sparse-checkout init --cone
git sparse-checkout set boilerplates/base-admin-panel
git checkout main
```

Or, to get the folder with no git history at all:

```bash
npx degit andreaswiren/boil/boilerplates/base-admin-panel my-panel
cd my-panel && claude
```

Either way you end up with a directory that stands on its own. Nothing in a
boilerplate reaches outside its own folder — that is enforced, not hoped for
(see [`CONVENTIONS.md`](CONVENTIONS.md)).

### Option C — clone the lot

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
