# Installer & Elevation

Owned by **B07 `installer`** (Wave 3). B07 owns `crates/install/**` and
`packaging/wix/**`, and it owns exactly three kinds of machine state: files in
the install directory, the Add/Remove Programs entry, and shortcuts
(`contracts/ownership.md`). It does not create the service, it does not write
the `Run` key, and it does not replace an installed binary afterwards — those
are B08's and B09's transitions, reached through the contract. B07 publishes
`install-mode` and `exit-codes`; it consumes `paths`, `version` and the public
half of `signing-keys`.

`windows-registry` 0.100.0 is called directly here for the ARP entry, which
`versions/manifest.json` records as B07's. Every other Win32 call goes through a
B01 `crates/ffi` wrapper; needing a new one is a CCR, never a
`use windows::Win32::…` in this crate (REQ-FND-03).

## Requirements covered

| ID | How this spec covers it |
|----|------------------------|
| REQ-INST-01 | `app.exe --install` installs completely from the shipped binary. No second download. |
| REQ-INST-02, REQ-INST-04 | Per-user default, no elevation; `--machine` elevates by re-launching an elevated child when it is needed, after stating why. |
| REQ-INST-05, REQ-INST-10 | ARP field table below; Start Menu shortcut always, desktop only when asked. |
| REQ-INST-06, REQ-INST-07 | Uninstall removes every registration it can name and asks about user data; every step is a desired-state assertion, so install, upgrade, repair and uninstall are re-runnable. |
| REQ-INST-08, REQ-INST-09 | The image verifies its own Authenticode signature and hashes every file it writes before activation; failure rolls back by reverse journal replay. |
| REQ-INST-03, REQ-INST-11, REQ-INST-12 | An MSI with the same option surface for GPO; `--silent` with the exit-code table below; a JSON Lines log at a documented path. |
| REQ-FND-11 | The application manifest stays `asInvoker`; only this path elevates, and only in a child process. |
| REQ-SEC-02, REQ-SEC-05, REQ-SEC-07 | Signature check on every executable written or launched; an install directory not writable by the users who run from it; an elevated child's command line treated as untrusted input. Verified on a clean image, including the upgrade from the previous released version (REQ-TST-02). |

## Elevation discipline

The application manifest is `asInvoker` (REQ-FND-11), embedded by B01 with
`winres` 0.1.12. Nothing here ships `requireAdministrator`, and a request to add
it is rejected rather than discussed. Per-user install writes only under
`%LOCALAPPDATA%` and `HKCU`, which the user already owns, and is the default.

An always-elevated app is a defect for two concrete reasons. First, it makes
every subsequent bug a privilege-escalation bug: a path traversal in a config
parser, an unquoted path, a DLL loaded from the working directory — each is a
nuisance in a user-token process and a machine compromise in an elevated one.
One manifest value sets the severity of every future defect. Second, it trains
the user: someone who sees a UAC prompt every time they open a tray app stops
reading UAC prompts, and the next one they approve is not ours.

### The elevation moment

Machine-wide install needs a token this process does not have. The sequence:

1. Check whether we already have it — `CheckTokenMembership` against the
   `S-1-5-32-544` (Administrators) alias, through `ffi::token`.
2. If not, state the reason **before** the prompt appears: which paths and which
   hive will be written, and that per-user install needs no administrator.
3. Re-launch — `ShellExecuteExW`, `lpVerb = "runas"`, `lpFile` from
   `GetModuleFileNameW` (never `argv[0]`, which the caller controls), the same
   arguments plus `--elevated-child`, `SEE_MASK_NOCLOSEPROCESS`.
4. Wait on the child handle and adopt its exit code verbatim; after step 3 the
   unelevated parent writes nothing. Under `--silent` there is no desktop to
   prompt on, so steps 3–4 are skipped: exit `4`, and say why in the log.

The elevated child does not trust its parent. The parent runs at medium
integrity and its command line is external input (REQ-SEC-07), so the child
re-verifies its own Authenticode signature (REQ-INST-08) and accepts a `--log`
path only if it resolves under the machine log directory. A path honoured from a
lower-integrity caller is a write primitive.

## The two layouts

| | Per-user (default) | Machine-wide (`--machine`) |
|---|---|---|
| Binary | `%LOCALAPPDATA%\Programs\<Publisher>\<App>\app.exe` | `%ProgramFiles%\<Publisher>\<App>\app.exe` |
| Data, logs | `%LOCALAPPDATA%\<Publisher>\<App>\` | `%ProgramData%\<Publisher>\<App>\` |
| Config | `%APPDATA%\<Publisher>\<App>\config.toml` | `%ProgramData%\<Publisher>\<App>\config.toml` |
| ARP key | `HKCU\…\CurrentVersion\Uninstall\<UpgradeGuid>` | `HKLM\…\CurrentVersion\Uninstall\<UpgradeGuid>` |
| Start Menu | `%APPDATA%\Microsoft\Windows\Start Menu\Programs\` | `%ProgramData%\Microsoft\Windows\Start Menu\Programs\` |
| Elevation | none | UAC, at the moment above |
| Service mode | unavailable | available (REQ-SVC-01) |

Every path comes from B01's `paths`; no crate resolves a known folder itself
(REQ-SEC-05). Service mode is unavailable per-user because
`SC_MANAGER_CREATE_SERVICE` needs administrator, so `--install --service`
implies `--machine` — stated, not failed obscurely.

The machine-wide install directory's ACL is inherited from `%ProgramFiles%` and
then asserted, not assumed: `SYSTEM` and `Administrators` full control, `Users`
read and execute only. A directory a standard user can write to, on the load
path of an elevated or service process, is a privilege-escalation primitive — so
B07 reads the DACL back through `ffi::acl` and fails the install on any write
ACE for a non-admin principal.

## Install flow

`app.exe --install [--machine] [--silent] [--desktop-shortcut] [--service]
[--autostart] [--channel stable|next] [--log <path>]`

1. **Guard.** Single-instance mutex `Global\<App>-setup-<UpgradeGuid>` (machine)
   or `Local\…` (per-user). Held is exit `10`.
2. **Self-check.** Our own Authenticode signature via `ffi::trust`
   (`WinVerifyTrust`) and the OS build against the stated minimum; failure is
   exit `7` or `3` (REQ-FND-05, REQ-INST-08).
3. **Detect.** From the ARP key and install record: `Fresh`, `UpgradeInPlace`,
   `Repair` or `SameVersion`. A newer version installed is exit `9` — B07 never
   downgrades (REQ-UPD-05, one layer up).
4. **Recover.** A journal with no `commit` record means a previous run died;
   roll it back first. Interactive asks, `--silent` does it and logs it.
5. **Elevate** if the layout requires it and we do not have it.
6. **Stage and journal.** Copy the running image into
   `<program_dir>.staging-<pid>`, hashing every written file against the hash
   taken from the source handle — mismatch is exit `8` — and append the inverse
   of each mutating step to the journal before performing it, flushed per line.
7. **Activate.** `MoveFileExW(MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)`
   staging into place. Any previous binary moves to
   `<program_dir>\rollback\app-<old>.exe` rather than being deleted — B09 needs
   it (REQ-UPD-06), and so does step 10.
8. **Register.** ARP entry, Start Menu shortcut, desktop shortcut if asked.
9. **Delegate what is not ours.** `--service` calls B08's
   `ServiceRegistrar::install`, `--autostart` calls B08's
   `AutostartRegistrar::enable`. B07 never touches `sc.exe`, `CreateService` or
   the `Run` key; either failure triggers rollback and surfaces B08's code from
   the `20`–`29` band.
10. **Commit, or roll back.** Commit writes the `commit` record, deletes staging
    and writes the summary. A failure after step 6 replays the journal in reverse
    — registrations, then files, then the ARP entry — and restores the previous
    binary. Clean rollback is exit `13`; a rollback that itself fails is exit
    `14`, the one code that means a human must look.

No Kernel Transaction Manager: `CreateTransaction` and the `*TransactedW` APIs
are deprecated and may be removed, and a journal plus same-volume renames gives
the same guarantee with APIs that will still exist. Staging is always on the
target's volume — a cross-volume "rename" is a copy, and not atomic.

## Idempotency (REQ-INST-07)

Each step is an assertion about desired state, keyed by something stable, so a
second run is a no-op rather than a second copy.

| Operation | Run twice | Key |
|-----------|-----------|-----|
| Install | detects `SameVersion`, re-asserts registrations, exits `0` | ARP key + `DisplayVersion` |
| Upgrade | `SameVersion` no-op, exits `0` | `semver` 1.0.28 comparison |
| Repair | re-stages, re-hashes, rewrites registrations, exits `0` | file hash vs the embedded shipped-file manifest |
| Uninstall | finds no ARP key, removes nothing, exits `0` | absence is success |

`UpgradeGuid` is a compile-time constant and never rotates. That is what stops
three entries for one app appearing in Add/Remove Programs.

## ARP registration (REQ-INST-05)

Under the Uninstall key above, native view — no `WOW6432Node`, since both
targets are 64-bit (REQ-FND-04).

| Value | Type | Content |
|-------|------|---------|
| `DisplayName` | `REG_SZ` | product name, no version suffix |
| `DisplayVersion` | `REG_SZ` | `1.4.2`, from B02's `version` |
| `Publisher` | `REG_SZ` | the signing subject, so ARP and the certificate agree |
| `DisplayIcon` | `REG_SZ` | `"<program_dir>\app.exe",0` |
| `InstallLocation`, `InstallDate` | `REG_SZ` | `<program_dir>\`, `YYYYMMDD` |
| `EstimatedSize`, `VersionMajor`, `VersionMinor` | `REG_DWORD` | measured size in KB, never guessed; the rest from the semver |
| `UninstallString`, `QuietUninstallString`, `ModifyPath`, `NoRepair` | mixed | `"<program_dir>\app.exe" --uninstall`, the same plus `--silent --keep-data`, `… --repair`, `0` |
| `HelpLink`, `URLInfoAbout`, `URLUpdateInfo` | `REG_SZ` | from intake |
| `SystemComponent` | — | never written; hiding from ARP is what unwanted software does |

## Uninstall (REQ-INST-06)

Removal is the reverse of registration, because a running service holds the
binary open: B08 `ServiceRegistrar::stop` then `uninstall`; B08
`AutostartRegistrar::disable`, both mechanisms checked; shortcuts; the ARP key;
files under `<program_dir>` including `rollback\`; then the user-data question.
The list shown to the user is read from the install record, never composed from
guesses, and each item named with its path. Anything the record claims that is
gone is reported as already-removed, not as an error.

**The user-data prompt.** Interactive uninstall asks once — *"Keep your settings
and data? `%LOCALAPPDATA%\<Publisher>\<App>` — 4.2 MB"*, default **keep**.
`--silent` has no one to ask, so it requires `--keep-data` or `--purge-data`;
neither present is exit `2`. Deleting a user's data because a flag was omitted
is not a default we are willing to have.

A running process cannot delete its own image. B07 copies itself to
`%LOCALAPPDATA%\Temp\<App>-uninstall-<random>.exe` — per-user, DACL asserted to
deny write to anyone but the owner, because a world-writable executable at a
predictable path is a planting primitive — verifies that copy's signature, then
re-execs it with `--uninstall --finalize <program_dir>`. The finalizer deletes
the directory and schedules its own removal with
`MoveFileExW(MOVEFILE_DELAY_UNTIL_REBOOT)`; a file still in use makes the result
exit `3010`.

## Silent mode and exit codes (REQ-INST-11)

`--silent` never prompts and never waits. An operation that would need an answer
exits with a code instead of blocking a deployment job.

| Code | Meaning | What the operator does |
|------|---------|------------------------|
| `0` | Success, including an idempotent no-op | nothing |
| `1` | Unclassified failure | read the log |
| `2` | Usage error: unknown or conflicting flags, or a silent run missing a required answer | fix the command line |
| `3` | Minimum supported Windows version not met (REQ-FND-05) | check the target image |
| `4` | Elevation required and not obtained — UAC cancelled, or `--silent --machine` with no desktop | run as administrator, or install per-user |
| `5` | Insufficient disk space | free space; the log states how much was needed |
| `6` | Target path not writable, or the DACL read-back failed | check policy and ACLs on the parent |
| `7` | Our own signature failed verification (REQ-INST-08) | binary is corrupt or tampered; re-download |
| `8` | A written file's hash did not match | disk or transfer fault; retry |
| `9` | A newer version is already installed; refused | uninstall first, deliberately |
| `10` | Another install, repair or uninstall is running | wait and retry |
| `11` | The app is running and could not be closed | pass `--force-close`, or close it |
| `12` | A B08-owned registration failed and rollback succeeded | see the B08 code in the log |
| `13` | Failed, rolled back cleanly to the previous state | the machine is safe; read the log |
| `14` | Failed, and rollback also failed — state indeterminate | escalate; the log names every applied step |
| `15` | Forbidden by policy (REQ-UPD-12) | change policy or accept |
| `3010` | Success, reboot required to complete | reboot |

`16`–`19` are reserved for B07, `20`–`39` are B08's, `40`–`59` are B09's. One
binary, one exit-code space, because deployment tooling sees one executable.
Nothing above `3010` is used, and MSI codes are Windows Installer's own — never
remapped.

## The MSI (REQ-INST-03)

Built with `cargo-wix` 0.3.9 from `packaging/wix/main.wxs`, one MSI per
architecture — an MSI is per-platform; a dual-arch package does not exist.
Signed with the same certificate as the exe (REQ-REL-04).

The MSI owns its own file and ARP inventory, because Windows Installer must: a
package whose resources are written by a custom action cannot be repaired or
patched. It does **not** use WiX `ServiceInstall` or a `Run`-key component —
that puts a second owner on a registration B08 owns, and an MSI repair then
fights B08's state machine. Those two registrations are deferred,
non-impersonating custom actions calling `app.exe --register service` and
`app.exe --register autostart`, each with a rollback action.

Option parity, verified by a test running both paths on a clean image:
`--machine` ↔ `ALLUSERS=1`, `--desktop-shortcut` ↔ `DESKTOPSHORTCUT=1`,
`--service` ↔ `SERVICEMODE=1`, `--autostart` ↔ `AUTOSTART=1`,
`--channel next` ↔ `UPDATECHANNEL=next`, `--silent` ↔ `/qn`, `--log` ↔ `/l*v`.

## The install log (REQ-INST-12)

Path `<log_dir>\install-<UTC ISO8601 basic>-<pid>.jsonl`, overridable with
`--log`, printed as the last console line of every run because it is the first
thing support asks for. JSON Lines, one object per step, in B12's `log-record`
shape:

```json
{"ts":"2026-09-22T08:25:06.481Z","level":"info","phase":"activate","step":"move_staging","req":"REQ-INST-09","outcome":"ok","detail":{"to":"…\\App"}}
{"ts":"2026-09-22T08:25:06.502Z","level":"error","phase":"register","step":"service_install","req":"REQ-SVC-02","outcome":"fail","detail":{"b08_exit":26}}
```

Every line is flushed before the next step runs, so a power loss leaves a log
ending at the step in flight. The last line is a summary with `exit`, `mode`,
`version_from`, `version_to` and `rolled_back`. Ten logs are retained; a
machine-wide run also writes start, result and rollback to the Windows Event Log
(REQ-OBS-06). Redaction is B12's, and tested (REQ-SEC-08).

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|----------|--------|-----|--------------------|
| Default scope | per-user | No elevation, and most users do not need `%ProgramFiles%` (REQ-INST-02) | yes — `--machine` for a managed image |
| Elevation model | re-launched elevated child, `asInvoker` parent | Keeps every future bug a user-token bug (REQ-FND-11, REQ-INST-04) | no |
| Transaction model | journal + same-volume rename | KTM is deprecated; renames are atomic and will still exist | no |
| Old binary, upgrade GUID | binary kept at `rollback\app-<old>.exe`; GUID a compile-time constant | B09 and rollback both need the binary (REQ-UPD-06); a rotating GUID produces three ARP entries for one app | retention count only |
| Shortcuts, user data | Start Menu always, desktop on request; data kept on uninstall unless told otherwise | An assumed desktop icon is an unwanted one (REQ-INST-10); losing data to an omitted flag is not acceptable | desktop only |
| Service at app install | never implicit | REQ-SVC-02; `--service` is a separate, separately logged operation | no |
| MSI resources | Installer owns files and ARP; registrations are custom actions | Repair and patching need it; B08 still owns the registrations | no |

## How this is verified

- `cargo test -p install` — layout table, ARP field set, exit-code mapping,
  journal reverse-replay, elevated-child argument validation, and one test per
  exit code asserting both the code and the final log line.
- End-to-end on a clean Windows image, both targets: fresh per-user, fresh
  machine-wide, upgrade **from the previous released version**, repair,
  uninstall, uninstall again (REQ-TST-02, REQ-INST-07).
- Fault injection: kill the process after each journaled step; the next run rolls
  back to the pre-install state and exits `13`.
- DACL assertion: after a machine-wide install, enumerate the install
  directory's ACEs and fail on any write ACE for a non-admin principal
  (REQ-SEC-05).
- Manifest assertion: fail if the built binary's embedded
  `requestedExecutionLevel` is anything but `asInvoker` (REQ-FND-11) — the
  regression is one word of XML.
- MSI parity: `/qn` with each property, then compare ARP values, file set and
  registrations against the CLI run.

## Open to intake

- Publisher, product name, `UpgradeGuid`, help and about URLs.
- Whether machine-wide is the default for the fleet, and whether service mode is
  on at all (REQ-SVC-01 is `OPT`).
- Whether an MSI is needed, `--force-close` semantics, and rollback retention
  beyond one version.
