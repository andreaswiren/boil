# Canonical Models & Normalization

Integration payloads arrive in whatever shape a vendor chose and leave as
canonical rows. The mapping between the two is versioned data, executed by a
generic engine, and adding a source ships no TypeScript. Owned by **A10**
(`data-normalization`): `packages/canonical/**`, `services/normalizer/**`, and
the tables `canonical_*`, `mapping_descriptors`, `quarantine`, `provenance`.
A10 publishes `canonical-models`, `mapping-descriptor` and `provenance`; it
consumes `entity-base`. A15's collectors and A11's ingest routes are callers;
neither may write a canonical row directly.

## Requirements covered

REQ-DAT-01 … REQ-DAT-08, REQ-ENT-01, REQ-FND-05, REQ-SEC-01, REQ-SEC-12,
REQ-AUD-04, REQ-CTR-01, REQ-CTR-08, REQ-VER-02, REQ-TST-01.

## 1. The canonical model set (REQ-DAT-01)

Seven models, defined once in `packages/contracts` as Zod and mirrored as
`canonical_*` tables carrying the entity envelope. The intake decides which are
instantiated; the definitions ship regardless.

| Model | Table | Identity | Holds |
|---|---|---|---|
| Identity | `canonical_identity` | `(tenant_id, external_key)` | A person or account from a source system, linked to `users` when it resolves |
| Organisation | `canonical_organisation` | `(tenant_id, external_key)` | Customer, department, cost centre |
| Asset | `canonical_asset` | `(tenant_id, external_key)` | Device, host, licence, circuit |
| Ticket | `canonical_ticket` | `(tenant_id, source_system, external_key)` | Case, incident, change |
| Event | `canonical_event` | `(tenant_id, external_key)` | A thing that happened at an instant |
| Metric | `canonical_metric` | `(tenant_id, asset_ref, metric, at)` | A numeric sample |
| Location | `canonical_location` | `(tenant_id, external_key)` | Site, room, rack, coordinates |

Every canonical field name is ours. **No vendor field name reaches a canonical
table** (REQ-DAT-02), and the rule has three teeth:

1. Canonical columns come from `packages/contracts` only. A migration adding a
   column not in the canonical schema fails `pnpm lint:migrations`.
2. **There is no `raw`, `extra`, `vendor_data` or `attributes` jsonb column on a
   canonical table.** That column is how vendor names get in — one team adds
   passthrough "temporarily", and six months later a report reads
   `extra->>'os_ver'`. Unmapped vendor fields stay in the payload store,
   referenced from `provenance` by hash, and are reachable for debugging without
   being queryable as product data.
3. `pnpm check:descriptors` fails if any canonical column name equals a `from`
   path used in any descriptor — a canonical field named after the vendor field
   it came from is the same defect spelled differently.

A source-specific field that genuinely has product meaning is a canonical field
with our name for it, added by an additive CCR. "The vendor calls it `os_ver`"
is not a reason to call it `os_ver`.

## 2. The mapping descriptor (REQ-DAT-03)

A descriptor is YAML, versioned, stored in `normalizers/<system>/<model>.v<N>.yaml`
in the repository and mounted read-only into the engine. It is data: there is no
hook, no callback, no code path a descriptor can reach.

```yaml
descriptor: vendor-a.asset          # <system>.<model>, globally unique
version: 3                          # integer, monotonic; part of provenance
canonical: asset
source:
  system: vendor-a
  payload: json
identity:
  external_key: { from: sn, required: true }   # the source's stable id
fields:
  display_name: { from: name, required: true, transform: [trim] }
  serial:
    from: sn
    required: true
    validate: { pattern: "^[A-Z0-9]{8,32}$" }
  os_version: { from: os_ver, coerce: string }
  status:
    from: status
    coerce: string
    enum:
      map: { "1": online, "0": offline, "2": degraded }
      default: unknown             # explicit, or an unmapped value quarantines
  last_seen_at: { from: last_seen, coerce: { epoch_seconds: utc } }
  site_ref:
    from: site
    object:
      external_key: { from: id, required: true }
      label:        { from: label }
computed:
  freshness:
    expr: "'fresh' if age_seconds(last_seen_at) < 900 else 'stale'"
    inputs: [last_seen_at]         # closed input list; no free variables
on_error: quarantine               # the only other value is `reject`
```

### The same canonical model, a second vendor

Vendor B sends different names, different types and different enum values. Only
the descriptor differs; the canonical row is identical in shape.

```yaml
descriptor: vendor-b.asset
version: 1
canonical: asset
source: { system: vendor-b, payload: json }
identity:
  external_key: { from: serialNumber, required: true }
fields:
  display_name: { from: hostname, required: true, transform: [trim] }
  serial:       { from: serialNumber, required: true,
                  validate: { pattern: "^[A-Z0-9]{8,32}$" } }
  os_version:   { from: firmware.version, coerce: string }   # dotted path
  status:
    from: state
    transform: [lower]
    enum:
      map: { online: online, offline: offline, reboot: degraded, unknown: unknown }
      default: unknown
  last_seen_at: { from: lastCheckin, coerce: { iso8601: utc } }
  site_ref:
    object:
      external_key: { from: locationId, required: true }
      label:        { from: location }
computed:
  freshness:
    expr: "'fresh' if age_seconds(last_seen_at) < 900 else 'stale'"
    inputs: [last_seen_at]
on_error: quarantine
```

### Two payloads in, one canonical row shape out

```jsonc
// vendor-a
{ "name": "fw-sto-01 ", "sn": "FGT60F1234", "os_ver": "7.4.3",
  "status": 1, "last_seen": 1758441600, "site": { "id": "S-12", "label": "Stockholm HQ" } }
// vendor-b
{ "hostname": "fw-sto-01", "serialNumber": "FGT60F1234",
  "firmware": { "version": "7.4.3" }, "state": "ONLINE",
  "lastCheckin": "2026-09-21T08:00:00Z", "locationId": "S-12", "location": "Stockholm HQ" }
```

Both normalise to:

```jsonc
{ "externalKey": "FGT60F1234", "displayName": "fw-sto-01", "serial": "FGT60F1234",
  "osVersion": "7.4.3", "status": "online", "lastSeenAt": "2026-09-21T08:00:00Z",
  "siteRef": { "externalKey": "S-12", "label": "Stockholm HQ" },
  "freshness": "fresh" }
```

What each mechanism did: **field mapping** moved `name`/`hostname` to
`displayName`; **type coercion** turned an epoch integer and an ISO string into
the same UTC instant; **enum normalization** turned `1` and `"ONLINE"` into
`online` through per-vendor maps onto our closed vocabulary; the **computed
field** derived `freshness` from a declared input list.

### A required-field failure

Vendor B omits `serialNumber` on one record:

```jsonc
// POST /normalize → 422
{ "outcome": "quarantined",
  "reason": "required_field_missing",
  "path": "identity.external_key",
  "detail": "serialNumber is absent and identity.external_key is required",
  "descriptor": "vendor-b.asset", "version": 1,
  "descriptorHash": "sha256:41c9…", "payloadHash": "sha256:8ab2…",
  "quarantineId": "q-0f31…" }
```

No canonical row is written. Nothing is guessed, nothing is defaulted, the
record is not dropped (REQ-DAT-06). A mapping that coerced a missing identity
into an empty string would create one canonical row that every unidentifiable
record from that vendor collapses into — a silent data merge, which is worse
than a visible failure.

## 3. The engine (REQ-DAT-04)

`services/normalizer/` — Python, FastAPI + Pydantic v2, uvicorn, versions from
`versions/manifest.json` (REQ-VER-02). It is generic: it contains no vendor
name, no model-specific branch and no descriptor. It is a separate service so a
mapping author edits YAML and reloads, with no Next.js build.

```
POST /normalize          {descriptor, version?, tenantId, receivedAt, payload}
                         → 200 {canonical, provenance} | 422 {quarantine}
POST /normalize/batch    NDJSON in / NDJSON out, ≤ 1000 records, per-record outcome
GET  /descriptors        loaded descriptors: name, version, sha256
POST /descriptors/reload → {loaded: [...], errors: [...]}  (§ hot reload)
GET  /healthz            liveness
GET  /readyz             ready only when ≥ 1 descriptor is loaded and valid
```

- mTLS on the compose network with the stack's own CA; the service publishes no
  host port and is unreachable from outside (REQ-SEC-01, REQ-SEC-03).
- The engine **never writes to Postgres**. It returns a canonical object and the
  app writes it through the DAL, so RLS, the entity envelope and the actor
  columns apply exactly as they do to a human write (`spec/entity-model.md` §4).
  A service with its own database credentials would be a second write path with
  its own idea of tenancy.
- The engine makes no outbound call. Fetching a lookup table from a vendor at
  normalisation time would make the same input produce different output
  (REQ-DAT-08) and would put an SSRF target inside the parser (REQ-SEC-12).

**Hot reload.** Descriptors are mounted read-only and reloaded by `POST
/descriptors/reload` or on file change:

1. Parse **every** file, validate every one against the canonical schema.
2. On any error, keep the current registry and return the errors. A partial
   registry is how one bad edit stops an unrelated source.
3. On success, swap the whole registry atomically under a lock; in-flight
   requests finish on the registry they started with.
4. The reload is audited as `normalizer.descriptor.reload` with the loaded set
   and each file's sha256.

The **hash**, not only the version, goes into provenance: a version number is
what an author remembered to bump, a hash is what actually ran.

## 4. Provenance (REQ-DAT-05)

```sql
provenance (A10)  -- immutable; exempt from the envelope (entity-base.md §6)
  id, tenant_id, canonical_table, canonical_id,
  source_system text not null, source_id text not null,
  source_payload_hash bytea not null,      -- sha256 of canonical JSON of the raw payload
  descriptor text not null, descriptor_version int not null,
  descriptor_hash bytea not null,
  engine_version text not null,
  received_at timestamptz not null,        -- when the payload reached us
  normalised_at timestamptz not null,      -- when this row was produced
  unique (canonical_table, canonical_id, source_payload_hash)
```

Every canonical row has at least one provenance row and answers, without
guessing: which system said this, which record of theirs, exactly which bytes,
which mapping and which build. The unique constraint makes re-ingestion
idempotent — the same payload through the same descriptor produces no second
row, which is what lets a collector retry freely (REQ-OBS-05). A descriptor
change produces a new provenance row against the same canonical row, so the
history of *how* a row was derived is itself a trail.

Raw payloads live in a payload store keyed by `source_payload_hash`, retained 90
days, readable only with `normalizer.payload.read`, and excluded from the debug
console. They are untrusted input that may contain PII, kept because a mapping
cannot be fixed against a payload nobody has, and fenced because they are not
redacted (`spec/observability.md` §4).

## 5. Quarantine (REQ-DAT-06)

Unmappable input is quarantined with a reason. It is never dropped and never
coerced into a shape that parses.

```sql
quarantine (A10)
  id, tenant_id, source_system, descriptor, descriptor_version, descriptor_hash,
  reason text not null, path text, detail text,
  payload_hash bytea not null, received_at timestamptz not null,
  retry_count int not null default 0, resolved_at timestamptz, resolution text
```

| `reason` | Means | Usual fix |
|---|---|---|
| `required_field_missing` | A required canonical or identity field has no value | Fix the descriptor, or the source |
| `type_coercion_failed` | `"abc"` into a number, an unparseable date | Add or correct a `coerce` |
| `enum_unmapped` | A source value outside the map, with no `default` | Extend the map deliberately |
| `validation_failed` | A `pattern`, range or length rule rejected the value | Decide whether the rule or the data is wrong |
| `unknown_descriptor` | No descriptor for that `(system, model)` at that version | Ship the descriptor |
| `schema_violation` | The produced object failed the canonical Zod schema | A descriptor bug CI should have caught (§6) |
| `payload_too_large` / `payload_too_deep` | Resource limits (§7) | Usually a hostile or broken producer |
| `engine_error` | An unexpected exception | An engine bug; the traceback goes to the log, never to the response |

The quarantine UI is a grid (`spec/datagrid.md`) with `normalizer.quarantine.read`:
group by reason, see the failing path, view the payload with
`normalizer.payload.read`, and retry a record or a whole reason class after a
descriptor fix. A retry is a fresh normalisation, not a patch — `retry_count`
increments and success sets `resolved_at`. Quarantine depth and its oldest
entry are exposed by `/readyz` and alerted on, because a quarantine nobody
watches is a queue where data goes to be forgotten.

## 6. CI validation of descriptors (REQ-DAT-07)

`pnpm check:descriptors` runs on every commit, against the JSON Schema generated
from the canonical Zod models — so the check cannot drift from the schema it
checks against (REQ-CTR-06).

| Check | Fails when |
|---|---|
| Parses | The YAML is invalid or has an unknown top-level key |
| Target exists | `canonical:` names a model that does not exist |
| **Field exists** | A target field is not in the canonical schema — "a descriptor that would write an unknown field fails the build" (REQ-DAT-07) |
| Type compatible | A `string`-coerced value maps onto a `timestamptz` target, or a numeric target has no numeric coercion |
| Required covered | A required canonical field is unmapped and has no default |
| Enum total | An `enum.map` has no `default` and does not cover the declared source vocabulary |
| Identity present | `identity.external_key` is missing or not required |
| Expression safe | A `computed.expr` uses a name outside `inputs`, a function outside the table, or any attribute access, call, comprehension or import (§7) |
| Version monotonic | `version` is not greater than the highest committed version for that descriptor |
| No vendor leak | A canonical column name equals a `from` path anywhere (§1) |
| Round-trips | Each descriptor's committed example fixtures normalise to the committed expected output, byte for byte |

Every descriptor ships with at least one success fixture and one quarantine
fixture. A descriptor with no fixture fails the check: the worked example above
is the documentation, and an undocumented mapping is unreviewable.

## 7. Determinism and fuzzing (REQ-DAT-08)

**Determinism.** Same payload + same descriptor bytes = same output, always.
Guaranteed by construction:

- No clock. `age_seconds()` measures against `receivedAt`, which is an input on
  the request, not `datetime.now()`. A `now()` function does not exist in the
  expression table, and a descriptor cannot obtain one.
- No randomness, no uuid generation, no iteration-order dependence — the engine
  walks descriptor fields in declared order and serialises with sorted keys.
- No network, no filesystem and no database in the normalisation path.
- Floats are never used for money or for anything compared for equality;
  decimal targets are parsed to `Decimal` and emitted as strings.
- The expression evaluator walks a whitelisted AST: names from `inputs` only,
  the function table (`age_seconds`, `lower`, `upper`, `trim`, `coalesce`,
  `concat`, `slice`, `int`, `round`, `len`, `startswith`, `contains`), the
  comparison and boolean operators, and a conditional expression. No attribute
  access, no subscripting of arbitrary objects, no calls to anything else, no
  comprehensions, no imports, no `eval`, no `exec`. A descriptor is data, and
  `eval` on a descriptor would make it code with a YAML syntax.

**Fuzzing posture.** The engine parses untrusted input from third-party systems.
It is treated as a parser, not as business logic.

| Target | Tool | Budget | Corpus |
|---|---|---|---|
| Payload normalisation | Atheris (libFuzzer) | 60 s per target in CI, 4 h nightly | Seeded with every committed vendor fixture, plus mutations |
| Descriptor loading | Atheris | 60 s / 4 h | Every committed descriptor, plus mutations |
| Properties | Hypothesis | Per CI run | Generated payloads against generated descriptors |

Properties asserted:

1. **Determinism** — normalising twice yields identical bytes.
2. **Two outcomes only** — a record either produces an object that validates
   against the canonical schema, or produces a quarantine row with a reason.
   There is no third outcome, and in particular no partially written row.
3. **No escape** — no input causes an unhandled exception, a non-`422` 5xx, or a
   process exit. An unexpected exception becomes `engine_error`.
4. **Bounded** — payload ≤ 1 MiB, nesting depth ≤ 32, ≤ 10 000 keys, ≤ 1 000
   records per batch, 2 s per record CPU limit. Exceeding a bound quarantines;
   it never OOMs the container.
5. **No amplification** — output size is bounded by the descriptor's field
   count, not by input size, so a 1 MiB payload cannot produce a 100 MiB row.

Every crasher and every failing property case is committed as a regression
fixture, so the corpus grows and a fixed bug stays fixed.

## Decisions and defaults

| Decision | Choice | Why | Intake-overridable? |
|---|---|---|---|
| Canonical models | The seven in §1, in `packages/contracts` | REQ-DAT-01 | Yes, which are instantiated |
| Vendor field names | Never on a canonical table | REQ-DAT-02 | No |
| Passthrough jsonb column | Does not exist | It is the loophole REQ-DAT-02 closes | No |
| Mapping | YAML descriptors, versioned, in-repo | REQ-DAT-03 — adding a source ships no TypeScript | No |
| Descriptor identity in provenance | Name, version **and** sha256 | A version is what someone remembered to bump | No |
| Engine | Python, FastAPI, at `services/normalizer/` | REQ-DAT-04 | No |
| Engine database access | None — it returns objects, the app writes them | One write path, one tenancy implementation | No |
| Engine outbound calls | None | Determinism and SSRF surface | No |
| Transport | mTLS on the internal network, no published port | REQ-SEC-01 | No |
| Hot reload | All-or-nothing registry swap; errors keep the old registry | One bad edit must not break other sources | No |
| Unmappable input | Quarantined with a reason, never dropped or coerced | REQ-DAT-06 | No |
| Missing identity | Quarantine, never an empty-string key | Silent merge into one row | No |
| Raw payload retention | 90 days, permission-gated, unredacted, off the console | A mapping cannot be fixed without the payload | Yes |
| Expression language | Whitelisted AST, closed function table, no clock | A descriptor must stay data | No |
| Fuzzing | Atheris + Hypothesis, 60 s in CI, 4 h nightly | REQ-DAT-08 — it is a parser | Yes, budget only |
| Resource bounds | 1 MiB, depth 32, 10k keys, 1k batch, 2 s CPU | A hostile producer is the normal case | Yes |

## How this is verified

- `pnpm check:descriptors` — the eleven checks in §6, including the committed
  example fixtures round-tripping byte for byte (REQ-DAT-07).
- `pnpm test:normalizer` — `services/normalizer/tests/**`: the §2 worked
  example, both vendors onto one canonical shape; every `reason` in §5 produced
  by a crafted payload; the required-field failure returning exactly the 422
  body shown; hot reload with one broken file leaving the registry intact.
- `pnpm test:fuzz` — the three targets in §7 at the CI budget, properties 1–5
  asserted, regression corpus replayed on every run.
- `pnpm test:integration` — `tests/integration/normalizer/**`: a normalised
  record written through the DAL lands in the right tenant under RLS and carries
  the envelope; re-ingesting the same payload writes no second provenance row;
  a quarantine retry after a descriptor fix succeeds and sets `resolved_at`.
- `pnpm test:e2e` — `tests/e2e/quarantine/**`: the quarantine grid groups by
  reason, the payload view requires `normalizer.payload.read`, and a retry of a
  reason class reports per-record outcomes.
- `pnpm test:contract` — `packages/contracts/tests/canonical.spec.ts`: every
  canonical model's Zod schema and its `canonical_*` table agree column for
  column; no canonical table has a passthrough jsonb column; the generated JSON
  Schema the descriptor check uses is generated from those Zod models
  (REQ-CTR-06, REQ-CTR-10).
- `GET /api/v1/normalizer/_selftest` — the engine is reachable over mTLS, the
  loaded descriptor set and hashes match the repository, quarantine depth and
  oldest entry are reported (REQ-CTR-08).

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| Which canonical models are instantiated | Asset, location and event; the rest ship as definitions |
| Integrations to normalise | None at first; the engine and the descriptor format ship regardless |
| Raw payload retention | 90 days |
| Quarantine alert threshold | Any record older than 24 h, or depth > 1 000 |
| Who may read raw payloads | `normalizer.payload.read`, global tier only |
| Nightly fuzz budget | 4 hours per target |
