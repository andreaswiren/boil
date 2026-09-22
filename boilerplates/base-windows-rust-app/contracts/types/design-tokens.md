# `design-tokens` — the compiled design system

**Published by:** B03 (`design-system`), from `crates/design/src/tokens.rs`.
**Requirements:** REQ-DSN-02, REQ-DSN-03, REQ-DSN-06, REQ-DSN-08, REQ-DSN-09,
REQ-DSN-10, REQ-DSN-11, REQ-TST-05, REQ-UI-01.
**Consumed by:** B04, B05, B06, B12, B14, B15.

Tokens are `const` Rust values. A view reads `Tokens`; it never names a colour.
The compiler is what stops a view inventing a twelfth colour role (REQ-DSN-02,
REQ-DSN-09). Rationale is `spec/design-system.md`; this is the frozen shape.

---

## 1. `Rgba8`

`crates/design` does not depend on a UI framework. The conversion is
feature-gated, so an intake that picks `iced` or `slint` over `eframe`
(`versions/manifest.json`, REQ-UI-01) replaces one `impl`, not the palette.

```rust
// crates/design/src/color.rs
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Rgba8 { pub r: u8, pub g: u8, pub b: u8, pub a: u8 }

impl Rgba8 {
    /// 0xRRGGBB, opaque. The only way a colour enters the token module.
    pub const fn hex(v: u32) -> Self {
        Self { r: (v >> 16) as u8, g: (v >> 8) as u8, b: v as u8, a: 0xFF }
    }
    /// 0xRRGGBBAA. Shadow and scrim only — never a contrast participant.
    pub const fn hexa(v: u32) -> Self {
        Self { r: (v >> 24) as u8, g: (v >> 16) as u8, b: (v >> 8) as u8, a: v as u8 }
    }
}

#[cfg(feature = "egui")]
impl From<Rgba8> for egui::Color32 {
    fn from(c: Rgba8) -> Self { egui::Color32::from_rgba_unmultiplied(c.r, c.g, c.b, c.a) }
}
```

There is no `Rgba8::new`. Three decimal `u8` arguments is how a raw colour gets
past the §7 lint, so the constructor does not exist.

## 2. The token struct

Every scalar is in **logical points** at 96 DPI. Nothing here is pre-multiplied
by a scale factor; scaling is applied once at the renderer, from the DPI of the
monitor the window is currently on (REQ-DSN-11).

```rust
// crates/design/src/tokens.rs
pub const TOKENS_VERSION: u32 = 1;      // bumped by §8

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ThemeId { Light, Dark, HighContrastLight, HighContrastDark }

/// Colour **roles**, not colour names. `accent` can become green at a rebrand;
/// `blue_600` would have to be renamed at every call site (REQ-DSN-09).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Palette {
    pub surface: Rgba8,          // window background
    pub surface_raised: Rgba8,   // card, popup, hovered list row
    pub text_primary: Rgba8,     // body text and meaningful icon glyphs
    pub text_muted: Rgba8,       // secondary text; never the only signal (REQ-DSN-07)
    pub accent: Rgba8,           // primary action fill, selection, link text
    pub accent_text: Rgba8,      // text and glyphs drawn ON `accent`
    pub danger: Rgba8,           // error text/glyph ON a surface, not a fill
    pub warning: Rgba8,
    pub success: Rgba8,
    pub border: Rgba8,           // control boundary; 3:1 on both surfaces
    pub focus_ring: Rgba8,       // outer stroke of the two-tone ring (§5)
}

#[derive(Clone, Copy, Debug)]
pub struct Spacing { pub xxs: f32, pub xs: f32, pub sm: f32, pub md: f32, pub lg: f32, pub xl: f32, pub xxl: f32 }
#[derive(Clone, Copy, Debug)]
pub struct Radii { pub sm: f32, pub md: f32, pub lg: f32, pub pill: f32 }
#[derive(Clone, Copy, Debug)]
pub struct TypeStyle { pub size: f32, pub line: f32, pub weight: u16, pub tracking: f32 }
#[derive(Clone, Copy, Debug)]
pub struct TypeScale {
    pub family: &'static str, pub mono_family: &'static str,
    pub display: TypeStyle, pub title: TypeStyle, pub heading: TypeStyle,
    pub body: TypeStyle, pub body_strong: TypeStyle, pub caption: TypeStyle, pub mono: TypeStyle,
}
#[derive(Clone, Copy, Debug)]
pub struct Shadow { pub y: f32, pub blur: f32, pub spread: f32, pub color: Rgba8 }
#[derive(Clone, Copy, Debug)]
pub struct Elevation { pub flat: Shadow, pub raised: Shadow, pub overlay: Shadow, pub modal: Shadow }
#[derive(Clone, Copy, Debug)]
pub struct Motion { pub instant: u16, pub fast: u16, pub normal: u16, pub slow: u16, pub ease_out: [f32; 4] }

impl Motion {
    /// REQ-DSN-08. Not "shorter" — zero. A 60 ms fade is still a fade.
    pub const fn reduced() -> Self {
        Self { instant: 0, fast: 0, normal: 0, slow: 0, ease_out: [0.0, 0.0, 1.0, 1.0] }
    }
}

#[derive(Clone, Copy, Debug)]
pub struct Tokens {
    pub id: ThemeId, pub version: u32,
    pub palette: Palette, pub space: Spacing, pub radius: Radii,
    pub text: TypeScale, pub elevation: Elevation, pub motion: Motion,
}
```

## 3. `LIGHT` and `DARK` — two designed themes (REQ-DSN-03)

Neither is derived from the other, and the values say so. `LIGHT.accent_text` is
white on a deep blue fill; `DARK.accent_text` is near-black on a light blue fill
— the accent strategy flips polarity rather than shifting lightness. `DARK`
separates `surface_raised` from `surface` by 1.11:1 where `LIGHT` uses 1.04:1,
because a dark surface needs more separation to read as lifted.

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

pub const LIGHT: Tokens = Tokens {
    id: ThemeId::Light, version: TOKENS_VERSION, palette: LIGHT_PALETTE, text: BASE_TYPE,
    space:  Spacing { xxs: 2.0, xs: 4.0, sm: 8.0, md: 12.0, lg: 16.0, xl: 24.0, xxl: 32.0 },
    radius: Radii { sm: 3.0, md: 6.0, lg: 10.0, pill: 999.0 },
    elevation: Elevation {
        flat:    Shadow { y: 0.0, blur:  0.0, spread:  0.0, color: Rgba8::hexa(0x00000000) },
        raised:  Shadow { y: 1.0, blur:  3.0, spread:  0.0, color: Rgba8::hexa(0x0F141F1F) },
        overlay: Shadow { y: 4.0, blur: 12.0, spread: -2.0, color: Rgba8::hexa(0x0F141F2E) },
        modal:   Shadow { y: 8.0, blur: 28.0, spread: -4.0, color: Rgba8::hexa(0x0F141F3D) },
    },
    motion: Motion { instant: 0, fast: 90, normal: 160, slow: 260, ease_out: [0.16, 1.0, 0.3, 1.0] },
};

/// Same shape, `DARK_PALETTE`, and shadow alpha 0x3D/0x52/0x66 — a shadow on a
/// dark surface is read by its spread, not its darkness.
pub const DARK: Tokens = /* … */;
```

`BASE_TYPE` is shared and overridden by neither theme: a theme change must not
reflow text (REQ-DSN-04).

## 4. High contrast replaces the palette (REQ-DSN-08)

Separate `const Palette` values. Nothing is tinted, no alpha is blended, and
every elevation collapses to `flat` plus a 1pt `border` stroke — a shadow
carries no information in high contrast, so it becomes a boundary.

```rust
const HIGH_CONTRAST_DARK_PALETTE: Palette = Palette {
    surface:     Rgba8::hex(0x000000), surface_raised: Rgba8::hex(0x000000),  // equal; §5 asserts the border
    text_primary:Rgba8::hex(0xFFFFFF), text_muted:     Rgba8::hex(0xFFFFFF),  // equal; muting is a lie here
    accent:      Rgba8::hex(0xFFFF00), accent_text:    Rgba8::hex(0x000000),
    danger:      Rgba8::hex(0xFF8080), warning:        Rgba8::hex(0xFFD75F),
    success:     Rgba8::hex(0x4CFF9E), border:         Rgba8::hex(0xFFFFFF),
    focus_ring:  Rgba8::hex(0xFFFFFF),
};
// HIGH_CONTRAST_LIGHT: surface and raised 0xFFFFFF, text_primary and text_muted
// 0x000000, accent 0x0000C0 with accent_text 0xFFFFFF, danger 0xA30000,
// warning 0x5C3A00, success 0x004B1C, border and focus_ring 0x000000.
```

`text_muted == text_primary` is the point of REQ-DSN-07: where colour cannot
differentiate, weight, icon and label must already be doing it. A view that
reads as ambiguous in high contrast was relying on `text_muted` alone.

These constants are the **fallback**. The live scheme is the user's own, read
through B01's FFI wrapper (§6). The constants exist so the §5 test has something
compiled to assert over when no Windows session is present — every CI run.

## 5. The contrast test contract (REQ-DSN-06, REQ-TST-05)

WCAG 2.2 relative luminance, per channel, over the 8-bit sRGB value:

```
c' = c / 255
lin(c') = c' / 12.92                      if c' <= 0.04045
lin(c') = ((c' + 0.055) / 1.055) ^ 2.4    otherwise
L = 0.2126*lin(r) + 0.7152*lin(g) + 0.0722*lin(b)
ratio(a, b) = (max(La, Lb) + 0.05) / (min(La, Lb) + 0.05)
```

Tokens are opaque, so there is no compositing step. The test iterates a
**declared pair table**, not a cross product — a cross product asserts pairs
nobody draws and then fails on them.

```rust
// crates/design/src/contrast.rs
pub enum Tier { Text, NonText, Adjacent }          // 4.5, 3.0, 3.0

/// Every pair any view is permitted to draw. Adding a role adds its pairs here.
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

The 19 pairs per theme: `text_primary`, `text_muted`, `accent`, `danger`,
`warning` and `success` each on `surface` and on `surface_raised` at `Text`;
`accent_text` on `accent` at `Text`; `border` and `focus_ring` each on both
surfaces at `NonText`; `surface` on `accent` at `Adjacent`.

That last pair is the two-tone focus ring, and it is why `focus_ring` on
`accent` is **not** in the table. A single ring on a filled accent button cannot
reach 3:1 in any of the four themes — the ratio is 1.73 in `LIGHT` and 1.07 in
`HIGH_CONTRAST_DARK`. So the ring is 2pt `focus_ring` outside a 1pt `surface`
gap: the gap scores 6.02:1 against the `LIGHT` accent fill and 19.56:1 in
`HIGH_CONTRAST_DARK`, so one of the two edges always clears 3:1 against what is
behind it. `border` on `accent` is 1.93 in `LIGHT` and is likewise not a pair —
a filled control's boundary is its fill.

At `TOKENS_VERSION = 1` the lowest ratio per tier is `Text` 5.97
(`LIGHT.text_muted` on `surface`), `NonText` 3.06 (`DARK.border` on
`surface_raised`), `Adjacent` 6.02. The `NonText` margin is thin on purpose: a
border nudged one step lighter fails the test.

## 6. Resolving a theme at runtime

```rust
pub fn resolve(appearance: SystemAppearance, override_: Option<ThemeId>) -> Tokens;
```

`SystemAppearance` carries three Windows facts: app light/dark mode, high
contrast on/off with its scheme, and whether client-area animation is enabled.
All three come from B01's `crates/ffi` wrapper — `windows-rs` is called from one
crate only (REQ-FND-03), so B03 files a CCR for the wrapper rather than calling
Win32. `spec/design-system.md` names the APIs and the one marked `unconfirmed`.

Precedence, highest first: high contrast (a user who turned it on is not
overridden by an app setting), then the app's explicit light/dark override, then
the system preference (REQ-DSN-04).

## 7. The lint: no raw colour outside the token module (REQ-DSN-09)

`crates/design/src/{tokens,color,high_contrast}.rs` are the only files allowed a
colour literal. Each `mockups/mockup-<n>/src/tokens.rs` is also allowed one — a
mockup proposes a palette, so that is where a literal is legitimate (REQ-MOC-06).

```bash
# ci/lint-no-raw-colour.sh — fails the build, not a warning (REQ-TST-05)
hits=$(grep -rnE 'Color32::from_rgb|from_rgba_(un)?multiplied|Rgba8::hexa?\(|0x[0-9A-Fa-f]{6}\b' \
         crates mockups --include='*.rs' \
       | grep -vE '^crates/design/src/(tokens|color|high_contrast)\.rs:' \
       | grep -vE '^mockups/mockup-[0-9]+/src/tokens\.rs:')
[ -z "$hits" ] || { printf '%s\n' "$hits"; echo "REQ-DSN-09: raw colour outside the token module"; exit 1; }
```

Two defeats get past that grep, and both have passed a review somewhere: a
colour read from a config string, and a framework constant like `Color32::RED`.
So the config schema has no colour field (B02 refuses one), and
`crates/design/clippy.toml` bans the framework's named-colour constants through
`disallowed_methods`. The grep, the schema and the clippy entry are three rules
for one requirement because one rule has three holes.

## 8. Additive vs breaking

| Change | Kind | What it costs |
|--------|------|---------------|
| A new colour role, spacing step or `TypeStyle` field | **additive** | A CCR B02 assembles without pausing Wave 3. Its pairs go into `PAIRS` in the same change. |
| A new `ThemeId` variant | **breaking** | Every `match` on `ThemeId`, deliberately: no arm has a `_ =>`, so a theme nobody styled cannot fall through to a default. |
| A role's **value** changed | **breaking** | Every screenshot baseline (B15) and every `PAIRS` assertion. Bump `TOKENS_VERSION`, re-run the contrast test, re-take both themes at every DPI step (REQ-TST-08). |
| A role's **meaning** changed, name kept | **breaking, and the worst case** | Nothing fails to compile and no test fails. Every call site is now wrong in a way only a human looking at the screen can see. Do not do it: add a role, migrate the call sites, delete the old role in a separate change. |
| A `Motion` duration changed | additive | Nothing asserts it, but `reduced()` must still return zeros. |

`TOKENS_VERSION` is compiled into the binary and shown in the diagnostics view
(B12, REQ-OBS-03), so a screenshot in a support bundle can be matched to the
token set that produced it.
