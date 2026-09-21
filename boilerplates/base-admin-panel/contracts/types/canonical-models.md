# Contract: `canonical-models`

**Published by:** A10. **Consumed by:** A07 (grids over canonical data), A11
(API surface), A15 (collector ingest), A13 (audit targets).
**Requirements:** REQ-DAT-01, REQ-DAT-02, REQ-DAT-05, REQ-DAT-06.

The canonical models are what the application stores. Vendor payloads are
normalised into them (REQ-DAT-02) and **no vendor field name reaches a canonical
table** — that is the whole point of the layer.

## 1. The rule that defines "canonical"

A model is canonical when a second, differently-shaped vendor can be mapped onto
it without changing it. If onboarding vendor B requires adding a field, the model
was a copy of vendor A's schema wearing a different name.

`normalizers/examples/` carries two descriptors mapping deliberately dissimilar
payloads onto `canonical.device` for exactly this reason. Adding a third vendor
that needs a schema change is a finding against the model, not against the
vendor.

## 2. Shape

Every canonical model extends the entity envelope (`entity-base.md`) and carries
provenance. Nothing else is mandatory.

```ts
export const ProvenanceSchema = z.object({
  sourceSystem: z.string(),              // the descriptor's source id
  sourceId: z.string(),                  // identity in the source system
  sourcePayloadHash: z.string().length(64),  // SHA-256 of the canonicalised raw payload
  descriptorVersion: z.number().int().positive(),
  normalisedAt: Timestamp,               // UTC (contracts/types/time.md §1)
});

export const CanonicalBase = EntityBase.extend({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),           // derived from session, never a parameter (REQ-RBA-03)
  provenance: ProvenanceSchema.nullable(),  // null for a record created in-app, not ingested
});
```

`provenance` being nullable is deliberate: a device a technician typed in by hand
has no source system, and pretending it does would make the field a lie.

## 3. The model set

A00 resolves which models a build needs from the intake (REQ-DAT-01). These are
the starters; a build adds to them, and the shape above is what makes an addition
mechanical rather than a redesign.

| Model | Represents | Notes |
|-------|------------|-------|
| `canonical.organisation` | A customer, site owner or business unit | Distinct from `tenants`: a tenant is an isolation boundary, an organisation is data inside one |
| `canonical.identity` | A person or service account as *data* | Not `users`. A03 owns login identity; this is the directory record an integration syncs |
| `canonical.location` | A site, building or logical place | The `lookup` target in both example descriptors |
| `canonical.device` | A managed asset with a lifecycle | The worked example; see `normalizers/examples/` |
| `canonical.event` | Something that happened in a source system | Distinct from `audit_events`, which is *our* trail (`events/audit-event.md`) |
| `canonical.metric` | A numeric sample with a unit and a timestamp | Unit is mandatory; a bare number is unmappable |

The `canonical.identity` / `users` and `canonical.event` / `audit_events`
distinctions are the two most commonly collapsed, and collapsing either produces
a tenant-isolation or tamper-evidence defect rather than a merely untidy schema.

## 4. Enum values are canonical too

A canonical model with a free-text status field has not normalised anything. Each
enumerated field declares its closed value set here, and a descriptor's `map`
transform must land on one of them or quarantine (REQ-DAT-06).

```ts
export const DeviceLifecycle = z.enum(["staging", "active", "repair", "retired"]);
```

Adding a value is additive. Removing or renaming one is breaking, and worse than
usual: every existing row holding the old value becomes invalid, and every
descriptor mapping to it starts quarantining.

## 5. Additive vs breaking

**Additive** — a new model; a new optional field; a new enum value; a new
`lookup` target.

**Breaking** — renaming a field or model (descriptors reference them by name and
would all start failing validation); making an optional field required (existing
rows and existing descriptors become invalid together); narrowing an enum;
changing a field's type. A field rename here breaks every descriptor at once,
which is why `contracts/README.md` §5 forbids it rather than scheduling it.
