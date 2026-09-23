# File Ownership

Ownership is primary responsibility, not exclusive access. Cross-boundary edits require owner review.

- **orchestrator** — architecture,requirements,delivery
- **product-owner** — requirements,ux
- **security-architect** — security,architecture
- **threat-modeler** — security,testing
- **nextjs-architect** — nextjs,architecture
- **ui-ux-engineer** — ui,nextjs
- **database-architect** — database,architecture
- **auth-identity-engineer** — auth,security
- **rbac-policy-engineer** — security,policy
- **rest-api-engineer** — api,security
- **ci-identity-engineer** — oidc,ci,security
- **signing-engineer** — signing,crypto
- **hsm-pkcs11-engineer** — hsm,pkcs11
- **dkek-recovery-engineer** — hsm,dkek
- **authenticode-engineer** — signing,authenticode
- **remote-provider-engineer** — pkcs11,api
- **pwa-approval-engineer** — pwa,auth
- **audit-engineer** — audit,security
- **rust-service-engineer** — rust,services
- **os-control-engineer** — linux,security
- **linux-hardening-engineer** — linux,security
- **dcui-engineer** — rust,tui
- **installer-engineer** — linux,installer
- **setup-wizard-engineer** — nextjs,installer
- **certificate-lifecycle-engineer** — pki,docs
- **observability-engineer** — ops,security
- **backup-restore-engineer** — backup,ops
- **test-automation-engineer** — testing
- **security-reviewer** — security,review
- **adversarial-reviewer** — security,review
- **documentation-engineer** — docs
- **release-engineer** — release,ci
- **dependency-license-reviewer** — supply-chain,review

## Build-state paths

These are not product code, and they are **committed**: the reviews and the
release record cite them as evidence, and evidence nobody can open is not
evidence.

| Path | Owner | Note |
|------|-------|------|
| `build/validation/<phase>/<agent>.json` | the agent that produced the hand-off | Its own validation block and output tail (`SZ-VAL-002`, `SZ-VAL-012`). |
| `build/validation/<gate>.json` | orchestrator | The whole-tree record per phase gate. |
| `build/validation/req-coverage.md`, `build/validation/unverified.md` | test-automation-engineer | Generated. Every `MUST` to its citing test; every REQ ID no available environment could verify (`SZ-TEST-001`, `SZ-TEST-007`). |
| `build/validation/suppressions.md` | orchestrator | Per gate, per class, with the delta (`SZ-VAL-007`). |
| `build/screenshots/**` | ui-ux-engineer | Images, sidecars and `index.json`. A capture feed, not a gate deliverable (`SZ-CAP-001` … `SZ-CAP-008`). Scanned for secrets before writing (`SZ-CAP-007`). |
