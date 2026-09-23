# Skills

Eighteen domain skills. Each carries the decisions and failure modes for its
area — not a restatement of the generic development process, which is in
`CLAUDE.md`.

They live here only. An earlier layout mirrored them under a top-level `skills/`
directory with an instruction to "keep both copies synchronized"; the copies had
already diverged, which is what duplicated sources of truth always do.

| Skill | Load it for |
|-------|------------|
| `dkek-ceremonies` | DKEK, key backup, DR — read it before writing anything a custodian follows |
| `hsm-pkcs11` | Device identity, sessions, mechanisms, PIN handling |
| `signing-policy` | Any authorization decision in the signing path |
| `identity-stepup` | Login, sessions, WebAuthn, OIDC, approval authentication |
| `pwa-approvals` | Mobile approval, push, transaction binding |
| `audit-tamper-evidence` | Any auditable action or event-schema change |
| `authenticode-linux` | Windows signing flows, timestamping |
| `rest-signing-api` | API and CI integration |
| `remote-pkcs11-compat` | The optional PKCS#11 compatibility module |
| `linux-appliance-hardening` | Verity root, LUKS2, TPM sealing, nftables, AppArmor |
| `os-control-rpc` | Any privileged appliance operation |
| `installer-setup` | Deployment and bootstrap |
| `dcui-ratatui` | The physical console |
| `nextjs-secure-admin` | Web tier |
| `shadcn-signzone-ui` | UI, and the approval screen's hard constraints |
| `postgres-drizzle` | Persistence |
| `certificate-providers` | CA enrollment and renewal |
| `security-review` | Before any security feature is called complete |

If a skill is not loaded, its `SKILL.md` is a plain file. Nothing here depends on
the skill mechanism (`spec/17-nethsm-parity.md` — Muse Code 1.3 does not load
skills).
