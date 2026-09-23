# The live instance

Owner: `A28` (keeps it alive) with `A01` (builds it) and `A19` (the production
exclusion). Requirements: `REQ-LIV-01`…`06`.

## 1. The problem it solves

A build runs for hours across five waves. Without a live instance the human's
only window into it is agent reports — prose, after the fact, about work they
cannot see. They find out the layout is wrong at `G1`, the grid is wrong at `G5`,
and anything they would have noticed in ten seconds of clicking is found by a
critic agent two gates later, if at all.

So: **one URL, up from Wave 0, up until the build ends.**

## 2. What it serves, and when

The instance exists before the product does. That is the point, not a compromise.

| Phase | What the URL serves |
|-------|--------------------|
| Wave 0–1, before any UI | **Build status**: current wave and gate, each dispatched agent and its state, what is waiting on a human, the running cost table (`REQ-COST-03`) |
| `G1` | The status page **plus the ten mockups**, browsable, at the same URL |
| Wave 2 onward | The application as it comes to exist, with the status page still reachable at `/_build` |
| After `G8` | The application |

The status page is not scaffolding to delete. It stays at `/_build` for the whole
build, because at `G6` the useful question is still "what is the fleet doing".

## 3. One instance, not one per purpose (`REQ-LIV-03`)

Development, debugging, screenshot capture and the human's browsing all happen
against **the same running process**.

The temptation is for `A21` to start its own server for a clean capture. That
must not happen, and the reason is not tidiness:

- An ephemeral server is freshly started, with empty caches, no accumulated
  session state and no other traffic. It is the one configuration no user ever
  experiences, so it hides exactly the defects that appear after an hour of use.
- A screenshot taken against a different process is not evidence about the thing
  the human looked at. When the human says "it looked wrong" and the screenshot
  says otherwise, there is no way to tell which was right.

`A21` attaches over CDP to a browser pointed at the shared instance
(`REQ-TST-02`).

## 4. Telling the human (`REQ-LIV-02`)

In the reply. Every gate. In full:

```
Live instance:  http://localhost:3000        build status at /_build
Test logins:    admin@dev.invalid    / <generated>   Administrator
                approver@dev.invalid / <generated>   Operator, can approve
                viewer@dev.invalid   / <generated>   read-only
```

Stated at every gate rather than once, because a build runs for hours and the
message that mattered has scrolled away by the time the human returns. An
approver who cannot log in cannot approve at `G1`, and the gate stalls on a
missing password rather than on a design decision.

Generated per build, never fixed strings, and never committed.

## 5. Keeping it up (`REQ-LIV-04`)

`A28` includes the instance in every check-in (`REQ-ORC-01`):

- Is it responding? Not "is the process alive" — does the URL answer.
- Is it serving the current state (`REQ-LIV-06`)? A preview two gates stale is
  worse than none, because it is believed.
- If it is down: restart it, record it, and **say so**. The human watching the
  URL must not be the mechanism that discovers the build's preview died.

A restart is a normal event, not a finding. A repeated restart is a finding
against whoever is crashing it.

## 6. Test credentials are a production defect (`REQ-LIV-05`)

The seeded accounts that make a build followable are, in a deployed product, a
set of standing credentials with known addresses.

- Seeds run only under an explicit non-production build flag.
- **A production build containing any seeded account fails `G7`.** Mechanical,
  asserted by `A19`'s supply-chain and configuration pass — not a habit of
  removing them later, because that habit fails exactly once and the failure is
  a publicly reachable admin login.
- Seeded addresses use `.invalid` (RFC 2606's reserved TLD) so they can never
  collide with a real address or receive real mail.
- Passwords are generated per build, shown in the reply, and never written to the
  repository.

## 7. How this is verified

- The URL answers before Wave 1 starts, and serves a build status page.
- It answers continuously through every gate; an induced crash is detected by
  `A28` and reported, not silently restarted into silence.
- Every screenshot in the build's evidence set came from the shared instance —
  asserted by the capture manifest recording the instance id, not by convention.
- The URL and every test login appear in the reply at every gate.
- A production build with a seeded account fails `G7`.
- No seeded credential appears in the repository.
