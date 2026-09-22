# `design-tokens` — the compiled design system

**Published by:** B03 (`design-system`), from `crates/design/src/tokens.rs`.
**Requirements:** REQ-DSN-02, REQ-DSN-03, REQ-DSN-06, REQ-DSN-08, REQ-DSN-09,
REQ-DSN-10, REQ-DSN-11, REQ-TST-05, REQ-UI-01.
**Consumed by:** B04, B05, B06, B12, B14, B15.

Tokens are `const` Rust values. A view reads `Tokens`; it never names a colour,
so the compiler is what stops a twelfth colour role appearing. Rationale is
`spec/design-system.md`; this is the frozen shape.

---

## 1. `Rgba8`

`crates/design` depends on no UI framework: an intake that picks `iced` or
`slint` over `eframe` (`versions/manifest.json`, REQ-UI-01) replaces one `impl`,
not the palette. There is no `Rgba8::new` — three decimal `u8` arguments is how
a raw colour gets past the §7 lint.

```rust
// crates/design/src/color.rs
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Rgba8 { pub r: u8, pub g: u8, pub b: u8, pub a: u8 }

impl Rgba8 {
    /// 0xRRGGBB, opaque. The only way a colour enters the token module.
    pub const fn hex(v: u32) -> Self { Self { r: (v >> 16) as u8, g: (v >> 8) as u8, b: v as u8, a: 0xFF } }
    /// 0xRRGGBBAA. Shadow and scrim only — never a contrast participant.
    pub const fn hexa(v: u32) -> Self { Self { r: (v >> 24) as u8, g: (v >> 16) as u8, b: (v >> 8) as u8, a: v as u8 } }
}

#[cfg(feature = "egui")]
impl From<Rgba8> for egui::Color32 {
    fn from(c: Rgba8) -> Self { egui::Color32::from_rgba_unmultiplied(c.r, c.g, c.b, c.a) }
}
```

## 2. The token struct

Every scalar is in **logical points** at 96 DPI, never pre-multiplied: scaling
is applied once at the renderer from the DPI of the monitor the window is on
(REQ-DSN-11). All structs below derive `Clone, Copy, Debug`; `Palette` and
`ThemeId` also derive `PartialEq, Eq`.

```rust
// crates/design/src/tokens.rs
pub const TOKENS_VERSION: u32 = 1;                 // bumped by §8

pub enum ThemeId { Light, Dark, HighContrastLight, HighContrastDark }

/// Colour **roles**, not colour names. `accent` can become green at a rebrand;
/// `blue_600` would have to be renamed at every call site (REQ-DSN-09).
pub struct Palette {
    pub surface: Rgba8,          pub surface_raised: Rgba8,   // window bg; card, popup, hovered row
    pub text_primary: Rgba8,     pub text_muted: Rgba8,       // body text and meaningful glyphs; secondary
    pub accent: Rgba8,           pub accent_text: Rgba8,      // action fill, selection, link; text drawn ON accent
    pub danger: Rgba8,           pub warning: Rgba8,          // text/glyph ON a surface, never a fill
    pub success: Rgba8,          pub border: Rgba8,           // control boundary, 3:1 on both surfaces
    pub focus_ring: Rgba8,                                    // outer stroke of the two-tone ring (§5)
}

pub struct Spacing { pub xxs: f32, pub xs: f32, pub sm: f32, pub md: f32, pub lg: f32, pub xl: f32, pub xxl: f32 }
pub struct Radii { pub sm: f32, pub md: f32, pub lg: f32, pub pill: f32 }
pub struct TypeStyle { pub size: f32, pub line: f32, pub weight: u16, pub tracking: f32 }
pub struct TypeScale {
    pub family: &'static str, pub mono_family: &'static str,
    pub display: TypeStyle, pub title: TypeStyle, pub heading: TypeStyle, pub body: TypeStyle,
    pub body_strong: TypeStyle, pub caption: TypeStyle, pub mono: TypeStyle,
}
pub struct Shadow { pub y: f32, pub blur: f32, pub spread: f32, pub color: Rgba8 }
pub struct Elevation { pub flat: Shadow, pub raised: Shadow, pub overlay: Shadow, pub modal: Shadow }
pub struct Motion { pub instant: u16, pub fast: u16, pub normal: u16, pub slow: u16, pub ease_out: [f32; 4] }

impl Motion {
    /// REQ-DSN-08. Not "shorter" — zero. A 60 ms fade is still a fade.
    pub const fn reduced() -> Self {
        Self { instant: 0, fast: 0, normal: 0, slow: 0, ease_out: [0.0, 0.0, 1.0, 1.0] }
    }
}

impl Shadow {
    /// Fully transparent, zero geometry. Not "a very light shadow" — a renderer
    /// that skips a zero-alpha draw and one that blends it must agree.
    pub const NONE: Self = Self { y: 0.0, blur: 0.0, spread: 0.0, color: Rgba8::hexa(0x00000000) };
}

impl Elevation {
    /// Every level collapsed to nothing, for the two high-contrast themes (§4).
    /// Named rather than repeated at each use site so that "high contrast draws
    /// no shadows" is one declaration a reviewer can check, not two identical
    /// literals that can drift apart.
    pub const FLAT_ALL: Self = Self {
        flat: Shadow::NONE, raised: Shadow::NONE, overlay: Shadow::NONE, modal: Shadow::NONE,
    };
}

/// REQ-DSN-10's seven states, as data. `contracts/README.md` promises this
/// member carries per-state tokens; without them each of the nine Wave 3 crates
/// decides for itself what "hover" costs, and `disabled` arrives as whatever the
/// framework's default opacity happens to be.
pub enum State { Rest, Hover, FocusVisible, Active, Disabled, Busy, Error }

/// Which palette role draws the stroke. An enum rather than an `Rgba8` so that
/// a state's stroke follows the theme instead of being frozen at one colour.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum BorderRole { Border, Danger, Accent }

#[derive(Clone, Copy)]
pub struct StateStyle {
    /// Overlay of `palette.text_primary` composited over the control's own fill.
    /// Expressed as an alpha, not a colour, so one number works in both themes:
    /// `text_primary` is near-black in `LIGHT` and near-white in `DARK`, so the
    /// same 0.08 darkens a light control and lightens a dark one. Tinting toward
    /// a fixed grey is the shortcut that produces a third palette nobody designed.
    pub layer_alpha: f32,
    pub border_pt: f32,
    pub border_role: BorderRole,
    /// A dashed stroke, which is the only `disabled` cue that survives high
    /// contrast: there `text_muted == text_primary` and the palette is two
    /// colours, so neither muting nor 38% opacity can carry the state (§4).
    pub border_dashed: bool,
    /// Multiplies the whole control, including its text and its icon.
    pub opacity: f32,
    /// The two-tone focus ring (§5). `0.0` means no ring is drawn.
    pub ring_pt: f32,
    pub ring_gap_pt: f32,
    /// `false` = the control ignores input. `busy` is non-interactive and still
    /// focusable, because a screen reader must be able to read the state
    /// (REQ-UI-05); the two flags are separate for exactly that case.
    pub interactive: bool,
    pub focusable: bool,
    /// `true` = the control must carry a tooltip saying why it is in this state.
    /// Asserted by the accessibility test, not left to each view (REQ-DSN-07).
    pub tooltip_required: bool,
}

#[derive(Clone, Copy)]
pub struct StateSet {
    pub rest: StateStyle, pub hover: StateStyle, pub focus_visible: StateStyle,
    pub active: StateStyle, pub disabled: StateStyle, pub busy: StateStyle,
    pub error: StateStyle,
}

/// Selection is not an eighth state — REQ-DSN-10 names seven and a selected row
/// can also be hovered, focused or in error. It composites on top.
pub struct Selection { pub fill_alpha: f32, pub leading_bar_pt: f32 }

pub struct Tokens {
    pub id: ThemeId, pub version: u32, pub palette: Palette, pub space: Spacing,
    pub radius: Radii, pub text: TypeScale, pub elevation: Elevation, pub motion: Motion,
    pub state: StateSet, pub selection: Selection,
}
```

## 3. `LIGHT` and `DARK` — two designed themes (REQ-DSN-03)

Neither is derived from the other and the values say so. `LIGHT.accent_text` is
white on a deep blue fill, `DARK.accent_text` near-black on a light blue fill —
the accent flips polarity rather than shifting lightness. `DARK` separates
`surface_raised` from `surface` by 1.11:1 where `LIGHT` uses 1.04:1, because a
dark surface needs more separation to read as lifted.

```rust
const LIGHT_PALETTE: Palette = Palette {
    surface:     Rgba8::hex(0xFAFAFA), surface_raised: Rgba8::hex(0xFFFFFF),
    text_primary:Rgba8::hex(0x16181D), text_muted:     Rgba8::hex(0x5A616E),
    accent:      Rgba8::hex(0x1A5FB4), accent_text:    Rgba8::hex(0xFFFFFF),
    danger:      Rgba8::hex(0xB4252A), warning:        Rgba8::hex(0x8A5300),
    success:     Rgba8::hex(0x1C6B3C), border:         Rgba8::hex(0x898F99),
    focus_ring:  Rgba8::hex(0x0B3C78),
};
const DARK_PALETTE: Palette = Palette {
    surface:     Rgba8::hex(0x16181D), surface_raised: Rgba8::hex(0x1E212A),
    text_primary:Rgba8::hex(0xECEEF2), text_muted:     Rgba8::hex(0xA3AAB8),
    accent:      Rgba8::hex(0x6FA8F5), accent_text:    Rgba8::hex(0x0B1220),
    danger:      Rgba8::hex(0xFF8A84), warning:        Rgba8::hex(0xE8B341),
    success:     Rgba8::hex(0x6FD79B), border:         Rgba8::hex(0x646C80),
    focus_ring:  Rgba8::hex(0x8FC0FF),
};
/// Shared by both themes and overridden by neither: a theme change must not
/// reflow text (REQ-DSN-04).
const BASE_TYPE: TypeScale = TypeScale {
    family: "Inter", mono_family: "JetBrains Mono",
    display:     TypeStyle { size: 28.0, line: 34.0, weight: 600, tracking: -0.4 },
    title:       TypeStyle { size: 20.0, line: 26.0, weight: 600, tracking: -0.2 },
    heading:     TypeStyle { size: 16.0, line: 22.0, weight: 600, tracking:  0.0 },
    body:        TypeStyle { size: 14.0, line: 20.0, weight: 400, tracking:  0.0 },
    body_strong: TypeStyle { size: 14.0, line: 20.0, weight: 600, tracking:  0.0 },
    caption:     TypeStyle { size: 12.0, line: 16.0, weight: 400, tracking:  0.1 },
    mono:        TypeStyle { size: 13.0, line: 18.0, weight: 400, tracking:  0.0 },
};
/// The seven states, straight out of `spec/design-system.md` §"Every state of
/// every control". Shared by `LIGHT` and `DARK`: the values are alphas, weights
/// and roles, so they resolve per theme without being restated per theme.
impl StateStyle {
    /// Every field at its resting value. Each state below states only what it
    /// changes, so "hover costs an 8% layer and nothing else" is readable as one
    /// line instead of being inferred by diffing ten fields against six siblings.
    pub const REST: Self = Self {
        layer_alpha: 0.0, border_pt: 1.0, border_role: BorderRole::Border, border_dashed: false,
        opacity: 1.0, ring_pt: 0.0, ring_gap_pt: 0.0,
        interactive: true, focusable: true, tooltip_required: false,
    };
}

/// The seven states, straight out of `spec/design-system.md` §"Every state of
/// every control". Shared by `LIGHT` and `DARK`: every value is an alpha, a
/// weight or a role, so it resolves per theme without being restated per theme.
const BASE_STATES: StateSet = StateSet {
    rest:          StateStyle::REST,
    hover:         StateStyle { layer_alpha: 0.08, ..StateStyle::REST },
    focus_visible: StateStyle { ring_pt: 2.0, ring_gap_pt: 1.0, ..StateStyle::REST },
    active:        StateStyle { layer_alpha: 0.12, ..StateStyle::REST },
    disabled:      StateStyle { opacity: 0.38, interactive: false, focusable: false,
                                tooltip_required: true, ..StateStyle::REST },
    busy:          StateStyle { interactive: false, ..StateStyle::REST },
    error:         StateStyle { border_pt: 2.0, border_role: BorderRole::Danger, ..StateStyle::REST },
};
/// `busy` keeps `opacity: 1.0` deliberately. Dimming a busy control is the
/// obvious move and it is wrong: the control is not unavailable, it is working,
/// and dimming it makes a 30-second operation look like a dead button.
///
/// High contrast cannot use `layer_alpha` or `opacity` at all — an 8% grey over
/// a two-colour palette is the tint §4 forbids, and 38% of black on white is a
/// grey that fails the contrast test the theme exists to pass. So weight and a
/// dashed stroke carry every state instead, and the ring goes to 3pt because it
/// is the only focus cue left.
const HIGH_CONTRAST_STATES: StateSet = StateSet {
    rest:          StateStyle::REST,
    hover:         StateStyle { border_pt: 2.0, ..StateStyle::REST },
    focus_visible: StateStyle { ring_pt: 3.0, ring_gap_pt: 1.0, ..StateStyle::REST },
    active:        StateStyle { border_pt: 3.0, ..StateStyle::REST },
    disabled:      StateStyle { border_dashed: true, interactive: false, focusable: false,
                                tooltip_required: true, ..StateStyle::REST },
    busy:          StateStyle { interactive: false, ..StateStyle::REST },
    error:         StateStyle { border_pt: 2.0, border_role: BorderRole::Danger, ..StateStyle::REST },
};
const BASE_SELECTION: Selection = Selection { fill_alpha: 0.12, leading_bar_pt: 3.0 };

pub const LIGHT: Tokens = Tokens {
    id: ThemeId::Light, version: TOKENS_VERSION, palette: LIGHT_PALETTE, text: BASE_TYPE,
    space:  Spacing { xxs: 2.0, xs: 4.0, sm: 8.0, md: 12.0, lg: 16.0, xl: 24.0, xxl: 32.0 },
    radius: Radii { sm: 3.0, md: 6.0, lg: 10.0, pill: 999.0 },
    elevation: Elevation {                              // y, blur, spread, 0xRRGGBBAA
        flat:    Shadow { y: 0.0, blur:  0.0, spread:  0.0, color: Rgba8::hexa(0x00000000) },
        raised:  Shadow { y: 1.0, blur:  3.0, spread:  0.0, color: Rgba8::hexa(0x0F141F1F) },
        overlay: Shadow { y: 4.0, blur: 12.0, spread: -2.0, color: Rgba8::hexa(0x0F141F2E) },
        modal:   Shadow { y: 8.0, blur: 28.0, spread: -4.0, color: Rgba8::hexa(0x0F141F3D) },
    },
    motion: Motion { instant: 0, fast: 90, normal: 160, slow: 260, ease_out: [0.16, 1.0, 0.3, 1.0] },
    state: BASE_STATES, selection: BASE_SELECTION,
};
/// The remaining three share `BASE_TYPE`, `space`, `radius` and `motion` with
/// `LIGHT` and differ only where the comment says. Spelled out rather than
/// elided because §7's test iterates all four by name: a snippet that names a
/// const the contract never defines is a snippet that does not compile, and
/// this file is the shape agents build against.
///
/// `DARK` — shadow alpha 0x3D/0x52/0x66 instead of 0x1F/0x2E/0x3D. A shadow on
/// a dark surface is read by its spread, not by its darkness.
pub const DARK: Tokens = Tokens {
    id: ThemeId::Dark, palette: DARK_PALETTE,
    elevation: Elevation {
        flat:    Shadow { y: 0.0, blur:  0.0, spread:  0.0, color: Rgba8::hexa(0x00000000) },
        raised:  Shadow { y: 1.0, blur:  3.0, spread:  0.0, color: Rgba8::hexa(0x0000003D) },
        overlay: Shadow { y: 4.0, blur: 12.0, spread: -2.0, color: Rgba8::hexa(0x00000052) },
        modal:   Shadow { y: 8.0, blur: 28.0, spread: -4.0, color: Rgba8::hexa(0x00000066) },
    },
    ..LIGHT
};

/// The two high-contrast themes collapse **every** elevation to `flat` (§4).
/// A shadow carries no information when the palette is two colours, so the
/// border stroke does the work instead. `motion` is unchanged here — reduced
/// motion is a separate system setting (REQ-DSN-08) and conflating the two
/// would make high contrast silently disable animation for users who did not
/// ask for that.
pub const HIGH_CONTRAST_LIGHT: Tokens = Tokens {
    id: ThemeId::HighContrastLight, palette: HIGH_CONTRAST_LIGHT_PALETTE,
    elevation: Elevation::FLAT_ALL, state: HIGH_CONTRAST_STATES, ..LIGHT
};
pub const HIGH_CONTRAST_DARK: Tokens = Tokens {
    id: ThemeId::HighContrastDark, palette: HIGH_CONTRAST_DARK_PALETTE,
    elevation: Elevation::FLAT_ALL, state: HIGH_CONTRAST_STATES, ..LIGHT
};
```

## 4. High contrast replaces the palette (REQ-DSN-08)

Separate `const Palette` values. Nothing is tinted, no alpha is blended, and
every elevation collapses to `flat` plus a 1pt `border` stroke: a shadow carries
no information here, so it becomes a boundary.

```rust
const HIGH_CONTRAST_DARK_PALETTE: Palette = Palette {
    surface:     Rgba8::hex(0x000000), surface_raised: Rgba8::hex(0x000000),  // equal; §5 asserts the border
    text_primary:Rgba8::hex(0xFFFFFF), text_muted:     Rgba8::hex(0xFFFFFF),  // equal; muting is a lie here
    accent:      Rgba8::hex(0xFFFF00), accent_text:    Rgba8::hex(0x000000),
    danger:      Rgba8::hex(0xFF8080), warning:        Rgba8::hex(0xFFD75F),
    success:     Rgba8::hex(0x4CFF9E), border:         Rgba8::hex(0xFFFFFF),
    focus_ring:  Rgba8::hex(0xFFFFFF),
};
const HIGH_CONTRAST_LIGHT_PALETTE: Palette = Palette {
    surface:     Rgba8::hex(0xFFFFFF), surface_raised: Rgba8::hex(0xFFFFFF),  // equal; §5 asserts the border
    text_primary:Rgba8::hex(0x000000), text_muted:     Rgba8::hex(0x000000),  // equal; muting is a lie here
    accent:      Rgba8::hex(0x0000C0), accent_text:    Rgba8::hex(0xFFFFFF),
    danger:      Rgba8::hex(0xA30000), warning:        Rgba8::hex(0x5C3A00),
    success:     Rgba8::hex(0x004B1C), border:         Rgba8::hex(0x000000),
    focus_ring:  Rgba8::hex(0x000000),
};
```

`text_muted == text_primary` is the point of REQ-DSN-07: where colour cannot
differentiate, weight, icon and label must already be doing it. A view that is
ambiguous in high contrast was relying on `text_muted` alone. These constants
are the **fallback** — the live scheme is the user's own, read through B01's FFI
wrapper (§6) — and they exist so the §5 test has something compiled to assert
over when no Windows session is present, which is every CI run.

## 5. The tests this contract owes (REQ-DSN-06, REQ-DSN-10, REQ-TST-05)

WCAG 2.2 relative luminance, per channel, over the 8-bit sRGB value:

```
c' = c / 255
lin(c') = c' / 12.92                      if c' <= 0.04045
lin(c') = ((c' + 0.055) / 1.055) ^ 2.4    otherwise
L = 0.2126*lin(r) + 0.7152*lin(g) + 0.0722*lin(b)
ratio(a, b) = (max(La, Lb) + 0.05) / (min(La, Lb) + 0.05)
```

Tokens are opaque, so there is no compositing step. The test iterates a
**declared pair table**, not a cross product: a cross product asserts pairs
nobody draws and then fails on them.

```rust
// crates/design/src/contrast.rs
pub enum Tier { Text, NonText, Adjacent }          // 4.5, 3.0, 3.0

/// Every pair any view may draw. Adding a role adds its pairs here (§8).
pub const PAIRS: &[(fn(&Palette) -> Rgba8, fn(&Palette) -> Rgba8, Tier)] = &[ /* … */ ];

#[test]
fn every_pair_meets_aa_in_every_theme() {
    for t in [LIGHT, DARK, HIGH_CONTRAST_LIGHT, HIGH_CONTRAST_DARK] {
        for (fg, bg, tier) in PAIRS {
            let r = ratio(fg(&t.palette), bg(&t.palette));
            assert!(r >= tier.min(), "{:?}: {r:.2} < {:.1}", t.id, tier.min());
        }
    }
}
```

The 18 pairs per theme: `text_primary`, `text_muted`, `accent`, `danger`,
`warning` and `success` each on `surface` and on `surface_raised` at `Text`;
`accent_text` on `accent` at `Text`; `border` and `focus_ring` each on both
surfaces at `NonText`; `surface` on `accent` at `Adjacent`.

`focus_ring` on `accent` is deliberately **not** a pair. A single ring on a
filled accent button cannot reach 3:1 in any of the four themes — 1.73 in
`LIGHT`, 1.07 in `HIGH_CONTRAST_DARK`. So the ring is 2pt `focus_ring` outside a
1pt `surface` gap, and the `Adjacent` pair asserts the gap: 6.02:1 against the
`LIGHT` accent fill, 19.56:1 in `HIGH_CONTRAST_DARK`. One of the two edges
always clears 3:1 against what is behind it. `border` on `accent` is 1.93 in
`LIGHT` and is not a pair either — a filled control's boundary is its fill.

Lowest ratio per tier at `TOKENS_VERSION = 1`: `Text` 5.97 (`LIGHT.text_muted`
on `surface`), `NonText` 3.06 (`DARK.border` on `surface_raised`), `Adjacent`
6.02. The `NonText` margin is thin on purpose — a border nudged one step lighter
fails the test.

The state set gets a test too, because REQ-DSN-10's failure mode is silence: an
unstyled state compiles, renders, and looks approximately right until someone
tries to use it.

```rust
#[test]
fn every_state_is_reachable_and_distinguishable() {
    for t in [LIGHT, DARK, HIGH_CONTRAST_LIGHT, HIGH_CONTRAST_DARK] {
        let s = &t.state;
        // busy is non-interactive and still focusable (REQ-UI-05). This is the
        // pair most likely to be "simplified" into one flag.
        assert!(!s.busy.interactive && s.busy.focusable, "{:?}", t.id);
        // a control the user cannot use must say why (REQ-DSN-07)
        assert!(s.disabled.tooltip_required, "{:?}", t.id);
        // the ring is two-tone or it is not a ring (§5)
        assert!(s.focus_visible.ring_pt > 0.0 && s.focus_visible.ring_gap_pt > 0.0, "{:?}", t.id);
        // no state may be a no-op against rest: it would be an undesigned state
        for (name, st) in [("hover", &s.hover), ("active", &s.active),
                           ("disabled", &s.disabled), ("busy", &s.busy), ("error", &s.error)] {
            assert!(differs_from_rest(st, s), "{:?}: {name} renders identically to rest", t.id);
        }
        // high contrast carries state by weight, never by alpha (§4)
        if matches!(t.id, ThemeId::HighContrastLight | ThemeId::HighContrastDark) {
            for st in [&s.rest, &s.hover, &s.focus_visible, &s.active, &s.disabled, &s.busy, &s.error] {
                assert!(st.layer_alpha == 0.0 && st.opacity == 1.0, "{:?}: tinted state", t.id);
            }
        }
    }
}
```

The `differs_from_rest` assertion is the one that earns its keep. Every other
check here fails loudly the moment someone writes the wrong value; that one fails
when someone writes **no** value, which is how `busy` became a dimmed button and
`disabled` became the framework default in every desktop app that has the bug.

## 6. Resolving a theme at runtime

```rust
pub fn resolve(appearance: SystemAppearance, override_: Option<ThemeId>) -> Tokens;
```

`SystemAppearance` carries three Windows facts: app light/dark mode, high
contrast on/off with its scheme, and whether client-area animation is enabled.
All three come from B01's `crates/ffi` wrapper — `windows-rs` is called from one
crate only (REQ-FND-03) — so B03 files a CCR, it does not call Win32.
`spec/design-system.md` names the APIs and the one marked `unconfirmed`.

Precedence, highest first: high contrast (a user who turned it on is not
overridden by an app setting), then the app's light/dark override, then the
system preference (REQ-DSN-04).

## 7. The lint: no raw colour outside the token module (REQ-DSN-09)

`crates/design/src/{tokens,color,high_contrast}.rs` are the only files allowed a
colour literal, plus each `mockups/mockup-<n>/src/tokens.rs` — a mockup proposes
a palette, so that is where a literal is legitimate (REQ-MOC-06).

```bash
# ci/lint-no-raw-colour.sh — fails the build, not a warning (REQ-TST-05)
hits=$(grep -rnE 'Color32::from_rgb|from_rgba_(un)?multiplied|Rgba8::hexa?\(|0x[0-9A-Fa-f]{6}\b' \
         crates mockups --include='*.rs' \
       | grep -vE '^crates/design/src/(tokens|color|high_contrast)\.rs:' \
       | grep -vE '^mockups/mockup-[0-9]+/src/tokens\.rs:')
[ -z "$hits" ] || { printf '%s\n' "$hits"; echo "REQ-DSN-09: raw colour outside the token module"; exit 1; }
```

Two defeats get past that grep and both have passed a review somewhere: a colour
read from a config string, and a framework constant such as `Color32::RED`. So
the config schema carries no colour field (B02 refuses one) and
`crates/design/clippy.toml` bans named-colour constants via `disallowed_methods`.
Three rules for one requirement, because one rule has three holes.

## 8. Additive vs breaking

| Change | Kind | What it costs |
|--------|------|---------------|
| A new colour role, spacing step or `TypeStyle` field | **additive** | A CCR B02 assembles without pausing Wave 3. Its pairs go into `PAIRS` in the same change. |
| A new `ThemeId` variant | **breaking** | Every `match` on `ThemeId`, deliberately: no arm has a `_ =>`, so a theme nobody styled cannot fall through to a default. |
| A role's **value** changed | **breaking** | Every screenshot baseline (B15) and every `PAIRS` assertion. Bump `TOKENS_VERSION`, re-run the contrast test, re-take both themes at every DPI step (REQ-TST-08). |
| A role's **meaning** changed, name kept | **breaking, worst case** | Nothing fails to compile and no test fails. Every call site is now wrong in a way only a human looking at the screen can see. Add a role, migrate the call sites, delete the old role in a separate change. |
| A `Motion` duration changed | additive | Nothing asserts it, but `reduced()` must still return zeros. |
| A new `StateStyle` field | **additive** | A CCR B02 assembles. It must be given a resting value on `StateStyle::REST`, or the six states that inherit from it change meaning silently. |
| A new `State` or `BorderRole` variant | **breaking** | Every renderer's `match`. A state nobody styled must not fall through to `rest`, which is precisely how an unstyled `busy` becomes a button that ignores clicks and looks fine. |

`TOKENS_VERSION` is compiled into the binary and shown in the diagnostics view
(B12, REQ-OBS-03), so a screenshot in a support bundle can be matched to the
token set that produced it.
