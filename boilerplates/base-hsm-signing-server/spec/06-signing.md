# Signing Engine

Signing is an explicit state machine: received -> validating -> denied/awaiting approval -> approved -> signing -> timestamping -> verifying -> completed/failed. Authenticode uses osslsigncode with OpenSSL 3 provider, OpenSC PKCS#11 module, SHA-256+ and RFC3161 (`-ts`). Signatures are always verified before success.
