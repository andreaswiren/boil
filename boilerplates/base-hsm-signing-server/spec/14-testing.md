# Test Strategy

Layers: TypeScript/Rust unit tests, DB integration, RPC contract tests, Playwright e2e, API negative/replay tests, policy tests, PWA approval tests, network rollback tests, mock PKCS#11 tests, real Nitrokey tagged tests, DKEK backup/restore ceremony tests, installer VM tests, security regression suite. Real HSM tests must never run destructive initialization against an unlabelled device.
