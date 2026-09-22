# Remote PKCS#11 Compatibility

Some existing tools only support PKCS#11. Provide an optional client-side PKCS#11 module/OpenSSL provider that presents configured virtual signing identities and forwards only approved digest-sign operations to SignZone REST/mTLS. It MUST NOT enumerate arbitrary HSM objects, expose unwrap/decrypt/keygen mechanisms, proxy raw CK_FUNCTION_LIST calls, or accept token PINs. The "PIN" presented to a legacy application, if required by the ABI, is a local unlock/credential handle and never the Nitrokey PIN.
