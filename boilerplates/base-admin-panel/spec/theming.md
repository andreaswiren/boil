# Theming

The shipped look is one shadcn preset, applied once and never hand-transcribed;
on top of it, an in-app theme editor at full parity with the shadcn theme
generator. Owned by **A06** (`ui-theming`): `packages/theme/**` and
`apps/<app>/components.json`. A06 publishes `theme-tokens` and the
`ThemeSelection` type; it consumes `entity-base` and A05's `user_preferences`
contract — the row lives in A05's table, the fields are A06's. A06 owns no
component: every other agent consumes tokens, and no agent writes a colour.

## Requirements covered

REQ-UI-04 (primary), REQ-UI-05, REQ-UI-06, REQ-UI-01, REQ-UI-02, REQ-UI-11,
REQ-SUP-07, REQ-FND-07, REQ-I18N-02, REQ-TST-03, REQ-TST-06.

## 1. The preset, decoded (REQ-UI-04)

Preset `b2CjxkL2O` is the shipped theme. Decoded, it is:

| Knob | Value |
|---|---|
| `style` | `mira` |
| `baseColor` | `mist` |
| `theme` | `emerald` |
| `chartColor` | `emerald` |
| `iconLibrary` | `lucide` |
| `font` | `montserrat` |
| `fontHeading` | `inherit` |
| `radius` | `small` |
| `menuAccent` | `bold` |
| `menuColor` | `default` |
| `base` | `radix` |

```bash
# Initialise the app. --base is MANDATORY.
npx shadcn@latest init --preset b2CjxkL2O --base radix

# The only way to read a preset code. Never decode one by hand.
npx shadcn@latest preset decode b2CjxkL2O
```

Two rules, both of which have cost people a rebuild:

1. **`--base radix` is mandatory.** A preset code does not encode the base. Omit
   `--base` and the CLI applies its own default base under an otherwise correct
   preset, so every token resolves to a near-but-wrong value and the drift shows
   up as "the greens look off" three waves later. REQ-UI-04 names the base
   explicitly for this reason.
2. **Preset codes are decoded with the CLI, never by hand.** The code is an
   encoding, not a mnemonic. The table above is the output of
   `preset decode b2CjxkL2O`, recorded here so an agent does not re-run it to
   read a value — and `pnpm test:theme` re-runs it in CI to prove the table is
   still what the code means.

`apps/<app>/components.json` is the CLI's anchor and carries the same values.
A06 owns that file; nobody else edits it, and no agent runs `init` a second time.

## 2. Generator parity: every knob is editable, previewable, persistable

REQ-UI-05 is parity with the generator, not a palette switcher. The generator
exposes eleven knobs and all eleven are live in-app, at
`/(app)/settings/appearance`, contributed to A05's settings shell through the
registry (`spec/baseline.md`).

| Knob | Values | Editable | Previewable | Persisted to |
|---|---|---|---|---|
| `style` | `mira`, and the other CLI-listed styles | yes | yes | `user_preferences.theme` |
| `baseColor` | the CLI's neutral ramps, incl. `mist` | yes | yes | same |
| `theme` | the CLI's accent themes, incl. `emerald` | yes | yes | same |
| `chartColor` | accent set for charts | yes | yes | same |
| `iconLibrary` | `lucide` (shipped), others the CLI lists | yes | yes | same |
| `font` | self-hosted set, `montserrat` shipped | yes | yes | same |
| `fontHeading` | `inherit`, or any self-hosted font | yes | yes | same |
| `radius` | `none`, `small`, `medium`, `large` | yes | yes | same |
| `menuAccent` | `default`, `subtle`, `bold` | yes | yes | same |
| `menuColor` | `default`, `tinted`, `contrast` | yes | yes | same |
| `mode` | `light`, `dark`, `system` | yes | yes | `user_preferences.theme_mode` + cookie (§4) |

- **Editable** — a control per knob, labelled from `i18n:theme` (REQ-I18N-02).
- **Previewable** — the editor writes the candidate values to the custom
  properties on a preview container, so the sample surfaces (a card, a button
  row, a table header, a chart, the sidebar) re-render live with no request and
  no page reload. `Apply` persists; `Discard` drops the candidate.
- **Persistable** — `ThemeSelection` is one jsonb object in `user_preferences`,
  with a tenant-level default and a system default beneath it. Resolution is
  user → tenant → system, matching the locale and timezone chains
  (REQ-I18N-04, REQ-TIM-03).

A generated preset is written as a CSS file, not interpolated at runtime:
`packages/theme/scripts/generate-presets.ts` renders
`packages/theme/presets/<name>.css` from a `ThemeSelection`, one selector per
preset. Applying a theme is swapping a class on `<html>`. That is what makes §4
possible — a runtime style object cannot be applied before first paint.

## 3. The token layer

Two levels, and components only ever see the second.

```css
/* packages/theme/presets/b2CjxkL2O.css — level 1: raw values, one selector */
[data-preset="b2CjxkL2O"] {
  --background: oklch(0.99 0.002 240);
  --foreground: oklch(0.21 0.01 250);
  --primary: oklch(0.62 0.13 162);        /* emerald */
  --primary-foreground: oklch(0.98 0.01 162);
  --muted-foreground: oklch(0.55 0.01 250);
  --radius: 0.375rem;                     /* radius: small */
  --chart-1: oklch(0.62 0.13 162);
  /* … the full shadcn token set, light values … */
}
[data-preset="b2CjxkL2O"].dark { /* … the dark values … */ }
```

```css
/* packages/theme/theme.css — level 2: Tailwind v4 sees the tokens */
@import "tailwindcss";
@custom-variant dark (&:where(.dark, .dark *));

@theme inline {
  --color-background: var(--background);
  --color-foreground: var(--foreground);
  --color-primary: var(--primary);
  --color-primary-foreground: var(--primary-foreground);
  --color-muted-foreground: var(--muted-foreground);
  --radius-md: var(--radius);
  --font-sans: var(--font-montserrat), ui-sans-serif, system-ui, sans-serif;
}
```

`@theme inline` is what makes `bg-primary` compile to
`var(--color-primary)` → `var(--primary)` rather than baking a literal into the
stylesheet. Without `inline`, changing a custom property at runtime changes
nothing, and the entire live-preview mechanism in §2 stops working.

**The rule every agent follows:** components use semantic tokens —
`bg-background`, `text-foreground`, `bg-primary`, `text-muted-foreground`,
`border-border`, `bg-card`, `text-destructive`, `bg-chart-1` — and never a raw
colour value, never a Tailwind palette class (`bg-emerald-500`, `text-gray-400`),
and never a manual `dark:` colour override. A `dark:` variant on a colour means
the token is wrong: the dark value belongs in the preset, where it is one edit
for the whole app instead of one per component. `dark:` remains legal for
non-colour concerns such as a shadow or an opacity.

Enforced by `pnpm lint:tokens` (A01 configures, A06 supplies the deny list):
any hex, `rgb(`, `hsl(`, `oklch(` literal outside `packages/theme/`, any
Tailwind colour-scale utility, and any `dark:` on a colour utility fails CI.
Charts read `--chart-1 … --chart-5`, so a chart re-themes with the app
(REQ-DOC-07).

## 4. Dark, light, system — and no flash of the wrong theme (REQ-UI-06)

The flash happens when the server renders one theme and a client script corrects
it after hydration. The fix is to make the server already know.

1. The resolved mode is written to a **cookie** — `theme_mode`, values
   `light` | `dark` | `system`, `SameSite=Lax`, `Path=/`, one year, **not**
   `HttpOnly` so the client can update it without a round trip. Not
   `localStorage`: the server cannot read `localStorage`, which is precisely why
   `localStorage`-based theming flashes.
2. The root layout (A05) reads the cookie server-side and renders
   `<html class="dark" data-theme="dark" data-preset="…" style="color-scheme: dark">`.
   For `light` or `dark` there is **no client script at all** — the first byte is
   already correct.
3. For `system`, the server cannot know the OS preference, so it renders
   `data-theme="system"` plus one blocking inline script in `<head>`, before any
   stylesheet, carrying the CSP nonce (REQ-SEC-08):

```html
<script nonce="{nonce}">
  if (document.documentElement.dataset.theme === "system" &&
      matchMedia("(prefers-color-scheme: dark)").matches) {
    document.documentElement.classList.add("dark");
    document.documentElement.style.colorScheme = "dark";
  }
</script>
```

4. A mode change is a Server Action that sets the cookie and toggles the class
   in the same tick, so the next navigation and the next SSR agree with what the
   user is looking at.
5. `color-scheme` is set on `<html>` so form controls, scrollbars and the
   browser's own canvas match before any CSS loads. `<meta name="theme-color">`
   is emitted per mode for the installed PWA's chrome (REQ-PWA-01).
6. A `prefers-color-scheme` change with mode `system` is applied live through a
   `matchMedia` listener — no reload, no request.

The preset class is on `<html>` for the same reason, so the *preset* cannot
flash either. `pnpm test:visual` asserts it: a first-paint screenshot at
`networkidle: false` in both modes, compared against the settled screenshot. A
difference is a flash, and it fails.

## 5. Fonts are self-hosted (REQ-SUP-07)

Montserrat ships in the repository. No `fonts.googleapis.com`, no
`fonts.gstatic.com`, no CDN, at build time or at runtime.

```ts
// packages/theme/fonts.ts
import localFont from "next/font/local";
export const montserrat = localFont({
  src: [{ path: "./fonts/Montserrat-Variable.woff2", style: "normal" }],
  variable: "--font-montserrat",
  display: "swap",
  fallback: ["ui-sans-serif", "system-ui", "sans-serif"],
});
```

- The variable woff2 is subset to `latin` + `latin-ext`, which covers `en` and
  `sv` including `å ä ö` (REQ-I18N-06). A locale needing more glyphs ships
  another subset file; it is a data change, not a code change.
- `next/font/local` emits `size-adjust` fallback metrics, so the swap does not
  shift layout.
- Every additional font offered by the `font`/`fontHeading` knobs is vendored
  the same way. A font the repository does not contain is not offered — the
  knob's option list is generated from the files present, so an unreachable
  remote font cannot be selected.
- `pnpm test:egress` fails the build on any font or asset request to a remote
  origin during an e2e run, and the CSP sets `font-src 'self'` (REQ-SEC-08,
  REQ-SUP-08).

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Preset | `b2CjxkL2O`, base `radix` | REQ-UI-04 | No |
| Init command | `npx shadcn@latest init --preset b2CjxkL2O --base radix` | A preset code does not encode the base | No |
| Decoding a preset code | `npx shadcn@latest preset decode`, asserted in CI | Hand-decoding produces a near-miss theme | No |
| Generator parity scope | All eleven knobs, editable + previewable + persistable | REQ-UI-05 | No |
| Preset representation | A generated CSS file per preset, one class on `<html>` | A runtime style object cannot beat first paint | No |
| Token indirection | Tailwind v4 `@theme inline` over CSS custom properties | Without `inline`, live preview is impossible | No |
| Component colour source | Semantic tokens only; no literals, no palette classes, no `dark:` colours | One edit re-themes the app | No |
| Mode storage | Cookie, server-read, plus `user_preferences` | `localStorage` is why themes flash | No |
| Mode default | `system` | Follows the OS until the user decides | Yes |
| `system` resolution | One nonce'd inline script, `<head>`, pre-stylesheet | The server cannot know the OS preference | No |
| Theme resolution order | user → tenant → system | Matches locale and timezone chains | No |
| Fonts | Self-hosted Montserrat variable, latin + latin-ext | REQ-SUP-07 | Yes, per intake font choice |
| Icon library | `lucide`, by name from the nav registry | REQ-UI-04; keeps the registry serialisable | Yes |

## How this is verified

- `pnpm test:theme` — `tests/unit/theme/**`: `npx shadcn@latest preset decode
  b2CjxkL2O` output matches §1 field for field, and matches
  `apps/<app>/components.json`; `generate-presets.ts` is deterministic — the
  same `ThemeSelection` renders a byte-identical CSS file.
- `pnpm lint:tokens` — no colour literal outside `packages/theme/`, no Tailwind
  colour-scale utility, no `dark:` on a colour utility, anywhere in
  `apps/**` or `packages/**`.
- `pnpm test:visual` — `tests/visual/theme.spec.ts` (REQ-TST-03): first-paint
  versus settled screenshots in `light`, `dark` and `system` (with the emulated
  OS preference both ways) prove no flash; all eleven knobs applied in
  combination screenshot the sample surfaces at 390/834/1440; axe AA contrast in
  both themes (REQ-TST-06, REQ-UI-11).
- `pnpm test:integration` — `tests/integration/theme/**`: the preference
  round-trip per user, the tenant default fallback, and the cookie surviving a
  session rotation (`spec/auth.md` §8).
- `pnpm test:egress` — no remote font or asset origin during an e2e run;
  `font-src 'self'` present on every response (REQ-SUP-07, REQ-SUP-08).
- `GET /api/v1/theme/_selftest` — the preset file exists, every token in the
  contract's token list resolves to a non-empty computed value in both modes,
  and every offered font has a file on disk (REQ-CTR-08).

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| Preset | `b2CjxkL2O` with base `radix` — fixed by REQ-UI-04 |
| Default mode | `system` |
| May tenants set a tenant-wide default theme | Yes; a user preference still wins |
| May users change the preset, or only the mode | The full eleven knobs (REQ-UI-05) |
| Extra fonts vendored beyond Montserrat | None — Montserrat plus the system stack |
| Tenant logo / brand mark in the shell | None; a slot exists in A05's shell |
