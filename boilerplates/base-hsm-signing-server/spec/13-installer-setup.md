# Installer and Setup

`install.sh` validates Debian 13, installs runtime/build dependencies, creates users/directories, initializes PostgreSQL, builds Next.js standalone and Rust services, installs systemd/nginx/nftables/AppArmor, creates temporary TLS, generates one-time setup token, starts setup-only mode and prints URL+fingerprint. Setup completion atomically disables bootstrap endpoints/token.
