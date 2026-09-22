# Nitrokey HSM 2 operations

SignZone uses PC/SC + OpenSC + SmartCard-HSM support. Production keys are generated on the device. Device serial/identity is recorded and mapped to Primary/DR roles.

Useful discovery commands during engineering:

```bash
opensc-tool --list-readers
pkcs11-tool --module /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so --list-slots
sc-hsm-tool --list-dkek-shares
```

Do not run initialization/import/delete commands from generic troubleshooting UI. Those are explicit ceremony operations with step-up auth, device identity checks and audit.
