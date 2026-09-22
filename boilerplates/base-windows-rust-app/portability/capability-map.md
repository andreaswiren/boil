# Capability Map

What this build needs a runtime to be able to do. The structure declares the
**capability**; each runtime column says how that runtime provides it
(REQ-PORT-02).

The last column is the one that matters: where a runtime cannot provide a
capability, it names the requirements that become unverifiable on it
(REQ-PORT-03). An unverifiable requirement is reported at the gate, never
silently dropped.

## File and shell

| Capability | Why the structure needs it | Claude Code | If unavailable |
|------------|---------------------------|-------------|----------------|
| Read a file | Every agent reads the register, its spec and the frozen contract | `Read` | Nothing works. This is the floor. |
| Write a file | Agents produce crates, specs and reports | `Write` | Nothing works. |
| Edit in place | Surgical changes rather than rewrites (REQ-GAT-06) | `Edit` | Whole-file rewrites lose the Karpathy lens's surgical-change check |
| Run a shell command | `cargo build`, `cargo test`, `cargo clippy`, `curl` | `Bash` | H2, H4, H5 and every `cargo`-based definition of done become unverifiable |
| Search file contents | The FFI-boundary lint, the raw-colour lint, the route scan | `Grep` | REQ-FND-03 and REQ-DSN-09 degrade from enforced to requested |
| List files by glob | Ownership checks, mockup discovery | `Glob` | Ownership violations stop being mechanically detectable (REQ-CTR-04 equivalent) |

## Network

| Capability | Why | Claude Code | If unavailable |
|------------|-----|-------------|----------------|
| Fetch a URL | crates.io and the Rust release channel (REQ-VER-02) | `WebFetch` / `curl` via shell | **H2 cannot pass.** Versions would come from memory, which REQ-VER-02 exists to forbid |
| Search the web | Confirming CRA/CER dates and obligations (REQ-CRA-06) | `WebSearch` | B13 cannot verify a date externally, so every compliance date must be marked unverified |

## Agents

| Capability | Why | Claude Code | If unavailable |
|------------|-----|-------------|----------------|
| Dispatch a subagent | The fleet model | `Agent` | The whole structure collapses to one agent reading 23 prompts in sequence. It still works; it is slower and loses the independence the gates depend on |
| Dispatch several **concurrently** | Wave 3 is 9-wide | Multiple `Agent` calls in one message | Waves run sequentially. Artefacts are identical, only wall-clock changes — record it in the cost table rather than pretending |
| Restrict an agent's tools | Gate agents must not write product code (REQ-GAT-07) | `tools:` frontmatter | **REQ-GAT-07 degrades from a structural guarantee to a prompt-level request.** Report it; do not treat the gate as equivalent |
| Per-agent model selection | B18 runs on the cheapest tier (REQ-COST-03) | `model:` frontmatter | Cost reporting still works, it just costs more than it measures. Note it in the table |
| Load a skill on demand | The orchestration and guard skills | `Skill` | Read the skill file directly; it is Markdown |

## Reporting and state

| Capability | Why | Claude Code | If unavailable |
|------------|-----|-------------|----------------|
| Report token usage | REQ-COST-01 | Task usage in the agent result | Cells read `unreported` and the total is marked incomplete (REQ-COST-04). **Never write `0`** — a zero is a claim |
| Persist state between turns | `build/` carries intake, approvals, verdicts, costs | The filesystem | Nothing works: the gate ladder is stateful by design |
| Present an image in a reply | Mockup and DPI screenshots (REQ-TST-04, REQ-MOC-05) | Image paths in the user-facing reply | H1 and H5 lose their human-verifiable evidence. The human decision at H1 still needs the screenshots somehow — state how, or the gate is unverifiable |

## The Windows-specific gap

This build targets Windows, and most agent runtimes run on Linux. That is not a
portability problem for the *prompt structure* — writing Rust does not require
Windows — but it does bound what any runtime can verify:

| Requirement | Verifiable on a non-Windows host? |
|-------------|----------------------------------|
| `cargo check --target x86_64-pc-windows-msvc` | Partially — cross-checking catches type errors, not behaviour |
| REQ-INST-* (install, upgrade, uninstall) | **No.** Needs a clean Windows image (REQ-TST-02) |
| REQ-SVC-* (service lifecycle) | **No.** Needs Windows |
| REQ-TRY-02 (Explorer restart) | **No.** Needs Windows |
| REQ-DSN-11 / REQ-TST-08 (DPI matrix) | **No.** Needs Windows |
| REQ-UPD-06 (atomic swap across power loss) | **No.** Needs Windows |

So H5 requires a Windows runner regardless of which agent runtime drives the
build. Say that at H0 rather than discovering it at H5: a build that reaches
integration with no Windows target available has nowhere to go.
