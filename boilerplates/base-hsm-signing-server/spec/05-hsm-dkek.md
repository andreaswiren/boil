# Nitrokey HSM 2 and DKEK

Use PC/SC + OpenSC and stable serial identities. Generate production keys on-device. DKEK configuration precedes exportable key generation. DKEK shares are never persisted. Wrapped backups may be stored with checksum/metadata. Restores require matching DKEK domain/check value, explicit step-up, audit, and verification on the DR HSM.
