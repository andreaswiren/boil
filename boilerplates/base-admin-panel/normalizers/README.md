# Normalizers

The mapping engine that keeps the canonical data models product- and
integration-agnostic. Owned by **A10 data-normalization**.

Requirements: REQ-DAT-01 … REQ-DAT-08.

## The rule this directory exists to enforce

**Adding an integration ships no TypeScript.** A new source system is a new
*descriptor* — versioned declarative data validated against
`descriptor.schema.json` — executed by a generic engine. If onboarding a vendor
requires a code change, the design has failed (REQ-DAT-03).

The engine is a lightweight Python service at `services/normalizer/`
(REQ-DAT-04). Python because descriptors are authored and reloaded far more often
than the app is rebuilt, and the engine's whole job is to be a boring,
hot-reloadable, deterministic transformer.

## Engine contract

```
POST /normalize
  { "source": "vendor-a", "descriptorVersion": "3", "payload": { ... } }
  → 200 { "canonical": { ... }, "provenance": { ... } }
  → 422 { "quarantine": { "reason": "...", "field": "...", "value": "..." } }

POST /validate      descriptor → schema check, no data
GET  /descriptors   loaded descriptors with their versions and hashes
POST /reload        re-read the descriptor directory
GET  /healthz
```

Hard properties, all tested (REQ-DAT-08):

- **Deterministic.** Same payload plus same descriptor equals same output. No
  clock, no randomness, no network, no database inside a transform.
- **Side-effect free.** The engine returns a value. Persistence is the caller's.
- **Untrusted-input parser.** Vendor payloads are hostile input. The engine is
  fuzz-tested with Hypothesis and must never hang, recurse without bound, or
  consume unbounded memory on a malformed document.

## Quarantine, never coerce

Unmappable input is quarantined with a reason (REQ-DAT-06). It is never dropped
and never forced into a wrong shape. A missing required field, an enum value with
no mapping, a type that will not coerce — each returns 422 with the offending
field and value, and the caller writes a `quarantine` row.

Silently coercing `"unknown"` to `null`, or an unrecognised status to `"active"`,
is the failure this requirement exists to prevent. It produces a database that
looks clean and is wrong.

## Provenance

Every normalised record carries where it came from (REQ-DAT-05):

| Field | Meaning |
|-------|---------|
| `sourceSystem` | The descriptor's `source` id |
| `sourceId` | The record's identity in the source system |
| `sourcePayloadHash` | SHA-256 of the canonicalised raw payload |
| `descriptorVersion` | Which descriptor produced this |
| `normalisedAt` | UTC `timestamptz` |

`sourcePayloadHash` plus `descriptorVersion` make a re-normalisation auditable:
you can prove which mapping produced a given row, and detect when re-running a
newer descriptor over the same payload would change it.

## Files

| File | What |
|------|------|
| `descriptor.schema.json` | JSON Schema for a mapping descriptor. CI validates every descriptor against it (REQ-DAT-07). |
| `examples/vendor-a-device.yaml` | A flat vendor payload mapped to `canonical.device`. |
| `examples/vendor-b-device.yaml` | A differently-shaped vendor payload mapped to the *same* canonical model. |

The two examples exist together on purpose: they are the proof that the canonical
model is genuinely vendor-agnostic (REQ-DAT-02). If a second vendor cannot reach
the same model without changing it, the model was a copy of the first vendor's
schema.

## Transform vocabulary

Deliberately small. A descriptor is configuration, not a scripting language — a
Turing-complete transform language would reintroduce the code it exists to
remove.

| Transform | Purpose |
|-----------|---------|
| `copy` | Move a value, with optional type coercion |
| `const` | Set a fixed value |
| `map` | Enum translation through an explicit table |
| `concat` | Join fields with a separator |
| `split` | Take an indexed part of a delimited string |
| `coerce` | `string`/`int`/`float`/`bool`/`timestamp`/`ipv4`/`ipv6`/`mac` |
| `default` | Fallback when the source field is absent — **not** when it fails to coerce |
| `lookup` | Resolve a reference against an already-normalised canonical table |
| `template` | Interpolate named source fields into a string |

`default` applying only to an *absent* field is the important distinction. A
present-but-invalid value is a quarantine, not a default. Collapsing those two
cases is how bad data gets laundered into a clean-looking table.

## Adding a source

1. Write the descriptor. Start from the closest example.
2. `POST /validate` — schema check.
3. Run it over real sample payloads and read the output. Every field that came
   out `null` is a question, not a pass.
4. Add the samples as fixtures so the descriptor is regression-tested.
5. Bump `version` in the descriptor. Versions are immutable: a changed mapping
   is a new version, because `descriptorVersion` is provenance.

No step in that list is a code change.
