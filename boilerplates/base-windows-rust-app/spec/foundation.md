# Foundation & Toolchain

The ground every other crate stands on: the workspace, the pinned compiler, both
targets, the startup OS check, the `unsafe`/FFI boundary, the lint gate, the
reproducible release build, the application manifest and the `paths` module.
Owned by **B01** (`arch-foundation`): the workspace `Cargo.toml`, `Cargo.lock`,
`rust-toolchain.toml`, `.cargo/config.toml`, the `crates/app/` scaffold,
`crates/ffi/**`, `build.rs` and the application manifest
(`contracts/ownership.md`). B01 publishes `env-config`, `ffi-boundary` and
`paths`; it consumes `versions/manifest.json` (B16) and `build/scope.md` (B00).
It runs in Wave 2 between B16 and B02, sequentially, because a crate added
against a remembered version is a version nobody validated (REQ-VER-02).

## Requirements covered

REQ-FND-01, REQ-FND-02, REQ-FND-03, REQ-FND-04, REQ-FND-05, REQ-FND-06,
REQ-FND-07, REQ-FND-08, REQ-FND-09, REQ-FND-11, REQ-FND-12, REQ-SEC-05,
REQ-VER-06, REQ-REL-05, REQ-REL-06, REQ-DSN-11.

## 1. The workspace (REQ-FND-01)

A Cargo workspace even though one binary ships, because nine agents writing into
one `src/` tree is the merge problem the wave design removes.

```
Cargo.toml  [workspace] resolver="3", [workspace.lints], [workspace.dependencies]
rust-toolchain.toml  channel + both targets    .cargo/config.toml  +crt-static, linker args
crates/app/  main.rs, build.rs, app.manifest   crates/ffi/  the only crate naming `windows`
crates/contracts/ B02  design/ B03  ui/ B05  tray/ B06  obs/ B12  install/ B07  update/ B09
crates/service/ + autostart/ B08   fixtures/ B14   mockups/ B04   tests/ B14 (not tests/visual/)
```

Every dependency pin lives once, in `[workspace.dependencies]`, read from
`versions/manifest.json`. A crate writes `serde = { workspace = true }` and never
a version of its own (REQ-FND-08): one place to bump, one place to check drift.

## 2. Toolchain pin and MSRV (REQ-FND-02, REQ-VER-06)

`rust-toolchain.toml` pins `channel = "1.98.1"` from `versions/manifest.json`.
A floating `stable` makes REQ-FND-09's reproducibility claim untestable, because
the compiler that built the tag is gone. The MSRV is a separate declaration —
`rust-version = "1.95"`, the floor the dependency graph actually imposes —
proved by `cargo +1.95.0 check --workspace --locked`.
Conflating the two is how a dependency bump raises the floor with nobody deciding
to, and B16 rejects a crate whose `rust_version` exceeds it (REQ-VER-05). Edition
2024, `resolver = "3"`.

## 3. Both targets (REQ-FND-04)

`x86_64-pc-windows-msvc` and `aarch64-pc-windows-msvc`, both built and both
published. ARM64 is not a stretch goal: a Snapdragon X laptop running the x64
build under emulation is slower, drains more battery, and hides ARM64-only faults
until a customer finds them. No `*-windows-gnu`, no `i686`. Both cross-compile
from an x64 runner with `--target`, but neither runs its integration suite there,
because an ARM64 binary does not execute on an x64 host — where no ARM64 runner
exists, B14 records which REQ IDs are unverified for that target rather than
reporting them green.

## 4. The minimum Windows version check (REQ-FND-05)

**Floor: Windows 10 22H2, build 19045.** Below that Windows 10 is out of
servicing, so our fix lands on an OS that no longer gets its own. The check is
the first statement in `main()`, before the runtime, UI, logger and config.

```rust
const MIN_BUILD: u32 = 19045; // Windows 10 22H2 (REQ-FND-05)
if let Err(found) = ffi::version::require_build(MIN_BUILD) {
    ffi::dialog::fatal("Unsupported Windows version", &format!(
        "This application requires Windows 10 22H2 (build {MIN_BUILD}) or later. \
         This computer reports build {found}."));
    return std::process::ExitCode::from(3); // reserved: UNSUPPORTED_OS
}
```

Read the build with `RtlGetVersion` (ntdll), not `GetVersionExW` and not
`VerifyVersionInfoW`: both of the latter are shimmed by the compatibility layer
and report Windows 8 to a process whose manifest lacks the right `supportedOS`
GUID. A version check that lies is worse than none, and what it lets through is
the dialog nobody can act on — *"The procedure entry point
SetProcessDpiAwarenessContext could not be located in USER32.dll"*.

`ffi::dialog::fatal` uses `MessageBoxW` with `MB_ICONERROR | MB_SETFOREGROUND` in
an interactive session; under `--service` or `--silent` it writes stderr and the
Event Log, because a modal box in session 0 blocks until the SCM times out and
nobody sees it. Exit code `3` is reserved here: the `ExitCode` enum is B07's
(REQ-INST-11), B01 declares the reserved value, and B02 fails the freeze if a
second crate claims 3.

## 5. One FFI crate, and the `unsafe` rules (REQ-FND-03, REQ-FND-06)

`crates/ffi` is the only crate whose `Cargo.toml` names `windows` or
`windows-sys`. Everyone else calls a safe wrapper. REQ-FND-06 as written permits
"a named FFI boundary module per crate"; we are stricter, and the reason is
arithmetic. Nine crates writing their own Win32 calls produce nine independent
sets of assumptions about three things:

- **Handle lifetime.** `DestroyIcon`, `CloseHandle` and "the shell owns it now"
  are each correct for different handles. The wrong one is a double free, or a
  leak that surfaces after a week in the tray.
- **Error convention.** `BOOL` zero plus `GetLastError`, `HRESULT`, a null
  return, `0xFFFFFFFF` and `S_FALSE`-means-success are all live in the surface we
  touch; checking the wrong one proceeds with a garbage handle.
- **String encoding.** UTF-16 with an explicit length, UTF-16 assumed
  NUL-terminated, and a `PCWSTR` borrowed from a temporary dropped at the end of
  the argument expression. The third compiles.

Those bugs are memory-unsafe, not merely wrong. One owner gives `T1` one place to
review and one place to fix. A Wave 3 agent that needs a missing call files a CCR
for a wrapper; it does not add `use windows::Win32::...` to its own crate.

```toml
[workspace.lints.rust]
unsafe_code            = "deny"     # crates/ffi lifts this locally, with a reason
unsafe_op_in_unsafe_fn = "forbid"   # not liftable anywhere
```

`deny` rather than `forbid` for `unsafe_code`, because `forbid` cannot be lifted
and exactly one crate must lift it; CI asserts only `crates/ffi` does. Four rules
inside it: **every `unsafe` block carries a `// SAFETY:` comment naming the
invariant** it relies on — which pointer is non-null and why, who owns the handle,
whether a length is in `u16` units or bytes, because "Win32 call" is not an
invariant; **no raw handle in a public signature**, so `HWND`, `HANDLE`, `HICON`
and `PCWSTR` stay inside, each behind a newtype whose `Drop` calls the right
release function; **every wrapper returns `Result`**, with `GetLastError` read on
the statement after the failing call rather than after an intervening call that
overwrites it; and **no panic crosses a callback**, since unwinding into a window
procedure or a service control handler is undefined behaviour, so each callback
body is `catch_unwind`, logs, and returns the documented default. The `unsafe`
block count is recorded in `build/foundation.md`, an increase needs a CCR, and
`T1` reads the delta rather than the whole crate.

## 6. The lint gate (REQ-FND-07)

```bash
cargo fmt --all --check
cargo clippy --workspace --all-targets --all-features --locked -- -D warnings
RUSTDOCFLAGS="-D warnings" cargo doc --workspace --no-deps
```

`clippy::pedantic` is `warn` workspace-wide and **reviewed** at H3, not denied:
denying it wholesale produces a wall of `module_name_repetitions` that teaches
everyone to add `#[allow]` without reading it. Each declined pedantic lint gets a
crate-level `#[allow]` with a one-line reason. Correctness, suspicious,
complexity, perf and style are `deny`.

## 7. Reproducible release builds (REQ-FND-09, REQ-REL-06)

Four inputs decide a byte — source, lockfile, compiler, flags — all recorded.

```toml
# .cargo/config.toml
rustflags = ["-Ctarget-feature=+crt-static",      # REQ-FND-12
             "-Clink-arg=/Brepro",                # deterministic PE timestamp
             "-Clink-arg=/PDBALTPATH:%_PDB%",     # no absolute PDB path in the image
             "--remap-path-prefix=$CARGO_HOME=/cargo"]
```

`--locked` is not optional: an unlocked release build is not the thing that was
tested (REQ-SBM-08). `build.rs` stamps the tag, commit SHA, triple, `rustc -Vv`
and the SHA-256 of `Cargo.lock` into the binary, so `app.exe --version --verbose`
states exactly what it is (REQ-REL-05). Rebuild from tag:

```bash
git checkout --detach <tag> && rustup toolchain install "$(grep channel rust-toolchain.toml | cut -d'"' -f2)"
cargo build --release --locked --target x86_64-pc-windows-msvc
certutil -hashfile target/x86_64-pc-windows-msvc/release/app.exe SHA256
```

Compare against the **unsigned** column of `checksums.txt`. A code-signed binary
is not byte-identical on rebuild — Authenticode embeds a timestamp and the
certificate — so the release publishes both hashes and this check uses the
pre-signature one. Publishing only the signed hash makes the claim unverifiable.

## 8. The manifest, and one executable (REQ-FND-11, REQ-FND-12)

Embedded by `winres 0.1.12` from `build.rs`. Five settings, each load-bearing:
`<requestedExecutionLevel level="asInvoker" uiAccess="false" />`, the Win10/11
`<supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}" />`,
`<dpiAwareness>PerMonitorV2</dpiAwareness>`,
`<activeCodePage>UTF-8</activeCodePage>` and `<longPathAware>true</longPathAware>`.

`asInvoker` is not negotiable. Only the installer path elevates, and only by
re-launching an elevated instance when it needs to (REQ-INST-04); a binary
manifested `requireAdministrator` trains its users to grant administrator to
everything, and the orchestrator rejects it on sight. `PerMonitorV2` lives in the
manifest rather than a `SetProcessDpiAwarenessContext` call, because a runtime
call runs after process start and any window created before it is stuck in the
old awareness mode (REQ-DSN-11).

`+crt-static` on both MSVC targets removes the VC++ redistributable step, and the
tradeoff is stated rather than discovered: a statically linked CRT means a CRT
security fix ships in **our** update, not Microsoft's, which makes it a
REQ-CRA-07 obligation and a standing B16 check. No .NET and no WebView2 — a
WebView2 UI needs the Evergreen bootstrapper on Windows 10, a runtime
prerequisite that fails this requirement, which is why the framework question at
intake (REQ-UI-01) is also a REQ-FND-12 question. `eframe 0.36.2` links only
`d3d12.dll` and `opengl32.dll`, both OS components.

## 9. `paths`: the only module that resolves a directory (REQ-SEC-05)

Nobody calls `std::env::var("APPDATA")`, nobody joins onto `current_exe()`, and
nobody writes beside the executable.

| Member | Location | Who writes |
|---|---|---|
| `paths::config()` | `%LOCALAPPDATA%\<Vendor>\<App>\config\` | B02 config, B05 settings |
| `paths::logs()` | `%LOCALAPPDATA%\<Vendor>\<App>\logs\` | B12 (REQ-OBS-01) |
| `paths::crash()`, `paths::cache()` | `…\<App>\crash\`, `…\<App>\cache\` | B12 (REQ-OBS-05), B09 |
| `paths::install_user()` | `%LOCALAPPDATA%\Programs\<App>\` | B07 only |
| `paths::install_machine()` | `%PROGRAMFILES%\<Vendor>\<App>\` | B07, B09, elevated |
| `paths::service_data()` | `%PROGRAMDATA%\<Vendor>\<App>\` | B08, B12 service log |

Resolution uses `directories 6.0.0`, verification uses `ffi::acl`, and three
rules make this a control rather than a convenience. **Every directory is created
with an explicit DACL, never an inherited one** — `paths::ensure()` creates with a
security descriptor and asserts the result, because `%PROGRAMDATA%` inherits one
that lets authenticated users create files, and a user-writable directory on an
elevated process's search path is a privilege-escalation primitive. **Machine
paths are read-only to the interactive app**, returned as a `MachinePath` with no
write helper, so the mistake does not compile. **A path that leaves its root after
canonicalisation is refused** — the `..` in a config value REQ-SEC-07 is about.

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Toolchain pin | `1.98.1` from the manifest | A floating channel breaks REQ-FND-09 | No |
| MSRV | `1.95`, tested at `1.95.0` | The graph's real floor; equal to the pin it tests nothing | No |
| Minimum Windows | 10 22H2, build 19045 | Older Windows 10 is out of servicing | Yes, upward only |
| OS version read via | `RtlGetVersion` | `GetVersionExW` is shimmed and lies | No |
| `unsafe` confined to | `crates/ffi` alone | Nine assumption sets give unsafe bugs | No |
| `unsafe_code` lint | `deny` plus one local `allow` | `forbid` cannot be lifted for `ffi` | No |
| `clippy::pedantic` | `warn`, reviewed at H3 | Denying it teaches blanket `#[allow]` | No |
| CRT linkage | `+crt-static` | REQ-FND-12; CRT fixes become ours | No |
| Elevation | `asInvoker` | REQ-FND-11 | No |
| DPI awareness | `PerMonitorV2`, in the manifest | A runtime call is too late | No |
| Directory resolution | `paths` only, `directories 6.0.0` | REQ-SEC-05 | No |
| Reproducibility compared on | The unsigned artefact | Authenticode embeds a timestamp | No |

## How this is verified

- `cargo build --release --locked` succeeds for both triples from a clean clone
  with no network write to `Cargo.lock`; `cargo fmt --all --check` and the §6
  clippy line both exit 0 (REQ-FND-07).
- `grep -rl 'windows\(-sys\)\? *=' crates/*/Cargo.toml` names only
  `crates/ffi/Cargo.toml` (REQ-FND-03); `tests/foundation/safety_comments.rs`
  asserts a `// SAFETY:` line before every `unsafe {` there, and a compile-fail
  test proves `unsafe {}` elsewhere fails the build (REQ-FND-06).
- Two `--release --locked` builds at one tag give an identical unsigned SHA-256,
  and the §7 procedure runs in CI on every release tag (REQ-FND-09, REQ-REL-06).
- `mt.exe -inputresource:app.exe;#1 -out:-` shows `asInvoker` and `PerMonitorV2`,
  asserted in CI rather than read by eye (REQ-FND-11); `dumpbin /dependents`
  lists no `VCRUNTIME140.dll` or `MSVCP140.dll` (REQ-FND-12).
- On a Windows Server 2016 image the binary exits 3 with the §4 message, not a
  missing-entry-point dialog (REQ-FND-05); `app.exe --version --verbose` prints
  tag, commit, triple, `rustc` version and the lockfile hash (REQ-REL-05).
- `tests/foundation/paths.rs` asserts each member's root, the DACL `ensure()`
  produces, and refusal of a config value containing `..\..\Windows\System32`
  (REQ-SEC-05, REQ-SEC-07).

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| Minimum Windows version | Windows 10 22H2, build 19045 |
| Vendor name used in every path | Derived from the forge owner in `build/scope.md` |
| UI framework (constrains REQ-FND-12) | `eframe 0.36.2` |
| Machine-wide install offered | Yes; per-user remains the default install mode |
| ARM64 integration runner available | No — B14 records the unverified REQ IDs |
