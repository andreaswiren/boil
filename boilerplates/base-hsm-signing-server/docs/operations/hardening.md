# Appliance hardening

The `scripts/harden.sh` skeleton is intentionally conservative. Final hardening must be validated on Debian 13 and include: minimal packages, nftables default-deny inbound, controlled egress, AppArmor for SignZone services, auditd, protected boot where available, root SSH disabled by default, service sandboxing, secure sysctl, time sync, unattended security update policy, TLS-only management, and periodic configuration drift checks.
