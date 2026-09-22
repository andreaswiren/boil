# Logging & Diagnostics

Structured logs, a runtime-adjustable level, the diagnostics view support reads
instead of asking the user to find a file, the one-action support bundle, local
crash records, and the Windows Event Log in service mode. Owned by **B12**
(`observability`, `crates/obs/**`), which publishes `log-record` and
`diagnostics` and consumes `config` (B02), `paths` (B01), `version` (B01/B17),
`design-tokens` (B03) for its settings panel, `service-state` (B08) and
`ffi::event_log` / `ffi::crash` (B01). B12 calls no Win32 API directly and
invents no colour. It writes nothing outside `crates/obs/**`: the Event Log
**registration** is B07's (it writes the registry), the panel host is B05's, and
B12 supplies the declaration each of them consumes.

## Requirements covered

REQ-OBS-01, REQ-OBS-02, REQ-OBS-03, REQ-OBS-04, REQ-OBS-05, REQ-OBS-06,
REQ-SEC-08, REQ-SEC-05, REQ-FND-10, REQ-SBM-06, REQ-CRA-08, REQ-UI-06.

## 1. One dependency B12 does not yet have

`versions/manifest.json` carries `tracing 0.1.44` and nothing else for this
domain. `tracing` alone cannot format or write a record, so B12 files one
dependency request to B16 at H2 — `tracing-subscriber`, for the JSON formatting
layer and the reloadable filter of §3 — and writes no `Cargo.toml` line until the
validated version is in the manifest (REQ-VER-02, REQ-FND-08).

It requests exactly one. The rotating writer is **ours**, not
`tracing-appender`'s, because `tracing-appender` rotates on a clock — hourly,
daily, never — and REQ-OBS-01 requires a **size** cap. A time-rotated log with no
size bound is exactly the disk-filling failure the requirement names, and a
second dependency that does not do the job is a shipping decision with no payoff
(REQ-SBM-05).

## 2. Where the log goes, and why it cannot fill a disk (REQ-OBS-01)

Every path comes from `paths` (REQ-SEC-05). B12 resolves no directory itself.

| Mode | Location | DACL |
|---|---|---|
| Interactive | `paths::logs()` = `%LOCALAPPDATA%\<Vendor>\<App>\logs\` | User only |
| Service | `paths::service_data()\logs\` under `%PROGRAMDATA%` | SYSTEM + Administrators full, `LocalService` write, Users read |

The service log is deliberately not under
`%WINDIR%\ServiceProfiles\LocalService\AppData\`, which is where `LocalService`'s
own `%LOCALAPPDATA%` resolves and which no administrator thinks to look in. Users
can read it, which is why REQ-SEC-08's redaction applies to it as hard as to the
bundle.

**A tray app runs for months.** The cap is enforced by three mechanisms, not one:

1. **Rotate at 8 MB**, checked before each write batch rather than on a timer,
   because a timer never fires in the tick where a process is being killed.
2. **Keep 10 files, 80 MB per set**, oldest deleted on roll. A startup sweep
   re-enforces the total, because a killed process leaves files behind that no
   roll accounted for.
3. **Free-space floor of 256 MB.** Below it, the level drops to `warn`, one
   event records the drop, and logging never fails the app. A logger that
   propagates a write error is a logger that takes the product down.

Open with `FILE_SHARE_READ | FILE_SHARE_DELETE` so support can copy the file
while the app runs, and so a lock from a backup agent does not stall a write. If
the current file cannot be opened at all, fall back to `<name>.1.jsonl` and log
that fallback once.

## 3. The record, and the level at runtime (REQ-OBS-02)

One JSON object per line. Timestamps are UTC RFC 3339 with milliseconds, never
local time — a support bundle crossing two time zones with local timestamps
cannot be correlated with anything.

```json
{"ts":"2026-09-22T08:25:06.412Z","level":"warn","target":"update::check",
 "span":"update_check{attempt=2}","msg":"manifest fetch failed",
 "err":{"code":"UPD-0042","win32":12007},"req":"REQ-UPD-11",
 "pid":7412,"tid":9001,"ver":"1.4.2+a1b2c3d","mode":"app","instance":"01JB…"}
```

`req` carries the REQ ID where the event is requirement-relevant, which is how a
gate verifies a behaviour happened rather than trusting that it was implemented.

The level changes at runtime with no restart and no registry edit. A
`tracing_subscriber` reload handle sits behind four inputs, in precedence order:
an IPC command from B08's `ipc-contract` (service mode), the settings control in
B12's Diagnostics panel, a watched change to the config file, and the
`--log-level` flag at launch. Two rules make it usable rather than dangerous:
the change takes effect on the next record, and **a level raised above `info`
expires after 15 minutes** and returns to the configured level with an event
recording it. Support tells a user to turn on debug; nobody turns it off, and the
80 MB cap then evicts the history that was actually wanted.

## 4. The diagnostics view (REQ-OBS-03)

The questions support asks, answered without asking the user to find a file. B12
publishes `DiagnosticsSnapshot` and renders the panel from inside `crates/obs`,
registered through B05's `settings-registry` — B12 does not open a file in
`crates/ui`.

| Field group | Contents |
|---|---|
| Identity | Version, commit, build time, target triple, toolchain, MSRV |
| Install | Mode (per-user/machine), install path, ARP entry present, install log path |
| Runtime | Running as, elevated yes/no, session, uptime, OS build and the §4 floor check |
| Service | Installed, state, account, service version, version-mismatch flag (REQ-SVC-05) |
| Startup | Autostart on/off and mechanism (`Run` key or scheduled task) |
| Updates | Channel, automatic on/off, last check, last result, next check, pinned by policy |
| Logs | Path, current level, whether a temporary level is active, bytes used of the cap |
| Errors | Last five errors with code, timestamp and REQ ID |
| Support | End-of-support date (REQ-CRA-08), embedded dependency list present (REQ-SBM-02) |

"Copy all" puts the whole snapshot on the clipboard as text, and the same
snapshot is `diagnostics.json` inside the bundle. One producer, two surfaces: a
view that formats its own fields drifts from the bundle support actually reads.

## 5. The support bundle (REQ-OBS-04, REQ-SEC-08)

One action, from the Diagnostics panel or the tray menu. The user picks the
destination with `rfd 0.17.2`'s **async** dialog, and the zip is built on a
worker thread — the blocking dialog and a synchronous zip would both violate
REQ-UI-06 in the one feature a user invokes while something is already wrong.

Contents, packaged with `zip 8.6.0`: the whole log set including rotated files,
`diagnostics.json`, the effective configuration, the embedded dependency list,
B07's install log (REQ-INST-12), the update history, the last crash records, this
provider's Event Log entries for the last 7 days, and `MANIFEST.txt` listing
every file with its SHA-256.

**Redaction happens on the way in, never as a pass over a finished zip.** Every
string is routed through one redactor, used by the log writer, the crash writer
and the bundle alike, so a value that never reaches a file needs no removing:

| Pattern | Action |
|---|---|
| `Authorization:` / `Bearer …` / `Basic …` | Replaced with `<redacted:auth>` |
| A base64 or hex run of 40+ characters | `<redacted:blob>` |
| `scheme://user:pass@host` | Userinfo replaced |
| `-----BEGIN … KEY-----` block | Whole block replaced |
| Credential-store and DPAPI values | Never logged; the key name only |
| `C:\Users\<name>\` | Rewritten to `C:\Users\<redacted>\` |

The last row is honest about a real limitation: the username appears in nearly
every per-user path, so the redactor rewrites the prefix and `MANIFEST.txt`
states that it did. A bundle that claims no personal data while carrying the
user's name in 400 paths is worse than one that says what it changed.

Verified by canary, not by inspection: a test seeds a distinctive token into the
config, the log and a crash record, builds a bundle, extracts it, and greps every
file for the canary. A hit fails the build (REQ-SEC-08).

## 6. Crash records, local and only local (REQ-OBS-05, REQ-FND-10)

Two hooks, because Rust panics and Win32 faults are different events.
`std::panic::set_hook` catches the panic; `ffi::crash::set_unhandled_filter`
(B01's wrapper over `SetUnhandledExceptionFilter`) catches the access violation
in a callback that a panic hook never sees. Both write the same record:

```rust
pub struct CrashRecord {
    pub ts: OffsetDateTime, pub version: String, pub commit: String,
    pub target: String, pub os_build: u32, pub mode: RunMode,
    pub kind: CrashKind,          // Panic { message } | Exception { code, address }
    pub thread: Option<String>, pub backtrace: String,
    pub fingerprint: String,      // hash of the top 5 normalised frames
    pub tail: Vec<LogRecord>,     // last 200 records from an in-memory ring
}
```

The ring buffer is the point: the log file may hold nothing from the final
milliseconds because the writer had not flushed. The fingerprint is what makes
"this has happened 14 times" a fact rather than an impression.

Records go to `paths::crash()`, capped at 20 records and 50 MB. **No minidump by
default** — a minidump contains process memory, therefore whatever the user
typed, and shipping that by default is a privacy decision nobody made. It is
available behind an explicit setting and written beside the record when enabled.

Nothing is transmitted. The UI offers "Open folder" and "Add to support bundle";
there is no "Send report" button, because a per-incident user action means the
user hands a file over deliberately (REQ-FND-10). A test asserts no network call
originates from the crash path, alongside B11's build-time and runtime telemetry
assertions (REQ-SBM-06).

## 7. The Event Log, in service mode (REQ-OBS-06)

Service-mode records go to the structured log **and** to the Windows Event Log,
because that is where an administrator looks and a JSONL file under
`%PROGRAMDATA%` is not. Written with `ReportEventW` through `ffi::event_log`.

B12 declares the source name, the event-ID table and the message resource. **B07
writes the registry key** at install time and re-writes it when an update moves
the executable — one owner per registration (`contracts/ownership.md`). Without a
valid `EventMessageFile`, Event Viewer shows *"The description for Event ID …
cannot be found"*, which is the classic form of this defect; the message table is
embedded in the executable itself by B01's `build.rs`, so a self-contained binary
stays self-contained (REQ-FND-12) and the key points at the installed path.

Not every log line goes here. An allow-list of nine events, rate-limited to one
per event ID per minute, because flooding the Application log is how an
administrator learns to filter your source out:

| ID | Level | Event |
|---|---|---|
| 1000 | Information | Service started, with version and account |
| 1001 | Information | Service stopped, with the requested transition |
| 1002 | Error | Service failed to start, with the reason |
| 1010 | Information | Update applied, old version → new version |
| 1011 | Error | Update failed after N retries (REQ-UPD-11) |
| 1020 | Error | Crash-loop detected, restart count and window (REQ-SVC-10) |
| 1030 | Warning | Configuration rejected, with the offending key |
| 1040 | Warning | IPC authentication failure, with the caller SID (REQ-SEC-09) |
| 1050 | Error | Unsupported OS at startup, with the detected build (REQ-FND-05) |

**Event IDs are permanent.** An administrator's alert rule cites the number, so
an ID is never renumbered and never reused for a different event — the same rule
the requirement register applies to REQ IDs, for the same reason.

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Formatting layer | `tracing-subscriber`, version from B16 at H2 | `tracing` alone cannot write | No |
| Rotating writer | Ours, not `tracing-appender` | Time rotation cannot honour a size cap | No |
| Format | JSONL, UTC RFC 3339 with ms | Local time cannot be correlated | No |
| Rotation / retention | 8 MB, 10 files, 80 MB per set | REQ-OBS-01 | Yes |
| Free-space floor | 256 MB, then drop to `warn` | Logging never takes the product down | Yes |
| Default level | `info`; `debug` expires after 15 min | Nobody turns debug off again | Yes |
| Service log location | `%PROGRAMDATA%`, explicit DACL | `LocalService`'s own profile is unfindable | No |
| Diagnostics source | One `DiagnosticsSnapshot` | A second formatter drifts from the bundle | No |
| Redaction point | On the way in, one redactor | A pass over the zip misses the log | No |
| Username in paths | Prefix rewritten, stated in `MANIFEST.txt` | Honest beats silently incomplete | No |
| Minidump | Off | It contains whatever the user typed | Yes |
| Crash transmission | None, and no send button exists | REQ-FND-10, REQ-OBS-05 | No |
| Event Log events | Nine IDs, allow-listed, rate-limited | A flooded log gets filtered out | Yes, additively |
| Event ID stability | Permanent, never reused | Admin alert rules cite the number | No |

## How this is verified

- `cargo test -p obs` — rotation at the byte boundary, the 10-file and 80 MB caps
  under a synthetic 500 MB write, the startup sweep against files left by a
  killed process, and the free-space floor with a simulated full volume
  (REQ-OBS-01).
- A level change through each of the four inputs takes effect on the next record
  with no restart, and a `debug` override reverts after 15 minutes with the event
  recorded (REQ-OBS-02).
- `tests/obs/bundle_canary.rs` — a canary token seeded into config, log and crash
  record does not appear in any extracted bundle file, and `MANIFEST.txt` lists
  every file with a matching SHA-256 (REQ-OBS-04, REQ-SEC-08).
- `tests/obs/crash.rs` — a forced panic and a forced access violation each
  produce a record with a stable fingerprint and a 200-record tail; repeats share
  the fingerprint; no minidump exists unless the setting is on; no socket is
  opened on the crash path (REQ-OBS-05, REQ-FND-10, REQ-SBM-06).
- `tests/obs/eventlog.rs` on a Windows image — each of the nine IDs renders a
  full description in Event Viewer (no "description … cannot be found"), the rate
  limit holds under a 100-event burst, and the source survives an update that
  moved the executable (REQ-OBS-06).
- Every field group in §4 is populated on a clean install, and B15 captures the
  Diagnostics panel in both themes (REQ-OBS-03, REQ-TST-04).

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| Log retention | 8 MB × 10 files, 80 MB per set |
| Default level | `info` |
| Temporary-level expiry | 15 minutes |
| Minidump on crash | Off |
| Extra Event Log events | None beyond the nine in §7 |
