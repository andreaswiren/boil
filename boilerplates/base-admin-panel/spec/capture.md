# Continuous Visual Capture (REQ-CAP-01 … REQ-CAP-10)

`A21` owns this. It is not a gate deliverable produced twice — it is a feed that
runs for the whole build, so that the human watching the live instance
(REQ-LIV-01) can also see what every surface looked like at every sha behind it.

Two delivery paths, both required (REQ-CAP-04):

- **The reply** — images in the chat response. Immediate, and it scrolls away.
- **The folder and the served feed** — `build/screenshots/` on disk, rendered at
  `/_build/screenshots` on the live instance. Durable, and nobody watches it
  unprompted.

Either alone loses something the other has. Both were asked for.

---

## 1. When a capture runs (REQ-CAP-01, REQ-CAP-10)

| Trigger | Scope |
|---------|-------|
| a UI-touching hand-off lands | the surfaces that agent owns |
| every wave boundary | every surface that exists |
| every gate | every surface the gate covers, at the gate's sha |
| a `C1`, `A27` or `C2` finding about appearance | the named surface, before and after the fix |

Capture never blocks a wave — it runs alongside the work. It does block a gate:
no gate passes on a surface whose newest capture predates the sha under review
(REQ-VAL-08), because a gate is precisely the moment that evidence is relied on.

## 2. Paths and sidecars (REQ-CAP-02, REQ-CAP-03)

```
build/screenshots/
├── wave-3/
│   ├── grid-users__1440__dark__4f2a9c1.png
│   ├── grid-users__1440__dark__4f2a9c1.json
│   ├── grid-users__390__light__4f2a9c1.png
│   └── …
└── index.json            the feed manifest the served page reads
```

Surface names come from the route (`/users` → `grid-users`), never invented per
run — an invented name breaks the one property the convention exists for, which
is that two captures of the same surface sort next to each other and a
regression is visible by scrolling.

```json
{
  "surface": "grid-users",
  "url": "http://localhost:3000/users?filter=status:active&sort=-created_at&page=2",
  "viewport": { "width": 1440, "height": 900, "dpr": 2 },
  "theme": "dark",
  "sha": "4f2a9c1e8b7d6a5c4b3e2f1a0d9c8b7a6e5d4c3b",
  "capturedAt": "2026-09-23T14:22:08Z",
  "reqIds": ["REQ-GRD-02", "REQ-GRD-04", "REQ-GRD-09", "REQ-UI-10"],
  "interaction": "filtered status=active, sorted created_at desc, paged to 2",
  "console": { "errors": [], "warnings": [], "failedRequests": [] },
  "axe": { "violations": 0, "level": "AA" }
}
```

## 3. The matrix (REQ-CAP-08)

Every surface, every set: **390 / 834 / 1440 px × light / dark** — six images.
Desktop-light is the configuration most likely to have been looked at during
development and therefore least likely to be broken, which makes it the least
informative single capture available.

## 4. States, not screens (REQ-CAP-09)

A route that renders is not a feature that works. Each surface's set covers its
loaded state and at least its working state:

| Surface kind | The state that must be in the set |
|--------------|-----------------------------------|
| grid | a filter and a sort applied, page two reached, the column chooser open (REQ-GRD-02 … REQ-GRD-09) |
| form | the validation-error state, not the empty one |
| dialog | open, over its parent surface |
| shell | sidebar collapsed, and at the collapse breakpoint (REQ-UI-10) |
| auth | the MFA step, not only the password step (REQ-AUT-01) |
| empty/error | the genuine empty state and a rendered error boundary |

An empty grid at 1440px in light mode is the screenshot most likely to be taken
and least likely to disprove anything.

## 5. The console is part of the evidence (REQ-CAP-07)

Every capture attaches a CDP console and network listener for its lifetime. A
surface captured with a page error, an unhandled rejection or a failed request is
**reported as failing**, with the error quoted next to the image — not presented
as a screenshot that happens to look correct.

This is the specific hole a screenshot leaves: a page whose data fetch 500s and
whose error boundary renders a tidy empty state photographs as a working feature.

## 6. Where the captures come from (REQ-CAP-06)

Playwright over CDP against **the live instance** (REQ-LIV-03), which is a
production build. Never `next dev` — the dev overlay and hot-reload client make
it a picture of the toolchain. Never a `file://` path, never a second server
started for the capture: a process with empty caches and no accumulated state is
the one configuration no user meets.

Browser resolution is detect-then-act, because this boilerplate runs on the
human's machine as often as in a container: use `PLAYWRIGHT_BROWSERS_PATH` if it
is set and the binary is there, otherwise a system Chromium if one resolves,
otherwise install. `.claude/skills/visual-qa-cdp/SKILL.md` carries the mechanics.

## 7. The served feed (REQ-CAP-05)

`/_build/screenshots` on the live instance, reading `index.json`:

- newest first, grouped by surface;
- each image beside its sidecar and beside the previous capture of the same
  surface, so a change is a side-by-side and not an act of memory;
- filters for viewport, theme, wave and sha;
- surfaces whose newest capture has console errors marked at the top.

The human already has that URL. Everything about the build's visual history is
therefore one click away from where they are already looking, which is the
difference between a history that is kept and a history that is consulted.
