# Generic public CA enrollment checklist

Before purchasing a certificate, obtain written answers to:

1. Is Nitrokey HSM 2 / SmartCard-HSM accepted for subscriber-controlled code-signing keys?
2. Which exact hardware certification is required?
3. How must key attestation be produced and submitted?
4. Which algorithms/key sizes are accepted?
5. Is the same key allowed for renewal/reissue, or must a new key be generated?
6. How is the issued certificate downloaded/imported?
7. What timestamp service URL and certificate chain are recommended?
8. What are revocation and compromise reporting procedures?

Never generate an exportable software private key as a shortcut unless the policy/CA explicitly allows it and the security architecture has been changed and reviewed.
