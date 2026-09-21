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
REQ-AUD-04, REQ-SET-05, REQ-CTR-01, REQ-CTR-08, REQ-VER-02, REQ-TST-01.

## 1. The canonical model set (REQ-DAT-01)

The models, their shape and the rule that defines "canonical" are frozen in
`contracts/types/canonical-models.md`. Six ship as definitions; A00 resolves
which a build instantiates. Each extends the entity envelope and carries
`provenance`, nullable — a device a technician typed in by hand has no source
system, and pretending it does would make the field a lie.

| Model | Table | Identity | Not to be confused with |
|---|---|---|---|
| `canonical.organisation` | `canonical_organisation` | `(tenant_id, external_key)` | `tenants` — a tenant is an isolation boundary, an organisation is data inside one |
| `canonical.identity` | `canonical_identity` | `(tenant_id, external_key)` | `users` — A03 owns login identity; this is the directory record an integration syncs |
| `canonical.location` | `canonical_location` | `(tenant_id, external_key)` | — |
| `canonical.device` | `canonical_device` | `(tenant_id, external_key)` | — the worked example below |
| `canonical.event` | `canonical_event` | `(tenant_id, external_key)` | `audit_events` — that is *our* trail, chained and append-only |
| `canonical.metric` | `canonical_metric` | `(tenant_id, device_ref, metric, at)` | — unit is mandatory; a bare number is unmappable |

The `identity`/`users` and `event`/`audit_events` collapses are the two that
look tidy and are not: the first puts a synced directory record where login
authority lives, the second puts vendor data inside the tamper-evident trail.

**A model is canonical when a second, differently-shaped vendor maps onto it
without changing it.** If onboarding vendor B needs a new field, the model was
a copy of vendor A's schema wearing a different name — a finding against the
model, not against the vendor.

**No vendor field name reaches a canonical table** (REQ-DAT-02). Three teeth:

1. Canonical columns come from `packages/contracts` only. A migration adding a
   column not in the canonical schema fails `pnpm lint:migrations`.
2. **There is no `raw`, `extra`, `vendor_data` or `attributes` jsonb column on a
   canonical table.** That column is how vendor names get in: one team adds
   passthrough "temporarily", and six months later a report reads
   `extra->>'os_ver'`. Unmapped vendor fields stay in the payload store,
   referenced from `provenance` by hash — reachable for debugging, not
   queryable as product data.
3. `pnpm check:descriptors` fails if a canonical column name equals a `from`
   path used in any descriptor. A canonical field named after the vendor field
   it came from is the same defect spelled differently.

Enum fields are canonical too (`canonical-models.md` §4): each declares a closed
value set, and a descriptor's `map` must land on one of them or the record
quarantines. `DeviceLifecycle` is `staging | active | repair | retired`.

## 2. The mapping descriptor (REQ-DAT-03)

A descriptor is YAML, versioned, living at
`normalizers/<system>/<model>.v<N>.yaml`, mounted read-only into the engine. The
two worked examples live at `normalizers/examples/` because
`contracts/types/canonical-models.md` §1 requires two dissimilar payloads
mapping onto `canonical.device` as the standing proof that the model is
canonical. A descriptor is data: there is no hook, no callback, no code path it
can reach.

```yaml
descriptor: vendor-a.device         # <system>.<model>, globally unique
version: 3                          # integer, monotonic; part of provenance
canonical: device
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
  lifecycle:
    from: status
    coerce: string
    enum:
      map: { "1": active, "0": retired, "2": repair }   # lands on DeviceLifecycle
  last_seen_at: { from: last_seen, coerce: { epoch_seconds: utc } }
  location_ref:
    lookup:
      model: canonical.location
      by: external_key
      from: site.id
      label_from: site.label            # used when the lookup creates a stub
      on_missing: stub                  # stub | quarantine
computed:
  freshness:
    expr: "'fresh' if age_seconds(last_seen_at) < 900 else 'stale'"
    inputs: [last_seen_at]              # closed input list; no free variables
on_error: quarantine                    # the only other value is `reject`
```

There is **no `default` on an enum map**. A source value outside the map
quarantines with `enum_unmapped`, because the canonical value set is closed and
inventing an `unknown` member to absorb surprises is how a lifecycle field ends
up meaning "we did not look".

### The same canonical model, a second vendor

Vendor B sends different names, different types, different enum values and a
nested path. Only the descriptor differs.

```yaml
descriptor: vendor-b.device
version: 1
canonical: device
source: { system: vendor-b, payload: json }
identity:
  external_key: { from: serialNumber, required: true }
fields:
  display_name: { from: hostname, required: true, transform: [trim] }
  serial:       { from: serialNumber, required: true,
                  validate: { pattern: "^[A-Z0-9]{8,32}$" } }
  os_version:   { from: firmware.version, coerce: string }   # dotted path
  lifecycle:
    from: state
    transform: [lower]
    enum:
      map: { online: active, offline: retired, reboot: repair, rma: repair }
  last_seen_at: { from: lastCheckin, coerce: { iso8601: utc } }
  location_ref:
    lookup:
      model: canonical.location
      by: external_key
      from: locationId
      label_from: location
      on_missing: stub
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
  "osVersion": "7.4.3", "lifecycle": "active",
  "lastSeenAt": "2026-09-21T08:00:00Z",
  "locationRef": { "externalKey": "S-12", "label": "Stockholm HQ" },
  "freshness": "fresh" }
```

What each mechanism did: **field mapping** moved `name`/`hostname` onto
`displayName`; **type coercion** turned an epoch integer and an ISO string into
the same UTC instant (RFC 3339 `Z`, REQ-TIM-03); **enum normalization** turned
`1` and `"ONLINE"` into `active` through per-vendor maps onto a closed canonical
set; the **lookup** resolved two differently-shaped site references to one
`canonical.location`; the **computed field** derived `freshness` from a declared
input list.

### A required-field failure

Vendor B omits `serialNumber` on one record:

```jsonc
// POST /normalize → 422
{ "outcome": "quarantined",
  "reason": "required_field_missing",
  "path": "identity.external_key",
  "detail": "serialNumber is absent and identity.external_key is required",
  "descriptor": "vendor-b.device", "version": 1,
  "descriptorHash": "sha256:41c9…", "payloadHash": "sha256:8ab2…",
  "quarantineId": "q-0f31…" }
```

No canonical row is written. Nothing is guessed, nothing is defaulted, the
record is not dropped (REQ-DAT-06). A mapping that coerced a missing identity
into an empty string would create one canonical row into which every
unidentifiable record from that vendor collapses — a silent data merge, which is
worse than a visible failure.

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
4. The reload is audited as `canonical.descriptor.reload` with the loaded set
   and each file's sha256; publishing a new descriptor version needs
   `canonical.descriptor.write`.

The reload and the loaded descriptor set are surfaced on the **global** settings
panel A10 contributes — normalizer mappings are global scope, not tenant, because
a descriptor is code-shaped data that governs every tenant's ingest (REQ-SET-05,
REQ-SET-08).

The **hash**, not only the version, goes into provenance: a version number is
what an author remembered to bump, a hash is what actually ran.

## 4. Provenance (REQ-DAT-05)

`CanonicalBase.provenance` is the frozen read shape — `sourceSystem`,
`sourceId`, `sourcePayloadHash`, `descriptorVersion`, `normalisedAt` — nullable
for an in-app record. The `provenance` table is the durable record it is
projected from, and it holds three fields more:

```sql
provenance (A10)  -- immutable; exempt from the envelope (entity-base.md §6)
  id, tenant_id, canonical_table, canonical_id,
  source_system text not null, source_id text not null,
  source_payload_hash bytea not null,      -- sha256 of canonical JSON of the raw payload
  descriptor text not null, descriptor_version int not null,
  descriptor_hash bytea not null,          -- additive: the bytes that actually ran
  engine_version text not null,            -- additive: which build produced it
  received_at timestamptz not null,        -- when the payload reached us
  normalised_at timestamptz not null,
  unique (canonical_table, canonical_id, source_payload_hash)
```

`descriptor_hash` and `engine_version` are A10's additive fields on top of the
frozen shape: a version number is what an author remembered to bump, a hash is
what actually ran, and without the engine version a determinism regression
cannot be attributed to a build. `mapping_descriptors` records the loaded set —
name, version, sha256, loaded_at — so provenance references a descriptor the
system can still identify after the file moved.

The unique constraint makes re-ingestion idempotent: the same payload through
the same descriptor writes no second row, which is what lets a collector retry
freely (REQ-OBS-05). A descriptor change writes a **new** provenance row against
the same canonical row, so how a row came to look the way it does is itself a
trail.

Raw payloads live in a payload store keyed by `source_payload_hash`, retained 90
days, excluded from the console stream. They are untrusted input that may
contain PII, kept because a mapping cannot be fixed against a payload nobody
has, and fenced because they are **not** redacted. Reading one needs
`canonical.payload.read`, which the initial registry does not contain — A10
declares it as an additive CCR at the freeze, global tier, audited per read.

## 5. Quarantine (REQ-DAT-06)

Unmappable input is quarantined with a reason. It is never dropped and never
coerced into a shape that parses.

```sql
quarantine (A10)
  id, tenant_id, source_system, descriptor, descriptor_version, descriptor_hash,
  reason text not null, path text, detail text,
  payload_hash bytea not null, received_at timestamptz not null,
  replay_count int not null default 0, resolved_at timestamptz, resolution text
  -- entity-base minus updated_by/deleted_by (entity-base.md §6)
```

| `reason` | Means | Usual fix |
|---|---|---|
| `required_field_missing` | A required canonical or identity field has no value | Fix the descriptor, or the source |
| `type_coercion_failed` | `"abc"` into a number, an unparseable date | Add or correct a `coerce` |
| `enum_unmapped` | A source value outside the map, and there is no default by design | Extend the map deliberately |
| `validation_failed` | A `pattern`, range or length rule rejected the value | Decide whether the rule or the data is wrong |
| `lookup_missing` | A `lookup` target does not exist and `on_missing: quarantine` | Ingest the referenced model first |
| `unknown_descriptor` | No descriptor for that `(system, model)` at that version | Ship the descriptor |
| `schema_violation` | The produced object failed the canonical schema | A descriptor bug CI should have caught (§6) |
| `payload_too_large` / `payload_too_deep` | Resource limits (§7) | Usually a hostile or broken producer |
| `engine_error` | An unexpected exception | An engine bug; the traceback goes to the log, never to the response |

The quarantine UI is a grid (`spec/datagrid.md`) behind
`canonical.quarantine.read`: group by reason, see the failing path, view the
payload with `canonical.payload.read`, and **replay** a record or a whole reason
class after a descriptor fix under `canonical.quarantine.replay`. A replay is a
fresh normalisation, not a patch — `replay_count` increments and success sets
`resolved_at`. Quarantine depth and its oldest entry are reported by `/readyz`
and alerted on, because a quarantine nobody watches is a queue where data goes
to be forgotten.

## 6. CI validation of descriptors (REQ-DAT-07)

`pnpm check:descriptors` runs on every commit, against the JSON Schema generated
from the canonical Zod models — so the check cannot drift from the schema it
checks against (REQ-CTR-06).

| Check | Fails when |
|---|---|
| Parses | The YAML is invalid or has an unknown top-level key |
| Target exists | `canonical:` names a model that is not in the frozen set |
| **Field exists** | A target field is not in the canonical schema — "a descriptor that would write an unknown field fails the build" (REQ-DAT-07) |
| Type compatible | A `string`-coerced value maps onto a `timestamptz` target, or a numeric target has no numeric coercion |
| Required covered | A required canonical field is unmapped and has no default |
| Enum lands canonical | An `enum.map` value is not a member of the target field's declared value set (`canonical-models.md` §4) |
| Identity present | `identity.external_key` is missing or not required |
| Expression safe | A `computed.expr` uses a name outside `inputs`, a function outside the table, or any attribute access, call, comprehension or import (§7) |
| Version monotonic | `version` is not greater than the highest committed version for that descriptor |
| No vendor leak | A canonical column name equals a `from` path anywhere (§1) |
| Lookup resolvable | A `lookup.model` is not a canonical model, or `by` is not one of its identity fields |
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
   process exit. An unexpected exception becomes `engine_error`, surfaced to the
  caller as `canonical.normalization_failed` (422) — codes live in the
  `canonical` namespace, never a `normalizer` one, because the error taxonomy's
  namespaces are the domain names of `contracts/types/rbac.md` §6.
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
| Canonical models | The frozen six, in `packages/contracts` | REQ-DAT-01 | Yes, which are instantiated |
| Vendor field names | Never on a canonical table | REQ-DAT-02 | No |
| Passthrough jsonb column | Does not exist | It is the loophole REQ-DAT-02 closes | No |
| Mapping | YAML descriptors, versioned, in-repo | REQ-DAT-03 — adding a source ships no TypeScript | No |
| Descriptor identity in provenance | Name, version **and** sha256, plus the engine version | A version is what someone remembered to bump | No |
| Engine | Python, FastAPI, at `services/normalizer/` | REQ-DAT-04 | No |
| Engine database access | None — it returns objects, the app writes them | One write path, one tenancy implementation | No |
| Engine outbound calls | None | Determinism and SSRF surface | No |
| Transport | mTLS on the internal network, no published port | REQ-SEC-01 | No |
| Hot reload | All-or-nothing registry swap; errors keep the old registry | One bad edit must not break other sources | No |
| Unmappable input | Quarantined with a reason, never dropped or coerced | REQ-DAT-06 | No |
| Missing identity | Quarantine, never an empty-string key | Silent merge into one row | No |
| Enum default | None — an unmapped value quarantines | An `unknown` member means "we did not look" | No |
| Raw payload retention | 90 days, `canonical.payload.read` (additive CCR), unredacted, off the console | A mapping cannot be fixed without the payload | Yes |
| Expression language | Whitelisted AST, closed function table, no clock | A descriptor must stay data | No |
| Fuzzing | Atheris + Hypothesis, 60 s in CI, 4 h nightly | REQ-DAT-08 — it is a parser | Yes, budget only |
| Resource bounds | 1 MiB, depth 32, 10k keys, 1k batch, 2 s CPU | A hostile producer is the normal case | Yes |

## How this is verified

- `pnpm check:descriptors` — the eleven checks in §6, including the committed
  example fixtures round-tripping byte for byte (REQ-DAT-07).
- `pnpm test:normalizer` — `services/normalizer/tests/**`: the §2 worked
  example, both `normalizers/examples/` descriptors producing one identical
  canonical shape; every `reason` in §5 produced by a crafted payload; the
  required-field failure returning exactly the 422 body shown; hot reload with
  one broken file leaving the registry intact.
- `pnpm test:fuzz` — the three targets in §7 at the CI budget, properties 1–5
  asserted, regression corpus replayed on every run.
- `pnpm test:integration` — `tests/integration/normalizer/**`: a normalised
  record written through the DAL lands in the right tenant under RLS and carries
  the envelope; re-ingesting the same payload writes no second provenance row;
  a quarantine retry after a descriptor fix succeeds and sets `resolved_at`.
- `pnpm test:e2e` — `tests/e2e/quarantine/**`: the quarantine grid groups by
  reason, the payload view requires `canonical.payload.read`, and a replay of a
  reason class reports per-record outcomes.
- `pnpm test:contract` — `packages/contracts/tests/canonical.spec.ts`: every
  canonical model's Zod schema and its `canonical_*` table agree column for
  column; every model composes the entity envelope and `provenance`; no
  canonical table has a passthrough jsonb column; the JSON Schema the descriptor
  check runs against is generated from those Zod models (REQ-CTR-06,
  REQ-CTR-10).
- `GET /api/v1/normalizer/_selftest` — the engine is reachable over mTLS, the
  loaded descriptor set and hashes match the repository, quarantine depth and
  oldest entry are reported (REQ-CTR-08).

## Open to intake

| Question | Default if the human says nothing |
|---|---|
| Which canonical models are instantiated | `device`, `location` and `event`; the rest ship as definitions |
| Integrations to normalise | None at first; the engine and the descriptor format ship regardless |
| Raw payload retention | 90 days |
| Quarantine alert threshold | Any record older than 24 h, or depth > 1 000 |
| Who may read raw payloads | `canonical.payload.read`, global tier only |
| Nightly fuzz budget | 4 hours per target |
