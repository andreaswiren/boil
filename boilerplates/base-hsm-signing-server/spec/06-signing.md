# Signing and policy

Owner: `signing-engineer` with `rbac-policy-engineer` and
`authenticode-engineer`. Requirements: `SZ-FUN-002`, `SZ-API-002`, `SZ-SEC-001`,
`SZ-SEC-004`, `SZ-DOC-002`.

## 1. The invariant

**The appliance signs what policy authorized, never what a caller asked for.**
Everything below follows from that sentence.

A request is an *assertion* — "I would like this digest signed under this
profile". The appliance independently establishes what is true, decides under
policy, obtains approval, re-checks, and only then opens the HSM.

## 2. The binding (`SZ-API-002`)

Every request binds five things at submission, and they are written once
(`spec/03-data-model.md` §2):

| Bound | Established how |
|-------|-----------------|
| Artefact digest | **Recomputed server-side** from the bytes received. A client-supplied digest is checked, never trusted. |
| Signing profile | Named by the caller, resolved against policy |
| Requester identity | From the authenticated session or workload token, never from the body |
| Repository and ref | From the **workload token's claims** where OIDC is used, not from caller-supplied fields |
| Expiry | Assigned by the appliance |

The distinction in rows 3 and 5 is the one that matters: anything a caller can
*state* about itself is an assertion; anything the appliance can *derive* is
evidence. A compromised build agent can claim any repository. It cannot mint a
token for one it does not build.

## 3. Policy evaluation is explainable or it is not a decision

The engine takes the binding, the requester, the profile and the key's tags, and
returns a decision **with a reason**: which rule, which value, and what would
have to change.

- A **denial** names the rule. An unexplainable denial becomes a ticket, and a
  ticket becomes pressure to add a bypass.
- An **approval** records the `policy_version_id` used, so the decision remains
  explainable after the policy changes.
- Evaluation is **pure and side-effect free**, so it can be run in a "would this
  be allowed" mode without producing a signature or an approval.

Policy constrains at minimum: which identities may request, which repositories
and refs, which keys and profiles, how many approvals and from whom, expiry, and
whether unattended signing is permitted for this profile (never by default —
`spec/00-product.md` §6).

## 4. Approval, and the re-check that follows

Approvals come from `spec/09-pwa-approvals.md`. The rule here is what happens
after: **the binding is re-verified immediately before the HSM is opened.**

Nothing true at approval time is assumed still true. The artefact is re-hashed
from stored bytes, the expiry re-checked, the policy version re-resolved, the
approver's authority re-confirmed. The window between approval and signing is
small, and it is exactly where a time-of-check/time-of-use attack would live.

**A requester cannot approve their own request** (`spec/00-product.md` §2),
enforced in the state machine and not only in the UI.

## 5. What `signerd` will and will not do

`signerd` receives a resolved decision, not a request. It:

- accepts a key **reference the policy engine resolved**, never a PKCS#11 URI or
  label from the caller;
- uses the mechanism the profile fixes, never one chosen per call;
- signs a digest, never a file it was asked to interpret;
- refuses if the appliance is not `Operational`, returning the state
  (`spec/07-rest-api.md` §1);
- never logs the PIN, the digest's preimage, or the key handle
  (`SZ-SEC-005`).

Failure is closed (`SZ-SEC-004`). An HSM error, a policy engine timeout, an
unavailable audit sink — every one of them ends the request without a signature.
A signing appliance that degrades to signing is not degraded, it is broken.

## 6. Authenticode and PowerShell on Linux (`SZ-DOC-002`)

The product signs Windows artefacts from Linux, which is the capability NetHSM
does not have (`spec/17-nethsm-parity.md` §6).

- **PE and MSI** via `osslsigncode` against the HSM through OpenSSL 3's PKCS#11
  provider.
- **PowerShell** via Authenticode over the script's canonical form.
- **RFC 3161 timestamping** on every signature, without exception: an untimestamped
  signature stops verifying the day the certificate expires, which is the defect
  that surfaces years later on machines nobody can update.
- **The timestamp authority is an allowlisted destination** (`SZ-OS-010`), and
  a timestamping failure fails the signature rather than producing one without.
- **The result is verified after signing**, on the appliance, before it is
  returned. A signing step that reports success without verifying its own output
  is a step that will eventually emit a corrupt signature to a customer.

**No PIN in any command line or `pkcs11:` URI** (`SZ-SEC-005`, rule 10). A
command line is world-readable on a running system, so the PIN reaches the
provider through a channel that does not appear in `/proc`.

## 7. How this is verified

- A submission whose bytes do not match the claimed digest is refused before the
  HSM is opened.
- A request claiming a repository its workload token does not assert is refused.
- An approval for artefact A cannot produce a signature for artefact B.
- A requester's own approval is refused by the API, not just hidden in the UI.
- An expired approval does not sign.
- Every produced signature verifies against the key's certificate and carries a
  valid RFC 3161 timestamp.
- A timestamp-authority outage produces a failure, never an untimestamped
  signature.
- `ps` and `/proc/<pid>/cmdline` during a signing operation contain no PIN.
