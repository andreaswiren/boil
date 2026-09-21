---
name: visual-qa-cdp
description: Drives Chromium over CDP with Playwright to capture the build's screenshot set — 390/834/1440 in light and dark, at named points during the run rather than only on failure — asserts each surface's chrome-vs-content budget from spec/screenspace.md, runs axe at WCAG AA in both themes, and presents the images in the chat reply. Load when a build touches the UI, at gate G5, when asked to "screenshot the app", "run the visual tests", "check the layout at mobile", "verify the surface budget", "run axe", or when Playwright cannot find a browser.
---

# Visual QA over CDP

A21 owns `tests/visual/**` and `build/screenshots/**`. Requirements: REQ-TST-02,
REQ-TST-03, REQ-TST-04, REQ-TST-06, REQ-UI-10. A21 writes no product code, so it
never screenshots its own work (REQ-GAT-07).

## 1. Environment facts — do not fight them

Chromium is **pre-installed**:

```bash
echo "$PLAYWRIGHT_BROWSERS_PATH"      # /opt/pw-browsers  (set for you)
ls -l /opt/pw-browsers/chromium       # symlink -> chromium-<rev>/chrome-linux/chrome
```

`PLAYWRIGHT_BROWSERS_PATH` is already exported. `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD`
is **not** — check it and export it yourself before any install, or an npm
postinstall hook will try to re-fetch a browser that is already on disk:

```bash
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
```

**Never run `playwright install`.** The download is blocked or wasted, and it
does not fix the one failure it looks like it would fix.

If the project pins a `@playwright/test` expecting a different browser revision,
Playwright reports "Executable doesn't exist at /opt/pw-browsers/chromium-<rev>/…".
Do not download that revision — launch the installed binary instead:
`chromium.launch({ executablePath: '/opt/pw-browsers/chromium' })`.

**When this fails:** the browser dies immediately with no page. In a container
without a user namespace, add `--no-sandbox` to `args`; if it still dies, check
`ldd /opt/pw-browsers/chromium | grep 'not found'` — a missing shared library is
a host problem to report, not something a reinstall fixes.

## 2. Connect: launch vs connectOverCDP

REQ-TST-02 is CDP, not "whatever Playwright defaults to". Two shapes, not
interchangeable:

- **`chromium.launch`/`launchServer` with `--remote-debugging-port`** — this run
  owns the browser. The normal suite: one browser per run, torn down at the end.
- **`chromium.connectOverCDP('http://127.0.0.1:9222')`** — attach to a browser
  already running: a long-lived Chromium kept open across tasks, or one started
  outside the suite. It reaches the existing default context, so you can capture
  state you did not create.

```ts
// tests/visual/cdp.ts — verified against Playwright 1.56 / Chromium 141
import { chromium } from '@playwright/test';

const PORT = 9222;
const server = await chromium.launchServer({
  executablePath: '/opt/pw-browsers/chromium',
  args: [`--remote-debugging-port=${PORT}`, '--no-sandbox', '--font-render-hinting=none'],
});
const browser = await chromium.connectOverCDP(`http://127.0.0.1:${PORT}`);

// contexts()[0] is the browser's existing default context over CDP;
// newContext() gives a clean one when the run must not inherit state.
const ctx = browser.contexts()[0] ?? await browser.newContext();
await browser.close(); await server.close();   // browser first, then its server
```

## 3. The matrix

Three viewports × two themes × every capture point. No "desktop only because the
change was small" (REQ-TST-03).

| Viewport | Size | Emulation |
|----------|------|-----------|
| mobile | 390 × 844 | `isMobile: true`, `hasTouch: true`, dpr 3 |
| tablet | 834 × 1112 | `hasTouch: true`, dpr 2 |
| desktop | 1440 × 900 | dpr 1, no touch |

Theme is set per context, not by clicking: `colorScheme: 'light' \| 'dark'` plus
the app's persisted preference, so the server-rendered theme matches and you are
not capturing a flash of the wrong theme (REQ-UI-06).

## 4. Capture points — named, not incidental

Screenshots are taken **during** the run — a suite that captures only on failure
fails REQ-TST-03. Capture at each point, named in the filename:

| Point | File suffix | Why it is in the set |
|-------|-------------|----------------------|
| initial paint | `01-initial` | first-paint theme correctness, no layout jump |
| after auth | `02-authed` | the shell as a real user sees it |
| after data load | `03-loaded` | grid with real fixture rows, not skeletons |
| after an interaction | `04-interacted` | drawer/sheet/palette open, focus visible |
| after a theme switch | `05-theme-switched` | in-app switch: no reload, no flash |
| assertion failure | `99-fail-<assertion>` | evidence for the finding |

```
build/screenshots/<surface>/<viewport>-<theme>-<point>.png   # users-grid/mobile-dark-03-loaded.png
```

## 5. Deterministic capture

A diff means something only if everything that is not the change is stable.

```ts
await ctx.addInitScript(() => {
  const s = document.createElement('style');
  s.textContent = `*,*::before,*::after{animation:none!important;transition:none!important}
                   html{scroll-behavior:auto!important}`;
  document.documentElement.appendChild(s);
});
await page.goto(url, { waitUntil: 'networkidle' });
await page.evaluate(() => document.fonts.ready.then(() => true));  // self-hosted fonts
await page.screenshot({
  path: out,
  fullPage: true,
  animations: 'disabled', caret: 'hide',
  mask: [page.locator('[data-volatile]')],   // timestamps, ids, durations
});
```

Volatile regions carry `data-volatile` in the product code — relative times,
generated ids, durations, chart tooltips. An unmarked one is a finding against
the owning agent, not a reason to widen the diff threshold.

**When this fails:** `networkidle` never settles — a websocket, a poll or the
service worker holds a connection open. Do not raise the timeout; wait on the
thing that matters (`page.waitForSelector('[data-loaded="true"]')`) and record
which surface needed it.

## 6. Surface-budget assertion (REQ-UI-10)

Declared budgets come from `spec/screenspace.md` and the winning thesis's
`mockups/theses.ts`, surfaced by A05 as `surface-budget`. Measure; do not eyeball.

```ts
const budget = budgets[surface][viewport];   // { maxChromeFraction, minContentPx }
const m = await page.evaluate(() => {
  const vh = window.visualViewport?.height ?? window.innerHeight;
  const px = (s: string) => document.querySelector(s)?.getBoundingClientRect().height ?? 0;
  const chrome = ['header', 'nav', 'toolbar', 'footer']
    .reduce((n, k) => n + px(`[data-surface="${k}"]`), 0);
  return { vh, chrome, content: vh - chrome };
});
const at = `${surface}/${viewport}`;
expect(m.chrome / m.vh, `${at} chrome`).toBeLessThanOrEqual(budget.maxChromeFraction);
expect(m.content, `${at} content px`).toBeGreaterThanOrEqual(budget.minContentPx);
```

Use `visualViewport.height` so a surface measured with the mobile keyboard open
is judged against the space that exists (REQ-UI-09). Over budget fails the gate,
and the fix belongs to the surface's owner — never to the budget number.

## 7. axe at AA, both themes (REQ-TST-06)

```ts
import AxeBuilder from '@axe-core/playwright';

for (const scheme of ['light', 'dark'] as const) {
  const page = await (await browser.newContext({ colorScheme: scheme })).newPage();
  await page.goto(url, { waitUntil: 'networkidle' });
  const r = await new AxeBuilder({ page }).withTags(['wcag2a','wcag2aa','wcag21aa','wcag22aa']).analyze();
  expect(r.violations, `axe ${scheme}: ${r.violations.map(v => v.id).join(', ')}`).toEqual([]);
}
```

Contrast violations differ per theme — running one and assuming the other is the
hole REQ-UI-11 exists to close. Write the violation list to
`build/screenshots/<surface>/axe-<theme>.json` as evidence.

## 8. Present the images in the reply

REQ-TST-04 and REQ-MOC-04: screenshots are **presented in the chat response to
the user**, not merely written to disk. Writing files and saying "they are in
`build/screenshots/`" does not satisfy it.

```bash
find build/screenshots -name '*.png' -newermt '-1 hour' | sort
```

Pass those paths into the reply as images, grouped by surface and labelled
`<viewport>/<theme>/<point>`, with the measured budget numbers and the axe result
beside them. If the set is large, present each surface's `03-loaded` and
`05-theme-switched` at all three viewports in both themes and list the rest by
path — never reduce the presented set to one desktop image.
