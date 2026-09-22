# SignZone (SZ) Agentic Boilerplate

SignZone is a high-security, self-hosted code-signing appliance for Debian 13 (Trixie). This boilerplate is designed for agentic AI development and deliberately separates the web UI, HSM signing plane, privileged OS management plane, and local DCUI.

## Starting a build

**There is no command to run.** Point an agent at this directory and describe
what you want signed and who approves it. It reads `AGENTS.md` (or `CLAUDE.md` —
they are identical), which sends it to `prompts/00-master-orchestrator.md`.

```bash
cd my-signer      # this directory: the project root, not a folder inside it
claude            # or muse, or any agent pointed here
```

> We sign Windows installers and PowerShell modules from GitHub Actions. Two
> release engineers must approve anything signed with the production cert.
> Nitrokey HSM 2, one primary and one DR unit, appliance not internet-facing.

That paragraph is the trigger. **This directory is the project root** — if you
copied it into a subfolder of an existing project, read *Where this folder sits*
in `AGENTS.md` first.

> **Status:** development boilerplate / architecture skeleton. Security-critical functions are intentionally represented by typed interfaces, policy documents, and safe stubs until implemented and independently reviewed.

## Core architecture

- **Next.js 16+ standalone** web/admin/PWA application
- **PostgreSQL** for application state, approvals, identities, and audit index
- **Rust `signzone-signerd`** for Nitrokey HSM 2 / OpenSC / PKCS#11 operations
- **Rust `signzone-osd`** for a tightly allowlisted privileged OS control plane
- **Rust `signzone-dcui`** for a persistent ESXi-like local console
- **Nitrokey HSM 2** as primary signer with DKEK-based DR replication to a secondary device
- **osslsigncode + OpenSSL 3 PKCS#11 provider** for Linux-hosted Authenticode
- **REST API / workload identity** for CI integrations
- **Optional remote PKCS#11 compatibility client/provider** that maps constrained signing operations to the SignZone API without exposing the HSM directly

## Start development

```bash
npm install
npm run dev
```

Rust services:

```bash
cargo build --manifest-path services/Cargo.toml
```

## Appliance installation

On a dedicated Debian 13 Trixie host:

```bash
git clone <your-signzone-repository>
cd signzone
sudo ./install.sh
```

The installer builds the application and services, configures PostgreSQL/nginx/systemd, starts SignZone in one-time **Setup Mode**, and prints an HTTPS setup URL plus a one-time setup token and bootstrap TLS fingerprint.

## Agentic workflow

Start with:

1. `AGENTS.md`
2. `.claude/CLAUDE.md`
3. `spec/requirements.md`
4. `spec/00-product.md`
5. `spec/01-architecture.md`
6. `spec/02-threat-model.md`
7. `agents/orchestrator.md`

No implementation agent may weaken a requirement merely to make a test pass. Security-significant changes require the security-review and adversarial-review agents.

## Important security invariant

**SignZone must never expose a generic remote shell, generic command execution endpoint, raw network-accessible PKCS#11 interface, private key export path, HSM PIN in a command line/URI, or browser-accessible root console.**

## Repository knowledge layout

- `agents/` detailed role contracts
- `skills/` project skill library
- `.claude/agents/` Claude Code agent adapters
- `.claude/skills/` Claude Code auto-discovered skill mirror
- `requirements/` stable requirement IDs and traceability
- `spec/` architecture/security/behavior contracts

