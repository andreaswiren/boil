# Vendored resources

Third-party reference material, copied in verbatim at a recorded commit and then
left alone. **Nothing in a subfolder here is ours**: it is not edited, not
linted, not counted, and this boilerplate's conventions do not apply to it.
`scripts/check-boilerplate.sh` skips `resources/` for exactly that reason, and
verifies the pin instead.

## `next-shadcn-admin-dashboard/`

The reference implementation `REQ-UI-03` and `REQ-MOC-09` measure layout and
navigation conventions against, and the source of the live demo at
<https://studio-admin.arhamkhnz.com/dashboard/default>.

| | |
|---|---|
| Upstream | `https://github.com/arhamkhnz/next-shadcn-admin-dashboard` |
| Commit | `5ac5a9a82a5b8012a12c08eaf2e3a8ccba481df1` |
| Commit date | 2026-09-22 |
| Vendored | complete tracked tree at that commit — 340 files |
| Licence | MIT, `next-shadcn-admin-dashboard/LICENSE`, Copyright (c) 2024 Mohammed Arham Khan |
| Integrity | `pin.json` — SHA-256 per file |

**Why a copy and not a link.** A URL is a moving target: the demo is redeployed
and `main` advances, so a build measured against a link is measured against
whatever that link served on the day — which the register never described, and
which nobody can reconstruct afterwards. `REQ-UI-16` requires the pin.

**Do not edit anything under `next-shadcn-admin-dashboard/`.** It is evidence of
what the conventions were at that commit. An edit turns the reference into an
undeclared fork and silently moves what every gate compares against; `pin.json`
fails the build if one happens.

**To move the pin:** re-vendor from the new commit, regenerate `pin.json`, and
record in `CHANGELOG.md` *why* it moved. A pin that moves without a reason is a
URL with extra steps.

## What to read it for

The conventions, not the code. The ten theses vary layout; they do not each
invent a navigation model (`REQ-MOC-09`).

| Path | The convention it carries |
|------|---------------------------|
| `src/navigation/sidebar/sidebar-items.ts` | How the menu is declared: groups, items, nesting depth, icon per item. `build/navigation.md` is this shape filled with the real entities (REQ-MOC-13). |
| `src/app/(main)/dashboard/layout.tsx` | Shell composition — where sidebar, header and content sit relative to each other. |
| `src/app/(main)/dashboard/_components/sidebar/app-sidebar.tsx` | Sidebar structure and collapse behaviour. |
| `src/app/(main)/dashboard/_components/sidebar/nav-main.tsx` | How a nav group renders and how depth is expressed. |
| `src/app/(main)/dashboard/_components/header/layout-controls.tsx` | Which layout knobs are exposed to the user, and where. |
| `src/lib/preferences/layout.ts` | Which layout preferences persist — the shape `REQ-GRD-08` extends to grid state. |
| `components.json` | The upstream shadcn configuration, for comparison with the preset this boilerplate pins in `REQ-UI-04`. |
| `media/` | Upstream's own screenshots, useful as a visual reference without running it. |
