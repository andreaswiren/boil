# Design System

Owned by **B03 `design-system`** (Wave 1). B03 writes `crates/design/**` and
`design/**` and publishes `design-tokens`
(`contracts/types/design-tokens.md`). It runs before B04 and before every Wave 3
agent, because a desktop design the framework's styling model cannot express is
discovered late — after every view has been built against it. That is the whole
reason this wave blocks (REQ-GAT-08, REQ-DSN-01).

This document is the rationale and the decisions. The values are in the token
module, and the token module is what compiles.

## Requirements covered

REQ-DSN-01, REQ-DSN-02, REQ-DSN-03, REQ-DSN-04, REQ-DSN-05, REQ-DSN-06,
REQ-DSN-07, REQ-DSN-08, REQ-DSN-09, REQ-DSN-10, REQ-DSN-11. Feeds REQ-UI-01,
REQ-UI-04, REQ-UI-07, REQ-TRY-01, REQ-TST-05, REQ-TST-08, REQ-MOC-03.

## Tokens are code (REQ-DSN-02)

The design system is four `const Tokens` values in `crates/design/src/tokens.rs`
and one resolver. It is not a PDF, not a Figma file and not this document.

A token in a document is a suggestion: it can be out of date, it can disagree
with the binary, and nothing fails when it does. A token that is a `const` is
compiled into the shipped executable, appears in `--version` output through
`TOKENS_VERSION`, and is asserted over by a test. `eframe`/`egui` 0.36.2
(`versions/manifest.json`) is the default framework for exactly this reason:
`egui::Color32` and `egui::Stroke` are plain values, so a token is a Rust value
and nothing is serialised, parsed or themed at runtime (REQ-UI-01).

`slint` 1.18.1 would put the design system in its own `.slint` styling language.
That is a better fit if the design must live outside Rust and a worse fit for
REQ-MOC-02, because the compiled proof then proves a `.slint` file compiles
rather than that the Rust tokens do. It remains an intake option; the tradeoff is
recorded here so the choice is made on purpose.

## Colour is a set of roles, not a set of colours (REQ-DSN-09)

Eleven roles: `surface`, `surface_raised`, `text_primary`, `text_muted`,
`accent`, `accent_text`, `danger`, `warning`, `success`, `border`, `focus_ring`.
Values are in `contracts/types/design-tokens.md` §3.

A role survives a rebrand. `blue_600` does not: when the accent becomes green,
`blue_600` is either renamed at every call site — a change that touches every
view and cannot be reviewed — or left in place, at which point the codebase says
blue and the screen shows green. `accent` changes value in one file and nothing
else moves.

Icons are drawn in a text role, never in a colour of their own. That is what
makes REQ-DSN-06 cover "meaningful iconography" without a second pair table: a
16pt glyph in `danger` on `surface` is a pair the test already asserts. A tray
icon is the exception and is B06's, drawn from the same roles in light, dark and
high-contrast variants (REQ-TRY-01).

`danger`, `warning` and `success` are **text and glyph** colours drawn on a
surface, never fills. A filled status banner needs a second contrast pair for
its own text, which is a role nobody added and a pair nobody asserted. A status
row is an icon plus `danger` text on `surface`, which is one pair the §contrast
test already covers.

## Typography (REQ-DSN-05)

**Decision: embed Inter Variable as the UI font and JetBrains Mono as the
monospace font.** Both are redistributable — Inter is SIL Open Font License 1.1,
JetBrains Mono is Apache License 2.0 — so shipping the bytes inside the
executable is licence-clear. Subset to Latin, Latin-1 Supplement and Latin
Extended-A; budget 400 KB of the binary for both, and CI fails the build if the
embedded font files exceed 700 KB.

The alternative is real and was rejected. Windows ships Segoe UI Variable, and
resolving it from the system is legitimate *if* the fallback chain is documented
— which would be: Segoe UI Variable Text → Segoe UI → Tahoma → the framework's
bundled fallback. Two things decided it against us. First, Segoe UI Variable
ships on Windows 11 and not on Windows 10, so on a Windows 10 target the app
silently renders in a different typeface with different metrics; the exact build
boundary is `unconfirmed` here and B01 confirms it against the minimum supported
version it enforces at startup (REQ-FND-05). Second, `egui` does not resolve
system fonts by default — getting Segoe UI means reading a font file from
`C:\Windows\Fonts` through a B01 FFI wrapper, which adds a Win32 dependency to
the design system in exchange for a font that may not be there.

Embedding costs binary size and gives up looking exactly like the rest of the
shell. It buys a layout that is identical on every machine, and it removes an
entire class of "it looks wrong on that laptop" defect. Take the size.

The scale — `display` 28pt through `caption` 12pt at `body` 14pt/20pt — is
shared by every theme and overridden by none. A theme switch must not reflow
text (REQ-DSN-04).

## Light and dark are two designs (REQ-DSN-03)

Both are designed. `DARK` is not `LIGHT` inverted, and the token values show it:
`LIGHT.accent_text` is white on a deep blue fill, `DARK.accent_text` is
near-black on a light blue fill. The accent flips polarity rather than shifting
lightness, because a saturated deep blue on a near-black surface fails contrast
and a pale blue on white fails it in the other direction.

Elevation differs too. `DARK` separates `surface_raised` from `surface` by
1.11:1 where `LIGHT` uses 1.04:1, and `DARK`'s shadows carry more alpha and more
spread, because a shadow on a dark surface is read by its spread and not by its
darkness. An inverted light theme gets both of these wrong and looks flat.

## Following and switching the system theme (REQ-DSN-04)

Default: follow the Windows app-mode preference. Settings offers a fixed light or
dark override. High contrast outranks both — a user who turned it on is not
overridden by an app setting.

The switch is live. No restart, no relaunch, no "changes take effect next time".
The mechanism, all of it behind a B01 wrapper in `crates/ffi` because
`windows-rs` is called from one crate only (REQ-FND-03):

| Fact | Mechanism | Status |
|------|-----------|--------|
| App light/dark now | `AppsUseLightTheme` (DWORD) under `HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize`; `0` dark, `1` light | confirmed by B01 at H3 |
| Light/dark changed | `WM_SETTINGCHANGE` where `lParam` is the string `"ImmersiveColorSet"` | **`unconfirmed`** — the string is widely relied on but B03 could not verify it against current Microsoft documentation. B01 confirms it or substitutes `UISettings.ColorValuesChanged` (WinRT) |
| High contrast on/off and its scheme | `SystemParametersInfoW(SPI_GETHIGHCONTRAST)` into `HIGHCONTRASTW`, then the scheme's own colours | confirmed by B01 at H3 |
| High contrast changed | `WM_SETTINGCHANGE` with `wParam == SPI_SETHIGHCONTRAST`, plus `WM_THEMECHANGED` | confirmed by B01 at H3 |
| Reduced motion | `SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION)` → `BOOL` | confirmed by B01 at H3 |

B03 consumes one function, `ffi::appearance::watch(tx)`, which sends a
`SystemAppearance` on every change and once at startup. B03 files a CCR for it;
it does not add `use windows::Win32::...` to `crates/design`.

The failure mode to design against is not the switch, it is the switch mid-frame:
a repaint that reads `LIGHT.surface` and `DARK.text_primary` in the same frame.
`resolve()` returns a whole `Tokens` by value and a frame borrows it once, so the
two cannot be mixed.

## Contrast (REQ-DSN-06)

WCAG 2.2 AA, asserted by a test over a declared pair table in all four themes,
including both high-contrast palettes. The formula, the tiers and the 18 pairs
per theme are `contracts/types/design-tokens.md` §5.

Three things the test does that a visual check does not: it covers the
high-contrast palettes, which nobody screenshots; it fails on the pair a human
would not think to compare, such as `text_muted` on `surface_raised` rather than
on `surface`; and it fails **before** the screenshots reach the human at H1. A
mockup that fails the contrast test is not a design direction. It is a proposal
to ship an inaccessible product.

The thinnest margin in the shipped set is `DARK.border` on `surface_raised` at
3.06:1 against a 3.0 floor. That is deliberate. A border nudged one step lighter
to look calmer fails the test, which is the conversation happening at review time
instead of at an accessibility audit.

## Colour is never the only signal (REQ-DSN-07)

Every state carries a second, non-colour carrier:

| State | Colour | Also |
|-------|--------|------|
| Error on a field | `danger` text | An icon, a text message under the field, and the field border at 2pt |
| Success | `success` text | A check glyph and the word |
| Warning | `warning` text | A triangle glyph and the word |
| Selected row | `accent` at 12% fill | A 3pt `accent` bar on the leading edge |
| Disabled | 38% opacity | The control does not respond to hover, and its tooltip says why |
| Busy | — | A determinate or indeterminate indicator plus a label; never a colour change alone |

The high-contrast palettes are the proof. `text_muted == text_primary` there, so
any distinction carried by muting alone disappears. If a view still reads
correctly in high contrast, REQ-DSN-07 holds. If it does not, it never did — the
colour was doing work the design never stated.

## Reduced motion and high contrast (REQ-DSN-08)

Reduced motion means `Motion::reduced()`: every duration **zero**, not shorter. A
90 ms fade is still a fade, and the setting exists because the movement is the
problem. State changes become instant; a busy indicator becomes a determinate
text count where one is available and a static label where it is not.

High contrast **replaces** the palette. Two separate `const Palette` values, no
tint, no alpha blend. Every elevation collapses to `flat` plus a 1pt `border`
stroke, because a shadow carries no information in a two-colour scheme. The
shipped constants are a fallback; the live scheme is the user's own, read through
the same B01 wrapper. Tinting a palette toward higher contrast is the common
shortcut and it produces a palette that is neither the design nor the user's
scheme.

## Every state of every control (REQ-DSN-10)

Seven states: **rest, hover, focus-visible, active, disabled, busy, error**.
Every control has all seven specified before any view uses it.

| State | Specification |
|-------|--------------|
| rest | The control's own fill, `border` at 1pt |
| hover | `surface_raised` fill, or accent fill lightened one elevation step; cursor change |
| focus-visible | 2pt `focus_ring` outside a 1pt `surface` gap — the two-tone ring. Keyboard focus only; a mouse click does not draw it (REQ-UI-04) |
| active | Fill one step darker, no movement and no scale transform |
| disabled | 38% opacity, no hover response, a tooltip stating why |
| busy | Indicator plus label, control non-interactive but still focusable so a screen reader can read the state (REQ-UI-05) |
| error | `danger` text, 2pt `danger` border, icon, message |

The undesigned states are the ones that look broken. Rest and hover get designed
because they are what a designer looks at. Disabled ends up as whatever 50%
opacity does to the fill, busy ends up as a control that silently ignores clicks,
and focus-visible ends up as the framework default outline — which on `egui` is a
thin rectangle that vanishes against `accent`. Each mockup renders all seven for
at least a button, a text field, a checkbox, a list row and a menu item
(REQ-MOC-03), so the states arrive designed rather than defaulted.

## DPI (REQ-DSN-11)

Correct from 100% to 250%, including a window dragged between monitors with
different scale factors.

Token scalars are logical points at 96 DPI and are never pre-multiplied. Scale is
applied once, at the renderer, from the scale factor of the monitor the window is
currently on. Two rules follow: no token is an integer pixel count, and no layout
rounds a dimension before scaling. A 1pt border at 250% is 2.5 device pixels and
the renderer decides how to draw it; a border stored as `1` and scaled by hand
becomes 2 px on one monitor and 3 px on the other, and the window shows both at
once while it is being dragged across the boundary.

The window is per-monitor DPI aware v2, set by B01 in the application manifest.
B15 screenshots every mockup at 100%, 150%, 200% and 250% and across a
mixed-scale pair (REQ-TST-08).

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|----------|--------|-----|---------------------|
| Token form | `const Tokens` in Rust | A token that cannot be compiled is a suggestion (REQ-DSN-02) | No |
| UI framework | `eframe`/`egui` 0.36.2 | Tokens are plain Rust values, so REQ-MOC-02 is cheap | Yes — `iced` 0.14.0, `slint` 1.18.1 |
| Colour naming | Role, not hue | `accent` survives a rebrand; `blue_600` does not | No |
| Palette size | 11 roles | Adding a role is additive; a role nobody asserted is not | Yes, additively |
| UI font | Inter Variable, embedded | OFL 1.1, identical rendering on every machine | Yes — Segoe UI Variable with the documented fallback chain |
| Mono font | JetBrains Mono, embedded | Apache-2.0; the diagnostics and log views need real columns | Yes |
| Iconography | Lucide, monochrome, 16pt and 20pt, 1.5pt stroke | One stroke weight at two sizes, and a monochrome glyph inherits the text role's asserted contrast pair rather than adding one. Licence text recorded in `design/icons.md` | Yes |
| Body size | 14pt / 20pt line | Readable at 100% without scaling, dense enough for a utility window | Yes, per direction (REQ-MOC-06) |
| Spacing base | 4pt grid, 7 steps | Divides cleanly at 150% and 250% | No |
| Theme default | Follow system | REQ-DSN-04 | No |
| Contrast floor | AA: 4.5 text, 3.0 non-text | REQ-DSN-06 | No — a `MUST` is not waivable |
| Reduced motion | All durations zero | Shorter is still movement | No |
| High contrast | Replacement palettes | REQ-DSN-08 | No |
| Focus ring | 2pt ring + 1pt gap, two-tone | A single ring cannot reach 3:1 on an accent fill in any theme | No |
| Elevation | 4 levels, shadow only | A border-based elevation cannot survive high contrast collapsing it | Yes |

## How this is verified

- `cargo test -p design` runs the contrast test over all four themes
  (REQ-DSN-06, REQ-TST-05). It is a gate item at H1, before screenshots are
  presented.
- `ci/lint-no-raw-colour.sh` fails the build on a colour literal outside the
  token module (REQ-DSN-09, REQ-TST-05).
- `cargo build -p mockup-<n>` proves the tokens are expressible in the chosen
  framework (REQ-MOC-02, REQ-MOC-04). This is the only proof that counts.
- A test asserts `Motion::reduced()` returns zero for all four durations
  (REQ-DSN-08).
- A test asserts every `ThemeId` variant resolves to a `Tokens` and that no
  `match` on `ThemeId` has a `_` arm.
- B15 screenshots both themes at 100/150/200/250% and across a mixed-scale
  monitor pair (REQ-TST-08, REQ-DSN-11).
- D1 votes on theme honesty, state coverage and DPI at H6 (REQ-GAT-01). B03 does
  not vote on its own work (REQ-GAT-07).

## Open to intake

- **UI framework.** `eframe` is the default. `iced` or `slint` changes the
  `From<Rgba8>` impl and, for `slint`, moves the design system out of Rust — a
  tradeoff recorded above, not a free swap.
- **Font.** Segoe UI Variable with the documented fallback chain is available if
  a native look matters more than identical rendering, and if the minimum
  supported Windows version makes it safe.
- **Accent hue.** Free. Changing `accent` is one value in one file, and the
  contrast test says immediately whether the new value is legal.
- **Density and typographic scale.** Set by the H1 winner, not by this document.
  The four directions in `spec/mockups.md` differ mostly here.
- **A new colour role.** Additive: a CCR B02 assembles, with its contrast pairs
  added in the same change (`contracts/types/design-tokens.md` §8).

Not open: the contrast floor, the reduced-motion semantics, the high-contrast
replacement, the no-raw-colour lint, and tokens being code. Those are `MUST`.
