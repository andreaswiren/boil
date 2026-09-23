# Testing (REQ-TST-01 … REQ-TST-16)

The register says what is tested. This document says when, by whom, and what
counts as having tested it — because the failure mode here is not an absent test
suite. It is a suite that exists, runs, reports green, and verifies nothing about
the requirement it cites.

---

## 1. Who writes which tests (REQ-TST-10)

| Layer | Owner | Lands |
|-------|-------|-------|
| unit tests on a domain's own logic | that domain's agent | same task as the behaviour |
| integration tests on that domain's tables and RLS | that domain's agent | same task as the behaviour |
| seeded fixtures, generated from the contract | `A23` | Wave 3, first — fourteen agents wait on them (REQ-CTR-05) |
| contract interface tests | `A23`, run by **both** parties | `G4` (REQ-CTR-10) |
| cross-cutting suites: isolation, permission denial, MFA, audit | `A23` | Wave 3, run from `G4` onward (REQ-TST-16) |
| e2e critical journeys | `A23` writes, `A21` captures | Wave 3 onward |

There is no phase in this build where testing catches up. A phase like that is
the first thing cut when a wave runs long, and it is cut by an orchestrator that
has already reported the features as done.

## 2. Red first (REQ-TST-09)

A feature is done when a test fails without it. Both runs are recorded in the
hand-off's `validation.redFirst` (`spec/validation.md` §2):

```
1. write the test            → run it → it fails, for the stated reason.   redSha
2. implement the behaviour   → run it → it passes.                         greenSha
3. record both shas and the assertion in the hand-off.
```

A test authored after the code, against code that already passes it, asserts the
code's present behaviour. That is a useful regression guard and it is not
evidence about the requirement, because the requirement was never what the
assertion was written from.

"It fails for the stated reason" carries weight: a test that fails because the
module does not exist yet has not yet demonstrated anything about the assertion.

## 3. Green is a number, not a sentence (REQ-TST-12, REQ-TST-15)

The runner's own counts go in the hand-off, and the raw output goes to
`build/validation/<wave>/<agent>/test-output.txt`.

`skipped` and `focused` are checked, not glanced at:

- a `.skip` or `xit` to reach green is a gate finding naming the test;
- a `.only` left in a file silently reduces the suite to one test and reports
  green — the single most effective way to pass a gate with nothing verified;
- a suite of 400 with 40 skipped reports as green and verifies 360.

## 4. Flake is a defect (REQ-TST-14)

A test that fails and then passes unchanged is investigated. If it is
quarantined it is quarantined **once**, dated, with an owning agent, and it
blocks `G8`.

Re-running until green is how a real intermittent failure — a race in a
transaction boundary, a missing `await`, an index that is only sometimes used —
is reclassified as an environment problem and shipped.

## 5. Coverage is per requirement, not per line (REQ-TST-11)

`build/validation/req-coverage.md` is generated from the register and the suites:

| REQ ID | Status | Test | Layer |
|--------|--------|------|-------|
| REQ-RBA-05 | MUST | `tests/isolation/matrix.spec.ts` (generated per table) | integration |
| REQ-AUT-06 | MUST | `tests/mfa/recovery-codes.spec.ts` | integration |
| REQ-CRA-02 | MUST | *not testable* — documentary obligation, evidence in `compliance/cra/` | — |

At `G8`, a `MUST` with neither a test nor a recorded reason fails the gate. A
line-coverage percentage is not this: 90% line coverage with the isolation suite
absent is a number that describes the wrong thing confidently.

## 6. What the suites verify against (REQ-VAL-09)

- integration tests → a real PostgreSQL over `sslmode=verify-full`, connected as
  the **non-owner** app role, with `rolbypassrls` false inside the suite. An
  RLS test run as the owner passes unconditionally and means nothing.
- e2e → a real Chromium over CDP against the live instance (REQ-LIV-03).
- mail → the real relay container, not a stub that records calls.

A mock proves the code called something. That is never the claim a test of this
kind is making.

## 7. The four silent ones (REQ-TST-05, REQ-TST-16)

Tenant isolation, permission denial, MFA enforcement and audit emission run at
every gate from `G4` onward, not once at `G5`.

They are separated out because nothing about the product changes when they
break. A grid that renders rows from both tenants looks exactly like a grid. An
endpoint that stopped checking a permission returns 200 faster than it used to.
These four fail invisibly, which is why they are the four with dedicated suites
and the four that re-run at every gate.

## 8. The three easily-faked ones (REQ-TST-08)

The debug console stream, the grid preference round-trip and read-audit
emission. Each is asserted against the database or the wire, never against
rendered output, and each writes its recorded evidence to `build/agents/A23/`
so a reviewer can verify rather than trust. `A23`'s brief carries the exact
assertions.
