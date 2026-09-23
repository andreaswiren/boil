# Testing

Owner: `test-automation-engineer`. Requirements: every `MUST` in the register —
that is the point of this document.

## 1. A requirement without a test is an intention

`spec/requirements.md` carries 65 requirements. The traceability matrix maps each
to an owner. This document is the other half: **what evidence exists that each is
true.**

The rule is `SZ-*` by ID. A test that does not cite a requirement is testing
something nobody asked for; a requirement with no citing test is an intention.
The completion gate on every agent brief says the traceability entries are
updated, and that is what it means.

## 2. Layers, and what each is actually for

| Layer | Answers |
|-------|---------|
| Unit | Does this function do what it says — policy evaluation, canonical serialisation, hash chaining |
| Integration | Do two components agree — web ↔ `signerd`, `signerd` ↔ HSM, restore ↔ schema |
| End-to-end | Does the product work — submit, approve, sign, verify |
| **Negative** | Does it refuse — §3 |
| Appliance | Does the *machine* hold — verity, unseal, firewall (`SZ-OS-010`) |

## 3. The negative tests are the important ones

For a signing appliance, most of the value is in what it refuses. These are not a
sub-category of the test suite; they are the suite's reason for existing.

Every one of these is a test, and each cites the requirement it defends:

- A digest that does not match the submitted bytes → refused before the HSM opens.
- A request claiming a repository its workload token does not assert → refused.
- An approval for artefact A → does not sign artefact B.
- A requester approving their own request → refused by the API, not just the UI.
- An expired approval → does not sign.
- A push notification with no transaction proof → not an approval.
- A `Metrics` credential on any other endpoint → refused.
- A `Backup` credential decrypting a backup → fails.
- A mechanism outside the profile, through the API or the PKCS#11 module →
  refused.
- Any operation in the wrong appliance state → `412`, with both states named.
- Rate limits → asserted at the stated numbers, per address **and** per username.
- A timestamp-authority outage → failure, never an untimestamped signature.
- An `UPDATE` on `audit_events` → fails at the database.
- An edited or truncated audit chain → detected.

## 4. Hardware, and how not to be blocked by it

HSM-dependent tests run in two modes (`SZ-HSM-001`):

- **Software mode** by default, against a SmartCard-HSM emulator or a
  software PKCS#11 token, so the whole suite runs in CI with no hardware.
- **Real-HSM mode**, explicitly tagged, run against actual Nitrokey HSM 2
  devices before a release.

**What software mode cannot prove is written down**: DKEK ceremonies, Key Check
Value comparison between two physical devices, PIN retry counters, and reader
enumeration behaviour. Those carry a real-HSM tag, and a release that has not run
them says so rather than implying the suite passed.

Same discipline for the appliance layer: TPM sealing, verity and firewall tests
need a real or virtualised machine, and the REQ IDs they cover are reported
`unverified` when that environment is absent — never silently skipped. A skipped
test that reports green is worse than a missing test.

## 5. Determinism

Flakiness in this suite is a security problem, because a flaky negative test gets
disabled and a disabled negative test is a removed control.

- Time is injected, never read from the clock, so expiry tests are exact.
- Entropy is seeded in tests, and the seed is logged.
- Fixtures for the updater's negative cases — wrong key, mutated signature,
  tampered artefact — are **generated out of band and committed**, because
  `minisign-verify` and `sc-hsm-tool` cannot produce them in CI
  (`.gitignore` exempts `tests/fixtures/`).
- A test that fails intermittently is quarantined **with a ticket and an owner**,
  never deleted, and a quarantined negative test blocks the release.

## 6. Security regression tests

Every security finding — from `security-reviewer`, `adversarial-reviewer`, an
advisory or an incident — gets a test that fails on the unfixed code before the
fix lands. The test cites the finding.

This is the only mechanism that stops a fixed vulnerability returning during a
refactor two years later, and it is cheap exactly once: while the finding is
still understood.

## 7. Coverage, honestly

Line coverage is reported and is **not** a gate. A signing appliance with 95%
line coverage and no negative test for approval replay is not tested.

The gate is requirement coverage: every `MUST` has at least one citing test, and
the ones that cannot be tested automatically are listed with the reason and the
manual procedure that covers them.

## 8. How this is verified

- A report maps every `SZ-*` `MUST` to its citing tests; any with none fails the
  build.
- Tests requiring hardware or an appliance report `unverified` rather than
  passing when the environment is absent.
- The negative suite in §3 runs on every commit.
- A deliberately broken control — a disabled digest re-check — fails the suite.
  The suite is tested by breaking the thing it guards, not by being read.
