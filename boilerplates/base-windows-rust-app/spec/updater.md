# Auto-update

Owned by **B09 `updater`** (Wave 3). B09 owns `crates/update/**` and one state
transition: **replacing files B07 put on disk** (`contracts/ownership.md`). It
does not create the ARP entry or touch shortcuts, and it never stops or starts
the service itself — that transition is B08's, reached through the contract. B09
publishes `update-manifest` and `channel`; it consumes `version`, `paths` and the
**public** half of `signing-keys`. No agent owns a private key: B09 embeds a
public one (REQ-UPD-03) and B10 consumes a CI signing credential it never reads
or logs (REQ-REL-04).

This is the highest-severity subsystem in the boilerplate. An auto-updater
without signature verification is a remote code execution channel that ships
enabled and turned on: it downloads an attacker-controlled file and executes it
with the user's privileges, on a schedule, unasked. Everything below exists to
keep that from being true, which makes REQ-UPD-02 a compliance control as well
as a security one (REQ-CRA-07).

## Requirements covered

| ID | How this spec covers it |
|----|------------------------|
| REQ-UPD-01, REQ-UPD-02, REQ-UPD-03 | Automatic checks on a staggered schedule plus a manual one in the tray and on the CLI; a minisign signature over the manifest verified against a key embedded with `include_str!` before anything is executed or swapped. |
| REQ-UPD-04, REQ-UPD-05, REQ-UPD-06 | HTTPS with certificate validation and the artefact's SHA-256 checked against the signed manifest; downgrade refused, with a forced path needing a local operator and a machine policy value; a journal plus same-volume rename reconciled at next start, so the result is old or new and never a mixture. |
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
  "schema": 1, "product": "com.example.widget", "channel": "stable",
  "generated_at": "2026-09-22T08:25:06Z",
  "releases": [
    {
      "version": "1.4.2", "released_at": "2026-09-19T11:00:00Z", "security": true,
      "advisories": ["CVE-2026-31887"], "min_upgrade_from": "1.2.0",
      "notes_url": "https://example.com/releases/v1.4.2",
      "artefacts": {
        "x86_64-pc-windows-msvc": {
          "url": "https://updates.example.com/widget/1.4.2/widget-x86_64.exe",
          "size": 14782976,
          "sha256": "9f2c41b0e6a7d3c58e1b0a94f7d2c6b5a81e3f04c9d7b2a6e5f81c3d0b7a4e92",
          "signature": "RUSHfNAAaxT4a1v0nGJ1t0rD1hG8aGzQmO1J2sQx0k9pV7c0Xw…",
          "authenticode_subject": "CN=Example AB, O=Example AB, C=SE"
        },
        "aarch64-pc-windows-msvc": { "…same shape…" },
        "msi-x86_64": { "…same shape, no authenticode_subject…" }
      }
    }
  ],
  "rollout": { "stagger_hours": 24, "min_client_version": "1.0.0" }
}
```

`schema` is checked first and an unknown value is a hard stop: a client guessing
at a format it does not know parses attacker input optimistically (REQ-SEC-07).
Every field is bounded — 1 MiB body, 64 releases, 2 KiB strings. The per-artefact
`signature` is redundancy on top of the manifest signature, so an artefact
fetched from a mirror can be verified alone.

## The trust chain (REQ-UPD-02, REQ-UPD-03, REQ-UPD-04)

Four checks, in this order, none skippable, all before anything executes:

1. **Manifest signature.** `minisign-verify` 0.2.5 against the embedded public
   key. Failure stops here — the manifest is not even parsed into a release list.
2. **Artefact hash.** `sha2` 0.11.0 over the downloaded bytes against `sha256`
   from the signed manifest, and the byte count against `size`.
3. **Artefact signature.** Minisign over the artefact, same key.
4. **Authenticode.** `WinVerifyTrust` through `ffi::trust`, subject compared to
   `authenticode_subject` (REQ-SEC-02).

The key lives in the crate, not on the network:

```rust
// crates/update/src/trust.rs — rotate by shipping a version that trusts both.
const KEY_CURRENT: &str = include_str!("../keys/update-current.pub");
const KEY_NEXT:    &str = include_str!("../keys/update-next.pub");
```

A key fetched at update time is not a trust anchor: whoever serves a manifest can
serve a key, and verification then proves only that the server is self-consistent.
Two keys are embedded so rotation is possible; a rotation that skips the overlap
release strands every client that missed the intermediate version, recoverable
only by a manual reinstall.

Order matters as much as presence: hashing before verifying the manifest trusts
an unsigned hash, and checking Authenticode after launching verifies a running
process. `self-replace` 1.5.0 is called *after* step 4 — it swaps files, it does
not decide whether they deserve swapping.

Transport (REQ-SEC-01, REQ-UPD-04): `ureq` 3.4.2 with rustls, HTTPS only; a
non-HTTPS URL from manifest or policy is rejected, not upgraded. At most 3
redirects, HTTPS, same registrable domain. Timeouts 10 s connect, 30 s read,
30 min total, and a body exceeding `size` is abandoned mid-stream.

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
supported: `app.exe --update --rollback` restores B07's
`<program_dir>\rollback\app-<old>.exe` after re-verifying its signature — a local
revert, not a version the network chose.

## The atomic swap (REQ-UPD-06)

1. Download to `<data>\update\staging\<version>-<rand>.part`, in a directory
   whose DACL grants write to the installing user or `SYSTEM` only.
2. `FlushFileBuffers`, then hash, verify and Authenticode-check **from the same
   open handle the download wrote**. Re-opening by path between check and use is
   a TOCTOU window, and a hash-checked file swapped in that window is the attack.
3. Write `<data>\update\swap.journal` — `{from, to, aside, target_version,
   phase}` — and flush it before proceeding.
4. Swap. For the running image, `self-replace` 1.5.0: Windows permits renaming a
   running executable, so the old image is renamed aside and the new one moved
   in, both same-volume renames. For a file that is not running — the service
   binary — `ReplaceFileW`, which preserves the original's ACL, streams and
   attributes; delete-then-move loses them and silently widens the ACL. Every
   rename uses `MOVEFILE_WRITE_THROUGH`: Windows has no directory fsync and a
   plain rename can be lost across power loss while the data it points to is on
   disk, which is the difference between usually atomic and atomic.
5. Mark the journal `committed`, then delete staging.

**Recovery.** On every start, whichever binary survived reads the journal. No
journal or `committed`: nothing to do. `swapping` with the target present and
verifying: finish the swap. Target absent or unverifiable: restore the aside
copy. The invariant is old-or-new, and it holds because the unit of swap is one
file — which is why REQ-FND-12's single executable matters here. Side files, if
intake adds them, go in `<program_dir>\v<version>\` and the swap becomes one
directory rename under the same journal.

## Channels (REQ-UPD-07)

`stable` and `next`, at `https://updates.example.com/<product>/<channel>/manifest.json`.
The channel lives in `config`, is selectable in settings (REQ-UI-09) and is shown
in diagnostics with the last check time (REQ-OBS-03).

Both channels are signed with the same key: a channel is release selection, not
a trust boundary, and a key per channel would double the rotation problem for
nothing. Moving from `next` back to `stable` while the installed version is ahead
of stable's newest is not a silent downgrade — the client holds and says so:
*"You are on 1.5.0-next.3. Stable is 1.4.2. No update until stable passes
1.5.0."*

## Stagger and rate limiting (REQ-UPD-08)

**Per-install phase offset.** Base interval 6 h; the offset inside it is
`HMAC-SHA256(install_id, "update-check") mod 6h`. `install_id` is a random UUID
generated by B07 at install — not the machine SID, not the hostname, nothing
identifying the machine to a server (REQ-FND-10). Deterministic, so it survives
restarts and a fleet that reboots together at 08:00 does not check together at
08:00. **Per-check jitter** of ±10 % uniform goes on top, so installs cloned from
one golden image drift apart instead of sharing a phase.
**Manifest rollout window.** `rollout.stagger_hours`: a release is taken only
after `released_at + bucket × stagger_hours`, where
`bucket = HMAC-SHA256(install_id, version) / 2^256` in `[0,1)`. Stable per
install and per version, so a client never changes bucket between checks, and
release day spreads over a day with no server-side cohort service.

**Floor and ceiling.** At most one automatic check per hour whatever triggers it;
a manual check bypasses the schedule — its purpose — limited to one per 5 minutes.
No check in the first 120 s after start, so a logon autostart (REQ-SVC-09) does
not compete with the desktop appearing.

Failure backoff is 5 m, 15 m, 1 h, 6 h, capped, and **fully jittered**:
`sleep = random(0, cap)`. Unjittered exponential backoff re-synchronises a fleet
on the failure path, exactly when the server is already struggling. `ETag` makes
an idle check cost a 304; `Retry-After` on 429 or 503 is honoured up to 24 h.

## Updating a running instance (REQ-UPD-09)

Default `on_restart`: check, download, verify, swap, then notify — *"Update 1.4.2
installed. It will be used the next time the app starts."* — with **Restart now**
and **Later**. The swap is safe while running because Windows keeps the old image
mapped: the running process finishes on the old code, unchanged underneath it.

The app is never restarted with work in flight. B09 asks through the contract —
`BusyGuard::state() -> Busy`, where `Busy { what }` means no automatic restart,
ever. With `RestartDeadlineHours` set by policy the app reminds hourly past the
deadline and restarts itself only when `Busy::Idle` holds and no window has
focus. An updater that closes a window with unsaved work in it gets the product
uninstalled, and correctly.

## Service-mode ordering (REQ-UPD-10)

1. Read `service-state` from B08. `Unknown`, or IPC unavailable: abort before any
   state change and report. Do not guess at a service you cannot see.
2. Complete the whole trust chain. Verification always precedes state change.
3. `B08::begin(TransitionReason::Update(1.4.2))` returns a `TransitionToken`,
   which is what suspends B08's failure actions and crash-loop counting.
4. `B08::stop(&token, 30s)`. On timeout, release the token and abort with the
   service still running the old version.
5. Swap the service binary with `ReplaceFileW`, journalled as above, then
   `B08::start(&token, expect: 1.4.2, 60s)`.
6. Wait for `Running` **and** an IPC `Hello` reporting 1.4.2 (REQ-SVC-05). "The
   SCM says Running" is not "the new version works".
7. On start or handshake failure: restore the aside binary, start again, report
   loudly — Event Log, UI, `update-state.last_error` — and leave the service
   Running on the old version, never stopped (REQ-UPD-10). If the restore also
   fails, report `Stopped` with the exact recovery command: the one case where a
   human must act.
8. `B08::end(token)` re-arms the failure actions.

B09 never calls `sc.exe`, `CreateService` or a service-control wrapper. The
reason is ordering: B09 cannot know B08's restart policy or crash-loop threshold,
so a direct stop either races the SCM's own restart — relaunching the old binary
mid-swap — or counts as a failure and trips the detector into disabling the
service. A direct call gets the sequence right by luck, and luck is not a design.

## Failure handling (REQ-UPD-11)

Transport faults and verification faults are handled differently on purpose.

| Error | Retry? | Surface |
|-------|--------|---------|
| `Transport`, `Timeout`, `Http(5xx)` | yes, jittered backoff | diagnostics; tray after 3 consecutive or 72 h |
| `ManifestSignature`, `ArtefactSignature`, `ArtefactHash`, `Authenticode` | **no** | immediate notification, Event Log error, tray error state |
| `Downgrade`, `MinUpgradeFrom` | no | stated in the UI with the reason |
| `PolicyDisabled`, `Pinned` | no | shown as managed, not as an error |
| `ServiceTransition` | once, then stop | Event Log and UI, naming the service's state |
| `SwapInterrupted` | reconciled on next start | diagnostics, with what was restored |

A verification failure is never retried against the same URL. The artefact goes
to `<data>\update\quarantine\`, checks stop until a user or operator
acknowledges, and the event is raised immediately. A retry loop on a signature
failure is a machine politely re-downloading an attack.

Never silent means `last_check_at`, `last_success_at` and `last_error` are always
in diagnostics (REQ-OBS-03), and no successful check for 72 h is itself an error
state shown in the tray (REQ-TRY-04) — a check that stopped happening is how a
fleet sits unpatched for months. Repeat notifications are capped at one per 24 h;
one per failure trains people to dismiss them.

## Policy (REQ-UPD-12) and security updates (REQ-UPD-13)

`HKLM\Software\Policies\<Publisher>\<App>`, machine scope only, ADMX-shaped.
`HKCU` is not read for policy: a policy a user can rewrite is not a policy.

| Value | Type | Effect |
|-------|------|--------|
| `UpdateEnabled` | `REG_DWORD` | `0` stops all checks |
| `Channel` | `REG_SZ` | forces `stable` or `next` |
| `PinnedVersion` | `REG_SZ` | a semver requirement such as `1.4.x`, so patches inside the pin still land |
| `ManifestUrl` | `REG_SZ` | HTTPS only; a non-HTTPS value is rejected, not honoured |
| `SecurityUpdatesOnly` | `REG_DWORD` | take releases with `security: true`, skip the rest |
| `CheckIntervalHours`, `RestartDeadlineHours` | `REG_DWORD` | interval clamped to 1–168; deadline `0` never restarts automatically; `AllowDowngrade` gates the forced path above |

Precedence is policy, then config, then default. Policy wins in effect but never
invisibly: the settings control is disabled and labelled *"Managed by your
organisation"* with the exact key and value, and diagnostics prints each
setting's effective source. `UpdateEnabled = 0` disables security updates too and
the UI says so in those words — a policy that silently exempts a class of update
is one an operator cannot reason about.

`SecurityUpdatesOnly = 1` is the honest version of separability: take the newest
release with `security: true`, skip feature releases above it. What it cannot do
is deliver the fix without the changes that shipped before it — one binary, no
maintenance branches, so taking 1.4.2 brings everything between the running
version and 1.4.2. The operator's real choice is "take 1.4.2 now, skip 1.5.0",
which is what REQ-UPD-13 and REQ-CRA-07 need; true per-fix backports are a
release-engineering commitment recorded at intake.

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|----------|--------|-----|--------------------|
| Signature scheme, key location, check order | minisign via verify-only `minisign-verify` 0.2.5; current + next keys via `include_str!` from `crates/update/keys/`; manifest signature → hash → artefact signature → Authenticode | The binary never signs, so it never needs a private key; a key fetched at update time is not a trust anchor (REQ-UPD-03); rotation needs an overlap release or clients are stranded; any other check order verifies something already trusted, or already running | no |
| Transport, swap | `ureq` 3.4.2 + rustls, HTTPS only, 3 same-domain redirects; `self-replace` 1.5.0 running, `ReplaceFileW` not running, always `MOVEFILE_WRITE_THROUGH` | A non-HTTPS URL is rejected, not upgraded (REQ-SEC-01); atomicity across power loss with ACLs preserved (REQ-UPD-06) | no |
| Downgrade, channels | refused unless flag + policy + elevation; `stable` and `next` under one key | A downgrade reintroduces patched vulnerabilities (REQ-UPD-05); a channel is release selection, not a trust boundary | a third channel |
| Check interval, backoff, stagger key | 6 h offset by `HMAC(install_id)`; 5 m → 6 h fully jittered; `install_id` a random UUID made at install | Deterministic de-synchronisation without a server, and unjittered backoff re-synchronises a struggling fleet (REQ-UPD-08); a stagger key must not identify the machine (REQ-FND-10) | interval 1–168 h |
| Restart, verification failure | asked for, never taken while `Busy`; a failed check quarantines, stops and notifies | Killing in-progress work ends the product (REQ-UPD-09); retrying an attack is not resilience (REQ-UPD-11) | deadline hours |
| Service transitions, policy scope | B08's token always; `HKLM` only | B09 cannot know the restart policy (REQ-UPD-10); a user-writable policy is not a policy (REQ-UPD-12) | no |

## How this is verified

Against a real signed manifest with a real key pair, and the negatives are the
point (REQ-TST-03):

- **Wrong signature.** A manifest signed with an untrusted key, and one with one
  byte of the signature altered. Both fail at check 1, nothing downloaded and
  nothing parsed into a release list.
- **Tampered artefact.** A correctly signed manifest whose artefact has one byte
  flipped: fails at check 2, quarantines the file, does not retry.
- **Downgrade attempt.** A signed manifest offering 1.3.0 to a 1.4.2 client:
  refused, logged, no download — and still refused with `--force-version` present
  and `AllowDowngrade` absent.
- **Interrupted swap.** Kill the process between each journal phase — after the
  journal write, after the aside rename, after the move — and assert on next
  start that the binary is either the old or the new one, that it runs, and that
  the version it reports matches the file on disk.
- Bounds and schema: a 2 MiB manifest, `schema: 2`, 10 000 releases, a 5 MiB
  string, a `size` smaller and larger than the real artefact — all rejected
  without allocating to match (REQ-SEC-07). Stagger: 10 000 synthetic
  `install_id`s over a 24 h window, asserting no bucket holds more than 2 % and
  that a given id is stable across runs.
- Service ordering: the sequence `state → begin → stop → swap → start →
  handshake → end`, and that a failed start restores the old binary and leaves
  the service `Running`. Static assertions: `crates/update` contains no
  `windows::Win32` import (REQ-FND-03) and no `sc.exe` string.

Fixture note: `minisign-verify` cannot sign, so fixture key pairs and signed
manifests are generated once out of band and committed under
`crates/update/tests/fixtures/` with the procedure beside them. Generating them
in CI needs a signing-capable crate validated by B16 — not a version written
from memory (REQ-VER-02).

## Open to intake

- Manifest base URL, and the channel names if not `stable` and `next`.
- Base check interval, and whether a rollout window is used at all.
- Whether `RestartDeadlineHours` is set for the fleet, and whether the MSI is an
  update artefact or only a first install.
- Whether maintenance branches exist — the only way true per-fix security
  updates become possible (REQ-UPD-13).
