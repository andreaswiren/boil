# Intake

You do not need to write a specification. You need to write a paragraph.

## What to say

```
Build me a panel for managing customer firewall estates across ~40 tenants.
Techs need to see devices, config backups and change history. Entra ID login.
```

That is enough. `A00` resolves the rest and asks you only the questions whose
answers change the build.

More examples that are all sufficient input:

```
An internal tool for our service desk to manage assets and licences.
One tenant, about 200 users, staff log in with Keycloak.
```

```
A multi-tenant portal where our clients see their own backup jobs and restore
history. They log in with email and passkeys. Needs Swedish.
```

```
MSP dashboard. We manage ~120 customers. Our engineers need everything, each
customer sees only their own estate. Collectors run on customer sites.
```

## What A00 will ask you

At most ten questions, and only the ones your paragraph left genuinely open.
Each has a default, which is used if you say "whatever you think".

| Question | Default if you do not answer |
|----------|------------------------------|
| App name (directory and display name) | Derived from your description |
| Tenant model: single, multi, or MSP-over-multi | Multi-tenant with a global tier |
| Which auth methods to enable | All three: password+TOTP, passkeys, OIDC |
| Which OIDC providers | All three configured, none enforced |
| Locales | `en` and `sv` |
| Core entities | Inferred from your description, confirmed back to you |
| Integrations to normalise | None at first; the engine ships regardless |
| Remote collectors needed | No (`REQ-OBS-01` is `OPT`) |
| Grid size classes | Small `[10,20,50,all]`, large `[20,50,100,200,500,all]` |
| Expected largest table | 100k rows — sets the server-side grid threshold |

Defaults that are **not** questions, because they are `MUST` requirements:

- MFA required (REQ-AUT-05)
- Multi-tenant RLS forced (REQ-RBA-04)
- Read/view logging on (REQ-AUD-02)
- Everything encrypted in transit (REQ-SEC-01)
- Europe/Stockholm, `YYYY-MM-DD HH:mm:ss` (REQ-TIM-01, REQ-TIM-02)
- Dark, light and system themes (REQ-UI-06)
- Telemetry off (REQ-SUP-06)

## What happens next

1. A00 confirms the resolved scope back to you.
2. Ten layout mockups are rendered and screenshotted. **You pick one.**
3. The build runs. You will be asked again only if a gate deadlocks
   (REQ-GAT-05) or a breaking contract change needs a human call.
