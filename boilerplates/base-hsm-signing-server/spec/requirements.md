# base-hsm-signing-server — Requirement Register

Every requirement has a stable ID. Nothing in this boilerplate refers to a
requirement by prose alone — agents cite `SZ-<DOMAIN>-<nnn>`, gates verify by ID,
and `spec/traceability.csv` maps every ID to an owner and a gate.

**The ID prefix here is `SZ-`, not `REQ-`.** It arrived that way and it is
load-bearing across 161 documents, so renaming it would mean rewriting every
citation to gain nothing — which is the dangling-citation failure the convention
exists to prevent. `CONVENTIONS.md` §3 requires IDs that are stable and never
renumbered; it does not require one spelling, and the conformance check derives
the prefix from this file rather than assuming one.

Status: `MUST` (release-candidate blocking), `SHOULD` (blocking unless intake
waives it), `OPT` (enabled per intake answer). A `MUST` cannot be waived; the
build fails instead.

The prose behind each row is in `spec/requirements-functional-source.md` and
`spec/requirements-security-source.md`, which are the documents this register was
derived from and are kept as the rationale.

---


## FUN — Product & functional surface

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-FUN-001 | MUST | The system shall provide user and administrator dashboards for signing activity and appliance health. |
| SZ-FUN-002 | MUST | Signing requests shall follow an explicit server-side state machine. |


## SEC — Security posture

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-SEC-001 | MUST | Production private signing keys shall remain non-exportable except encrypted DKEK-wrapped backup where supported and explicitly configured. |
| SZ-SEC-002 | MUST | The Next.js web process shall run unprivileged and shall not execute arbitrary OS commands or access HSM device nodes directly. |
| SZ-SEC-003 | MUST | No generic remote shell, command execution API, or raw network HSM/PKCS#11 interface shall be exposed. |
| SZ-SEC-004 | MUST | Security-sensitive operations shall fail closed and require explicit authorization. |
| SZ-SEC-005 | MUST | Secrets shall never be stored in logs, audit payloads, command-line arguments, URLs, browser storage, source control, or telemetry. |


## HSM — Nitrokey HSM 2, PKCS#11 and DKEK

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-HSM-001 | MUST | Nitrokey HSM 2 shall be supported through OpenSC/PCSC/PKCS#11 on Debian 13. |
| SZ-HSM-002 | MUST | The system shall support a designated primary and secondary/DR Nitrokey HSM 2. |
| SZ-HSM-003 | MUST | DKEK shall be configured before exportable production keys are generated. |
| SZ-HSM-004 | MUST | DKEK share ceremonies, wrapped-key export/import, and DR restore verification shall be supported without persisting plaintext shares. |
| SZ-HSM-005 | MUST | HSM devices shall be identified by stable identity/serial rather than enumeration order. |


## AUTH — Identity, step-up and RBAC

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-AUTH-001 | MUST | Local production users shall use password+TOTP or passkey; password-only login is prohibited. |
| SZ-AUTH-002 | MUST | Microsoft Entra ID OIDC login shall be supported using stable tenant+subject identities. |
| SZ-AUTH-003 | MUST | Sensitive actions shall require recent step-up authentication. |
| SZ-AUTH-004 | MUST | CI automation shall prefer workload OIDC, then mTLS, then narrowly scoped service credentials. |


## API — REST signing API and clients

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-API-001 | MUST | A versioned REST API with OpenAPI documentation shall support signing request submission, approval state, retrieval and verification. |
| SZ-API-002 | MUST | API signing requests shall bind repository/ref/build identity, artifact digest, profile and requester identity. |
| SZ-API-003 | MUST | The optional remote PKCS#11 compatibility client shall be policy constrained and shall not expose arbitrary HSM mechanisms or objects. |
| SZ-API-004 | MUST | REST mutating operations shall support idempotency keys where replay could duplicate effects. |


## PWA — Approval app

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-PWA-001 | MUST | The web app shall be installable as a PWA and support Web Push signing approval notifications. |
| SZ-PWA-002 | MUST | Push notifications alone shall never authorize signing; approval shall use a transaction-bound challenge code and/or WebAuthn step-up. |
| SZ-PWA-003 | MUST | Approval UI shall show artifact name/digest suffix, requester, repository/ref, signing profile and expiry before acceptance. |


## AUD — Audit and tamper evidence

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-AUD-001 | MUST | Security and signing actions shall create canonical append-only audit events with tamper-evident chaining/checkpoints. |
| SZ-AUD-002 | MUST | Audit events shall be exportable and optionally forwarded to remote syslog/SIEM. |


## OS — Linux appliance and OS control

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-OS-001 | MUST | A privileged Rust OS daemon shall expose only typed allowlisted appliance operations over a Unix socket. |
| SZ-OS-002 | MUST | Network/firewall management changes shall be transactional with automatic rollback unless confirmed. |
| SZ-OS-003 | MUST | SSH shall be disabled by default and normal administration shall be possible from structured web controls. |
| SZ-OS-004 | MUST | A persistent fullscreen local DCUI shall run on tty1. |
| SZ-OS-005 | MUST | Local maintenance console access shall require a separate physical-console maintenance credential with rate limiting and auto-relock. |


## INS — Installer and first-run setup

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-INS-001 | MUST | A root-run install.sh shall bootstrap a supported Debian 13 host from a git checkout. |
| SZ-INS-002 | MUST | Installation shall compile Next.js standalone output and Rust services, configure PostgreSQL/nginx/systemd and start one-time setup mode. |
| SZ-INS-003 | MUST | Setup mode shall use HTTPS, a cryptographically random one-time token, and become unavailable after initialization. |
| SZ-INS-004 | MUST | Installer and upgrade actions shall be idempotent where practical and shall not disable TLS verification. |


## DOC — Documentation

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-DOC-001 | MUST | The repository shall document REST signing from Linux, Windows and CI systems. |
| SZ-DOC-002 | MUST | The repository shall document local OpenSSL 3/PKCS#11/osslsigncode signing without placing HSM PINs in commands or URIs. |
| SZ-DOC-003 | MUST | The repository shall document DigiCert and Sectigo code-signing enrollment/import procedures and link to current official provider documentation. |

