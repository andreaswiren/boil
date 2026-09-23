# The live instance

Owner: `test-automation-engineer` with `installer-engineer` and
`release-engineer`. Requirements: `SZ-LIV-001`…`006`.

## 1. Why the URL exists from the first minute

A build runs for hours. Without a live instance the human's only window is agent
reports — prose, after the fact, about work they cannot see. Defects that ten
seconds of clicking would catch are instead found by a reviewer two phases later,
or not at all.

So: **one URL, up from the start, up until the build ends.** It exists before the
appliance's surface does, and that is the point rather than a compromise.

| Phase | What the URL serves |
|-------|--------------------|
| Before any UI | **Build status** — current phase, each agent's state, what is waiting on a human |
| As surfaces land | Those surfaces, with the status page still at `/_build` |
| At acceptance | The appliance's own web surface |

The status page is not scaffolding to delete. It stays reachable for the whole
build, because "what is the fleet doing" remains a useful question late.

## 2. Told to the human, every phase (`SZ-LIV-002`)

In the reply. Not a file they have to find, and not once at the start of a build
whose opening message scrolled away hours ago.

```
Live instance:  https://localhost:8443       build status at /_build
Test logins:    admin@dev.invalid     / <generated>   Administrator
                approver@dev.invalid  / <generated>   Operator, can approve
                viewer@dev.invalid    / <generated>   read-only
```

Generated per build, never fixed strings, never committed. Addresses use
`.invalid` so they cannot collide with a real address or receive real mail.

An approver who cannot log in cannot exercise the approval flow, and the build
stalls on a missing password rather than on a real decision.

## 3. One instance, for everything (`SZ-LIV-003`)

Development, debugging, screenshot capture and the human's browsing all happen
against the **same running process**. No agent starts its own server for a clean
capture.

The reason is not tidiness. An ephemeral server is freshly started, with empty
caches, no sessions and no accumulated state — the one configuration no operator
ever experiences, and therefore the one that hides the defects which appear after
an hour of use. And a screenshot taken against a different process is not
evidence about the thing the human looked at: when they say "it looked wrong" and
the screenshot disagrees, nothing can settle it.

## 4. It never touches a real key (`SZ-LIV-005`)

This is the difference between this boilerplate and an ordinary web project.

The development instance runs against a **software PKCS#11 token or an HSM
emulator**, never a production Nitrokey HSM 2 and never a production DKEK
(`spec/14-testing.md` §4). A development appliance wired to a real signing key is
a signing oracle with seeded logins and a URL the team has been told to open.

What software mode cannot prove is already written down — DKEK ceremonies, Key
Check Value comparison, PIN retry counters, reader enumeration — and those carry
a real-HSM tag and run against hardware before release, not against the live
instance.

## 5. The seeded logins are a production defect (`SZ-LIV-006`)

On a signing appliance a standing credential with a known address is not
untidiness. It is authorization to sign.

- Seeds run only under an explicit non-production build flag.
- **A production build containing any seeded account fails the release gate.**
  Mechanical, asserted by the release pass — never a habit of deleting them
  later. That habit fails exactly once, and the failure is a reachable
  administrator login on an appliance that holds a publisher identity.
- Passwords are generated per build, shown in the reply, never written to the
  repository (`.gitignore` covers the generated seed file regardless).

## 6. Keeping it up (`SZ-LIV-004`)

Checked continuously — does the URL *answer*, not merely "is the process alive"
— restarted when it dies, and **reported when it is down**. A build whose preview
died silently is a build the human believes they are watching.

A restart is a normal event. A repeated restart is a finding against whatever is
crashing it.

## 7. How this is verified

- The URL answers before the first agent produces a surface, serving build status.
- It answers continuously; an induced crash is detected and reported.
- Every screenshot in the evidence set came from the shared instance — asserted
  by the capture manifest recording the instance id, not by convention.
- The URL and every test login appear in the reply at every phase boundary.
- The live instance's PKCS#11 provider is the software token — asserted, because
  the failure mode is silent and severe.
- A production build containing a seeded account fails the release gate.
- No seeded credential appears in the repository.
