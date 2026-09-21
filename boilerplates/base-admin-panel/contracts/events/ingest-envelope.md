# Contract: `ingest-envelope`

**Published by:** A15. **Consumed by:** A10 (normalisation), A13 (audit), A11
(the ingest route).
**Requirements:** REQ-OBS-01, REQ-OBS-02, REQ-OBS-04, REQ-OBS-05, REQ-DAT-05, REQ-SEC-01.

The envelope a remote collector sends to the server. It exists whether or not
remote agents are enabled: REQ-OBS-01 is `OPT`, but the ingest route and its
contract are not optional, because a build that turns collectors on later must
not need a contract change to do it.

## 1. Shape

```ts
export const IngestEnvelopeSchema = z.object({
  /** Idempotency key. The server MUST treat a repeat as a no-op (REQ-OBS-05). */
  ingestKey: z.string().min(16).max(128),

  agentId: z.string().uuid(),
  agentVersion: z.string(),

  /** The descriptor that should normalise this payload (REQ-DAT-03). */
  source: z.string().regex(/^[a-z0-9][a-z0-9-]*$/),

  /** Collected-at, from the agent's clock. UTC (contracts/types/time.md §1). */
  collectedAt: Timestamp,

  /** Opaque to the server. Only the normalizer interprets it (REQ-DAT-02). */
  payload: z.unknown(),

  /** SHA-256 of the canonicalised payload, computed by the agent. */
  payloadHash: z.string().length(64),

  /** Set when the agent is draining a local buffer rather than sending live. */
  replay: z.object({
    bufferedAt: Timestamp,
    attempt: z.number().int().positive(),
  }).optional(),
});
```

`payload` is `unknown` on purpose. The server does not know vendor shapes and
must not learn them — that knowledge lives in a descriptor
(`normalizers/descriptor.schema.json`), not in TypeScript.

## 2. Exactly-once, without a distributed transaction

`ingestKey` is the whole mechanism (REQ-OBS-05). The agent derives it
deterministically from the record it is reporting, so a retry produces the same
key:

```
ingestKey = base64url(sha256(agentId + source + sourceRecordId + payloadHash))
```

The server stores keys with a retention window at least as long as the agent's
maximum buffer age, and a second arrival is acknowledged without re-processing.

A random key per attempt would satisfy the schema and violate the requirement:
buffered records would duplicate on every resume. The derivation is part of the
contract, not an implementation detail.

`payloadHash` lets the server detect the case where the same logical record
arrives with changed content — same source record, different hash. That is an
update, not a duplicate, and the key derivation includes the hash so it gets a
new key.

## 3. Transport and identity

Mutual TLS, per-agent identity, short-lived credentials (REQ-OBS-02). The
envelope carries `agentId` for routing and auditing, but **the server derives the
authenticated agent from the client certificate, never from this field**. A
mismatch between the certificate subject and `agentId` is rejected and audited.

This is the same rule as REQ-RBA-03 for tenants: an identifier in a request body
is data, not authority.

## 4. What the server sends back

```ts
export const IngestAckSchema = z.object({
  ingestKey: z.string(),
  status: z.enum(["accepted", "duplicate", "quarantined", "rejected"]),
  quarantineReason: z.string().optional(),   // set when quarantined (REQ-DAT-06)
});
```

`duplicate` is a success: the agent may drop the record from its buffer.
`quarantined` is also terminal for the agent — the payload is stored server-side
with its reason and the agent must not retry it, or a malformed record retries
forever.

`rejected` is the only status the agent retries, and only with backoff.

## 5. Commands the server may not send

The response schema above is the entire server-to-agent surface for ingest.
There is no field carrying a script, a shell command, a configuration blob, or a
URL to fetch and execute (REQ-OBS-03). An agent's behaviour comes from its own
signed configuration, not from an ingest acknowledgement.

This is stated in the contract rather than left to the implementation because a
"just add a `command` field" change would be schema-additive and therefore pass
the breaking-change detector, while turning every collector into a remote
execution endpoint. Adding any such field is a security decision for S1 and S2,
not an additive CCR.

## 6. Additive vs breaking

**Additive** — a new optional envelope field; a new `status` value that agents
treat as `rejected` by default; a new optional field on the ack.

**Breaking** — changing the `ingestKey` derivation (every buffered record in the
field changes identity at once, and duplicates follow); making `replay`
required; removing a `status` value. A key-derivation change is the one to watch:
it is invisible in the schema and catastrophic in behaviour.
