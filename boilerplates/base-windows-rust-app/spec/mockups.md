# Mockups

Owned by **B04 `mockup-builder`** (Wave 1). B04 writes `mockups/**` and nothing
else. It runs after B03 has published `design-tokens` and before every Wave 3
agent, because gate H1 blocks the build until a human names a winning direction
(REQ-MOC-01, REQ-GAT-08).

## Requirements covered

REQ-MOC-01 through REQ-MOC-08. Consumes REQ-DSN-02, REQ-DSN-03, REQ-DSN-06,
REQ-DSN-10. Feeds REQ-TST-04, REQ-DSN-01.

## A mockup is a compiled program (REQ-MOC-02)

`cargo build -p mockup-2` either works or it does not. That sentence is the
entire method.

A mockup is a small Rust binary, one screen, built against a token module in the
chosen framework. Running it proves three things a picture cannot: that the
framework can express the design, that the palette passes the contrast test as
compiled constants, and that both themes render from the same code path.

**What it is** (REQ-MOC-03): one screen. A token swatch strip, a heading
hierarchy sample, and enough controls to render all seven states of REQ-DSN-10 —
at minimum a button, a text field, a checkbox, a list row and a menu item, each
in rest, hover, focus-visible, active, disabled, busy and error. A light/dark
toggle. Roughly 300 lines of `src/main.rs`.

**What it is not**: a prototype. No navigation, no second screen, no real data,
no app logic, no tray, no settings. A mockup that grows a second screen is a
product prototype competing with Wave 3 for the same decisions, and it will be
thrown away with the four-fifths of mockups that do not win.

## Why images are refused

An image proves that an image can look like that.

The failure this wave exists to prevent is specific: a design whose styling the
framework cannot express, discovered after every view has been built against it.
A picture cannot fail that way, so a picture cannot detect it. A 6pt shadow with
a negative spread, a 1pt hairline that stays 1pt at 250%, a two-tone focus ring
on a filled button, a variable font at weight 600 — each of these is trivial in
an image editor and each is a real question in `egui`. The compiler answers all
four.

If the orchestrator finds itself accepting a PNG, it has accepted a claim in
place of a proof. Reject it (`prompts/00-master-orchestrator.md`).

## Workspace layout (REQ-MOC-04)

```
mockups/
├── mockup-1/
│   ├── Cargo.toml          # [package] name = "mockup-1"
│   ├── README.md           # direction, tradeoff, what to look at
│   └── src/
│       ├── main.rs         # the header of REQ-MOC-07, then one screen
│       └── tokens.rs       # this direction's proposed token set
├── mockup-2/  …
├── mockup-3/  …
└── mockup-4/  …
```

Each directory is its own crate and a member of the workspace `Cargo.toml` (B01
owns that file; B04 declares the members through a CCR). One crate per mockup is
what makes `cargo build -p mockup-<n>` the gate rather than a convention: a
mockup that does not build cannot be presented, and a mockup that builds only on
the author's machine fails the same command in CI.

Each mockup carries its **own** `src/tokens.rs`. A mockup proposes a palette and
a scale — that is what a direction is — so a colour literal is legitimate there
and only there (`contracts/types/design-tokens.md` §7). Each one imports
`crates/design`'s `Rgba8`, `Tokens` structs and contrast test, so the pair table
runs against the proposed palette before the screenshots are taken.

## The four directions (REQ-MOC-06)

Four, differentiated by density, typographic scale, chrome weight and accent
strategy. Not by hue: all four may ship the same `accent` value and still be
four different designs.

### 1. `mockup-1` — Console

**Thesis:** a tray utility is glanced at, not read. Maximise rows per window.

12pt body on a 16pt line, 2pt/4pt/8pt spacing, no card and no elevation above
`raised`, a single 1pt `border` between rows. `accent` appears only in the focus
ring and the selection bar — never as a fill, so the screen is monochrome until
you interact with it. `display` is 20pt, so the hierarchy is nearly flat.

**Tradeoff:** gives up approachability and headroom. 12pt at 100% on a
high-density laptop panel is at the edge of comfortable, and the flat hierarchy
means a settings page with eight sections has nothing to structure it with. If
this product grows a second and third view, this direction fights it.

### 2. `mockup-2` — Workbench

**Thesis:** an administrator trusts a tool whose structure is drawn rather than
implied.

14pt body on a 20pt line, 8pt/12pt/16pt spacing, cards at `surface_raised` with
a 1pt `border` and the `raised` shadow, section headings at 16pt/600. `accent`
fills exactly one control per screen — the primary action — and appears nowhere
else. `display` 28pt gives four clear levels.

**Tradeoff:** chrome costs vertical space; a list shows about 70% of Console's
rows. Every border and every card is something that must still read when high
contrast collapses elevation to a stroke, which is more surface to verify
(REQ-DSN-08).

### 3. `mockup-3` — Quiet

**Thesis:** a background utility should be legible from two feet away and calm
enough to leave open.

16pt body on a 24pt line, 16pt/24pt/32pt spacing, **no borders at all** —
separation is whitespace and a `surface`/`surface_raised` step. One accent per
screen, used on text rather than as a fill. `display` 28pt, `caption` 14pt: a
short, tall scale with no small type anywhere.

**Tradeoff:** gives up density hard — roughly half of Console's rows — and it is
the direction most at risk in high contrast, where the `surface`/`surface_raised`
step is gone and whitespace-only separation has nothing left to carry it. A
log-tail or a file list is the wrong content for this direction, and this app may
well have one.

### 4. `mockup-4` — Shell-native

**Thesis:** the app should be hard to tell apart from a first-party Windows
utility.

14pt body, 4pt radii on inputs and 8pt on containers, layered surfaces
approximating a Mica backdrop, and `accent` **derived from the user's Windows
accent colour** rather than chosen by us — read through B01's FFI wrapper
(REQ-FND-03), with `accent_text` computed at runtime as whichever of
`text_primary` or `surface` clears 4.5:1 against it.

**Tradeoff:** the largest and the most interesting. A runtime accent cannot be
asserted at compile time, so the contrast test covers the *derivation* rather
than the value, and a user with a pale yellow system accent gets a different
`accent_text` than the screenshots show. `egui` also cannot render Mica, so the
layering is an approximation that looks subtly wrong beside a real WinUI window —
the direction most likely to land in the uncanny valley it was chosen to avoid.

## The source header (REQ-MOC-07)

Every `src/main.rs` opens with this block. A direction with no stated tradeoff
has not been thought through, and the header is where the thinking is checked.

```rust
//! mockup-2 — "Workbench"
//!
//! DIRECTION: Medium density, four-level type scale (28/20/16/14), visible
//! chrome (1pt border + `raised` shadow on cards), accent on exactly one
//! control per screen.
//!
//! TESTING: whether drawn structure makes an eight-section settings surface
//! readable without a second navigation level.
//!
//! TRADEOFF: ~30% fewer list rows than mockup-1. Every card border is surface
//! that must still read when high contrast collapses elevation to a stroke
//! (REQ-DSN-08).
//!
//! TOKENS: src/tokens.rs. Contrast asserted over all four themes by
//! `cargo test -p mockup-2` (REQ-DSN-06).
//! STATES: button, text field, checkbox, list row, menu item — all seven
//! states of REQ-DSN-10 rendered on this screen.
```

## What H1 checks before the screenshots are shown

The orchestrator verifies all of this first. A failing item is not a caveat in
the reply; it is a mockup that is not ready to be looked at.

- [ ] `cargo build --workspace --locked` succeeds from a clean checkout, and
      `cargo build -p mockup-<n>` succeeds for every `n` (REQ-MOC-04).
- [ ] Each mockup **runs** and does not panic on the light/dark toggle
      (REQ-MOC-02).
- [ ] `cargo test -p mockup-<n>` passes the contrast pair table over all four
      themes (REQ-DSN-06). A mockup that fails contrast is not a design
      direction, it is a proposal to ship an inaccessible product.
- [ ] Between three and five mockups, differing in density, typographic scale,
      chrome weight and accent strategy — not in hue (REQ-MOC-06).
- [ ] Every `src/main.rs` carries the header above, with a tradeoff that names
      something given up (REQ-MOC-07).
- [ ] All seven states of REQ-DSN-10 are visible on each screen.
- [ ] A light and a dark screenshot per mockup from B15 (REQ-MOC-05,
      REQ-TST-04).
- [ ] The cost table for the wave (REQ-COST-02).

Then the screenshots go in the chat reply with the four theses and the four
tradeoffs, and the question is which direction wins. **Then the build stops.**

## After the human names a winner (REQ-MOC-08)

1. The orchestrator records the direction, the person who named it and the date
   in `build/approvals.md`.
2. B03 derives `crates/design/src/tokens.rs` from the winner's `src/tokens.rs`:
   the palette, the scale, the spacing and the chrome weight, re-expressed in the
   published token shape (`contracts/types/design-tokens.md`) with
   `TOKENS_VERSION = 1`.
3. **Every mockup stays in-tree.** The winner is the reference the design is
   checked against; the others are the record of what was rejected and why, which
   is what stops the same direction being re-proposed in three months.
4. The winner keeps building. `cargo build -p mockup-<n>` stays in CI, so a
   later token change that the framework cannot express fails on the reference
   before it fails on a view.
5. B15 re-screenshots the winner at 100/150/200/250% for the DPI baseline
   (REQ-TST-08).

A mockup is deleted only when the design system is retired, and that is a B17
change with a changelog entry.
