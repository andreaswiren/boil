# Local Linux signing with Nitrokey HSM 2 and osslsigncode

This mode is for the SignZone signer host or an explicitly approved directly attached HSM workstation. Remote clients should normally use the SignZone REST API.

## Inspect the token

```bash
pkcs11-tool --module /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so --list-slots
pkcs11-tool --module /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so --login --list-objects
```

## Never put the HSM PIN in a PKCS#11 URI

Avoid examples such as:

```text
pkcs11:...;pin-value=...
pkcs11:...;pin=...
```

and avoid `-pass PIN` on a command line because process arguments can be observable.

Use a protected credential source. Example using a root/service-readable tmpfs credential file:

```bash
osslsigncode sign \
  -provider /usr/lib/x86_64-linux-gnu/ossl-modules/pkcs11prov.so \
  -pkcs11module /usr/lib/x86_64-linux-gnu/opensc-pkcs11.so \
  -pkcs11cert 'pkcs11:token=SignZone;object=CodeSigning-Cert' \
  -key 'pkcs11:token=SignZone;object=CodeSigning-Key' \
  -readpass /run/credentials/signzone-hsm-pin \
  -h sha256 \
  -n 'Your Application Name' \
  -ts 'https://timestamp.example-ca.com/' \
  -in unsigned_app.exe \
  -out signed_app.exe
```

Use RFC3161 (`-ts`) rather than legacy Authenticode timestamping (`-t`) unless a specific compatibility requirement has been documented.

Verify:

```bash
osslsigncode verify -in signed_app.exe
```

SignZone production code must additionally enforce policy, audit, post-sign hash calculation, trusted timestamp endpoint allowlists, and signature verification.
