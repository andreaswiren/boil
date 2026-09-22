# `editor` — language registry, editing surfaces, formatters

**Published by:** A05 (`EditorLanguage`, `FormatterDescriptor`, `EditorSurface`,
`EditorRedaction`). Declared by every domain that opens an editing surface.
Assembled by A02.
**Requirements:** REQ-MON-01 … REQ-MON-12, REQ-RBA-01, REQ-RBA-02, REQ-AUD-04,
REQ-AUD-05, REQ-DAT-07, REQ-MOB-12, REQ-DOC-03, REQ-I18N-05, REQ-CTR-03.
**Consumed by:** A01, A10, A11, A12, A14, A16, A25, and every domain that
contributes a settings field holding a structured document.

**A language is a registry row; a surface is a declaration.** Neither is a
component. `packages/editor` exports one mounted editor
(`<DocumentEditor surfaceId=… />`, REQ-MON-01) and resolves grammar, formatter,
worker, schema, permission, audit action and mobile behaviour from the two
tables below. A domain that needs a second editor has found a missing registry
row. The design and the surface inventory are `spec/editor.md`. `config` on a
formatter is contract, not preference: it decides the bytes every stored
document is written back as.

---

## 1. `EditorLanguageId` (REQ-MON-04)

```ts
// packages/editor/contract.declaration.ts
export const EditorLanguageIdSchema = z.enum([
  "json", "yaml", "sql", "markdown", "typescript",
  "javascript", "html", "css", "xml", "plaintext",
]);
```

The ten REQ-MON-04 names. The id is declared by the surface, never guessed from
content or extension (REQ-MON-02): `extensions` below labels a download and
picks an icon, and detects nothing.

## 2. `EditorLanguage` — the single registry (REQ-MON-03, REQ-MON-04)

```ts
export const EditorLanguageSchema = z.object({
  id: EditorLanguageIdSchema,
  /** Monaco's own id. Equal to `id` for all ten; separate because Monaco's ids
      are its namespace, and a rename there is not a rename here. */
  monacoId: z.string().min(1),
  extensions: z.array(z.string().regex(/^\.[a-z0-9.]+$/)).nonempty(),
  /** null hides the format action. It never means a button that does nothing. */
  formatter: FormatterIdSchema.nullable(),
  formatOnSave: z.boolean(),           // registry default; a surface may lower it (§4)
  formatOnType: z.boolean(),           // stated per language (REQ-MON-03); false for all ten
  schemaBinding: z.enum(["none", "json-schema"]),
  /** Which worker the surface loads. "none" is Monarch highlighting only. */
  worker: z.enum(["none", "json", "yaml", "css", "html", "typescript"]),
}).strict();
```

Highlighting, bracket matching, folding and the diff view are properties of the
editor, not of a row: no flag turns them off, because REQ-MON-02 grants them to
every supported language.

## 3. `FormatterDescriptor`

```ts
export const FormatterIdSchema = z.enum(["prettier", "prettier-xml", "sql-formatter"]);

export const FormatterDescriptorSchema = z.object({
  id: FormatterIdSchema,
  package: z.string().min(1),   // name only; the version is versions/manifest.json (REQ-FND-06)
  languages: z.array(EditorLanguageIdSchema).nonempty(),
  /** Frozen. Changing a value here is breaking — §7. */
  config: z.record(z.unknown()),
  supportsRangeFormat: z.boolean(),
  /** Always a worker: a formatter on the UI thread stalls typing at 4000 lines. */
  runsIn: z.literal("worker"),
}).strict();
```

## 4. `EditorSurface` — how a domain declares one

```ts
export const EditorSurfaceSchema = z.object({
  /** "<domain>.<surface>", globally unique, and the deep-link segment. */
  id: z.string().regex(/^[a-z][a-z0-9-]*\.[a-z][a-z0-9-]*$/),
  agent: z.string().regex(/^A\d{2}$/),
  language: EditorLanguageIdSchema,
  mode: z.enum(["read-only", "editable"]),
  readPermission: PermissionStringSchema,  // deny-by-default; unresolved hides it (REQ-RBA-02)
  writePermission: PermissionStringSchema.nullable(),   // gates save; null iff read-only
  /** JSON Schema `$id`, served from our own origin (REQ-MON-06). Null where none
      exists; requires `schemaBinding: "json-schema"` on the language. */
  schemaId: z.string().nullable(),
  /** Operation id that re-validates server-side. Client markers are presentation only. */
  validateOperation: z.string().nullable(),
  formatOnSave: z.boolean().optional(),   // lowers the language default; never raises it
  maxBytes: z.number().int().positive().max(1_048_576),  // 1 MiB ceiling: larger is a file transfer
  redact: z.array(EditorRedactionSchema).default([]),
  audit: z.object({                       // REQ-MON-12; the editor never invents the name
    action: z.string().regex(/^[a-z][a-z0-9-]*\.[a-z][a-z0-9-]*\.[a-z][a-z0-9-]*$/),
    targetKind: z.string().min(1),
    settingsScope: z.enum(["personal", "tenant", "global"]).nullable(),
  }),
  /** REQ-MON-10 / REQ-MOB-12. "plain-edit" is a textarea over A27's primitives. */
  mobile: z.enum(["read-only", "plain-edit", "hidden"]),
  /** i18n key, rendered to the user. Mandatory: REQ-MOB-12 requires the reduced
      surface to say what it is, in every case. */
  mobileReasonKey: z.string().min(1),
  i18nNamespace: z.string().regex(/^[a-z][a-z0-9]*$/),
  /** Mandatory: a surface without a help topic fails the doc gate (REQ-DOC-03). */
  helpTopicId: z.string().min(1),
}).strict();
```

## 5. `EditorRedaction` (REQ-MON-11)

```ts
export const EditorRedactionSchema = z.object({
  kind: z.enum(["path", "pattern"]),
  /** "path": a JSON Pointer into the parsed document (json, yaml only).
      "pattern": an anchored, backtracking-free regex applied per line. */
  selector: z.string().min(1),
  /** `audit-event.md` §4's vocabulary, deliberately: one declaration feeds the
      editor and the audit diff, and two would drift. */
  mode: z.enum(["drop", "mask", "hash"]),
  revealPermission: PermissionStringSchema.nullable(),   // null: revealed by nobody
  placeholder: z.string().default("[redacted]"),
}).strict();
```

Redaction happens **server-side, before the document reaches the model**: the
client never holds the value, so the mask is not a UI state to defeat
(REQ-RBA-02). The placeholder round-trips — on save the server restores every
unmodified one from storage. An edited placeholder is refused with
`common.validation_failed`, rule `redacted_region_edited`: a caller who cannot
read a secret cannot rewrite it either.

## 6. Collision and consistency rules A02 enforces at assembly

A collision is a **hard failure** naming both claimants, never last-write-wins
(`contracts/README.md` §3).

| Check | Fails when | Why it is fatal |
|---|---|---|
| Duplicate surface or language id | Two declarations share an `id` | The surface id is the deep link and the mount key, so which one renders would depend on collection order; two language rows are two grammars and two formatters for one document (REQ-MON-03) |
| Unresolved permission | `readPermission` or `writePermission` is not in the assembled `rbac` registry | It resolves to deny, so the surface ships invisible with no error |
| Editable without a writer | `mode: "editable"` and `writePermission: null` | The save would run under the read permission, which is the widest audience |
| Schema on a language that has none | `schemaId` set where `schemaBinding: "none"` | The binding would be silently ignored and the surface would ship unvalidated (REQ-MON-05) |
| Structured document on a phone textarea | `mobile: "plain-edit"` with a non-null `schemaId` | A schema-bound document edited with no validation and no bracket matching is REQ-MON-01's `<textarea>` defect wearing a breakpoint |
| Path redaction on an unparsed language | `kind: "path"` where `language` is not `json` or `yaml` | There is no document tree to resolve the pointer against; the declaration would silently redact nothing |
| Foreign audit action | `audit.action`'s first segment is not the declaring agent's domain | The event would be attributed to a domain that did not emit it (REQ-AUD-04) |
| Formatting claimed but absent | `formatOnSave: true` with `formatter: null`, or a surface setting `true` where its language declares `false` | Save would claim a step that does not exist; the registry default is the decision (REQ-MON-03) and a surface may only be more conservative |
| Missing help topic, foreign i18n key | `helpTopicId` not in A16's registry, or `mobileReasonKey` outside `i18nNamespace` | REQ-DOC-03; REQ-I18N-05 |

```bash
jq -r '.declarations[].editorSurfaces[]? | select(.mobile=="plain-edit" and .schemaId!=null) | .id' \
  build/contract-surface.json && echo "SCHEMA-BOUND SURFACE DECLARED PLAIN-EDIT ON MOBILE"
```

## 7. Additive vs breaking

**Additive**
- A new `EditorLanguage` row and a new `FormatterDescriptor` — the point of
  REQ-MON-04: a language is a row plus a formatter, no consumer changes, and no
  second editor is written.
- A new `EditorSurface` in a domain's own namespace; a new optional field on any
  of the four types; lowering a surface's `formatOnSave` to `false`; a new
  redaction declaration, or tightening one from `mask` to `hash` to `drop` — the
  direction `contracts/events/audit-event.md` §7 allows.

Adding a member to `EditorLanguageId` is additive **only because no consumer
switches on it**: behaviour is resolved through the registry row. An exhaustive
`switch` over the enum outside `packages/editor` would make the next language a
breaking change, so `pnpm lint:boundaries` fails on one.

**Breaking**
- **Changing a formatter's output for a language already in use.** No type
  changes, no field moves, and the breaking-change detector (REQ-CTR-07) sees
  nothing: `printWidth: 100` becoming `80` is one edited literal. The damage is
  a diff across every stored document — the next save of each reformats lines
  nobody touched, and REQ-MON-12 makes every save an audited before/after diff,
  so the trail fills with large diffs whose real content is one changed line.
  A mapping descriptor carries `descriptor_hash` into provenance
  (`spec/data-normalization.md` §4), so a reflow rewrites the hash of a
  descriptor whose behaviour did not change. Such a change gets a **new
  `FormatterId`**; languages move to it one at a time and the corpus is
  reformatted once, as a declared migration with one audit event.
- Renaming a surface id, a language id or a formatter id.
- Removing a language from a `FormatterDescriptor.languages`.
- Loosening or removing a redaction declaration — a data-protection regression,
  refused for the reason `audit-event.md` §7 gives (REQ-AUD-05).
- Lowering `maxBytes`: documents already above the new ceiling stop saving, and
  the failure lands on whoever next opens one.
- Making `helpTopicId`, `mobileReasonKey` or `audit` optional.
