# Identity and Authentication

Local auth requires password+TOTP or passkey. Entra OIDC is supported. Sensitive operations use recent step-up authentication. Service/CI access uses workload OIDC or mTLS. Stable external identities are provider+tenant+subject, never email alone.
