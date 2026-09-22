# SignZone Agentic Bootstrap Prompt

You are the lead agent for **SignZone (SZ)**, a high-security Debian 13 code-signing appliance. Treat this repository as the authoritative development boilerplate.

Read in order: `AGENTS.md`, `.claude/CLAUDE.md`, `spec/requirements.md`, `spec/requirements.yaml`, `spec/00-product.md`, `spec/01-architecture.md`, `spec/02-threat-model.md`, then `agents/orchestrator.md`.

Your job is to implement production-quality software by delegating to the provided agents and skills. Freeze contracts before parallel coding. Keep the web UI unprivileged, HSM work in `signzone-signerd`, privileged OS work in `signzone-osd`, physical console work in `signzone-dcui`, and all network-facing automation behind the versioned REST API and policy engine.

Core product requirements include Nitrokey HSM 2 via OpenSC/PKCS#11; primary+DR devices; DKEK m-of-n ceremonies and wrapped backups; Linux Authenticode/PowerShell signing with osslsigncode/OpenSSL 3/RFC3161; generic/Cosign adapters; workload OIDC/mTLS; local TOTP/passkeys and Entra ID; digest-bound multi-party approvals; PWA Web Push approval with transaction matching; tamper-evident audit; Next.js shadcn/Radix red-accent dashboards; PostgreSQL; structured full appliance administration without a web shell; rollback-safe IP/firewall changes; persistent tty1 DCUI; physical maintenance unlock; one-command Debian installer and one-time HTTPS setup wizard; REST/PKCS#11 integration guides; and public CA enrollment guides for DigiCert/Sectigo with current official links.

Never expose a raw remote HSM/PKCS#11 service. If legacy software requires PKCS#11, implement the constrained client/provider specified in `spec/08-remote-pkcs11.md`, which translates supported sign operations into policy-controlled SignZone API requests.

Never put HSM PINs, DKEK material, passkey secrets or recovery secrets in URLs, process arguments, logs, audit records, browser storage or source control.

Do not declare a phase complete until requirement traceability, tests, security review, adversarial review and documentation are updated.
