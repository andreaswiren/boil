# Installer & Elevation

Owned by **B07 `installer`** (Wave 3). B07 owns `crates/install/**` and
`packaging/wix/**`, and it owns exactly three kinds of machine state: files in
the install directory, the Add/Remove Programs entry, and shortcuts
(`contracts/ownership.md`). It does not create the service, it does not write
the `Run` key, and it does not replace an installed binary after the fact —
those are B08's and B09's transitions, reached through the contract. B07
publishes `install-mode` and `exit-codes`; it consumes `paths`, `version` and
the public half of `signing-keys`.

## Requirements covered

| ID | How this spec covers it |
|----|------------------------|
| REQ-INST-01 | `app.exe --install` performs a complete installation from the shipped binary. No second download. |
| REQ-INST-02 | Per-user is the default and needs no elevation; `--machine` is available and elevates only then. |
| REQ-INST-03 | An MSI is built from the same crate with the same option surface, for GPO deployment. |
| REQ-INST-04 | Elevation happens by re-launching an elevated instance at the moment it is needed, after the reason is stated. |
| REQ-INST-05 | ARP registration field table below. |
| REQ-INST-06 | Uninstall removes every registration it can name, and asks about user data. |
| REQ-INST-07 | Every step is a desired-state assertion; install, upgrade, repair and uninstall are re-runnable. |
| REQ-INST-08 | The image verifies its own Authenticode signature, and every file it writes is hashed before activation. |
| REQ-INST-09 | Journal-and-reverse rollback. No half-installed state. |
| REQ-INST-10 | Start Menu shortcut always; desktop shortcut only when asked. |
| REQ-INST-11 | `--silent` plus the exit-code table below. |
| REQ-INST-12 | JSON Lines install log at a documented path. |
| REQ-FND-11 | The application manifest stays `asInvoker`. Only this path elevates, and only as a child process. |
| REQ-SEC-02 | Signature verification on every executable this code writes or launches. |
| REQ-SEC-05 | Documented locations, and an install directory that is not writable by the users who run from it. |
| REQ-SEC-07 | The command line handed to an elevated child is untrusted input and is validated. |
| REQ-TST-02 | Verified on a clean image, including the upgrade from the previous released version. |

## Elevation discipline

The application manifest is `asInvoker` (REQ-FND-11), embedded by B01 with
`winres` 0.1.12. Nothing in this boilerplate ships a `requireAdministrator`
manifest, and a request to add one is rejected rather than discussed.

An always-elevated app is a defect for two concrete reasons. First, every
subsequent bug becomes a privilege-escalation bug: a path-traversal in a config
parser, an unquoted service path, a DLL loaded from the working directory — each
of those is a nuisance in a user-token process and a full machine compromise in
an elevated one. The severity of every future defect is decided by this one
manifest value. Second, it trains the user. A person who sees a UAC prompt every
time they open a tray app stops reading UAC prompts, and the next one they
approve is not ours.

So per-user install is the default and needs no elevation at all. It writes only
under `%LOCALAPPDATA%` and `HKCU`, which the user already owns.

### The elevation moment

Machine-wide install (`--install --machine`) needs a token this process does not
have. The sequence is exact:

1. Ask whether we already have it: `CheckTokenMembership` against the
   `S-1-5-32-544` (Administrators) alias, through the `ffi::token` wrapper. If
   yes, proceed in-process.
2. If not, state the reason **before** the prompt appears, in the console for a
   CLI run and in a dialog for a GUI run: which paths and which registry hive
   will be written, and that per-user install needs no administrator.
3. Re-launch: `ShellExecuteExW` with `lpVerb = "runas"`, `lpFile` from
   `GetModuleFileNameW` — never `argv[0]`, which the caller controls — the same
   arguments plus `--elevated-child`, and `SEE_MASK_NOCLOSEPROCESS`.
4. Wait on the child handle, adopt its exit code verbatim, and write nothing
   ourselves. The unelevated parent's job after step 3 is to relay an exit code.
5. Under `--silent` there is no desktop to prompt on. Do not attempt the
   re-launch: exit `4` and say so in the log.

The elevated child does not trust its parent. The parent runs at medium
integrity and its command line is external input (REQ-SEC-07), so the child
re-verifies its own Authenticode signature (REQ-INST-08), and accepts a
`--log` path only if it resolves under the machine log directory. A path handed
to an elevated child is a write primitive if you honour it.

## The two layouts

| | Per-user (default) | Machine-wide (`--machine`) |
|---|---|---|
| Binary | `%LOCALAPPDATA%\Programs\<Publisher>\<App>\app.exe` | `%ProgramFiles%\<Publisher>\<App>\app.exe` |
| Data | `%LOCALAPPDATA%\<Publisher>\<App>\` | `%ProgramData%\<Publisher>\<App>\` |
| Config | `%APPDATA%\<Publisher>\<App>\config.toml` | `%ProgramData%\<Publisher>\<App>\config.toml` |
| Logs | `%LOCALAPPDATA%\<Publisher>\<App>\logs\` | `%ProgramData%\<Publisher>\<App>\logs\` |
| ARP key | `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\<UpgradeGuid>` | `HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall\<UpgradeGuid>` |
| Start Menu | `%APPDATA%\Microsoft\Windows\Start Menu\Programs\` | `%ProgramData%\Microsoft\Windows\Start Menu\Programs\` |
| Elevation | none | UAC, at the moment above |
| Service mode | unavailable | available (REQ-SVC-01) |

Every path comes from B01's `paths` module. No crate resolves a known folder
itself (REQ-SEC-05), and `directories` 6.0.0 is B01's dependency, not B07's.

Service mode is unavailable per-user because registering a service needs
`SC_MANAGER_CREATE_SERVICE`. `--install --service` therefore implies
`--machine`, and B07 states that implication rather than failing obscurely.

ACLs on the machine-wide install directory are inherited from `%ProgramFiles%`
and then asserted, not assumed: `SYSTEM` and `Administrators` full control,
`Users` read and execute, no write and no create-file for `Users`. A directory
that a standard user can write to, on the load path of a process that runs
elevated or as a service, is a privilege-escalation primitive (REQ-SEC-05) — so
after writing, B07 reads the DACL back through `ffi::acl` and fails the install
if a write ACE for a non-admin principal is present.

## Install flow

`app.exe --install [--machine] [--silent] [--desktop-shortcut] [--service]
[--autostart] [--channel stable|next] [--log <path>]`

1. **Guard.** Take the single-instance mutex — `Global\<App>-setup-<UpgradeGuid>`
   for machine, `Local\…` for per-user. Held → exit `10`.
2. **Self-check.** Verify our own Authenticode signature via `ffi::trust`
   (`WinVerifyTrust`) and check the OS build against the stated minimum
   (REQ-FND-05, REQ-INST-08). Fail → exit `7` or `3`.
3. **Detect.** Read the ARP key and the install record. Decide `Fresh`,
   `UpgradeInPlace`, `Repair` or `SameVersion`. A newer version installed →
   exit `9`; B07 never downgrades (REQ-UPD-05 is the same rule one layer up).
4. **Recover.** If a journal exists with no `commit` record, a previous run died.
   Roll it back first. Interactive asks; `--silent` does it and logs it.
5. **Elevate** if the layout requires it and we do not have it.
6. **Stage.** Copy the running image and its side files into
   `<program_dir>.staging-<pid>`, hash each written file and compare against the
   hash computed from the source handle. A mismatch is exit `8`.
7. **Journal.** Append the inverse of each mutating step before performing it.
   Flush per line.
8. **Activate.** `MoveFileExW(MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)`
   the staging directory contents into place. The old binary, if any, is moved
   to `<program_dir>\rollback\app-<oldversion>.exe` rather than deleted — B09
   needs it (REQ-UPD-06) and so does step 12.
9. **Register.** ARP entry, Start Menu shortcut, desktop shortcut if asked.
10. **Delegate the registrations that are not ours.** `--service` calls B08's
    `ServiceRegistrar::install`; `--autostart` calls B08's
    `AutostartRegistrar::enable`. B07 does not touch `sc.exe`, `CreateService`
    or the `Run` key (`contracts/ownership.md`). A failure returned from either
    is a rollback trigger, and its exit code is B08's band (`20`–`29`).
11. **Commit.** Write the `commit` record, delete staging, write the summary log
    line.
12. **Rollback**, if any step after 7 failed: replay the journal in reverse —
    registrations first, then files, then the ARP entry — and restore the
    previous binary from `rollback\`. Success is exit `13`; a rollback that
    itself fails is exit `14`, the one code that means a human must look.

There is no Kernel Transaction Manager in this design. `CreateTransaction` and
the `*TransactedW` file APIs are deprecated by Microsoft and may be removed;
a journal plus same-volume renames gives the same guarantee with APIs that will
still exist. Staging is always on the same volume as the target, because a
cross-volume "rename" is a copy and is not atomic.

## Idempotency (REQ-INST-07)

Every step is written as an assertion about desired state, keyed by something
stable, so running it twice is a no-op rather than a second copy.

| Operation | Run twice | Key |
|-----------|-----------|-----|
| Install | second run detects `SameVersion`, re-asserts registrations, exits `0` | ARP key + `DisplayVersion` |
| Upgrade | second run is a `SameVersion` no-op, exits `0` | version comparison via `semver` 1.0.28 |
| Repair | re-stages and re-hashes every file, rewrites registrations, exits `0` | file hash vs the embedded manifest of shipped files |
| Uninstall | second run finds no ARP key, removes nothing, exits `0` | absence is success |

The `UpgradeGuid` is a compile-time constant and never changes across versions.
This is what stops the classic defect: three entries for the same app in
Add/Remove Programs, because each installer minted a fresh GUID.

## ARP registration (REQ-INST-05)

Under the Uninstall key above, native view — no `WOW6432Node`, since both
targets are 64-bit (REQ-FND-04).

| Value | Type | Content |
|-------|------|---------|
| `DisplayName` | `REG_SZ` | product name, no version suffix |
| `DisplayVersion` | `REG_SZ` | `1.4.2`, from B02's `version` |
| `Publisher` | `REG_SZ` | the signing subject, so ARP and the certificate agree |
| `DisplayIcon` | `REG_SZ` | `"<program_dir>\app.exe",0` |
| `InstallLocation` | `REG_SZ` | `<program_dir>\` |
| `InstallDate` | `REG_SZ` | `YYYYMMDD` |
| `EstimatedSize` | `REG_DWORD` | measured size in KB, never guessed |
| `UninstallString` | `REG_SZ` | `"<program_dir>\app.exe" --uninstall` |
| `QuietUninstallString` | `REG_SZ` | `"<program_dir>\app.exe" --uninstall --silent --keep-data` |
| `ModifyPath` | `REG_SZ` | `"<program_dir>\app.exe" --repair` |
| `NoRepair` | `REG_DWORD` | `0` |
| `VersionMajor`, `VersionMinor` | `REG_DWORD` | parsed from the semver |
| `HelpLink`, `URLInfoAbout`, `URLUpdateInfo` | `REG_SZ` | from intake |
| `SystemComponent` | — | never written. Hiding from ARP is what unwanted software does. |

## Uninstall (REQ-INST-06)

Removal order is the reverse of registration, because a service still running
holds the binary open:

1. B08 `ServiceRegistrar::stop` then `uninstall` — through the contract.
2. B08 `AutostartRegistrar::disable`, both mechanisms checked.
3. Shortcuts, Start Menu and desktop.
4. The ARP key.
5. Files under `<program_dir>`, including `rollback\`.
6. The user-data question.

The list shown to the user is read from the install record, not composed from
guesses, and every item is named with its path. Anything the record claims but
that is already gone is reported as already-removed, not as an error.

**The user-data prompt.** Interactive uninstall asks once: *"Keep your settings
and data? `%LOCALAPPDATA%\<Publisher>\<App>` — 4.2 MB"*, default **keep**.
`--silent` has no one to ask, so it requires `--keep-data` or `--purge-data`
explicitly; neither present is exit `2`. Deleting a user's data because a flag
was omitted is not a default we are willing to have.

A running process cannot delete its own image. B07 copies itself to
`%LOCALAPPDATA%\Temp\<App>-uninstall-<random>.exe` — a per-user directory, with
the copy's DACL asserted to deny write to everyone but the owner, because a
world-writable executable in a predictable location is a planting primitive —
verifies the copy's signature, and re-execs it with
`--uninstall --finalize <program_dir>`. The finalizer removes the directory and
schedules its own removal with `MoveFileExW(MOVEFILE_DELAY_UNTIL_REBOOT)`.
Any file still in use at that point makes the overall result exit `3010`.

## Silent mode and exit codes (REQ-INST-11)

`--silent` never prompts, never opens a window, and never waits. An operation
that would need an answer exits with the code instead of blocking a deployment
job forever.

| Code | Meaning | What the operator does |
|------|---------|------------------------|
| `0` | Success, including an idempotent no-op | nothing |
| `1` | Unclassified failure | read the log |
| `2` | Usage error: unknown flag, conflicting flags, a silent run missing a required answer | fix the command line |
| `3` | Minimum supported Windows version not met (REQ-FND-05) | check the target image |
| `4` | Elevation required and not obtained — UAC cancelled, or `--silent --machine` with no desktop | run as administrator, or install per-user |
| `5` | Insufficient disk space | free space; the log states how much was needed |
| `6` | Target path not writable, or the DACL read-back failed | check policy and ACLs on the parent |
| `7` | Our own signature failed verification (REQ-INST-08) | the binary is corrupt or tampered; re-download |
| `8` | A written file's hash did not match | disk or transfer fault; retry |
| `9` | A newer version is already installed; refused | uninstall first, deliberately |
| `10` | Another install, repair or uninstall is already running | wait and retry |
| `11` | The app is running and could not be closed | pass `--force-close`, or close it |
| `12` | A registration transition owned by B08 failed and rollback succeeded | see the B08 code in the log |
| `13` | Failed, and rolled back cleanly to the previous state | the machine is safe; read the log |
| `14` | Failed, and rollback also failed — state is indeterminate | escalate; the log names every applied step |
| `15` | Forbidden by policy (REQ-UPD-12) | change policy or accept |
| `3010` | Success, reboot required to complete | reboot |

Codes `16`–`19` are reserved for B07. `20`–`39` belong to B08. `40`–`59` belong
to B09. One binary, one exit-code space, because deployment tooling sees one
executable. Nothing above `3010` is used; MSI codes are Windows Installer's own
and are never remapped.

## The MSI (REQ-INST-03)

Built with `cargo-wix` 0.3.9 from `packaging/wix/main.wxs`, one MSI per
architecture — an MSI is per-platform and a single dual-arch package does not
exist. Signed with the same certificate as the exe (REQ-REL-04).

The MSI owns its own file and ARP inventory, because Windows Installer must:
a package whose resources are written by a custom action cannot be repaired or
patched. It does **not** use WiX `ServiceInstall` or a `Run`-key component. That
would put a second owner on a registration B08 owns, and an MSI repair would
then fight B08's state machine (`contracts/ownership.md`). Those registrations
are deferred custom actions calling `app.exe --register service` and
`app.exe --register autostart`, each with a rollback custom action, each
non-impersonating.

Option parity, verified by a test that runs both paths on a clean image:

| CLI | MSI property |
|-----|--------------|
| `--machine` / default per-user | `ALLUSERS=1` / per-user package |
| `--desktop-shortcut` | `DESKTOPSHORTCUT=1` |
| `--service` | `SERVICEMODE=1` |
| `--autostart` | `AUTOSTART=1` |
| `--channel next` | `UPDATECHANNEL=next` |
| `--silent` | `/qn` |
| `--log <path>` | `/l*v <path>` |

## The install log (REQ-INST-12)

Path: `<log_dir>\install-<UTC ISO8601 basic>-<pid>.jsonl`, overridable with
`--log`. This path is printed as the last line of console output on every run,
success or failure, because it is the first thing support asks for.

Format is JSON Lines, one object per step, using B12's `log-record` shape:

```json
{"ts":"2026-09-22T08:25:06.481Z","level":"info","phase":"activate","step":"move_staging","req":"REQ-INST-09","outcome":"ok","detail":{"from":"…\\.staging-7412","to":"…\\App"}}
{"ts":"2026-09-22T08:25:06.502Z","level":"error","phase":"register","step":"service_install","req":"REQ-SVC-02","outcome":"fail","detail":{"b08_exit":26}}
```

Every line is flushed before the next step runs, so a power loss leaves a log
that ends at the step that was in flight. The final line is a summary object
carrying `exit`, `mode`, `version_from`, `version_to` and `rolled_back`.
Ten logs are retained per directory. Machine-wide runs additionally write the
start, the result and any rollback to the Windows Event Log (REQ-OBS-06).
Redaction is B12's and is tested, not assumed (REQ-SEC-08).

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|----------|--------|-----|--------------------|
| Default scope | per-user | Needs no elevation, and most users do not need `%ProgramFiles%` (REQ-INST-02) | yes — `--machine` default for a managed image |
| Elevation model | re-launched elevated child, `asInvoker` parent | Keeps every future bug a user-token bug (REQ-FND-11, REQ-INST-04) | no |
| Transaction model | journal + same-volume rename | KTM is deprecated; renames are atomic and will keep existing | no |
| Old binary retention | `rollback\app-<old>.exe`, kept | B09 and step 12 both need it (REQ-UPD-06) | yes — retention count |
| Upgrade GUID | compile-time constant, never rotated | Stops duplicate ARP entries | no |
| Desktop shortcut | off unless `--desktop-shortcut` | REQ-INST-10; an assumed desktop icon is an unwanted one | yes |
| Start Menu shortcut | always | REQ-INST-10 | no |
| User data on uninstall | kept by default; silent must choose | Losing data to an omitted flag is not acceptable | no |
| Service install at app install | never implicit | REQ-SVC-02; `--service` is a second, separately logged operation | no |
| MSI resource ownership | Windows Installer owns files and ARP; registrations are custom actions | Repair and patching need it; B08 still owns the registrations | no |
| Exit-code space | shared across B07/B08/B09 in bands | One executable, one contract for deployment tooling (REQ-INST-11) | no |

## How this is verified

- `cargo test -p install` — the layout table, ARP field set, exit-code mapping,
  journal reverse-replay, and command-line validation for the elevated child.
- `tests/e2e/install.rs` (B14) on a clean Windows image, both targets: fresh
  per-user, fresh machine-wide, upgrade **from the previous released version**,
  repair, uninstall, then uninstall again (REQ-TST-02, REQ-INST-07).
- Fault injection: kill the process after each journaled step and assert that
  the next run rolls back to the pre-install state and exits `13`.
- DACL assertion: after a machine-wide install, the test enumerates the install
  directory's ACEs and fails on any write ACE for a non-admin principal
  (REQ-SEC-05).
- Elevation assertion: a test parses the built binary's embedded manifest and
  fails if `requestedExecutionLevel` is anything but `asInvoker`
  (REQ-FND-11) — this is the check that stops the regression, because the
  regression is one word in an XML file.
- MSI parity: install via `/qn` with each property, and compare the resulting
  ARP values, file set and registration state against the CLI run.
- Exit-code coverage: one test per code in the table, each asserting the code
  and the final log line.

## Open to intake

- Publisher, product name, `UpgradeGuid`, help and about URLs.
- Whether machine-wide is the default for the target fleet.
- Whether service mode is on at all (REQ-SVC-01 is `OPT`).
- Whether an MSI is needed, or only the self-install path.
- `--force-close` semantics: refuse, or close the running instance.
- Rollback retention count beyond one previous version.
