# Service & Autostart

Owned by **B08 `service-autostart`** (Wave 3). B08 owns `crates/service/**` and
`crates/autostart/**`, and it owns two *registrations*: the Windows service
entry and the autostart entry (`contracts/ownership.md`). Nobody else calls
`sc.exe`, `CreateService` or the service-control wrappers, and nobody else
writes the `Run` key or creates a scheduled task — not B07 at install time, not
B09 during an update. B08 publishes `service-state` and `ipc-contract`; it
consumes `config`, `paths` and `version`.

B08 is dispatched only when intake turns on service mode (REQ-SVC-01 is `OPT`).
The autostart half ships either way.

`windows-service` 0.8.1 and `windows-registry` 0.100.0 are called directly here,
which `versions/manifest.json` records as B08's. Every other Win32 call goes
through a B01 `crates/ffi` wrapper; needing a new one is a CCR, never a
`use windows::Win32::…` in these crates (REQ-FND-03).

## Requirements covered

| ID | How this spec covers it |
|----|------------------------|
| REQ-SVC-01 | The same binary runs as a service under `--service run`, dispatched through `windows-service` 0.8.1. |
| REQ-SVC-02, REQ-SVC-04 | `--service install\|start\|stop\|uninstall\|status`, each with an exit code and never implicit in an app install; an explicit status machine that reports `StartPending` with checkpoints while initialising and `Running` only once the endpoint is live. |
| REQ-SVC-03 | Virtual service account by default; `LocalService` as the alternative; `LocalSystem` only with a recorded justification. |
| REQ-SVC-05 | Handshake carrying protocol version and semver; a mismatch is reported, not worked around. |
| REQ-SVC-06, REQ-SEC-09 | Named pipe with an explicit DACL, caller authenticated by SID and image, no network socket by default. |
| REQ-SVC-07, REQ-SVC-08 | Per-user `Run` key by default, Task Scheduler where a delay or a condition is needed; default off, visible in settings, removed on uninstall. |
| REQ-SVC-09 | Autostart launches with `--tray`: no window, no focus steal during login. |
| REQ-SVC-10 | Declared `SERVICE_FAILURE_ACTIONS` plus in-process crash-loop detection that stops restarting and reports. |
| REQ-FND-11, REQ-OBS-06, REQ-TST-07 | Nothing here elevates the app: the service runs as its own low-privilege account and autostart never uses `RunLevel=Highest`. Events go to the structured log and the Event Log; lifecycle, crash recovery and version mismatch are tested. |

## Service mode from the same binary (REQ-SVC-01)

One executable, three modes, selected by `clap` 4.6.7: `app.exe` is the
interactive UI with tray, `app.exe --tray` is the same minimised with no window
(REQ-SVC-09), and `app.exe --service run` is the ServiceMain entry point, only
ever launched by the SCM.

`--service run` calls `service_dispatcher::start`, which must happen within
about 30 seconds of process start or the SCM reports error 1053. So the service
path does no configuration parsing, no network and no disk scan before
dispatch: it registers the control handler first and initialises afterwards,
under `StartPending`.

## The account (REQ-SVC-03)

Default: a **virtual service account**, `NT SERVICE\<ServiceName>`, passed as the
account name with a null password at `CreateService` time.

It is the default because it has a unique SID, which can be named in an ACE:
`%ProgramData%\<Publisher>\<App>\state` grants write to this service and
nothing else. `LocalService` has no such property — it is shared by dozens of
services, so an ACE for `NT AUTHORITY\LocalService` grants every other
LocalService-hosted service on the machine. It is the alternative only when the
service needs no writable state of its own.

`LocalSystem` is refused. Installing with `--service-account LocalSystem`
requires a requirement ID and a one-line reason recorded in `build/waivers.md`;
without that record the command exits `29`. `LocalSystem` is the machine's
`SYSTEM` token: any memory-safety bug, any path handled from an untrusted
source, any IPC parsing bug in that process is a full machine compromise.

Hardening applied at install, through the `windows-service` config:

- `SERVICE_CONFIG_REQUIRED_PRIVILEGES` set to `SeChangeNotifyPrivilege` only, so
  the SCM strips every other privilege from the token. A service that does not
  ask for a privilege cannot be tricked into using it.
- `SERVICE_CONFIG_SERVICE_SID_INFO` set to `SERVICE_SID_TYPE_UNRESTRICTED`, so
  the per-service SID is in the token and can be ACLed against. Restricted is an
  intake option: stronger, and it breaks every write whose ACL omits that SID.
- `SERVICE_CONFIG_DELAYED_AUTO_START_INFO` true — a tray app's helper has no
  business competing with logon for disk.
- No service dependencies. The service tolerates having no network rather than
  declaring `Tcpip` and pretending the network is a startup precondition.

## Lifecycle (REQ-SVC-04)

Accepted controls: `STOP | SHUTDOWN | PAUSE_CONTINUE`.

| State reported | When | `wait_hint` |
|---------------|------|-------------|
| `StartPending{checkpoint: 1..3}` | handler registered (1), config loaded and log open (2), pipe created with its DACL (3) | 5 s each |
| `Running` | the pipe is accepting and the worker loop is live | — |
| `StopPending` | stop received, work draining | 10 s |
| `Stopped` | drained, handles closed | — |
| `Paused` | worker loop suspended, pipe still answering `GetStatus` | — |

Reporting `Running` before the endpoint accepts is the defect this table exists
to prevent: the UI connects, gets `ERROR_FILE_NOT_FOUND`, and reports "service
not running" about a service the SCM calls healthy. Checkpoints increment, so
the SCM sees progress rather than a stall.

`SERVICE_CONTROL_SHUTDOWN` is not `SERVICE_CONTROL_STOP`. Windows gives a
service a few seconds at shutdown and then kills it, so the shutdown path
flushes the log and the state journal and returns rather than draining. A
service that treats shutdown like stop is killed mid-write, and the corrupt file
is found at the next boot. `Paused` keeps the pipe answering status queries: a
paused service that goes quiet is indistinguishable from a dead one.

## Version mismatch (REQ-SVC-05)

Both sides compile in `version::SEMVER` and `contracts::IPC_PROTOCOL` from B02.
The first frame on every connection is `Hello`, and the rules are exact:

- Different `IPC_PROTOCOL`: refuse. Protocol compatibility is equality, not a
  range — a range is a claim nobody tested.
- Same protocol, different semver: the connection stays open but is
  **restricted**. Only `GetStatus` and `GetVersion` are answered; every other
  request returns `VersionMismatch { service, client }`.

Restricted rather than refused, because the UI has to explain: *"The background
service is running 1.4.1, this app is 1.4.2. Restart the service to finish the
update."* A refused connection produces a spinner and a support ticket. The CLI
equivalent exits `24`. This state is normal for a few seconds during an update,
and keeping it short is what REQ-UPD-10's ordering is for.

## The IPC contract (REQ-SVC-06, REQ-SEC-09)

A named pipe. `\\.\pipe\<Publisher>-<App>-svc-v1` — the protocol version is in
the name, so an incompatible pair fails to connect instead of misparsing.

Never a TCP or loopback socket by default. A loopback listener is reachable by
every process of every user on the machine, it is reachable through some
hypervisor and VPN configurations, and it cannot name its caller. A network
endpoint is an explicit intake decision with mutual TLS, and it is not this.

Server side, created through the `ffi::pipe` wrapper B01 publishes:

- `CreateNamedPipeW` with `FILE_FLAG_FIRST_PIPE_INSTANCE`. Without it, a process
  that got there first owns the name and harvests every connection.
- An explicit DACL, built from SDDL: `D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;0x12019b;;;<user SID>)`
  — full control to `SYSTEM` and `Administrators`, read/write/query to the SID
  recorded at install, and no other ACE. Not `WD`, not `AU`, and specifically not
  `IU`: on a Remote Desktop host, interactive users means every session.
- One pipe instance per connection, a 1 MiB cap on a frame, length-prefixed
  (`u32` LE) `serde` JSON, and the length rejected before allocation
  (REQ-SEC-07).

Caller authentication, on every connection before the first request is served:

1. `ImpersonateNamedPipeClient`, then `GetTokenInformation(TokenUser)` to read
   the caller's SID. Compare against the allow-list recorded at install. Revert
   immediately.
2. `GetNamedPipeClientProcessId`, then check the caller's image path is the
   installed binary and its Authenticode signature verifies (REQ-SEC-02).

Local origin is not authentication. "It came from this machine" includes every
other user on a shared or RDS host, and inside one session it includes every
process that user runs. The DACL narrows who can open the pipe; the two checks
above decide who is answered.

The client authenticates the server too: it opens with
`SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION`, so a compromised server
cannot impersonate the user beyond identification, and it verifies the pipe
owner's SID is `SYSTEM` or `Administrators` — otherwise a same-user process that
creates the pipe first collects whatever the UI sends.

## Autostart (REQ-SVC-07, REQ-SVC-08, REQ-SVC-09)

**Default mechanism: the per-user `Run` key.**
`HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, value name `<App>`, data
`"<program_dir>\app.exe" --tray`, written with `windows-registry` 0.100.0.

Chosen because it needs no elevation, is per-user by construction, is removed by
deleting one value, and — the deciding reason — Windows itself shows it in Task
Manager's Startup tab and in Settings, so a user who wants it gone can remove it
without finding our settings page. A mechanism the user can already see and
control is the honest default for something that runs without being asked.

The quoting is not cosmetic: an unquoted path with spaces makes Windows try
`C:\Program.exe` first, which is a hijack primitive wherever that path is
writable.

**Task Scheduler** (`ITaskService` through `ffi::tasks`, task
`\<Publisher>\<App>\Logon`) is used when, and only when, the `Run` key cannot
express what is needed:

| Need | Mechanism | Why |
|------|-----------|-----|
| Start at logon, nothing else | `Run` key | Visible to the user, no elevation, trivial to remove |
| A delay after logon | Task Scheduler | `Run` has no delay; a `LogonTrigger` has `Delay = PT60S` |
| Start only on AC power, or only with a network | Task Scheduler | `Run` has no conditions |
| Start with no user logged on | neither — that is service mode | An autostart entry without a session is a service wearing a costume |

`RunLevel=Highest` is never set: a scheduled task that runs elevated at logon is
a documented UAC bypass, and shipping one undoes REQ-FND-11 in one XML
attribute. Rules holding for both mechanisms:

- Default **off** (REQ-SVC-07). It is offered at install (`--autostart`) and in
  settings, never assumed.
- Created for the installing user only (REQ-SVC-08). A machine-wide install does
  **not** write `HKLM\…\Run`: starting the app for every account on the machine
  is not what anyone asked for.
- Removed on uninstall, both mechanisms checked, and removed when the recorded
  path no longer matches the installed binary — a stale `Run` value pointing at
  a deleted path is a failure dialog at every logon.
- Visible in settings (REQ-SVC-08, REQ-UI-09). The toggle reads live state, and
  it reads `HKCU\…\Explorer\StartupApproved\Run` as well: if Explorer has
  disabled the entry, the UI says *"Disabled in Task Manager → Startup"* instead
  of showing a toggle that lies.
- `--tray` starts minimised, no window, no activation (REQ-SVC-09), and holds
  off the first update check for 120 s so login is not competing with a download
  (REQ-UPD-08).

## Failure recovery and crash loops (REQ-SVC-10)

Declared failure actions, set with `ChangeServiceConfig2`:

| Setting | Value |
|---------|-------|
| `dwResetPeriod` | 86400 s |
| Action 1 | `SERVICE_ACTION_RESTART`, 5 s delay |
| Action 2 | `SERVICE_ACTION_RESTART`, 30 s delay |
| Action 3 | `SERVICE_ACTION_NONE` |
| `SERVICE_CONFIG_FAILURE_ACTIONS_FLAG` | `TRUE` |

The third action is deliberately `NONE`. A service that restarts forever turns a
deterministic startup failure into a silent loop that burns CPU and fills the
Event Log, and nobody looks until the disk is full. The flag matters as much as
the actions: without `SERVICE_CONFIG_FAILURE_ACTIONS_FLAG` the actions fire only
on abnormal termination, so a service that exits cleanly with a non-zero code is
never restarted — a defect found months later.

In-process detection, because the SCM's counter resets and ours does not:
each start appends `{ts, pid, version, outcome}` to
`<data>\state\service-starts.jsonl`. Three starts within 10 minutes without one
reaching `Running` is a crash loop. B08 then:

1. Reports `Stopped` with `ServiceSpecificExitCode = 25`, and writes Event Log
   error 2501 with the last error and the start records (REQ-OBS-06).
2. Sets `service-state.health = CrashLoop { starts, window }`, which the tray
   shows as an error state (REQ-TRY-04) and diagnostics shows with the last
   error (REQ-OBS-03).
3. Does not start again until `--service start` is run explicitly.

## The update seam (REQ-UPD-10)

B09 never stops this service itself. B08 publishes a transition token:
`begin(reason)` suspends failure actions and crash-loop counting and returns a
token; `stop(&token, timeout)` and `start(&token, expect_version, timeout)` run
the transition; `end(token)` re-arms. B09 holds the token across its swap.

The reason is ordering, not politeness. B09 does not know the restart policy or
the crash-loop threshold, so `sc.exe stop` followed by a swap either races the
SCM's own restart — relaunching the old binary mid-swap — or counts as a failure
and trips the crash-loop detector into disabling the service. That sequence
without the token is right by luck.

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|----------|--------|-----|--------------------|
| Service account | virtual `NT SERVICE\<name>` | Unique SID that can be named in an ACE (REQ-SVC-03) | `LocalService`; `LocalSystem` only with a recorded reason |
| SID type, start type, privileges | unrestricted SID; delayed auto-start; `SeChangeNotifyPrivilege` only | Restricted breaks writes whose ACL omits the SID; a helper does not compete with logon; a privilege not requested cannot be abused | yes, each with a reason |
| IPC transport | named pipe, version in the name | Nameable caller, ACL-able endpoint, no network exposure (REQ-SVC-06) | network only as an explicit mTLS decision |
| IPC framing, caller auth | length-prefixed JSON with a 1 MiB cap; SID allow-list plus image path and signature | Bounded before allocation (REQ-SEC-07); local origin is not authentication (REQ-SEC-09) | framing only |
| Version mismatch | restricted connection, status only | The UI must explain rather than spin (REQ-SVC-05) | no |
| Autostart mechanism | per-user `Run` key | Visible and removable in Windows' own UI; no elevation (REQ-SVC-07) | Task Scheduler where a delay or condition is needed |
| Autostart default, scope, elevation | off; installing user only; never `RunLevel=Highest` | Nothing runs at logon unasked (REQ-SVC-07); `HKLM\…\Run` starts it for everyone (REQ-SVC-08); an elevated logon task is a UAC bypass (REQ-FND-11) | default only |
| Failure actions | restart 5 s, restart 30 s, then none | A forever-loop is a silent fault (REQ-SVC-10) | delays, not the third action |
| Crash-loop threshold | 3 starts in 10 minutes | Survives the SCM's own reset period | yes |

## How this is verified

- `cargo test -p service` — status transition table, `Hello` handshake matrix
  (equal, protocol mismatch, semver mismatch), frame-length rejection, SDDL
  construction, start-record parsing, crash-loop arithmetic. `cargo test -p
  autostart` — `Run` value quoting, `StartupApproved` reading, stale-path
  detection, and the mechanism-selection table above.
- On a Windows image (REQ-TST-07): install, start, stop, pause, continue,
  uninstall, uninstall again; a forced crash three times inside 10 minutes,
  asserting `ServiceSpecificExitCode = 25`, Event Log 2501 and no fourth start;
  and a deliberate version-mismatch run asserting that only `GetStatus` and
  `GetVersion` answer.
- IPC negative tests: a second process pre-creating the pipe name fails against
  `FILE_FLAG_FIRST_PIPE_INSTANCE`; a different user's SID is refused; an
  unsigned binary at another path is refused; a 2 MiB frame is rejected without
  allocating 2 MiB.
- Account assertion: read back `QueryServiceConfig` and fail on `LocalSystem`
  without a matching entry in `build/waivers.md` (REQ-SVC-03). After uninstall,
  neither the `Run` value nor the scheduled task exists (REQ-SVC-08).

## Open to intake

- Whether service mode is needed at all (REQ-SVC-01 is `OPT`), and the service
  name, display name and description.
- Whether the service needs writable state (virtual account vs `LocalService`).
- Whether a logon delay or a power/network condition is required — that is what
  moves autostart to Task Scheduler.
- Which SIDs beyond the installing user may use the IPC endpoint, and whether
  autostart is offered pre-checked for a managed fleet.
