# Coordinated Vulnerability Disclosure Policy

Requirement: `REQ-CRA-04`. Annex I Part II(5) and II(6) of [Regulation (EU) 2024/2847](https://eur-lex.europa.eu/eli/reg/2024/2847/oj).
Owner: **A18** (this text). Published by **A22** in `SECURITY.md` (`REQ-REL-05`).

This file is the **publishable** policy. It is written to be lifted verbatim
into `SECURITY.md` and onto the product's public site. A CVD policy that lives
only in a compliance folder does not satisfy Annex I Part II(5) — the obligation
is to put one in place **and enforce it**, which means a reporter must be able to
find it without asking.

The internal mechanics it commits us to are
`compliance/cra/vulnerability-handling.md`.

---

## Policy text — publish from here down

### Our commitment

We want to hear about security flaws in this product. If you report one in good
faith under this policy, we will acknowledge you, keep you informed, fix the
flaw, and credit you unless you ask us not to. We will not pursue legal action
against you.

### Single point of contact

| | |
|---|---|
| Email | `<<PLACEHOLDER: security@<domain> — the single point of contact required by Annex II §2>>` |
| PGP key | `<<PLACEHOLDER: fingerprint and key URL, or "not offered">>` |
| Postal address | `<<PLACEHOLDER: legal entity name and address>>` |
| Languages | English, Swedish |
| Response hours | `<<PLACEHOLDER: working week and timezone; default Europe/Stockholm>>` |

One address, monitored, with a named owner and a named deputy. Do not report a
vulnerability through a support ticket, a sales contact, or a public issue
tracker.

### In scope

- The product's source code and released container images, at any version
  listed as supported in `SECURITY.md`.
- The default configuration as shipped, and the security properties claimed in
  `compliance/cra/secure-by-default.md`.
- The authentication, MFA, RBAC and tenant-isolation mechanisms
  (`REQ-AUT-*`, `REQ-RBA-*`) — in particular anything that crosses a tenant
  boundary.
- The audit trail's integrity and redaction behaviour (`REQ-AUD-03`,
  `REQ-AUD-05`, `REQ-AUD-06`).
- The API surface and API key handling (`REQ-API-*`).
- The build and release pipeline, the SBOM, and the signing of releases.
- Dependencies shipped inside our images: report them to us **and** to the
  upstream project. We track them to a fixed upstream version.

### Out of scope

- **Any deployment you do not own or have written permission to test.** This is
  self-hosted software. Someone else's running instance is someone else's
  system, and testing it without permission is not covered by this policy.
- Denial of service by volume, load testing, or resource exhaustion against any
  instance you do not own.
- Social engineering of our staff or of an operator's staff, phishing, and
  physical intrusion.
- Findings that depend on an operator having deliberately weakened a documented
  secure default (`compliance/cra/secure-by-default.md`). Tell us anyway — it may
  mean the default is too easy to weaken.
- Missing hardening headers or best-practice gaps with no demonstrated impact,
  scanner output without an exploit path, and self-XSS.
- Vulnerabilities in an operator's own infrastructure: their host, network,
  identity provider or backups. Those are the operator's, per
  `compliance/cer/applicability.md`.

### Safe harbour

If you follow this policy we will treat your research as authorised, will not
initiate or support legal action against you for it, and will not report you to
law enforcement. Specifically, we consider the following authorised conduct:

- Testing against your **own** installation of the product.
- Accessing only the minimum data needed to demonstrate the flaw, stopping the
  moment it is demonstrated.
- Reporting to us before disclosing anywhere else.

Safe harbour ends if you exfiltrate or publish personal data, destroy or modify
data that is not yours, degrade an operator's service, use a finding for extortion,
or test a third party's deployment without their written permission. We cannot
grant safe harbour on behalf of an operator whose instance you tested — only they
can.

### How to report

Send to the contact address above. Include as much of this as you have:

1. Product version, and the image digest if you have it.
2. The affected component or endpoint.
3. Reproduction steps that someone else can follow, with a request/response
   trace where relevant.
4. What an attacker gains: whose data, which privilege, which tenant boundary.
5. Any proof-of-concept, as an attachment rather than a link to a third-party host.
6. Whether anyone else knows, and any disclosure date you already have in mind.
7. How you want to be credited, or that you want anonymity.

Please do **not** include personal data belonging to third parties. If your
proof unavoidably contains some, say so and we will handle it under
`<<PLACEHOLDER: data-handling contact / DPO route>>`.

### What happens next, and when

| Stage | Our commitment |
|---|---|
| Acknowledgement | Within **1 business day**; within **24 hours** for a report indicating active exploitation |
| Triage verdict and severity | Within **5 business days**; within **48 hours** for Critical |
| Status updates | At least every **10 business days** until closure, and immediately on a change of severity |
| Fix available | Critical **7 days**, High **30 days**, Medium **90 days**, Low next scheduled release |
| Advisory published | With the fix, naming affected and fixed versions, impact and operator action |
| Credit | In the advisory, as you asked |

If we will miss a date, we tell you before we miss it, with the reason.

### Disclosure coordination

- We aim to publish the advisory **when the fix is available**, and we ask you
  to hold public disclosure until then.
- **Default embargo: 90 days** from acknowledgement. After 90 days you are free
  to publish whether or not we have shipped, and we will not object.
- If the flaw is already being exploited, speed beats embargo. We may publish a
  mitigation before a fix exists, and we will tell you first.
- We request a CVE through `<<PLACEHOLDER: CNA used, e.g. the relevant root CNA>>`
  and put the CVE in the advisory. If you have already obtained one, tell us the id.
- We publish a machine-readable CSAF 2.0 advisory alongside the human-readable
  one: `<<PLACEHOLDER: CSAF feed URL>>`.
- We may delay publishing the details of a fixed vulnerability where the risk of
  publication outweighs the benefit until operators have had a chance to patch
  (Annex I Part II(4)). We will tell you if we do, with the reason and a
  committed date. **This never delays a regulatory filing.**

### Regulatory reporting, so you know what we do with your report

Where your report shows a vulnerability in this product is **actively
exploited**, we are required to notify ENISA and our national CSIRT through the
ENISA Single Reporting Platform within 24 hours of becoming aware, with
follow-up submissions after that (CRA Article 14, in force since 11 September
2026). Our runbook is `compliance/cra/reporting-runbook.md`. Your identity is
not part of what we are required to file, and we do not include it.

### Rewards

`<<PLACEHOLDER: state plainly whether a bounty is offered. If none: "We do not
operate a bug bounty. We offer acknowledgement and credit." Do not imply a
reward that does not exist.>>`

## Policy text ends

---

## `security.txt` (RFC 9116)

Served at `https://<host>/.well-known/security.txt`, and reachable over HTTPS
only (`REQ-SEC-02`). `Contact` and `Expires` are the required fields. **Set
`Expires` no more than one year out and renew it** — an expired `security.txt`
tells a reporter the process is abandoned.

```
# https://<<PLACEHOLDER: host>>/.well-known/security.txt
Contact: mailto:<<PLACEHOLDER: security@<domain>>>
Contact: https://<<PLACEHOLDER: host>>/security
Expires: <<PLACEHOLDER: ISO 8601 UTC, e.g. 2027-09-21T00:00:00.000Z — under 1 year>>
Encryption: https://<<PLACEHOLDER: host>>/.well-known/pgp-key.txt
Preferred-Languages: en, sv
Canonical: https://<<PLACEHOLDER: host>>/.well-known/security.txt
Policy: https://<<PLACEHOLDER: host>>/security/disclosure-policy
CSAF: https://<<PLACEHOLDER: host>>/.well-known/csaf/provider-metadata.json
Acknowledgments: https://<<PLACEHOLDER: host>>/security/hall-of-fame
Hiring: https://<<PLACEHOLDER: host>>/careers
```

Optional but recommended: sign the file with the PGP key it advertises and serve
the detached signature at `/.well-known/security.txt.sig`.

## Where this policy is published

| Location | Owner | Requirement |
|---|---|---|
| `SECURITY.md` in the repository | A22 | `REQ-CRA-04`, `REQ-REL-05` |
| `https://<host>/security` | `<<PLACEHOLDER: who publishes the public page>>` | `REQ-CRA-04` |
| `/.well-known/security.txt` | A01 (static route) | RFC 9116 |
| Annex II user information — contact point and where to find this policy | A18 | `REQ-CRA-09` |
| Annex VII technical documentation — evidence that a contact address is provided | A18 | `REQ-CRA-09` |

Review at every release, and whenever the contact, the PGP key or the `Expires`
date changes. A policy naming someone who left is worse than no policy.
