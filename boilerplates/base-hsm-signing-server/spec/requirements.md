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
| SZ-SEC-006 | MUST | Failed-authentication rate limits are stated as numbers, not as the word "rate limiting": **one failed unlock attempt per second per source address**, and **one failed authentication per second per source address and username** (NetHSM's figures, `docs/system-design.md` §Rate Limiting). A limit without a number cannot be tested, and an untested limit is an assumption. |
| SZ-SEC-011 | MUST | The appliance **refuses to become operational without its entropy sources**. On first provisioning, the Device Key is not generated until the TPM RNG and the kernel CSPRNG have both been confirmed healthy; if a source required at boot is absent, the system logs to the console and stops in a non-operational state rather than proceeding with degraded entropy. NetHSM halts rather than generating a key it cannot vouch for, and a signing key generated from weak entropy is unrecoverable — it must be rotated, and everything it signed re-examined. |


## HSM — Nitrokey HSM 2, PKCS#11 and DKEK

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-HSM-001 | MUST | Nitrokey HSM 2 shall be supported through OpenSC/PCSC/PKCS#11 on Debian 13. |
| SZ-HSM-002 | MUST | The system shall support a designated primary and secondary/DR Nitrokey HSM 2. |
| SZ-HSM-003 | MUST | DKEK shall be configured before exportable production keys are generated. |
| SZ-HSM-004 | MUST | DKEK share ceremonies, wrapped-key export/import, and DR restore verification shall be supported without persisting plaintext shares. |
| SZ-HSM-005 | MUST | HSM devices shall be identified by stable identity/serial rather than enumeration order. |
| SZ-HSM-006 | MUST | The appliance has four explicit states — `Unprovisioned`, `Locked`, `Operational`, `Failed` — and the state is a first-class value in the API, the DCUI and the audit log, not an inference from whether requests succeed. |
| SZ-HSM-007 | MUST | **A provisioned appliance boots Locked.** The application, audit and key-metadata stores are encrypted at rest under a *Domain Key* that exists only in memory and is never written to disk unencrypted. A disk removed from the appliance yields ciphertext. This is the control that makes the difference between an appliance and a server with an HSM in it. |
| SZ-HSM-008 | MUST | The Domain Key is recovered at boot from a TPM-sealed *Device Key* using two slots: slot 1 holds it wrapped to the Device Key alone (**unattended boot**), slot 0 wrapped to an *Unlock Key* which is itself wrapped to the Device Key (**attended boot**). Enabling unattended boot populates slot 1; disabling it overwrites slot 1. A failed unattended decryption **falls back to attended**, never to open. Neither the Unlock Passphrase nor the derived Unlock Key is ever persisted. |
| SZ-HSM-009 | MUST | `POST /unlock` and `POST /lock` are API operations. `lock` returns the appliance to ciphertext without a reboot, so an operator who suspects compromise has an action available that does not require physical access. |
| SZ-HSM-010 | MUST | The Device Key is sealed by the TPM against firmware measurements, so it does not unseal under modified firmware and a disk image is not portable to different hardware. Where no TPM is present the appliance starts in attended mode only and states that unattended boot is unavailable — it does not silently fall back to an unsealed key on disk. |
| SZ-HSM-011 | MUST | Backups are **double-encrypted and the backup role cannot read them**. An administrator sets a Backup Passphrase; the backup endpoint does not exist until they have. The outer layer is the derived Backup Key; the inner layers are the already-encrypted stores. Reading a backup requires **both** the Backup Key and an Unlock Key, so an automated client holding only backup credentials can fetch backups indefinitely and decrypt none of them. |
| SZ-HSM-012 | MUST | Restore behaviour is specified and its destructiveness is stated before it runs. Restoring into an operational appliance is a **partial restore**: users, keys and namespaces present on the device and absent from the backup are **removed**, and device-local configuration (network, TLS) is not touched. Restoring to different hardware requires the Unlock Passphrase current when the backup was taken. A backup taken by any previous version must remain restorable. |


## AUTH — Identity, step-up and RBAC

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-AUTH-001 | MUST | Local production users shall use password+TOTP or passkey; password-only login is prohibited. |
| SZ-AUTH-002 | MUST | Microsoft Entra ID OIDC login shall be supported using stable tenant+subject identities. |
| SZ-AUTH-003 | MUST | Sensitive actions shall require recent step-up authentication. |
| SZ-AUTH-004 | MUST | CI automation shall prefer workload OIDC, then mTLS, then narrowly scoped service credentials. |
| SZ-AUTH-005 | MUST | Tag-based key restriction is enforced **at the key**, independently of the policy engine: a key carries tags, a user carries tags, and use requires a match. Two independent authorization axes mean a policy-engine mistake does not by itself unlock every key. |
| SZ-AUTH-006 | SHOULD | Namespaces separate users and keys inside one appliance, so two teams can share a device without sharing a key store. Blocking unless intake states the appliance is single-tenant. |
| SZ-AUTH-007 | MUST | The role set is explicit and each role's power is stated: `Administrator`, `Operator`, `Metrics`, `Backup`. A role that is not in this list does not exist, and "admin" is not a synonym for "can read key material". |


## API — REST signing API and clients

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-API-001 | MUST | A versioned REST API with OpenAPI documentation shall support signing request submission, approval state, retrieval and verification. |
| SZ-API-002 | MUST | API signing requests shall bind repository/ref/build identity, artifact digest, profile and requester identity. |
| SZ-API-003 | MUST | The optional remote PKCS#11 compatibility client shall be policy constrained and shall not expose arbitrary HSM mechanisms or objects. |
| SZ-API-004 | MUST | REST mutating operations shall support idempotency keys where replay could duplicate effects. |
| SZ-API-005 | MUST | `GET /health/alive`, `/health/ready`, `/health/state` and `/health/diagnose` exist, and `state` is readable **without authentication**. A client that cannot distinguish "locked" from "broken" retries against a locked appliance forever, and the operator sees an outage instead of a prompt. |
| SZ-API-006 | MUST | `GET /metrics` is served to a dedicated `Metrics` role whose only power is reading counters. Monitoring never holds an operator credential; a standing privilege granted for graphing is a standing privilege. |
| SZ-API-007 | MUST | The key-object certificate lifecycle is on the API, not a manual procedure: retrieve the public key, generate a CSR for a key that never leaves the HSM, and store, retrieve and delete the issued certificate against that key. A signing appliance whose CSR step happens by hand is an appliance whose CSR step is eventually done wrong. |


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
| SZ-OS-006 | MUST | System updates are A/B with a **separate commit step**: the image is written to the inactive root while its signature and downgrade eligibility are verified, and the commit operation is only available once both have passed. Commit arms a one-shot boot; a failure to boot falls back to the previous root automatically. Downgrades that would migrate data backwards are refused. Updates are applied deliberately by an administrator — there is no over-the-air update path. |
| SZ-OS-007 | MUST | Factory reset is a defined, audited operation that destroys the Device Key and every encrypted store, so decommissioning is a procedure rather than an improvisation. Destroying the Device Key is what makes the remaining disk contents unrecoverable. |
| SZ-OS-008 | MUST | The root filesystem is **read-only and integrity-verified** — a `dm-verity` image whose root hash is carried in the signed UKI, in an A/B pair. Modification fails the read rather than being discouraged, so an attacker with code execution cannot persist into the root, and recovery from a corrupted root is a reboot into the other partition rather than a rebuild. All mutable state lives on one encrypted volume, so "is data at rest encrypted" has a single answer. |
| SZ-OS-009 | MUST | The state volume is LUKS2 (AES-256-XTS) with its key **sealed to the TPM against PCR 7 and PCR 11**, and additionally to a PIN in the attended profile. Because PCR 11 carries the boot-phase measurements, sealing against the pre-`ready` value means an attacker who obtains root on the *running* appliance cannot unseal it: the TPM refuses a policy that no longer matches. A recovery key is generated at provisioning, shown once and never stored on the appliance, and TPM re-enrolment happens inside the update transaction before commit — a kernel update changes the measurement, and that is the control working, not a fault. |
| SZ-OS-010 | MUST | The hardening posture is **asserted by tests, not described**: the root rejects writes, the disk refuses to unlock with Secure Boot disabled, the disk refuses to unlock from a shell on the running system, the nftables ruleset matches the committed policy including default-deny egress, every systemd unit carries a sandbox stanza, and AppArmor is in enforce for every profile. CIS benchmark deviations are recorded with a reason; a benchmark score is not a threat model. |


## INS — Installer and first-run setup

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-INS-001 | MUST | A root-run install.sh shall bootstrap a supported Debian 13 host from a git checkout. |
| SZ-INS-002 | MUST | Installation shall compile Next.js standalone output and Rust services, configure PostgreSQL/nginx/systemd and start one-time setup mode. |
| SZ-INS-003 | MUST | Setup mode shall use HTTPS, a cryptographically random one-time token, and become unavailable after initialization. |
| SZ-INS-004 | MUST | Installer and upgrade actions shall be idempotent where practical and shall not disable TLS verification. |
| SZ-INS-005 | MUST | Initial provisioning is available as an API operation and not only through the setup wizard, so a fleet can be provisioned reproducibly rather than by a human repeating a browser flow. It remains one-shot: once provisioned, the endpoint is gone until a factory reset (SZ-OS-007), which is the same property the wizard has (SZ-INS-003). |


## DOC — Documentation

| ID | Status | Requirement |
|----|--------|-------------|
| SZ-DOC-001 | MUST | The repository shall document REST signing from Linux, Windows and CI systems. |
| SZ-DOC-002 | MUST | The repository shall document local OpenSSL 3/PKCS#11/osslsigncode signing without placing HSM PINs in commands or URIs. |
| SZ-DOC-003 | MUST | The repository shall document DigiCert and Sectigo code-signing enrollment/import procedures and link to current official provider documentation. |

