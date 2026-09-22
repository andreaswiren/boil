# Coordinated Vulnerability Disclosure Policy

CRA Annex I Part II points 5 and 6 require a policy on coordinated vulnerability
disclosure and a contact address for reporting. The policy also underpins the
reporting obligation in force since 11 September 2026: a public intake channel is
how we become aware in the first place (REQ-CRA-04, REQ-CRA-06, REQ-SEC-10).

Owner: `B13`. Published by `B17` in `SECURITY.md` and served at
`/.well-known/security.txt` (REQ-REL-09 — `B13` supplies the text, `B17` owns the
file).

Everything between the rules below is publishable as written, once the
placeholders are filled.

---

## Policy (publishable text)

### Scope

In scope:

- the application binary and installer we publish (`app.exe`, the MSI);
- the update mechanism, the update manifest and its signature chain;
- the Windows service and the local IPC endpoint between service and UI;
- our release artefacts and the release pages on both forges;
- `<<PLACEHOLDER: product domain(s) that serve update manifests or artefacts>>`.

Out of scope:

- third-party infrastructure we do not operate (the forges themselves, the
  operating system);
- findings that require a machine the attacker already controls as administrator;
- reports whose only content is a scanner output with no demonstrated impact;
- volumetric denial of service against our download hosts.

A dependency vulnerability is in scope when the dependency is compiled into our
binary — which you can check yourself: the dependency list is embedded in the
shipped executable (`cargo audit bin app.exe`), so the artefact answers the
question without our release page (REQ-SBM-02).

### How to report

Email `<<PLACEHOLDER: security contact address>>`, encrypted to
`<<PLACEHOLDER: PGP key fingerprint>>` if the report contains exploit detail.

Please include:

1. affected version and architecture — `Help ▸ About` states both (REQ-OBS-03);
2. install mode: per-user, machine-wide, or service mode;
3. Windows version and build;
4. reproduction steps, and the observed versus expected behaviour;
5. impact, and whether you have any indication the issue is being exploited.

Point 5 matters more than the rest. Active exploitation starts a 24-hour
statutory clock for us (`compliance/cra/reporting-runbook.md`), so any indication
of it — however uncertain — should be in the first message rather than a later
one.

### What we commit to

| Stage | Commitment |
|-------|-----------|
| Acknowledgement | Within 2 business days, with a tracking identifier |
| Triage outcome | Within 24 hours for critical or exploited, 3 business days for high, 10 for medium, 20 for low (`compliance/cra/vulnerability-handling.md` §2) |
| Fix released | 7 calendar days for critical or exploited, 30 for high, 90 for medium (§3) |
| Public advisory | When the fix is released, with affected versions, severity and remediation |
| Updates to you | At each stage, and on request |

Business hours: `<<PLACEHOLDER: support hours and timezone>>`.

If we are going to miss a date we tell you the new date and why, rather than
going quiet. Silence from us is a defect in this process, not a signal about your
report.

### Coordinated disclosure

We ask for **90 days** from acknowledgement before public disclosure, or until a
fix is released, whichever is sooner. We will:

- keep you informed and agree the disclosure date with you;
- publish an advisory naming the affected versions and the fix;
- credit you by name or handle unless you ask us not to;
- coordinate with you if the issue affects an upstream crate, so the upstream fix
  and ours are disclosed sensibly.

If a vulnerability is being actively exploited, we may disclose sooner —
mitigation information reaching users quickly outweighs a coordination schedule,
and we are separately obliged to report it (`compliance/cra/reporting-runbook.md`).

If we fail to respond within the commitments above, publishing after 90 days is
reasonable and we will not treat it as a hostile act.

### Safe harbour

We will not pursue or support legal action against a reporter who, in good faith:

- stays within the scope above;
- tests only against their own installation;
- does not access, modify, exfiltrate or destroy other people's data;
- does not degrade a service for others;
- gives us a reasonable opportunity to fix the issue before disclosure.

Testing against a third party's deployed installation is outside this safe
harbour, because their data is not ours to authorise access to.

### Rewards

`<<PLACEHOLDER: bounty position — "we do not currently operate a bounty
programme" or the programme terms>>`. Credit in the advisory is offered in every
case.

---

## `security.txt` (RFC 9116)

Served over HTTPS at `https://<<PLACEHOLDER: product domain>>/.well-known/security.txt`.
`Contact` and `Expires` are the only required fields; the rest are optional and
worth having. `Expires` should be less than a year out, so a stale file is
visibly stale rather than quietly wrong
(<https://www.rfc-editor.org/info/rfc9116/>, <https://datatracker.ietf.org/doc/rfc9116/>).

```text
# Coordinated vulnerability disclosure policy for <<PLACEHOLDER: product name>>
# RFC 9116. Required fields: Contact, Expires.

Contact: mailto:<<PLACEHOLDER: security contact address>>
Contact: https://<<PLACEHOLDER: product domain>>/security
Expires: <<PLACEHOLDER: ISO 8601 timestamp, under 12 months away, e.g. 2027-09-01T00:00:00.000Z>>
Encryption: https://<<PLACEHOLDER: product domain>>/.well-known/pgp-key.txt
Preferred-Languages: en
Canonical: https://<<PLACEHOLDER: product domain>>/.well-known/security.txt
Policy: https://<<PLACEHOLDER: product domain>>/security/disclosure-policy
Acknowledgments: https://<<PLACEHOLDER: product domain>>/security/acknowledgments
# Optional, if a signed advisory feed exists:
# CSAF: https://<<PLACEHOLDER: product domain>>/.well-known/csaf/provider-metadata.json
```

Signing the file with the PGP key referenced by `Encryption` is recommended by
RFC 9116; do it once the key exists, and record the signing in the evidence
index.

### Maintenance

| Item | Rule |
|------|------|
| `Expires` | Renewed at least annually. An expired `security.txt` is evidence the channel is unmaintained |
| Contact address | A role address that survives a person leaving. A personal mailbox fails on the day it matters |
| Both forges | `SECURITY.md` carries the same contact, so the GitHub and Gitea repository pages both surface it |
| User information | The contact also appears in the Annex II user information (REQ-CRA-09) |
| Verification | Fetching the URL is part of the release checks; a 404 here makes Annex I Part II points 5 and 6 **weak** in the obligations matrix (REQ-CRA-10) |

## Placeholders to resolve before publication

| Placeholder | Supplied by |
|-------------|-------------|
| Security contact address | Intake (`B00`) |
| Product domain(s) | Intake (`B00`) |
| PGP key fingerprint and key file | `<<PLACEHOLDER: key custodian>>` — a person, not an agent. No agent owns a key (`contracts/ownership.md`) |
| Support hours and timezone | Intake (`B00`) |
| Bounty position | The organisation |
| `Expires` timestamp | Set at publication, renewed annually |

Until these are filled, this policy is **not published**, and the obligations
matrix marks Annex I Part II points 5 and 6 as **weak** with a placeholder
contact. That is the honest state, and it is visible rather than implied.
