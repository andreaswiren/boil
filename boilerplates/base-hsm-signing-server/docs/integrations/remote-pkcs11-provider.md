# Using SignZone from software that expects PKCS#11

## Recommended model

Do **not** network-export the Nitrokey/OpenSC PKCS#11 module. Instead install the optional `sz-pkcs11` compatibility module on the client. It exposes only virtual SignZone signing identities and translates `C_Sign*` operations into authenticated SignZone REST signing requests.

```text
legacy app -> libszpkcs11.so -> HTTPS/mTLS/OIDC -> SignZone policy/approval -> Nitrokey
```

### Allowed compatibility surface

- enumerate configured virtual certificates/public keys;
- open a local virtual session;
- select a configured signing profile;
- digest-sign operations for explicitly supported mechanisms;
- return the resulting signature/status.

### Prohibited surface

- raw HSM slot/object enumeration;
- key generation/deletion;
- decrypt;
- unwrap/wrap;
- arbitrary mechanism forwarding;
- DKEK operations;
- exposing Nitrokey PIN/SO-PIN;
- bypassing SignZone approvals.

If an application insists on a PKCS#11 PIN, the value is a **local SignZone provider unlock credential** or OS keyring handle. It is never the Nitrokey PIN.

## OpenSSL 3 provider

A future `sz-provider.so` may expose an OpenSSL 3 signing provider backed by the same REST client. Keep that module separate from OpenSC's local `pkcs11-provider`; this avoids misleading clients into believing the remote SignZone service is the raw HSM.

See `clients/pkcs11-provider/README.md` and `spec/08-remote-pkcs11.md`.
