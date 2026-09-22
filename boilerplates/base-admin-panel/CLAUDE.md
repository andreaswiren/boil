# base-admin-panel — operating instructions

You have been pointed at a boilerplate. It builds a multi-tenant Next.js admin
panel from a short description, using a 33-agent fleet — 29 builders and 4
reviewers — across 5 waves behind 9 gates.

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

**If the user has not described anything yet** — ask for a paragraph. Not a
specification: a paragraph. What the panel is for, roughly how many tenants, who
logs in and how. `A00` will resolve the rest and ask only the questions whose
answers change the build.

**If the user is asking a question about this boilerplate** rather than asking
you to run it — answer from `spec/requirements.md` and the relevant `spec/`
document. Do not start a build to answer a question.

## The map

| File | What it is |
|------|------------|
| `prompts/00-master-orchestrator.md` | How the build runs. Read this first. |
| `spec/requirements.md` | 354 requirements with stable IDs. The source of truth. |
| `spec/agents.md` | The fleet: agent IDs, waves, who publishes and consumes what. |
| `contracts/ownership.md` | Who owns which path. The routing table for tasks and findings. |
| `contracts/README.md` | Contract law. Why 16 agents can build at once. |
| `gates/gate-ladder.md` | G0–G8. |
| `.claude/agents/` | The agent prompts themselves. |
| `.claude/skills/` | `build-orchestrate`, `contract-guard`, `version-guard`, `visual-qa-cdp`, `supply-chain-audit`, `release-build`. |

## Rules that are not negotiable

1. **Cite requirement IDs.** Never refer to a requirement in prose alone. It is
   `REQ-GRD-08`, not "the grid preference thing". Gates verify by ID.
2. **No version from memory.** Every version is validated against the
   authoritative registry and recorded in `versions/manifest.json` with the
   source URL and timestamp (REQ-VER-02). A version you remember is wrong.
3. **Ten mockups, then stop.** No production UI code before a human names the
   winning layout (REQ-MOC-05). Present the screenshots in the chat reply, not
   just to disk (REQ-MOC-04).
4. **Single ownership.** Write only inside your owned paths. Writing outside them
   is a build defect, not a merge conflict (REQ-CTR-04).
5. **Additive-only after the G3 freeze.** No rename, no removal, no retype, no
   optional-to-required. A breaking change needs orchestrator arbitration and a
   version (REQ-CTR-03).
6. **Nothing self-approves.** The agent that wrote it never votes on it
   (REQ-GAT-07).
7. **Screenshots for anything visual.** Playwright over CDP, multiple points
   during the run, 390/834/1440, light and dark, presented in the reply
   (REQ-TST-02..04).
8. **Encrypted everywhere.** Nothing enters or leaves the server in cleartext,
   including inside the compose network (REQ-SEC-01).
9. **Commit, push, bump, log.** Every build bumps the semver and updates
   `CHANGELOG.md`, `README.md`, `SECURITY.md` and `TODO.md` — and only `A22` may
   touch those files (REQ-REL-01..08).

## Where this folder sits

**This folder becomes the project root. It is not a folder you add to a
project.** `contracts/ownership.md` opens with a *Workspace root* section that
assigns the workspace manifest, the lockfile, the toolchain pin,
`.github/workflows/**` and `README.md` / `CHANGELOG.md` / `SECURITY.md` /
`TODO.md` / `VERSION` to agents. The build writes the application beside these
documents, at the paths the ownership map names with no prefix.

Three consequences, and the first one is destructive if you miss it:

1. **Copy this folder out of the collection before you build in it.** A build in
   place overwrites the boilerplate's own `README.md` with the generated
   project's, and drops the workspace manifest and CI workflows into the
   collection repository. Clone or copy it to where the new project should live,
   then start there. The repository README has the one-line command.
2. **Do not nest it inside an existing project.** Every path here is relative to
   this folder, so at `yourproject/this-folder/` the ownership map's
   `Cargo.toml` and `.github/workflows/**` are ambiguous between two roots, and
   an agent will pick one silently. If you find yourself running inside a
   subdirectory of a larger project, **stop and say so** rather than guessing a
   prefix. To add what this produces to an existing system, build it as its own
   repository and integrate at the API or deployment boundary.
3. **`spec/`, `contracts/`, `gates/` and `compliance/` stay.** They are not
   scaffolding to delete once the app exists. They are the register every gate
   verdict cites, the frozen contract the code is built against, and the CRA
   conformity evidence, which has to ship with the product rather than live in
   whatever repository the prompt structure came from.

## This folder is self-contained

Nothing here reaches outside `boilerplates/base-admin-panel/`. If you find
yourself wanting a file from a sibling directory, that is a bug — someone will
clone this folder on its own.

## Style

Decide. "Consider using X" is a failed spec; write "we use X, because Y". Prefer
a command, a path, a schema or a number over an adjective. State failure modes
bluntly: what breaks, and what to do instead.
