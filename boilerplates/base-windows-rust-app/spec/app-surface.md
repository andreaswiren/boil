# Application Surface & Tray

The window and the notification area: chrome, placement, keyboard, accessibility,
threading, view states, strings, settings, and everything that happens in the
tray. Owned by **B05** (`ui-shell`, `crates/ui/**`, publishes `view-registry` and
`settings-registry`) and **B06** (`systray`, `crates/tray/**`, publishes
`tray-state`). Both consume `design-tokens` (B03), `config`, `version` and
`paths`; B06 also consumes `view-registry`. **Neither invents a colour** — every
pixel's colour comes from the token module derived from the mockup a human
approved at H1 (REQ-DSN-02, REQ-DSN-09, REQ-MOC-08), and a raw hex literal in
`crates/ui` or `crates/tray` is a lint failure. Neither calls `windows-rs`:
window, shell, DPI and notification calls go through B01's `crates/ffi` wrappers,
and a missing wrapper is a CCR, not a local `unsafe` block (REQ-FND-03).

## Requirements covered

REQ-UI-01 … REQ-UI-09, REQ-TRY-01 … REQ-TRY-07, REQ-DSN-04, REQ-DSN-08,
REQ-DSN-10, REQ-DSN-11, REQ-TST-06, REQ-TST-08, REQ-TST-09, REQ-INST-10.

## 1. Window chrome, and what a custom title bar costs (REQ-UI-02)

**Default: system chrome.** `eframe::ViewportBuilder` with decorations on. A
custom title bar is an intake option, not a default, because it is not a visual
choice — it is a list of Win32 behaviours you now own:

| Behaviour | What you must implement | What breaks if you do not |
|---|---|---|
| Snap Layouts | `WM_NCHITTEST` returning `HTMAXBUTTON` over the maximise button | Hovering maximise shows nothing on Windows 11 |
| Resize borders | `HTLEFT`/`HTTOPRIGHT`/… per edge, at the system metric width | The window cannot be resized from an edge |
| Alt+Space, Win+Arrow | `WM_SYSCOMMAND` pass-through | The keyboard window commands of REQ-UI-04 disappear |

That is the tradeoff: custom chrome buys a coherent look and costs those rows
plus their DPI and multi-monitor variants. We default to system chrome and spend
the budget on the states in §6 instead.

## 2. Window placement, including a monitor that no longer exists (REQ-UI-03)

Persist the full `WINDOWPLACEMENT` — restored position, show state, maximised
flag — plus the device name of the monitor, its work-area rect, **and the DPI the
size was measured at**. Size is stored logically; a size captured at 200% and
restored at 100% as physical pixels gives a window twice the intended size, which
is the bug this requirement's second clause hides behind.

Restore: `MonitorFromRect(&saved, MONITOR_DEFAULTTONULL)`. A null result means
the monitor is gone — an undocked laptop, a projector unplugged, a remote session
with a different layout — so fall back to the primary monitor, scale the logical
size to its DPI, and clamp into `rcWork` so at least 48 px of title bar and
120 px of width are on-screen. Never open off-screen and never trust a saved rect
without intersecting it against the current virtual desktop.

Save is debounced 500 ms after `WM_EXITSIZEMOVE` or a move and forced on
`WM_ENDSESSION`; writing on every `WM_MOVE` rewrites the config a few hundred
times while the user drags a window.

## 3. Keyboard completeness (REQ-UI-04)

Every action reachable without a mouse, and that is a testable claim: the view
registry knows every action id and a test walks the tab cycle asserting each is
reachable. In egui the tab order is widget instantiation order, so keyboard order
is a property of code order rather than of a layout tree — a two-column layout
that reads left-to-right visually and top-to-bottom in source has a tab order
that surprises everyone. The registry records the intended order; the test
compares.

Accelerators: `Alt`/`F10` menu, `F6`/`Ctrl+F6` pane cycle, `Tab`/`Shift+Tab`,
arrows within a group, `Space`/`Enter` activate, `Esc` cancel or close a
transient, `Applications` key context menu, `Ctrl+W` close, `Alt+F4` close
honouring §8's close behaviour, `Ctrl+,` settings, `Ctrl+Shift+D` diagnostics,
`F1` help. Focus is drawn as a 2 px `focus.ring` token outline and is never
suppressed for mouse users — it is shown on keyboard interaction and hidden on
pointer interaction, per-widget, never globally disabled.

## 4. Accessibility through UI Automation (REQ-UI-05)

Blunt: egui paints to a GPU surface and exposes **no** UIA tree of its own. The
tree comes from AccessKit, enabled through eframe's `accesskit` feature, which is
not optional here — without it a screen reader sees one opaque window and
REQ-UI-05 is unmet no matter how the UI looks.

Every control carries a name from the string catalogue (§7), a role and a value
where it has one. State changes that matter — an operation finished, an error
appeared, a service state changed — are announced through a polite live region and
critical failures through an assertive one, debounced and de-duplicated because an
announcement per frame is noise. If intake selects a framework without an
accessibility adapter, REQ-UI-05 cannot be met: that is an H0 blocker, not an H6
finding. Verification is Narrator over the primary flows plus an Accessibility
Insights tree dump, not a property inspection (REQ-TST-09).

## 5. The UI thread never blocks (REQ-UI-06)

**A frozen window is the most common defect class in this kind of app**, and the
easiest to ship, because the blocking version of every call is shorter to write.
The rule is absolute: `crates/ui` performs no file I/O, no network I/O, no
registry read, no process spawn, no lock held across a frame and no `sleep`.
The tokio runtime lives in `crates/app`; the UI holds a `TaskSpawner` from the
contract, sends a `Command`, and drains a bounded channel of `Progress`,
`Done(T)` and `Failed(Error)` once per frame. Every task carries a
`CancellationToken`, and the cancel control is enabled the instant the task
starts — a cancel button that appears after the operation is already slow is the
same defect wearing a hat.

Numbers, so this is checkable: a frame closure taking longer than 8 ms logs a
warning naming the view; a spinner appears only after 600 ms and a skeleton after
150 ms, so a fast operation does not flash; a task with no progress for 10 s
shows the elapsed time and the cancel path in the foreground. Enforcement is a
banned-symbol lint over `crates/ui`: `std::fs`, `std::net`, `ureq`,
`std::thread::sleep`, `block_on` and `rfd`'s blocking dialogs (use the async
ones). B12's log writer is called through a non-blocking sink for the same reason.

## 6. Empty, loading, error and offline (REQ-UI-07)

Every view returns one of five states, and the `view-registry` refuses
registration of a view that does not render all five (REQ-DSN-10):

```rust
pub enum ViewState<T> {
    Empty   { reason: EmptyReason, primary_action: Option<ActionId> },
    Loading { started: Instant, determinate: Option<f32> },
    Error   { code: ErrorCode, message: StringKey, retry: Option<ActionId> },
    Offline { last_success: Option<SystemTime> },
    Ready(T),
}
```

`Empty` is designed, not blank: it says why, and offers the one action that
changes it. `Error` shows a code support can search for, not a stack trace.
`Offline` states when data was last good, because "offline" without that is
indistinguishable from "broken". B15 captures all five in both themes
(REQ-TST-04), which is how "designed" is verified rather than asserted.

## 7. Strings and locale (REQ-UI-08)

No user-visible literal in a view. Keys live in `strings/<locale>.json` and
`build.rs` generates a typed `StringKey` enum from the base locale, so a missing
key is a compile error and an unused one is a warning. That choice adds no
dependency: an ICU-grade plural or gender need is a CCR to B16 for a validated
crate, not an invented `Cargo.toml` line (REQ-VER-02, REQ-SBM-05).

Locale resolves from `GetUserDefaultLocaleName` via `ffi::locale`, falls back per
key rather than per file, and is overridable in settings. Dates, times and numbers
go through one formatter; a hand-rolled `format!("{}/{}/{}")` is a defect, and a
CI grep rejects a four-letter-or-longer literal in `crates/ui/src/views/`.

## 8. Settings, and the tray as its front door (REQ-UI-09, REQ-TRY-03, REQ-TRY-04)

`settings-registry` has six sections, and each panel is contributed by the crate
that owns the domain — B05 owns the registry and the shell, not the content of
another agent's panel:

| Section | Contents | Panel owner |
|---|---|---|
| Appearance | System / light / dark (REQ-DSN-04), reduced motion | B05 |
| Startup | Autostart on/off, start minimised, mechanism shown | B08 |
| Updates | Channel, automatic/notify, last check, policy banner | B09 |
| Service | State, install/start/stop, version-mismatch warning | B08 |
| Diagnostics | Log level, log folder, support bundle, diagnostics view | B12 |
| About | Version, commit, end-of-support date (REQ-CRA-08) | B05 |

**Close behaviour** (REQ-TRY-03) defaults to minimise-to-tray, changeable in
Startup, and the first close explains where the window went — once, recorded as
`close_hint_shown`. It is a toast, falling back to an in-window dialog shown
*before* the window hides when `SHQueryUserNotificationState` reports
notifications suppressed. A first-time explanation delivered only through a
channel Focus Assist can silence is not an explanation.

**The menu reflects live state** (REQ-TRY-04), rebuilt from `tray-state` on every
transition: Open (default, bold, also double-click), the state action
(Pause/Resume), Check for updates — disabled and labelled "Checking…" during a
check — Settings, Diagnostics, About, Exit. The states are `Running`, `Paused`,
`Updating { percent }`, `Error { code }` and `ServiceMode { running,
version_mismatch }`, each with a distinct icon and text, never a colour alone
(REQ-DSN-07). The tooltip carries the same state, truncated deliberately to fit
`szTip`'s 128 `u16` limit rather than overflowing it.

## 9. Tray icon variants, DPI, and the Explorer restart (REQ-TRY-01, REQ-TRY-02)

Three icon variants — light background, dark background, high contrast — each an
ICO holding hand-tuned 16, 20, 24, 32, 40 and 48 px frames, because a 256 px glyph
downscaled to 16 px is mud. The variant follows the system theme and
`SPI_GETHIGHCONTRAST`, re-chosen on `WM_SETTINGCHANGE` and `WM_THEMECHANGED`. The
size comes from `GetSystemMetricsForDpi(SM_CXSMICON, dpi)` for the **taskbar's**
monitor — not necessarily the window's — and is re-supplied on `WM_DPICHANGED`.

**The Explorer restart is the defect users actually report** (REQ-TRY-02). When
Explorer dies the notification area is recreated and every icon in it is gone. The
mechanism is exact: register `RegisterWindowMessageW("TaskbarCreated")` at startup
and, on receiving it, call `Shell_NotifyIconW(NIM_ADD)` again — every time, not
once, because Explorer can restart repeatedly. Three details are routinely missed,
each producing a half-working icon:

1. Re-issue `NIM_SETVERSION` with `NOTIFYICON_VERSION_4` after every add.
   Without it the callback message semantics silently revert.
2. The tooltip, the icon handle and the menu are re-supplied too. A bare re-add
   gives a working icon with no tooltip.
3. `Shell_NotifyIconW` can fail with a timeout while the shell is still starting.
   Retry with backoff at 1 s, 2 s, 4 s, 8 s and 16 s before reporting failure.

`tray-icon 0.25.1` handles some of this internally. That is verified by test, not
trusted: B14 kills and restarts `explorer.exe` three times on a clean image and
asserts the icon returns within 10 s each time (REQ-TST-06).

## 10. Notifications (REQ-TRY-05)

Posted through the Windows notification platform so Focus Assist, quiet hours and
per-app settings apply — we do not query the state and post anyway. On top of
that our own `Informational` class is suppressed when
`SHQueryUserNotificationState` returns `QUNS_PRESENTATION_MODE`,
`QUNS_RUNNING_D3D_FULL_SCREEN`, `QUNS_QUIET_TIME` or `QUNS_BUSY`. `Transactional`
(update installed, restart needed) and `Critical` (update failed repeatedly,
service crash loop) still post.

**The trap:** a toast needs a registered AppUserModelID backed by a Start Menu
shortcut (REQ-INST-10). Without both, on Windows 10 the toast silently does not
appear and no error is returned. B06 consumes the AUMID from B07's install
contract; the string in the shortcut and the string in the registration must be
identical, and B14 asserts a toast is visible on a clean install rather than
asserting the call returned `Ok`.

A notification carries one line and at most one action, which opens the window at
the relevant view. Anything longer belongs in the window.

## 11. Single instance, and a real exit (REQ-TRY-06, REQ-TRY-07)

Single instance uses a named mutex in the **`Local\`** namespace, not `Global\`:
per-user, per-session, so a second user on the machine gets their own instance
instead of being locked out. On `ERROR_ALREADY_EXISTS` the new process calls
`AllowSetForegroundWindow` for the owning PID, posts a registered
`"<app-id>.Activate"` to the existing hidden message window, and exits 0.
`AllowSetForegroundWindow` is the part usually missing: without it
`SetForegroundWindow` fails in the running instance and the window flashes in the
taskbar instead of coming forward. The new process retries finding the window for
5 s, because the first may not have created it yet.

Exit from the tray is a real exit, in order: cancel every task and await with a
5 s deadline, call `Shell_NotifyIconW(NIM_DELETE)` explicitly — relying on
process teardown leaves a ghost icon until the user mouses over it — destroy the
message window, flush B12's log sink, release the mutex, stop the runtime,
return 0. **Exiting the UI does not stop the service.** When service mode is on,
the menu item reads "Exit (service keeps running)", and the service is left in
its declared state (REQ-TRY-07, REQ-SVC-04).

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Window chrome | System chrome | §1's table is the cost of custom | Yes |
| Placement stored as | `WINDOWPLACEMENT` + monitor + DPI | A physical size restored at another DPI is wrong | No |
| Lost-monitor fallback | Primary, clamped into `rcWork` | REQ-UI-03 | No |
| Accessibility | AccessKit via eframe's feature | egui exposes no UIA tree otherwise | No |
| UI-thread I/O | Banned by lint | REQ-UI-06 | No |
| Close behaviour | Minimise to tray, one-time hint | REQ-TRY-03 | Yes |
| Explorer restart | `TaskbarCreated` + re-add + `NIM_SETVERSION` | REQ-TRY-02 | No |
| Instance mutex | `Local\` namespace | `Global\` locks out a second user | No |
| Tray Exit with a service | Exits the UI only, and says so | REQ-TRY-07 | No |

## How this is verified

- `cargo test -p ui` — tab-cycle reachability of every registered action
  (REQ-UI-04), five-state completeness (REQ-UI-07), placement round-trips
  including a rect on a monitor absent from the layout and a size saved at 200%
  restored at 100% (REQ-UI-03), string-key coverage per locale (REQ-UI-08).
- `cargo clippy` plus the banned-symbol lint over `crates/ui`: no `std::fs`,
  `std::net`, `ureq`, `sleep`, `block_on`, blocking `rfd` (REQ-UI-06). A grep
  rejects any raw hex colour in `crates/ui` or `crates/tray` (REQ-DSN-09).
- `tests/tray/**` (B14) — Explorer killed and restarted three times, icon back
  within 10 s with tooltip and menu intact (REQ-TRY-02, REQ-TST-06);
  second-launch focuses the first window and exits 0 (REQ-TRY-06); after Exit no
  process remains and no icon lingers (REQ-TRY-07); a toast appears on a clean
  install with the AUMID from B07 (REQ-TRY-05).
- B15's capture sets: every view in all five states, light and dark, presented in
  the chat reply (REQ-TST-04); the DPI matrix at 100/150/200/250% and a window
  dragged between mixed-scale monitors (REQ-TST-08, REQ-DSN-11); the tray menu in
  each of its five states. Narrator over the primary flows with the transcript
  recorded, plus an Accessibility Insights tree dump showing a named control per
  action (REQ-UI-05, REQ-TST-09).

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| UI framework | `eframe 0.36.2` (REQ-UI-01) |
| System chrome or custom title bar | System chrome |
| Close button behaviour | Minimise to tray |
| Shipped locales | Base locale only, catalogue ready for more |
| Informational notifications | Off; `Transactional` and `Critical` only |
