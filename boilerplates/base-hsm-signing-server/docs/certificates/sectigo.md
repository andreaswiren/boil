# Sectigo — customer HSM workflow

Official current references:

- Code signing products/requirements: https://www.sectigo.com/ssl-certificates-tls/code-signing
- Enterprise code-signing solution: https://www.sectigo.com/enterprise-solutions/certificate-manager/code-signing-solutions
- SCM key attestation procedure: https://www.sectigo.com/faqs/detail/key-attestation-for-code-signing
- SCM documentation: https://docs.sectigo.com/scm/scm-administrator/understanding-code-signing-certificates

## Important compatibility check

Sectigo publishes explicit lists of supported attestation HSM/token types for some SCM workflows. **Do not assume Nitrokey HSM 2 is accepted merely because it is hardware-backed.** Obtain written confirmation for the exact customer-HSM workflow and attestation method before creating the production key.

## SignZone procedure

1. Confirm exact Nitrokey/SmartCard-HSM support and attestation requirements with Sectigo or your Sectigo partner.
2. Complete organization/authority verification.
3. Initialize HSM + DKEK before production key creation.
4. Generate the non-exportable key on the HSM.
5. Generate CSR and the CA-required attestation evidence using the approved procedure.
6. Submit CSR/attestation in Sectigo Certificate Manager or the applicable enrollment flow.
7. Download the issued certificate/chain and import it into the matching HSM object.
8. Verify key match, EKU, chain, expiry and test signature before activating the signing profile.
9. Track renewal/reissue and revocation metadata in SignZone.
