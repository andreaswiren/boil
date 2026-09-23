---
name: security-review
description: Independent security review and adversarial testing across trust boundaries, secret handling, authn/authz, HSM, setup, OS controls and signing-oracle risk. Load before any security feature is called complete.
---

# Security review

Rule 5: security-critical code requires **two independent reviews** —
`security-reviewer` and `adversarial-reviewer`. Independent means they do not see
each other's findings before submitting. Two reviewers who confer produce one
review.

Neither ever reviews code they wrote.

## Review in this order

The order matters — a finding at step 1 invalidates the rest.

1. **Trust boundaries.** Does anything cross one that should not? Is there a new
   path from the web tier toward a device, a root operation or a shell?
2. **The signing-oracle question.** Can a caller get bytes of their choosing
   signed without policy and approval? This is the question the product exists to
   answer no to.
3. **Evidence versus assertion.** Is any authorization decision made against a
   caller-supplied field instead of a verified claim or a recomputed value?
4. **Secrets.** Any new path to a log, a process argument, a URI, browser
   storage, telemetry or an error message (`SZ-SEC-005`)?
5. **Fail-closed.** What happens on timeout, on an HSM error, on an unavailable
   audit sink? Does anything degrade *to signing*?
6. **State.** Is the operation correct in `Locked` and `Failed`, not just
   `Operational`?
7. **Audit.** Is the refusal path logged, not just the success path?

## Findings

Each carries: the requirement it violates, a concrete exploitation path, the
evidence (file and line), and a proposed fix. "This looks risky" is not a
finding.

**Every finding gets a regression test that fails on the unfixed code before the
fix lands** (`spec/14-testing.md` §6). It is cheap exactly once — while the
finding is still understood — and it is the only thing that stops the
vulnerability returning during a refactor in two years.

## Adversarial testing

Beyond reading: try it. Replay an approval against a different digest. Submit a
digest that does not match the bytes. Approve your own request. Call an
operational endpoint while locked. Attempt an unseal from a root shell. Exhaust
the audit queue and see whether signing continues.

## What "complete" means

Not "no findings". **Every finding is resolved or explicitly accepted by a named
human with a stated rationale**, and an accepted risk is recorded where the next
reviewer will see it rather than in a closed thread.

A `SECURITY-BLOCKED` TODO **fails closed** and is never shipped as permissive
behaviour to be tightened later.

## Definition of done

- [ ] Both reviewers submitted without seeing the other's findings.
- [ ] Every finding has a requirement, an exploitation path and evidence.
- [ ] Every finding has a regression test that failed before the fix.
- [ ] Accepted risks are named, justified and recorded.
- [ ] The adversarial cases above were attempted, not just considered.
