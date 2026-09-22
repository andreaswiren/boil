# Threat Model

## Assets
Publisher identity, non-exportable signing keys, approvals, policies, audit evidence, HSM PIN/DKEK material, administrator identities, appliance integrity.

## Primary threats
Compromised agentic build submitting malware; signing-oracle abuse; stolen admin session; push fatigue; replayed approval; HSM PIN leakage; DKEK leakage; root compromise; SSRF from timestamp/OIDC URLs; setup-mode takeover; network lockout; audit deletion; supply-chain dependency compromise.

## Mandatory mitigations
Digest-bound requests, workload identity validation, explicit policy, independent approval, transaction challenge/WebAuthn, strict egress destinations, provider allowlists, HSM isolation, no raw remote PKCS#11, Unix sockets, root allowlist daemon, append-only audit chain, setup token, rollback watchdog, service sandboxing, dependency lock/review.

