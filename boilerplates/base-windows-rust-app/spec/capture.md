# Continuous Visual Capture (REQ-CAP-01 … REQ-CAP-11)

`B15` owns this. It is not a set produced at `H1` and again at `H5` — it runs for
the whole build, so the human can see what every view looked like at every sha
behind it.

A desktop app has no URL to serve a feed from, so the two delivery paths are the
chat reply and a generated on-disk index (REQ-CAP-04, REQ-CAP-05). The reply is
immediate and scrolls away; the index persists and nobody opens it unprompted.
Either alone loses something the other has.

---

## 1. When a capture runs (REQ-CAP-01, REQ-CAP-10)

| Trigger | Scope |
|---------|-------|
| a UI-touching hand-off lands | the views that agent owns, all five states |
| every wave boundary | every view that exists |
| every gate | every view the gate covers, at the gate's sha |
| a `D1` or `D2` finding about appearance | the named view, before and after the fix |

Capture never blocks a wave. It always blocks a gate: no gate passes on a view
whose newest capture predates the sha under review.

## 2. Paths and sidecars (REQ-CAP-02, REQ-CAP-03)

```
build/screenshots/
├── wave-3/
│   ├── settings__150__dark__9b1c4e7.png
│   ├── settings__150__dark__9b1c4e7.json
│   └── …
└── index.md            generated: newest first, grouped by view and state
```

View names come from the view registry, never invented per run — the convention
exists so two captures of the same view sort next to each other and a regression
is visible by scrolling rather than by remembering.

```json
{
  "view": "settings",
  "state": "error",
  "theme": "dark",
  "dpiScale": 150,
  "monitors": [{ "scale": 150, "primary": true }],
  "sha": "9b1c4e77a0f2d3c5b6e8a9d0f1c2b3a4e5d6c7b8",
  "binary": "target/debug/app.exe",
  "mechanism": "in-process",
  "capturedAt": "2026-09-23T14:22:08Z",
  "reqIds": ["REQ-UI-07", "REQ-DSN-06"],
  "logs": { "warn": [], "error": [] }
}
```

## 3. The matrix (REQ-CAP-08)

Both themes for every view, high contrast as its own variant rather than
inferred from dark (REQ-DSN-08), and the full DPI ladder — 100 / 150 / 200 /
250% — at every gate set, including a window moved between mixed-scale monitors
(REQ-TST-08).

One capture at 100% in light is the configuration most likely to have been
looked at during development, and therefore the least informative one to keep.

## 4. States, not screens (REQ-CAP-09)

Five states per view — empty, loading, error, offline, ready (REQ-UI-07) — and
the tray menu in each of its states (REQ-TRY-01).

A view's ready state proves it renders. What a view does when the thing it
renders is missing is the part that was designed last and is wrong most often.

## 5. The log is part of the evidence (REQ-CAP-07)

Every `warn` and `error` emitted while a view was captured is recorded beside the
image, and a view captured with an error is **reported as failing** — not
presented as a screenshot that happens to look correct. A view whose data load
failed and whose error state renders tidily photographs as a working feature.

## 6. Where the captures come from (REQ-CAP-06)

A built binary of the tree under review (REQ-VAL-10), at a named sha, recorded in
the sidecar. Never a stale binary from a previous wave, never a drawing.

Two mechanisms, and the difference is recorded rather than blurred:

- **In-process** (`request_screenshot`) — deterministic, the UI's own pixels,
  works anywhere including a headless agent session.
- **Desktop capture** (`PrintWindow` with `PW_RENDERFULLCONTENT`) — the only way
  to see the window frame, Mica, the tray and the shell, and it needs a real
  interactive session.

## 7. State what could not be captured (REQ-CAP-11)

An agent running in session 0 has no desktop, so the desktop captures do not
run there. The honest report names which images were taken in-process, which
were skipped, and what therefore remains unverified — a tray icon nobody could
photograph is an unverified tray icon, and a capture set that looks complete
because the impossible ones were quietly dropped is worse than one that is
visibly short.
