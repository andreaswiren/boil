# Implementation phases

1. **Contracts & threat model** — OpenAPI, RPC, DB, policy, audit schemas.
2. **Web foundation** — auth, RBAC, dashboard design system, setup state.
3. **Signer foundation** — Unix RPC, HSM discovery, safe sessions, mock PKCS#11.
4. **Authenticode** — osslsigncode provider, RFC3161, verification.
5. **Policies & approvals** — CI identity, state machine, PWA transaction approval.
6. **DKEK/DR** — primary/secondary ceremonies and restore tests.
7. **Appliance control** — osd, network rollback, nftables, updates, logs.
8. **DCUI & maintenance** — tty1 and break-glass workflow.
9. **Installer/upgrade** — clean Debian VM acceptance.
10. **Remote integrations** — REST CLI/SDK and constrained PKCS#11 provider.
11. **Audit/compliance** — tamper evidence, exports, remote SIEM.
12. **Release hardening** — adversarial review, SBOM/provenance, signed release.
