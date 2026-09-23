---
name: shadcn-signzone-ui
description: The SignZone red-accent Radix/shadcn visual system — dashboard patterns, status semantics, dark mode, responsive behaviour and the approval screen's hard constraints. Load for UI work.
---

# SignZone UI

Design: `spec/16-ui.md`.

## One screen has rules the rest do not

Most of this is ordinary admin UI. **The approval screen is a security control**
(`spec/09-pwa-approvals.md`):

- The **digest suffix is never truncated** below the fixed length, at any
  viewport. The layout reflows; the evidence does not shrink. A truncated digest
  makes two artefacts indistinguishable.
- **Actions sit below the bound details**, and stay there at the largest
  supported system font. An approver who must scroll up to see what they are
  approving will not scroll up.
- Approve and reject are **not adjacent**, and reject is not the quiet option.

## Visual system

shadcn/ui on Radix, Tailwind, red accent. Dark mode is a designed theme, not an
inversion — appliances live in racks and operations rooms.

**Status is never colour alone.** Every state carries a glyph and a word: an
operations room has bad monitors, and a meaningful fraction of operators cannot
distinguish the red and green we would otherwise rely on.

## Dashboards

The two things discovered too late are **certificate expiry** and **a DR HSM
whose Key Check Value no longer matches**. Both are persistent dashboard items,
not report entries.

## Accessibility is not a compliance item here

WCAG 2.2 AA, axe-asserted in both themes, full keyboard with a visible focus
indicator.

On the approval screen the bound details are announced to a screen reader
**before** the actions, in the order a sighted user reads them. Otherwise an
approver using assistive technology approves something different from what the
sighted user approved.

## Definition of done

- [ ] Every `SZ-PWA-003` field visible at 320 px and at the largest system font,
      actions below — asserted by screenshot.
- [ ] Digest suffix never below the fixed length at any viewport.
- [ ] axe: zero violations, both themes.
- [ ] Every status indicator has a glyph and a word.
- [ ] Screen-reader order presents details before actions.
