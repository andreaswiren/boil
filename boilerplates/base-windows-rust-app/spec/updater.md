# Auto-update

Owned by **B09 `updater`** (Wave 3). B09 owns `crates/update/**`. It owns one
state transition: **replacing files B07 put on disk**
(`contracts/ownership.md`). It does not create the ARP entry, it does not touch
shortcuts, and it never stops or starts the service itself — that transition is
B08's and is reached through the contract. B09 publishes `update-manifest` and
`channel`; it consumes `version`, `paths` and the **public** half of
`signing-keys`. No agent owns a private signing key; B09 embeds a public key
(REQ-UPD-03) and B10 consumes a CI signing credential it never reads or logs
(REQ-REL-04).

This is the highest-severity subsystem in the boilerplate. An auto-updater
without signature verification is a remote code execution channel that ships
enabled and turned on: it downloads an attacker-controlled file and executes it
with the user's privileges, on a schedule, without being asked. Everything below
exists to keep that from being true, and REQ-UPD-02 is a compliance control as
well as a security one (REQ-CRA-07).

## Requirements covered

| ID | How this spec covers it |
|----|------------------------|
| REQ-UPD-01, REQ-UPD-02, REQ-UPD-03 | Automatic checks on a staggered schedule plus a manual one in the tray and on the CLI; a minisign signature over the manifest verified against a key embedded with `include_str!` before anything is executed or swapped. |
| REQ-UPD-04, REQ-UPD-05 | HTTPS with certificate validation and the artefact's SHA-256 checked against the signed manifest; downgrade refused, with a forced path needing a local operator and a machine policy value. |
| REQ-UPD-06 | Journal plus same-volume rename, reconciled on next start. Old or new, never a mixture. |
| REQ-UPD-07, REQ-UPD-08 | `stable` and `next`, selectable in settings and shown in diagnostics; deterministic per-install phase offset, jittered backoff, and a manifest-driven rollout window. |
| REQ-UPD-09, REQ-UPD-10 | Verified and staged while running, with the restart asked for and never taken; service transitions through B08's token, with the new version confirmed over IPC. |
| REQ-UPD-11 | Typed errors, visible last-check state, backoff for transport faults and a hard stop for verification faults. |
| REQ-UPD-12, REQ-UPD-13 | `HKLM` policy keys with documented precedence, shown in the UI as managed; `security: true` and `advisories` in the manifest with a `SecurityUpdatesOnly` policy. |
| REQ-SEC-01, REQ-SEC-02, REQ-SEC-07 | HTTPS only, Authenticode checked before execution, manifest parsed as untrusted input. |
| REQ-TST-03 | The negatives are the point: wrong signature, tampered artefact, downgrade attempt, interrupted swap. |

## The manifest

Two files per channel, published atomically and last (REQ-REL-10):
`manifest.json` and its detached `manifest.json.minisig`.

```json
{
  "schema": 1,
  "product": "com.example.widget",
  "channel": "stable",
  "generated_at": "2026-09-22T08:25:06Z",
  "releases": [
    {
      "version": "1.4.2",
      "released_at": "2026-09-19T11:00:00Z",
      "security": true,
      "advisories": ["CVE-2026-31887"],
      "min_upgrade_from": "1.2.0",
      "notes_url": "https://example.com/releases/v1.4.2",
      "artefacts": {
        "x86_64-pc-windows-msvc": {
          "url": "https://updates.example.com/widget/1.4.2/widget-x86_64.exe",
          "size": 14782976,
          "sha256": "9f2c41b0e6a7d3c58e1b0a94f7d2c6b5a81e3f04c9d7b2a6e5f81c3d0b7a4e92",
          "signature": "RUSHfNAAaxT4a1v0nGJ1t0rD1hG8aGzQmO1J2sQx0k9pV7c0Xw…",
          "authenticode_subject": "CN=Example AB, O=Example AB, C=SE"
        },
        "aarch64-pc-windows-msvc": { "url": "…/widget-aarch64.exe", "size": 14213120, "sha256": "3ad9e7c1…f207", "signature": "RUSHfNAAaxT4pQ9m…", "authenticode_subject": "CN=Example AB, O=Example AB, C=SE" },
        "msi-x86_64": { "url": "…/widget-x86_64.msi", "size": 15204352, "sha256": "c41f9b02…a920", "signature": "RUSHfNAAaxT4kM8v…" }
      }
    }
  ],
  "rollout": { "stagger_hours": 24, "min_client_version": "1.0.0" }
}
```

`schema` is checked first and an unknown value is a hard stop: a client that
guesses at a format it does not know parses attacker input optimistically
(REQ-SEC-07). Every field is bounded — 1 MiB body, 64 releases, 2 KiB strings.

The per-artefact `signature` is deliberate redundancy. The manifest signature is
the trust anchor and already covers the hash; the artefact's own signature lets
a file fetched from a mirror or a release page be verified without the manifest,
and it is verified anyway.

## The trust chain (REQ-UPD-02, REQ-UPD-03, REQ-UPD-04)

Four checks, in this order, none skippable, all before anything executes:

1. **Manifest signature.** `minisign-verify` 0.2.5 against the embedded public
   key. Failure stops here; the manifest is not even parsed into the release
   list.
2. **Artefact hash.** `sha2` 0.11.0 over the downloaded bytes, compared to
   `sha256` from the signed manifest, and the byte count compared to `size`.
3. **Artefact signature.** Minisign over the artefact, same key.
4. **Authenticode.** `WinVerifyTrust` through `ffi::trust`, subject compared to
   `authenticode_subject` (REQ-SEC-02).

The key lives in the crate, not on the network:

```rust
// crates/update/src/trust.rs
/// Minisign public key for release artefacts. Rotation: ship a version that
/// trusts CURRENT and NEXT, then sign with NEXT (REQ-UPD-03).
const KEY_CURRENT: &str = include_str!("../keys/update-current.pub");
const KEY_NEXT:    &str = include_str!("../keys/update-next.pub");
```

A key fetched at update time is not a trust anchor: whoever can serve a manifest
can serve a key, and verification then proves only that the server is
internally consistent. Two keys are embedded so rotation is possible — ship N+1
trusting both, then sign N+2 with the new key. A rotation that skips the overlap
release breaks the update path for every client that missed the intermediate
version, and the only recovery is a manual reinstall.

Order matters as much as presence. Hashing before verifying the manifest trusts
an unsigned hash. Checking Authenticode after launching the installer verifies a
process that is already running. `self-replace` 1.5.0 is called *after* step 4 —
it swaps files, it does not decide whether they deserve swapping.

Transport (REQ-SEC-01, REQ-UPD-04): `ureq` 3.4.2 with rustls, HTTPS only. A
non-HTTPS URL — manifest, policy, anywhere — is rejected, not upgraded. At most
3 redirects, HTTPS, same registrable domain. Timeouts 10 s connect, 30 s read,
30 min total. A body exceeding the manifest's `size` is abandoned mid-stream.

## Downgrade refusal (REQ-UPD-05)

`semver` 1.0.28 compares the running version with the candidate. Lower is
refused and logged; equal is a no-op, not an error. A `min_upgrade_from` above
the running version is refused with the version to install first named, because
a state migration would be skipped.

The narrow forced path is `app.exe --update --force-version 1.3.9
--i-accept-downgrade`, which additionally requires
`HKLM\Software\Policies\<Publisher>\<App>\AllowDowngrade = 1` and, for a
machine-wide install, elevation. Three conditions, and a remote manifest
satisfies none of them. A downgrade is how a patched vulnerability is
reintroduced, so the decision belongs to an operator at the machine and never to
whoever serves the manifest. It is recorded in the Event Log with both versions.

Rolling back to the version that was on *this* machine is different and is
supported: B07 keeps `<program_dir>\rollback\app-<old>.exe`, and
`app.exe --update --rollback` restores it after re-verifying its signature — a
local revert, not a version the network chose.

## The atomic swap (REQ-UPD-06)

1. Download to `<data>\update\staging\<version>-<rand>.part` in a directory
   whose DACL grants write to the installing user or `SYSTEM` only.
2. `FlushFileBuffers`, then hash, verify and Authenticode-check **from the same
   open handle** the download wrote. Re-opening the file by path between check
   and use is a TOCTOU window, and a hash-checked file swapped in that window is
   the whole attack.
3. Write `<data>\update\swap.journal` — `{from, to, aside, target_version,
   phase}` — and `FlushFileBuffers` it before proceeding.
4. Swap. For the running image, `self-replace` 1.5.0: Windows permits renaming a
   running executable, so the old image is renamed aside and the new one moved
   into place, both same-volume renames. For a file that is not running — the
   service binary — `ReplaceFileW`, which preserves the original's ACL, streams
   and attributes; delete-then-move loses them and silently widens the ACL.
5. Every rename uses `MOVEFILE_WRITE_THROUGH`. Windows has no directory fsync,
   and a plain rename can be lost across power loss while the data it points to
   is already on disk. This flag is the difference between "usually atomic" and
   atomic.
6. Mark the journal `committed`, then delete staging.

**Recovery.** On every start, whichever binary survived reads the journal. No
journal or `phase = committed`: nothing to do. `phase = swapping` with the target
present and verifying: complete the swap. Target absent or failing verification:
restore the aside copy. The invariant is old-or-new, and it holds because the
unit of swap is one file — which is why REQ-FND-12's single self-contained
executable matters here. A multi-file swap cannot be made atomic with renames
alone; side files, if intake adds them, go in `<program_dir>\v<version>\` and
the swap becomes one directory rename under the same journal.

## Channels (REQ-UPD-07)

`stable` and `next`, at
`https://updates.example.com/<product>/<channel>/manifest.json`. The channel
lives in `config`, is selectable in settings (REQ-UI-09) and is shown in
diagnostics with the last check time (REQ-OBS-03).

Both channels are signed with the same key: a channel is release selection, not
a trust boundary, and a key per channel would double the rotation problem for
nothing. Moving from `next` back to `stable` while the installed version is ahead
of stable's newest is not a silent downgrade — the client holds and says so:
*"You are on 1.5.0-next.3. Stable is 1.4.2. No update until stable passes
1.5.0."*

## Stagger and rate limiting (REQ-UPD-08)

Four mechanisms, because they solve different synchronisations:

**Per-install phase offset.** Base interval 6 h; the offset inside that window
is `HMAC-SHA256(install_id, "update-check") mod 6h`. `install_id` is a random
UUID generated by B07 at install and stored in config — not the machine SID, not
the hostname, nothing that identifies the machine to a server (REQ-FND-10).
Deterministic, so it survives restarts and a fleet that reboots together at
08:00 does not then check together at 08:00.

**Per-check jitter.** ±10 % uniform on top of the offset, so installs cloned
from one golden image drift apart instead of locking to a shared phase.

**Manifest rollout window.** `rollout.stagger_hours`: a release is taken only
after `released_at + bucket × stagger_hours`, where
`bucket = HMAC-SHA256(install_id, version) / 2^256` in `[0,1)`. Stable per
install and per version, so a client never moves bucket between checks, and
release day spreads over a day with no server-side cohort service.

**Floor and ceiling.** At most one automatic check per hour whatever triggers
one. A manual check bypasses the schedule — that is its purpose — and is limited
to one per 5 minutes. No check in the first 120 s after start, so a logon
autostart (REQ-SVC-09) is not competing with the desktop appearing.

Failure backoff is 5 m, 15 m, 1 h, 6 h, capped, and **fully jittered**:
`sleep = random(0, cap)`. Unjittered exponential backoff re-synchronises a fleet
on the failure path, exactly when the server is already struggling. `ETag` makes
an idle check cost a 304, and `Retry-After` on 429 or 503 is honoured up to 24 h.

## Updating a running instance (REQ-UPD-09)

Default `on_restart`: check, download, verify, swap, then notify — *"Update
1.4.2 installed. It will be used the next time the app starts."* — with
**Restart now** and **Later**. The swap is safe while running because Windows
keeps the old image mapped: the running process finishes on the old code and
nothing changes underneath it.

The app is never restarted with work in flight. B09 asks through the contract:

```rust
pub enum Busy { Idle, Busy { what: &'static str } }
pub trait BusyGuard { fn state(&self) -> Busy; }
```

`Busy` means no automatic restart, ever. With `RestartDeadlineHours` set by
policy the app reminds hourly past the deadline and restarts itself only when
`Busy::Idle` holds and no window has focus. An updater that closes a window with
unsaved work in it gets the product uninstalled, and correctly.

## Service-mode ordering (REQ-UPD-10)

1. Read `service-state` from B08. `Unknown`, or IPC unavailable: abort before any
   state change and report. Do not guess at a service you cannot see.
2. Complete the whole trust chain. Verification always precedes state change.
3. `B08::begin(TransitionReason::Update(1.4.2))` → a `TransitionToken`. This is
   what suspends B08's failure actions and crash-loop counting for the duration.
4. `B08::stop(&token, 30s)`. On timeout, release the token and abort with the
   service still running the old version.
5. Swap the service binary with `ReplaceFileW`, journalled as above.
6. `B08::start(&token, expect: 1.4.2, 60s)`.
7. Wait for `Running` **and** an IPC `Hello` reporting 1.4.2 (REQ-SVC-05). "The
   SCM says Running" is not "the new version works".
8. On start or handshake failure: restore the aside binary, start again, and
   report loudly — Event Log, UI, `update-state.last_error`. The service ends up
   Running on the old version. Never left stopped (REQ-UPD-10). If the restore
   also fails, report `Stopped` with the exact recovery command; that is the one
   case where a human must act.
9. `B08::end(token)` re-arms the failure actions.

B09 never calls `sc.exe`, `CreateService` or a service-control wrapper. The
reason is ordering, not etiquette: B09 cannot know B08's restart policy or its
crash-loop threshold, so a direct stop either races the SCM's own restart —
which relaunches the old binary in the middle of the swap — or counts as a
failure and trips the detector into disabling the service. A direct call gets
the sequence right by luck, and luck is not a design.

## Failure handling (REQ-UPD-11)

Transport faults and verification faults are handled differently on purpose.

| Error | Retry? | Surface |
|-------|--------|---------|
| `Transport`, `Timeout`, `Http(5xx)` | yes, jittered backoff | diagnostics; tray after 3 consecutive or 72 h |
| `Http(404)` on an artefact | yes, slowly — the manifest may be ahead of the CDN | diagnostics, warning after 6 h |
| `ManifestSignature`, `ArtefactSignature`, `ArtefactHash`, `Authenticode` | **no** | immediate notification, Event Log error, tray error state |
| `Downgrade`, `MinUpgradeFrom` | no | stated in the UI with the reason |
| `PolicyDisabled`, `Pinned` | no | shown as managed, not as an error |
| `ServiceTransition` | once, then stop | Event Log and UI, with the service's state named |
| `SwapInterrupted` | reconciled on next start | diagnostics, with what was restored |

A verification failure is never retried against the same URL. The artefact goes
to `<data>\update\quarantine\`, checks stop until a user or operator
acknowledges, and the event is raised immediately. A retry loop on a signature
failure is a machine politely re-downloading an attack.

Never silent means `last_check_at`, `last_success_at` and `last_error` are always
visible in diagnostics (REQ-OBS-03). No successful check for 72 h is itself an
error state shown in the tray (REQ-TRY-04), because a check that stopped
happening is how a fleet sits unpatched for months. Repeat notifications are
capped at one per 24 h — one per failure trains people to dismiss them.

## Policy (REQ-UPD-12) and security updates (REQ-UPD-13)

`HKLM\Software\Policies\<Publisher>\<App>`, machine scope only, ADMX-shaped.
`HKCU` is not read for policy: a policy a user can rewrite is not a policy.

| Value | Type | Effect |
|-------|------|--------|
| `UpdateEnabled` | `REG_DWORD` | `0` stops all checks |
| `Channel` | `REG_SZ` | forces `stable` or `next` |
| `PinnedVersion` | `REG_SZ` | a semver requirement, e.g. `1.4.x`, so patches inside the pin still land |
| `ManifestUrl` | `REG_SZ` | HTTPS only; a non-HTTPS value is rejected, not honoured |
| `SecurityUpdatesOnly` | `REG_DWORD` | take releases with `security: true`, skip the rest |
| `AllowDowngrade` | `REG_DWORD` | required for the forced path above |
| `CheckIntervalHours` | `REG_DWORD` | clamped to 1–168 |
| `RestartDeadlineHours` | `REG_DWORD` | `0` means never restart automatically |

Precedence is policy, then config, then default. Policy wins in effect but never
invisibly: the settings control is disabled and labelled *"Managed by your
organisation"* with the exact key and value, and diagnostics prints the
effective source for every setting. A setting that silently ignores the user is
how an update system becomes mysterious.

`UpdateEnabled = 0` disables security updates too, and the UI says so in those
words. A policy that silently exempts a class of update is one an operator
cannot reason about.

`SecurityUpdatesOnly = 1` is the honest version of separability: the client takes
the newest release with `security: true` and skips feature releases above it.
What it does not do is deliver the fix without the changes that shipped before
it — one binary, no maintenance branches, so taking 1.4.2 brings everything
between the running version and 1.4.2. The operator's real choice is "take 1.4.2
now, skip 1.5.0", and that satisfies REQ-UPD-13 and REQ-CRA-07. True backports
are a release-engineering commitment recorded at intake, not something the
updater can fake.

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|----------|--------|-----|--------------------|
| Signature scheme | minisign via `minisign-verify` 0.2.5, verify-only | The binary never signs, so it never needs a private key (`contracts/ownership.md`) | no |
| Key location | `include_str!` from `crates/update/keys/` | A key fetched at update time is not a trust anchor (REQ-UPD-03) | no |
| Keys embedded | current + next | Rotation needs an overlap release or clients are stranded | no |
| Check order | manifest signature → hash → artefact signature → Authenticode | Any other order verifies something already trusted or already running | no |
| Transport | `ureq` 3.4.2 + rustls, HTTPS only, 3 redirects, same domain | REQ-SEC-01; a non-HTTPS URL is rejected, not upgraded | no |
| Swap | `self-replace` 1.5.0 running, `ReplaceFileW` not running, `MOVEFILE_WRITE_THROUGH` | Atomicity across power loss, and ACLs preserved (REQ-UPD-06) | no |
| Downgrade | refused; forced needs flag + policy + elevation | It reintroduces patched vulnerabilities (REQ-UPD-05) | no |
| Channels | `stable`, `next`, one key | A channel is release selection, not a trust boundary | a third channel |
| Check interval | 6 h, offset by `HMAC(install_id)` | Deterministic de-synchronisation without a server (REQ-UPD-08) | 1–168 h |
| Backoff | 5 m → 6 h, fully jittered | Unjittered backoff re-synchronises a struggling fleet | no |
| Install identity | random UUID at install | A stagger key must not identify the machine (REQ-FND-10) | no |
| Restart | asked for, never taken while `Busy` | REQ-UPD-09; killing in-progress work ends the product | deadline hours |
| Verification failure | quarantine, stop, notify | Retrying an attack is not resilience (REQ-UPD-11) | no |
| Service transitions | B08's token, always | B09 cannot know the restart policy (REQ-UPD-10) | no |
| Policy scope | `HKLM` only | A user-writable policy is not a policy (REQ-UPD-12) | no |

## How this is verified

Against a real signed manifest, with a real key pair, and the negatives are the
point (REQ-TST-03):

- **Wrong signature.** A manifest signed with a key the binary does not trust,
  and a manifest with one byte of the signature altered. Both must fail at check
  1, with nothing downloaded and nothing parsed into a release list.
- **Tampered artefact.** A correctly signed manifest whose artefact has one byte
  flipped. Must fail at check 2, quarantine the file, and not retry.
- **Downgrade attempt.** A signed manifest offering 1.3.0 to a 1.4.2 client.
  Refused, logged, no download. Repeat with `AllowDowngrade` absent and the
  `--force-version` flag present: still refused.
- **Interrupted swap.** Kill the process between each journal phase — after the
  journal write, after the aside rename, after the move — and assert on next
  start that the binary is either the old or the new one, that it runs, and that
  it reports the version matching the file on disk.
- Size and schema fuzzing: a 2 MiB manifest, `schema: 2`, 10 000 releases, a
  5 MiB string, a `size` smaller and larger than the real artefact. All rejected
  without allocating to match (REQ-SEC-07).
- Stagger: 10 000 synthetic `install_id`s over a 24 h `stagger_hours` window,
  asserting no bucket holds more than 2 % and that a given id is stable across
  runs.
- Service ordering: an integration test asserting the call sequence
  `state → begin → stop → swap → start → handshake → end`, and that a failed
  start restores the old binary and leaves the service `Running`.
- Static assertion: `crates/update` contains no `windows::Win32` import
  (REQ-FND-03) and no `sc.exe` string (`contracts/ownership.md`).

Fixture note: `minisign-verify` cannot sign. Fixture key pairs and signed
manifests are generated once, out of band, and committed under
`crates/update/tests/fixtures/` with the procedure recorded beside them. If CI
must generate them instead, that needs a signing-capable crate validated by B16
— not a version written from memory (REQ-VER-02).

## Open to intake

- Manifest base URL and the channel names, if not `stable` and `next`.
- Base check interval and whether a rollout window is used at all.
- Whether `RestartDeadlineHours` is set for the fleet, and to what.
- Whether the MSI is offered as an update artefact or only as a first install.
- Whether maintenance branches exist, which is the only way true per-fix
  security updates become possible (REQ-UPD-13).
