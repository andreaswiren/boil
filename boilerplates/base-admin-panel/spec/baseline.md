# Baseline — `arhamkhnz/next-shadcn-admin-dashboard` as Layout Reference

This domain fixes what we copy from the reference implementation named in
REQ-UI-03 and what we deliberately do differently. It is owned by **A05**
(`ui-shell`), because A05 owns the shell, the layout and the nav registry. A06
owns the theme half of the reference (presets, generator parity), A07 owns the
data-table half. The reference is a **layout reference, not a dependency**: we do
not add it to `package.json`, we do not vendor its source, we do not fork it. We
read it, we decide, we write our own files. That decision is recorded here so no
Wave 3 agent re-opens it.

## Requirements covered

REQ-UI-03 (primary), REQ-UI-01, REQ-UI-02, REQ-UI-04, REQ-UI-05, REQ-UI-06,
REQ-FND-01, REQ-GRD-01, REQ-GRD-08, REQ-CTR-04, REQ-SUP-04, REQ-SUP-07.

## What the reference actually is

Inspected facts, recorded so nobody guesses:

| Aspect | Reference implementation |
|--------|--------------------------|
| App root | `src/` at repository root — single app, no workspace |
| Route groups | `src/app/(main)/` and `src/app/(external)/` |
| Navigation | `src/navigation/sidebar/sidebar-items.ts` — one exported array |
| App config | `src/config/app-config.ts` |
| Preferences | `src/stores/preferences/` — Zustand store, client-side |
| Theme presets | `src/styles/presets/*.css` — one CSS file per preset |
| Preset generation | `src/scripts/generate-theme-presets.ts` |
| Data table | `src/lib/data-table-features.ts` — feature flags per table |
| shadcn config | `components.json` with `style: radix-nova`, `baseColor: neutral` |
| Lint / format | Biome |

## What we take

1. **The route-group split.** Authenticated application chrome and
   unauthenticated pages are different route groups with different root layouts.
   We name ours `(app)` and `(auth)` instead of `(main)` and `(external)`,
   because `(auth)` is what `contracts/ownership.md` already assigns to A03 and
   ownership strings are not renamed for cosmetics. The mechanism is identical:
   one shell layout for the signed-in surface (A05), one bare layout for login,
   error and legal pages.
2. **The shape of a sidebar item.** The reference's item shape — `title`,
   `url`, `icon`, `subItems`, section grouping, `comingSoon` flag — is a good
   shape and we keep it, extended with `permission` and `i18nKey`. See the nav
   registry below.
3. **The preference-store pattern.** A typed preferences object read by the
   shell through one hook, not props threaded through layouts. We keep the
   pattern and change where it persists (see deviations).
4. **Theme-preset-as-a-CSS-file.** A preset is a CSS file of custom-property
   assignments under one selector, not a JS object interpolated at runtime.
   Swapping a preset is swapping a class on `<html>`. This is what makes
   REQ-UI-06 (no flash of wrong theme) achievable.
5. **The generated-presets script idea.** Presets are generated from a source of
   truth, not hand-edited. A06 owns `packages/theme/scripts/generate-presets.ts`
   as our equivalent.
6. **The data-table feature-flag idea.** A table declares which features it
   wants rather than every table getting every feature. We generalise it into
   `GridDefinition` (see `spec/datagrid.md`).
7. **`components.json` at the app root** as the shadcn CLI's anchor, and the
   shadcn block workflow — `dashboard-01` for the dashboard (REQ-UI-01),
   `login-02` for login (REQ-UI-02).

## What we deviate from, and why

| Reference | Ours | Why |
|-----------|------|-----|
| `src/` at repository root | `apps/<app>/` + `packages/<name>/` | REQ-FND-01 mandates a monorepo layout even for one app. The reference is a single-app template; we are a boilerplate that generates shared packages. |
| `src/navigation/sidebar/sidebar-items.ts` — one array | `nav-registry`: each domain declares its own entries inside its own package | A shared array is a merge point. Wave 3 is 13 agents wide and `contracts/README.md` §"Registry, never a shared list" makes this a law, not a taste. REQ-CTR-04. |
| `style: radix-nova`, `baseColor: neutral` | preset `b2CjxkL2O`, base `radix` — style `mira`, baseColor `mist`, theme `emerald` | REQ-UI-04 fixes the preset. See `spec/theming.md`. |
| Preferences in a client Zustand store only | Zustand as the client cache, `user_preferences` (A05) and `user_grid_prefs` (A07) as the durable store | REQ-GRD-08 requires preferences to survive a device change. Client-only state cannot. |
| Its own hand-rolled table layer | TanStack Table as the headless base | REQ-GRD-01. |
| Biome | Biome, kept | The reference is right and A01 configures it. No deviation. |
| A fixed set of presets | Full generator parity: every knob editable, previewable, persistable in-app | REQ-UI-05 goes beyond the reference. The reference lets you pick a preset; we let you build one. |
| No screenspace measurement | `packages/screenspace` measurement layer + declared surface budgets | REQ-UI-09, REQ-UI-10. The reference assumes breakpoints; we measure. |

## The nav registry, concretely

```ts
// packages/contracts/nav.ts — published by A05, consumed by every domain
export type NavEntry = {
  id: string;                  // "audit.console" — globally unique, A02 checks collisions
  section: NavSection;         // "overview" | "operate" | "administer" | "global"
  order: number;               // sparse, step 100, so inserts need no renumber
  i18nKey: string;             // "nav.audit.console" — never a literal (REQ-I18N-02)
  href: string;
  icon: LucideIconName;        // name, not component — the registry stays serialisable
  permission?: PermissionString;   // hidden when absent; enforcement is server-side
  tier?: "tenant" | "global";  // global entries render only in the global tier
  subItems?: NavEntry[];
  badge?: "beta" | "new";
};
```

Each domain exports `nav: NavEntry[]` from its `contract.declaration.ts`. A02
fails assembly on a duplicate `id`. A05's shell imports the assembled registry,
sorts by `section` then `order`, filters by the session's permissions, and
renders. No agent ever edits another agent's entry, and the file every agent
would otherwise have fought over does not exist.

The same registry pattern covers settings panels, command-palette entries
(REQ-UI-12), help topic links (REQ-DOC-02) and notification categories
(REQ-PWA-06).

## Directory mapping, reference to ours

```
reference                              ours                                   owner
src/app/(main)/                    →   apps/<app>/app/(app)/                   A05
src/app/(external)/                →   apps/<app>/app/(auth)/                  A03
src/navigation/sidebar/*.ts        →   packages/contracts/nav.ts + per-domain  A05 + all
src/config/app-config.ts           →   packages/config/** (Zod, env-driven)    A01
src/stores/preferences/            →   packages/screenspace + user_preferences A05
src/styles/presets/*.css           →   packages/theme/presets/*.css            A06
src/scripts/generate-theme-presets →   packages/theme/scripts/generate-presets A06
src/lib/data-table-features.ts     →   packages/datagrid GridDefinition        A07
components.json                    →   apps/<app>/components.json              A06
```

## What "not a dependency" means in practice

- No entry for the reference in any `package.json`. A19's dependency inventory
  (REQ-SUP-01) will not list it and must not.
- No copied file carrying its licence header. If a file would be a copy, it is
  rewritten against our contract instead.
- No `git submodule`, no `git subtree`, no vendored `third_party/` copy.
- The reference's version is not in `versions/manifest.json`, because nothing is
  installed from it (REQ-VER-02 has nothing to validate).
- REQ-SUP-04 is therefore satisfied trivially: no new dependency is introduced
  by REQ-UI-03.
- REQ-SUP-07 is unaffected: the reference fetches fonts remotely in places; we
  self-host Montserrat and never inherit a remote origin.

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|----------|--------|-----|---------------------|
| Reference is a dependency or a reading | Reading only — no vendor, no fork | Keeps REQ-SUP-01/04 clean and lets us deviate freely | No |
| Route group names | `(app)` and `(auth)` | Matches `contracts/ownership.md` verbatim | No |
| Nav as array or registry | Registry, per-domain declarations | Shared array is a merge point in a 15-wide wave (REQ-CTR-04) | No |
| Nav `order` step | 100, sparse | Insert without renumbering anyone else's entry | No |
| Icon reference in registry | Icon *name* string, not component | Registry stays serialisable and cheap to assemble | No |
| Lint/format tool | Biome, as the reference | One tool for lint and format; A01 configures | No |
| Preference persistence | Server-side row, client store as cache | REQ-GRD-08 | No |
| shadcn blocks | `dashboard-01`, `login-02` | REQ-UI-01, REQ-UI-02 | No |
| Sidebar collapsed by default on desktop | No — expanded | Density-first desktop (REQ-UI-08); the collapse state is a persisted preference | Yes |
| Mobile primary navigation | Bottom bar, not a hamburger drawer | REQ-UI-07 thumb reach; the reference uses a drawer and we reject it | Yes — drawer if intake asks |

## How this is verified

- `pnpm lint:boundaries` — A01's import-boundary rule. Fails if any app file
  imports a nav array rather than the assembled registry, and if any domain
  package imports another domain package (REQ-CTR-01).
- `pnpm test:contract` (`packages/contracts/tests/nav.spec.ts`) — asserts every
  registered `NavEntry` has a unique `id`, a resolvable `i18nKey`, and a
  `permission` that exists in the assembled permission set. Run by A05 and by
  every domain that registers an entry (REQ-CTR-10).
- `pnpm test:unit` (`tests/unit/shell/nav-registry.spec.ts`) — permission
  filtering: a tenant user never receives a `tier: "global"` entry.
- `pnpm test:visual` (`tests/visual/shell.spec.ts`) — A21 screenshots the shell
  at 390 / 834 / 1440 in light and dark (REQ-TST-03) and asserts the surface
  budgets from `spec/screenspace.md` (REQ-UI-10).
- `grep -ri "next-shadcn-admin-dashboard" --include=package.json --include=*.lock .`
  returns nothing. This is the test that we took a reading, not a dependency.
- `pnpm check:ownership` — every file changed in a task is inside the acting
  agent's owned paths (REQ-CTR-04).

## Open to intake

| Question | Default if the human says nothing |
|----------|-----------------------------------|
| App directory name under `apps/` | `admin-panel` (A00 resolves, REQ-FND-01) |
| Mobile primary nav: bottom bar or drawer | Bottom bar |
| Desktop sidebar default state | Expanded |
| Nav sections shipped | `overview`, `operate`, `administer`, `global` |
| Whether a `(marketing)` public route group exists | No — `(auth)` covers the unauthenticated surface |
