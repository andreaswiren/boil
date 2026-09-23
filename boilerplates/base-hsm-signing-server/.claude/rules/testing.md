# Testing Rules

Full reasoning: `spec/14-testing.md`. IDs: `SZ-TEST-001` … `SZ-TEST-013`.
Compilation is a separate, earlier question: `spec/20-validation.md`.

1. **Every requirement needs an automated test where technically possible**, and
   a `MUST` with neither a test nor a recorded reason fails the build
   (`SZ-TEST-001`). A requirement with no citing test is an intention.
2. **Red first.** The test is run and seen to fail, for the reason you expect,
   before the behaviour exists; both shas go in the hand-off (`SZ-TEST-002`). A
   test written against code that already passes it asserts that code's present
   behaviour, not the requirement.
3. **Tests land with the behaviour**, never in a later cleanup phase
   (`SZ-TEST-003`). That phase is the first one cut when a phase runs long.
4. **The negative suite runs on every commit** (`SZ-TEST-004`). Most of this
   product's value is in what it refuses.
5. **Security bugs get a regression test that fails on the unfixed code**,
   citing the finding (`SZ-TEST-005`).
6. **Hardware tests support a software mode plus explicitly tagged real-HSM
   tests** (`SZ-TEST-006`), and what software mode cannot prove is written down.
7. **`unverified` is never green and never a silent skip** (`SZ-TEST-007`). A
   skipped test that reports green is worse than a missing one: the missing one
   is visible.
8. **Nothing is skipped, `#[ignore]`d or `.only`-scoped to reach green**
   (`SZ-TEST-008`). The test most likely to be disabled for being inconvenient
   here is a negative test, and **a disabled negative test is a removed
   control**.
9. **A flaky test is a defect with an owner** (`SZ-TEST-009`) — fixed, not
   re-run until green. A quarantined negative test blocks the release.
10. **Gate on requirement coverage, not line coverage** (`SZ-TEST-011`).
11. **Prove the suite can fail** (`SZ-TEST-012`): disable a control at every
    phase gate and assert the suite goes red.
