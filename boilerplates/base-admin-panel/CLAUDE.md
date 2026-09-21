# base-admin-panel — operating instructions

You have been pointed at a boilerplate. It builds a multi-tenant Next.js admin
panel from a short description, using a 24-agent fleet across 5 waves behind 9
gates.

## Start here

**If the user has described what they want** — even in a sentence — load the
orchestration skill and begin:

```
/build-orchestrate
```

That turns this session into the orchestrator. Its full instructions are
`prompts/00-master-orchestrator.md`.

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
| `spec/requirements.md` | 215 requirements with stable IDs. The source of truth. |
| `spec/agents.md` | The fleet: agent IDs, waves, who publishes and consumes what. |
| `contracts/ownership.md` | Who owns which path. The routing table for tasks and findings. |
| `contracts/README.md` | Contract law. Why 13 agents can build at once. |
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

## This folder is self-contained

Nothing here reaches outside `boilerplates/base-admin-panel/`. If you find
yourself wanting a file from a sibling directory, that is a bug — someone will
clone this folder on its own.

## Style

Decide. "Consider using X" is a failed spec; write "we use X, because Y". Prefer
a command, a path, a schema or a number over an adjective. State failure modes
bluntly: what breaks, and what to do instead.
