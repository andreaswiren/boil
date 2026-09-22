# DCUI

`signzone-dcui` owns tty1 and shows hostname/IP/URL/version/HSM/service/security status. Maintenance unlock is physical-console only, rate-limited, Argon2id-verified and auto-relocks. tty1 does not expose a normal getty by default. Emergency maintenance actions are minimal and audited locally even when PostgreSQL is unavailable.
