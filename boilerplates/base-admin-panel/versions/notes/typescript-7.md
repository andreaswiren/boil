# typescript 5 → 7

Detected: 2026-09-21
Source: https://registry.npmjs.org/typescript/latest (reports `7.0.2` as latest stable)
Decision: **deferred pending verification**
Acknowledged by: <<PLACEHOLDER: name of the human who made the call>>

## Why this is not an ordinary major

TypeScript 7 is the native rewrite of the compiler, not an incremental major.
The type system is intended to be compatible, but the *toolchain surface* is
where a rewrite breaks things: compiler APIs, language-service plugins, custom
transformers, and anything that loads `typescript` as a library rather than
running `tsc`.

REQ-VER-04 makes this a reviewed decision. REQ-VER-01 says latest stable, and
7.0.2 is latest stable — so the rule that decides it is REQ-VER-04, not
REQ-VER-01. Being newest is not on its own a reason to adopt.

## What must be confirmed before adopting

Each of these is confirmed **externally**, from the dependency's own release
notes or issue tracker — not from an assumption that a recent version probably
works:

| Dependency | Why it matters | Confirmed? |
|------------|----------------|-----------|
| `next` (16.3.5) | Runs type checking in the build and ships its own plugin | <<PLACEHOLDER>> |
| `@biomejs/biome` (2.5.14) | Parses TS; a rewrite can change emitted syntax it must accept | <<PLACEHOLDER>> |
| `drizzle-kit` (0.31.11) | Generates and type-checks schema code | <<PLACEHOLDER>> |
| `vitest` (5.0.1) | Transforms TS in test runs | <<PLACEHOLDER>> |
| `@asteasolutions/zod-to-openapi` (9.1.0) | REQ-API-01 depends on schema types surviving | <<PLACEHOLDER>> |
| `tsx` (4.23.15) | Runs the scripts A01 and A02 rely on | <<PLACEHOLDER>> |

## What in this build touches it

| Agent | What it uses | Impact if 7.x misbehaves |
|-------|--------------|--------------------------|
| A01 | `tsconfig.base.json`, `strict`, `noUncheckedIndexedAccess` (REQ-FND-03) | The whole monorepo fails to typecheck; nothing downstream starts |
| A02 | Zod schema inference across the contract package (REQ-CTR-01) | Contract types degrade to `any` and every consumer loses its guarantee silently — the worst failure mode here |
| A11 | Zod → OpenAPI generation (REQ-API-01) | The API document stops matching the runtime |
| A07 | TanStack Table generics (REQ-GRD-01) | Grid column typing breaks across twelve surfaces |
| A23 | Type-level assertions in contract interface tests (REQ-CTR-10) | Interface tests pass while being vacuous |

The A02 row is the reason this is deferred rather than tried. A contract package
whose inference silently widens is worse than one that fails to compile, because
G4 would pass.

## If deferred

Pinned line: the newest `5.x` — A20 resolves the exact patch at G2 from
`https://registry.npmjs.org/typescript` rather than hardcoding it here.

Revisit when: all six rows above are confirmed, or when a build has a reason to
need something only 7.x provides.

Recorded as `VER-TRAP-002` in `versions/traps.json` so the next build inherits
this decision instead of rediscovering it (REQ-VER-05).
