# sz-pkcs11 compatibility provider

Optional client-side compatibility layer for software that requires PKCS#11. The final implementation should be a Rust `cdylib` exposing a deliberately tiny CK_FUNCTION_LIST surface and mapping allowed sign operations to SignZone HTTPS. It must never proxy the Nitrokey module directly.

See `spec/08-remote-pkcs11.md` and `docs/integrations/remote-pkcs11-provider.md`.
