# REST API

Version under `/api/v1`. OpenAPI is authoritative. Requests use trusted identity context, idempotency for mutating operations, strict content limits, digest verification and immutable job context. Large artifacts should use pre-authorized object storage or streaming uploads; never trust a client-provided digest without recomputing.
