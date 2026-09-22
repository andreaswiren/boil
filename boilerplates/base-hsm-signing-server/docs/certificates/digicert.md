# DigiCert CertCentral — customer HSM workflow

Official current references:

- Request Code Signing certificate: https://docs.digicert.com/en/certcentral/order-and-manage-certificates/request-certificates/request-a-code-signing-or-ev-code-signing-certificate/request-code-signing-certificate.html
- Code-signing request overview: https://docs.digicert.com/en/certcentral/order-and-manage-certificates/request-certificates/request-a-code-signing-or-ev-code-signing-certificate.html
- Provisioning methods: https://docs.digicert.com/en/certcentral/order-and-manage-certificates/manage-certificate-orders/identify-the-provisioning-method-on-a-code-signing-order.html
- Renewal: https://docs.digicert.com/en/certcentral/order-and-manage-certificates/manage-certificate-orders/renew-your-code-signing-certificate.html

## SignZone procedure

1. Confirm with DigiCert that the exact Nitrokey HSM 2/firmware/OpenSC configuration is acceptable for **Install on HSM** and ask what key-attestation/evidence they require.
2. Complete organization/verified-contact validation in CertCentral.
3. Initialize the production HSM/DKEK through a SignZone ceremony.
4. Generate a new signing key **inside the HSM**. Follow the CA's current minimum algorithm/size; public requirements may change.
5. Generate a CSR from that non-exportable key. Do not generate a software private key/PFX first.
6. Submit the request choosing the HSM/customer hardware provisioning method and supply any required attestation/evidence.
7. After issuance, download the certificate/chain from CertCentral (certificate material is public) and import it into the matching HSM object ID through SignZone.
8. Verify public-key match, chain, EKU, expiration, and a test signature before enabling the production signing profile.
9. Record order/provider metadata and renewal reminder in SignZone without storing CA account passwords.

As of 2026 DigiCert documents a 459-day maximum public code-signing certificate validity. Always verify current CA documentation during implementation/renewal.
