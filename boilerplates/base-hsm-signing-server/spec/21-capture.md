# Continuous Visual Capture (SZ-CAP-001 … SZ-CAP-008)

Owner: `ui-ux-engineer`, with `test-automation-engineer` for the browser
harness.

Capture is a feed that runs for the whole build, from the live instance
(SZ-LIV-003) — not a set produced at a design review and again at release, which
leaves everything between them unobserved.

Two delivery paths, both required (SZ-CAP-004): the images in the chat reply,
and `build/screenshots/` on disk served at `/_build/screenshots` on the live
instance. The reply is immediate and scrolls away; the folder persists and
nobody watches it unprompted.

---

## 1. When a capture runs (SZ-CAP-001, SZ-CAP-008)

| Trigger | Scope |
|---------|-------|
| a UI-touching hand-off lands | the surfaces that agent owns |
| every phase boundary | every surface that exists |
| every gate | every surface the gate covers, at the gate's sha |
| a review finding about appearance or flow | the named surface, before and after |

Capture never blocks a phase. It always blocks a gate.

## 2. Paths and sidecars (SZ-CAP-002, SZ-CAP-003)

```
build/screenshots/
├── phase-4/
│   ├── approval-detail__390__dark__c3f1a92.png
│   ├── approval-detail__390__dark__c3f1a92.json
│   └── …
└── index.json
```

```json
{
  "surface": "approval-detail",
  "url": "https://localhost:8443/approvals/req_01H…",
  "viewport": { "width": 390, "height": 844, "dpr": 3 },
  "theme": "dark",
  "applianceState": "Operational",
  "sha": "c3f1a92e7b40d58c6a1f2e3d4c5b6a7980f1e2d3",
  "capturedAt": "2026-09-23T14:22:08Z",
  "reqIds": ["SZ-PWA-002", "SZ-AUTH-004"],
  "interaction": "opened from a push notification, step-up completed",
  "console": { "errors": [], "failedRequests": [] },
  "secretScan": "clean"
}
```

## 3. Appliance states, not only screens (SZ-CAP-005)

This product has four states — `Unprovisioned`, `Locked`, `Operational`,
`Failed` — and most surfaces behave differently in each. A surface captured only
in `Operational` is a surface whose other three renderings nobody has seen.

The **refusal** is captured too: `412` with both states named (SZ-API-004) is a
user-visible behaviour and it is the one nobody looks at, because it only
appears when something is already wrong.

The approval flow is captured at the PWA viewport as well as desktop — it is the
surface an operator actually uses, usually one-handed, usually in a hurry.

## 4. The console is part of the evidence (SZ-CAP-006)

Page errors, unhandled rejections and failed requests are recorded during every
capture, and a surface captured with one is **reported as failing** — not
presented as a screenshot that happens to look right. A page whose fetch failed
and whose error boundary renders tidily photographs as a working feature.

## 5. No secrets in a capture (SZ-CAP-007)

Screenshots are committed. A screenshot is therefore a durable, greppable copy of
whatever was on screen, and this product puts things on screen that operating
rule 9 forbids storing anywhere.

Two controls, and the first is the one that matters:

1. **The development instance holds no real key material** (SZ-LIV-005). Nothing
   captured from it is a real PIN, share or recovery code.
2. **Every capture is scanned before it is written** — a PIN or SO-PIN field, a
   DKEK share, a recovery code list, a session token, a live QR enrolment payload
   — and a hit fails the capture rather than being cropped. The sidecar records
   the scan result, so "nobody checked" and "checked and clean" are
   distinguishable afterwards.

## 6. Where the captures come from

The live instance (SZ-LIV-003), over CDP against a production build, at a named
sha. Never a second server started for the capture: a process with empty caches
and no accumulated state is the one configuration no operator ever meets.
