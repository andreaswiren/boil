# Editing surfaces

One editor, mounted once, configured from a registry. Owned by **A05**
(`ui-shell`): `packages/editor/**` (REQ-MON-01). A05 publishes `editor`
(`contracts/types/editor.md`) — the language registry, the formatter
descriptors, the `EditorSurface` declaration and the redaction declaration — and
consumes `theme-tokens` (A06), `rbac` (A04), `audit-event` (A13), `time` and
`errors` (A02), and A27's mobile primitives. A05 owns no document: each one
belongs to the domain that declared its surface, and A05 never learns what a
mapping descriptor or an ACME log is.

## Requirements covered

REQ-MON-01 … REQ-MON-12 (primary), REQ-UI-04, REQ-UI-05, REQ-UI-11, REQ-SUP-06,
REQ-SUP-07, REQ-SEC-08, REQ-AUD-01, REQ-AUD-04, REQ-AUD-05, REQ-DAT-03,
REQ-DAT-07, REQ-MOB-02, REQ-MOB-12, REQ-RBA-01, REQ-RBA-02, REQ-VER-01,
REQ-TIM-04, REQ-CTR-01, REQ-DOC-03.

## 1. Where an editor appears

Nine surfaces, seven agents. This list is the scope: a surface not in it is a
CCR, not an improvisation.

| Surface | Agent | Language | Mode | Schema | Read / write permission | Mobile |
|---|---|---|---|---|---|---|
| Mapping descriptor | A10 | `yaml` | editable | `descriptor.schema.json` | `canonical.descriptor.read` / `canonical.descriptor.write` | read-only |
| Email template body | A12 | `html` | editable | none; variable allowlist server-side | `mail.template.read` / `mail.template.write` | read-only |
| Email template text part | A12 | `plaintext` | editable | none | same | plain-edit |
| i18n catalogue entry | A14 | `plaintext` | editable | none; ICU parse | `i18n.message.read` / `i18n.message.write` **(CCR)** | plain-edit |
| Help topic | A16 | `markdown` | editable | front-matter only | `help.topic.read` / `help.topic.admin` | plain-edit |
| OpenAPI document | A11 | `yaml` | **read-only** | OpenAPI 3.1 | `api.docs.read` | read-only |
| HAProxy config | A01 | `plaintext` | **read-only** | none | `global.edge-config.read` **(CCR)** | read-only |
| ACME debug output | A25 | `plaintext` | **read-only** | none | `global.certificate.read` | read-only |
| Structured settings value | A05 | `json` / `yaml` | editable | the field's schema | the panel's `permission` / `writePermission` | read-only |

The three read-only surfaces are read-only by requirement. The OpenAPI document
is generated from the runtime's Zod schemas (REQ-API-01) and the HAProxy config
from the same validated config source as the app (REQ-PROX-04); an editable copy
of either is a second source of truth. The ACME output is a log (REQ-ACME-10).

Two permission strings these surfaces need are **not in the frozen catalogue**:
`i18n.message.read` / `i18n.message.write` (A14) and `global.edge-config.read`
(A01). An unresolved permission denies, so the surface would ship invisible
(`contracts/types/rbac.md` §7). Both are additive CCRs at the freeze, filed by
the owning agent, not by A05.

`sql`, `typescript`, `javascript`, `css` and `xml` are registered with no
shipped surface. That is the registry working: REQ-MON-04 names them, §3's
conformance fixtures exercise them, and the first surface that needs one ships a
declaration and no editor code.

## 2. One component (REQ-MON-01, REQ-MON-02)

`packages/editor` exports `<DocumentEditor surfaceId="canonical.descriptor" />`
and nothing lower-level. Only `packages/editor/src/monaco.ts` may import
`monaco-editor`; `pnpm lint:boundaries` fails on any other importer, which is
also what stops a domain from configuring its own Monaco behind A05's back
(REQ-CTR-01). Highlighting, folding, bracket matching and the diff view follow
the declared `language` id, never content sniffing (REQ-MON-02). The diff view
is the same component in `diff` mode against the stored revision, which is what
makes §10's audit record free rather than a feature.

## 3. Languages and formatters (REQ-MON-03, REQ-MON-04)

| Language | Extensions | Formatter | On demand | On save | On type | Worker |
|---|---|---|---|---|---|---|
| `json` | `.json` | prettier | yes | **yes** | no | json (bundled) |
| `yaml` | `.yaml`, `.yml` | prettier | yes | **yes** | no | monaco-yaml |
| `sql` | `.sql` | sql-formatter | yes | no | no | none |
| `markdown` | `.md` | prettier | yes | no | no | none |
| `typescript` | `.ts`, `.tsx` | prettier | yes | **yes** | no | typescript |
| `javascript` | `.js`, `.mjs` | prettier | yes | **yes** | no | typescript |
| `html` | `.html` | prettier | yes | **yes** | no | html |
| `css` | `.css` | prettier | yes | **yes** | no | css |
| `xml` | `.xml` | prettier-xml | yes | **yes** | no | none |
| `plaintext` | `.txt` | none | — | no | no | none |

Format **on demand is on for every language that has a formatter**, with no
per-surface opt-out. That is REQ-MON-03's "active for every supported file type"
at minimum.

Format **on save is on for machine-shaped documents, off for prose and SQL**. A
descriptor, a template, a stylesheet or an OpenAPI fragment has one correct
shape and a diff nobody argues about. A help topic, an ICU message and a SQL
statement are written by a human mid-thought: reflowing a paragraph or
upper-casing keywords at the moment of save loses the shape the author was
holding, and a formatter that surprises is switched off by the first user it
bites — after which nothing is formatted anywhere. Off for those three is what
keeps the other seven on.

Format **on type is off for all ten**. Prettier and sql-formatter are
whole-document formatters; they cannot format a half-written line, and wiring a
second formatter for the on-type path means two shapes per language. Bracket and
tag auto-closing stay on — an editor option, not a formatter.

```ts
// packages/editor/src/formatters.ts — frozen config (contracts/types/editor.md §3)
prettier:      { printWidth: 100, tabWidth: 2, semi: true, singleQuote: false,
                 trailingComma: "all", proseWrap: "preserve", endOfLine: "lf" }
prettier-xml:  { xmlWhitespaceSensitivity: "ignore", xmlQuoteAttributes: "double" }
sql-formatter: { language: "postgresql", keywordCase: "upper", tabWidth: 2 }
```

`postgresql` because Postgres is the only datastore (REQ-FND-05). Every
formatter runs in a worker: a 4000-line descriptor formatted on the UI thread
drops frames while the user types. Versions live in `versions/manifest.json`
(REQ-FND-06), never in this document. Each language ships a fixture at
`packages/editor/tests/fixtures/<id>.<ext>` that formats, re-formats byte-
identically (`format(format(x)) === format(x)`) and produces no markers, so a
language with no surface is still proven.

## 4. Schema-aware validation (REQ-MON-05)

The worked example is a mapping descriptor (REQ-DAT-03) validated against
`normalizers/descriptor.schema.json`, bound as an object imported at build time
rather than a URL, so validation fetches nothing (§5). An author edits
`normalizers/examples/vendor-a-device.yaml` and types two mistakes:

```yaml
canonicalModel: device                                    # line 3
serial_number: { op: copy, from: serial, cast: string }   # line 27
```

Inline, on the line, while typing:

```
3:17   error  String does not match the pattern "^canonical\.[a-z_]+$"
27:42  error  Property cast is not allowed.  (did you mean "as"?)
```

Both come from the schema: `canonicalModel` carries a `pattern`, and every
transform in `$defs/transform` is `additionalProperties: false`. The squiggle is
on the offending token, the text is in the hover and the problems list, and
**Save is disabled while a schema error stands** on a surface with a `schemaId`.

Client markers are presentation only (REQ-RBA-02). Save re-validates through the
surface's `validateOperation` — for a descriptor, `POST /validate` on the
normalizer engine — which also runs the cross-reference checks a browser cannot:
unknown canonical field, `enum` name with no table, a `from` path colliding with
a canonical column (REQ-DAT-07). A 422 returns `canonical.descriptor_invalid`
with `errors[]: [{ path, rule }]` (`contracts/types/errors.md`); the editor
resolves each `path` against the parsed document to a line and column and sets
markers with `owner: "server"`, kept apart from the client's `owner: "schema"`
set so a re-validate clears the right one.

An after-save toast is the failure mode REQ-MON-05 names, and it is worse than
no validation: the document is already stored, the message has no line number,
the user's next move is a manual hunt, and for a descriptor a bad version has
already become provenance. Errors belong on the line, before the write.

## 5. Self-hosting (REQ-MON-06, REQ-SUP-06, REQ-SUP-07)

The bundler config is where this is won or lost, because the defaults in this
stack point at a CDN.

1. **`@monaco-editor/react` fetches Monaco from `cdn.jsdelivr.net` unless told
   not to** — its `@monaco-editor/loader` dependency loads `min/vs` from jsDelivr
   by default. `packages/editor/src/monaco.ts` imports monaco locally and calls
   `loader.config({ monaco })` before any editor renders. One line, one file, the
   whole requirement.
2. **Workers are ours.** Monaco ships its own; `self.MonacoEnvironment.getWorker`
   returns `new Worker(new URL("monaco-editor/esm/vs/language/json/json.worker",
   import.meta.url))` and the equivalents for css, html, typescript, the editor
   worker and `monaco-yaml`. The bundler emits them as same-origin files.
3. **CSP is the backstop** (REQ-SEC-08): `worker-src 'self'`, `script-src 'self'
   'nonce-…'`, `connect-src 'self'`, `font-src 'self'`. A misconfigured loader
   then fails visibly instead of quietly reaching jsDelivr. The ESM build needs
   no `unsafe-eval`; the AMD loader did, which is the second reason we use ESM.
4. **Fonts.** `fontFamily` is the `--font-mono` token, self-hosted by A06 like
   every other font (`spec/theming.md` §5). Monaco measures glyph widths at
   construction, so the editor mounts behind `document.fonts.ready` and calls
   `monaco.editor.remeasureFonts()` if the font settles late; otherwise the
   cursor sits a fraction of a character off.
5. **JSON language service.** We take **no** `vscode-json-languageservice`
   dependency. Checked 2026-09-21, its npm `latest` dist-tag points at
   `6.0.0-next.3` — a prerelease, forbidden by REQ-VER-01 — and the newest stable
   is `5.7.2`. Monaco's bundled JSON worker already vendors the service at the
   version Monaco was tested against and gives us validation, completion, hover
   and formatting for `json`; a direct dependency would add a second copy for no
   gain. If one is ever forced, pin `5.7.2` and never resolve from `latest`.
   This belongs in `versions/traps.json`, which A20 owns.

None of `monaco-editor`, `prettier` or `sql-formatter` phones home (REQ-SUP-06),
and `pnpm test:egress` is the assertion, not this sentence.

## 6. Weight and lazy loading (REQ-MON-07)

`DocumentEditor` loads through `next/dynamic` at `ssr: false` — Monaco touches
`window` — behind a skeleton sized from the surface's declared height, so the
lazy load shifts nothing (REQ-UI-10). A surface pulls the core, its one language
chunk and its one worker.

| Chunk | Budget (gzip) | Loaded by |
|---|---|---|
| App first-load JS, any route | 300 kB | every route; unchanged by the editor |
| `editor-core` (monaco + wrapper + theme bridge) | 900 kB | a route with a surface, on mount |
| `editor-lang-<id>` | 120 kB | that surface only |
| `json` / `css` / `html` worker | 150 kB each | that surface only |
| `yaml` worker (monaco-yaml, bundles prettier) | 400 kB | yaml surfaces only |
| `typescript` worker | 2.2 MB | the ts/js surfaces only |
| `prettier` worker plus the surface's plugins | 400 kB | on first format |

`pnpm bundle:measure` writes the measured values to
`packages/editor/bundle-budget.json` on the first green build; CI asserts them
from then on, and raising a number needs a line in the hand-off saying why.
"Monaco is big" is not a budget. A route that edits no text pays nothing, and
that is checked: `pnpm test:bundle` walks `.next/app-build-manifest.json` per
route and fails if a chunk matching `monaco|prettier|sql-formatter` appears in
the graph of a route with no declared `EditorSurface`.

## 7. Theming (REQ-MON-08)

Monaco does not read CSS custom properties; its theme API takes literal hex. The
bridge reads the resolved tokens off `document.documentElement` at mount,
converts `oklch()` to sRGB hex in `packages/editor/src/theme/oklch.ts` (40
lines, gamut-clamped, unit-tested against the preset's values — a token that
clips is a test failure, not a quiet shift), and calls
`monaco.editor.defineTheme("app-light" | "app-dark", …)`.

| Monaco key | Token |
|---|---|
| `editor.background`, `editor.foreground` | `--card`, `--card-foreground` |
| `editorLineNumber.foreground` | `--muted-foreground` |
| `editor.selectionBackground`, `editor.lineHighlightBackground` | `--accent`, `--muted` |
| `editorCursor.foreground`, `focusBorder` | `--primary`, `--ring` |
| `editorError.foreground`, `editorWarning.foreground` | `--destructive`, `--chart-4` |
| Token rules: comment, string, number, keyword, type | `--muted-foreground`, `--chart-2`, `--chart-3`, `--primary`, `--chart-5` |

A theme switch is a class change on `<html>` (`spec/theming.md` §4), so the
bridge observes that element's `class` and `data-preset` and re-derives.
Redefining a theme under the same name applies live: no reload, no remount, no
lost cursor position. Stock `vs-dark` beside an emerald mist app is a different
grey, a different keyword blue and a focus ring from another product — the one
place a user would conclude the editor was bolted on, which is what it would be.
Every mapped token is contrast-checked at AA in both themes by the test that
already covers the console and ANSI families (REQ-UI-11).

## 8. Accessibility (REQ-MON-09)

The requirement most often waved through, so it is specified as behaviour with a
test each.

- **Screen-reader mode.** `accessibilitySupport: "auto"` detects most readers,
  but detection fails often enough that it cannot be the only path. The toolbar
  carries a labelled **Screen reader mode** toggle — visible, not in a menu —
  persisted to `user_preferences` as `editor.a11y.screen-reader`, plus
  `accessibilityPageSize: 500` so a reader can page a long document. Monaco's
  `Alt+F1` accessibility help stays bound and is named in the help topic.
- **The Tab trap.** In an editable Monaco, Tab inserts a tab, and a keyboard
  user who cannot leave fails REQ-UI-11. Three exits ship: `Ctrl+M` (`⌃⇧M` on
  macOS) toggles tab-moves-focus; a persistent hint line under the editor states
  that binding as text, not as a tooltip and not only in help; and read-only
  surfaces set `tabFocusMode: true` from the start, since there is nothing to
  indent. Escape closes a widget, and with no widget open moves focus to the
  toolbar.
- **Focus.** Monaco's internal focus is not a visible outline on the container,
  so the container draws a `--ring` focus ring, asserted in both themes.
- **Labelling.** `ariaLabel` per surface from the declaring agent's i18n
  namespace (REQ-I18N-02), never "editor". The problems list is
  `aria-live="polite"`, so a validation error is heard and not only seen.
- **Tested:** a keyboard-only path from the page heading into the editor,
  through it and out to Save, at 1440 in both themes, and axe with zero
  violations (REQ-TST-06).

## 9. Mobile (REQ-MON-10, REQ-MOB-12)

Monaco renders only at `width ≥ 1024` (`laptop`, `spec/screenspace.md` §2) **and**
`(pointer: fine)`. Width alone is the wrong test: an iPad at 1024 is
touch-primary, and Monaco's selection handles, context menus and 12px gutter are
built for a mouse. Between 834 and 1024 a coarse-pointer user gets a per-surface
"Use the full editor anyway" opt-in, persisted; below 834 there is none, because
no width below it would help.

| Kept | Dropped |
|---|---|
| Syntax highlighting, server-rendered — no client highlighter ships | Monaco and every keybinding it carries |
| Validation through the same server `validateOperation`, listed with line numbers, tap to scroll | Inline squiggles, hovers, the problems panel |
| Scrolling, word wrap, copy, and the diff of unsaved against stored | Autocomplete, folding, minimap, multi-cursor, find-and-replace |
| Format on demand, one button | Format on save, format on type |

Editing below the threshold is `plain-edit`: a textarea inside A27's
keyboard-avoidance container with the mobile input affordances (REQ-MOB-02,
REQ-MOB-05, REQ-MOB-06), and allowed **only for prose languages**. A
schema-bound document is read-only on a phone, and assembly rejects the
alternative (`contracts/types/editor.md` §6): editing YAML on a 390px soft
keyboard with no bracket matching and no inline schema errors is how a bad
descriptor reaches provenance, and REQ-MON-01's rejection of a `<textarea>` for
structured content does not stop being true at a breakpoint.

This is a deliberate degradation and the UI says so: every reduced surface
renders its `mobileReasonKey` in place — "Read-only on this screen size. Open on
a larger screen to edit." — which is what REQ-MOB-12 asks for: name the limit,
offer the useful subset.

## 10. Redaction, permissions and audit (REQ-MON-11, REQ-MON-12)

Redaction runs **server-side before the document reaches the model**, from the
surface's `redact` declaration (`contracts/types/editor.md` §5). The client
receives `[redacted]` in place of the value, so there is no hidden text to
select, copy or read out of the DOM. A `revealPermission` holder gets the value;
everyone else gets the placeholder, and on save the server restores every
unmodified placeholder from storage. Reveal and save are both server checks — a
client-side mask is presentation, never enforcement (REQ-RBA-02). The same
declaration feeds the audit diff, so a value cannot be hidden in the editor and
leak through the trail (REQ-AUD-05). A secret does not become visible because it
is inside a config document.

Every save emits one audit event (REQ-AUD-01) with the surface's declared
`action`, `targetKind` and, for a settings surface, `settingsScope`:

```
mail.template.update   actor, tenant, permission=mail.template.write,
                       target={kind:"mail.template", id, label}, correlationId,
                       diff={ before:{…}, after:{…} }, result=success
```

- The diff is the document: up to 64 KiB per side it is the text, above that
  `before`/`after` carry `{ sha256, unifiedDiff }` with the hunks. Both fit the
  frozen `diff: { before: record, after: record }`, so no CCR is needed
  (`contracts/events/audit-event.md` §1).
- A save whose content hash is unchanged emits nothing. A no-op is not an edit,
  and a trail padded with them is a trail nobody reads.
- A formatting-only save is a real diff and is recorded as one — the cost §3's
  on-save defaults are set to keep small.
- Revision timestamps render only through `packages/contracts/time`
  (REQ-TIM-04).

The editor's natural output is a diff. A weaker audit record here than anywhere
else in the app would take effort to achieve.

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Editor | Monaco, ESM build, self-hosted | REQ-MON-01, REQ-MON-06 | No |
| React binding | `@monaco-editor/react`, `loader.config({ monaco })` in one file | Its default is a jsDelivr fetch | No |
| JSON language support | Monaco's bundled JSON worker; no `vscode-json-languageservice` | Its npm `latest` is a prerelease (REQ-VER-01); newest stable 5.7.2 | No |
| YAML | `monaco-yaml`, schema bound as an imported object | The only route to schema-aware YAML, and it fetches nothing | No |
| Formatters | prettier (7 languages), `@prettier/plugin-xml`, sql-formatter | One formatter per language, declared once (REQ-MON-03) | No |
| Format on demand | On for every language with a formatter | REQ-MON-03 | No |
| Format on save | On for json, yaml, ts, js, html, css, xml; off for markdown, sql, plaintext | A formatter that reflows a document mid-thought gets switched off entirely | Yes, per surface, downward |
| Format on type | Off for all ten | A whole-document formatter cannot format a half-written line | No |
| SQL dialect | `postgresql`, `keywordCase: "upper"` | REQ-FND-05 | Yes |
| Monaco threshold | `width ≥ 1024` and `(pointer: fine)` | REQ-MON-10 is about touch, not width | No |
| Mobile editing | `plain-edit` for prose; read-only for schema-bound surfaces | REQ-MON-01, REQ-MON-10 | Yes, may be read-only throughout |
| Document ceiling | 256 KiB default, 1 MiB hard | Above that it is a file transfer | Yes, to the ceiling |
| Screen-reader mode | `auto` plus a visible persisted toggle | Detection fails too often to be the only path | No |
| Audit diff | Text to 64 KiB per side, then hunks plus sha256 | REQ-MON-12 inside the frozen envelope | No |

## How this is verified

- `pnpm test:unit` — `packages/editor/tests/**`: every language resolves a
  formatter and a worker; each conformance fixture formats idempotently (§3);
  `oklch.ts` against the preset values; the `errors[].path` → line/column mapper
  on the descriptor fixture; the placeholder round-trip, including an edited
  placeholder refused.
- `pnpm test:bundle` — §6's table per chunk, and no `monaco|prettier|
  sql-formatter` chunk in the graph of a route with no surface (REQ-MON-07).
- `pnpm test:egress` — no remote origin during an e2e run that opens every
  surface; `grep -rE "jsdelivr|unpkg|cdnjs" .next/` empty (REQ-MON-06,
  REQ-SUP-06, REQ-SUP-07).
- `pnpm test:visual` — the editor at 1440 in both themes against §7's map, AA
  contrast per mapped token, the focus ring visible, and a theme switch with no
  reload and no remount (REQ-TST-03).
- `pnpm test:e2e` — §8's keyboard path with no mouse, `Ctrl+M` releasing Tab;
  at 390 with touch emulation the reduced editor renders, Monaco loads no byte,
  and the reason text is present (REQ-MOB-11, REQ-MON-10).
- `pnpm test:audit` — one event per save with a before/after diff, none for a
  no-op save, no redacted value in any diff (REQ-MON-12, REQ-AUD-05).
- `pnpm check:descriptors` — §4's worked example stays valid against
  `normalizers/descriptor.schema.json` (REQ-DAT-07).
- `GET /api/v1/editor/_selftest` — every language row resolves its formatter and
  worker, every surface's permissions resolve in the `rbac` registry, every
  `schemaId` resolves to a local file, and the loader points at a local Monaco
  (REQ-CTR-08).

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| Is the mapping descriptor editable in-app, or read-only | Editable, `canonical.descriptor.write` with step-up |
| Format on save for markdown and SQL | Off |
| Full-editor opt-in on a coarse-pointer tablet (834–1024) | Offered per surface, persisted |
| Editing on a phone at all | Prose surfaces only; schema-bound surfaces read-only |
| Languages beyond the ten in REQ-MON-04 | None |
| Maximum document size | 256 KiB |
