# Migration notes

One file per major-version jump, named `<package>-<major>.md`.

REQ-VER-04: a major jump is a reviewed decision, not an automatic bump. A20
detects the jump against the previous manifest, writes the note here, and stops
until a human acknowledges it. An unacknowledged major never reaches
`versions/manifest.json`.

The note exists for two readers: the human making the call, and A22, which cites
it in the changelog entry for the build that adopted the version.

## Template

```md
# <package> <old major> → <new major>

Detected: <date>  ·  Source: <the release notes URL, not a summary of them>
Decision: adopted | deferred  ·  Acknowledged by: <name>

## Breaking changes that touch this stack
- …

## What in this build touches them
| Agent | What it uses | Impact |
|-------|--------------|--------|

## If deferred
Pinned line: <version>. Reason: <why>. Revisit when: <condition>.
```

A note that lists breaking changes without naming which agents they affect is
half a note — the affected-agent column is what turns it into dispatchable work.
