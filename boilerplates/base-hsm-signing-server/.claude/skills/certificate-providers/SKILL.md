---
name: certificate-providers
description: Code-signing certificate enrollment, import and renewal for DigiCert, Sectigo and generic CAs, with current HSM attestation requirements. Load for PKI documentation or enrollment work.
---

# Certificate providers

## Confirm acceptance before you buy

**Do not assume a CA accepts Nitrokey HSM 2 / SmartCard-HSM.** Code-signing
ecosystems require hardware-protected keys, and possession of a certified secure
controller does not mean every CA will accept that specific token for
subscriber-controlled issuance.

Get a provider case confirming: the exact hardware and firmware is accepted, what
certification evidence is required, and how key attestation must be supplied.
**Never represent the appliance as CA-approved until that confirmation exists.**

Record per provider: product (OV/EV), case ID, key algorithm and size, HSM model
and firmware, attestation method, certificate delivery format, timestamp URL,
renewal and rekey rules, revocation contact, date verified.

## Link, do not copy

CA requirements change without notice. Document **our** side of the procedure
precisely and **link** theirs. A copied enrollment procedure goes stale silently
and is discovered during an enrollment.

## The key never leaves

CSR generation happens on the appliance for a key generated **in the HSM**
(`POST /keys/{id}/csr.pem` — `SZ-API-007`). A provider process that expects a
PKCS#12 upload is a process that expects an exportable key, and that is a
different product.

## Renewal is a calendar item that will be missed

Certificate expiry is one of the two things most often discovered too late, so it
is a **persistent dashboard item** rather than a report — along with a DR HSM
whose Key Check Value no longer matches (`spec/00-product.md` §4).

Expired certificates also make **timestamping** load-bearing: a timestamped
signature keeps verifying after expiry, an untimestamped one does not
(`spec/06-signing.md` §6).

## Definition of done

- [ ] Every provider guide links current official documentation rather than
      restating it.
- [ ] The compatibility checklist is filled with a real case ID and date.
- [ ] No procedure requires an exportable key.
- [ ] Expiry appears on the dashboard, not only in a document.
