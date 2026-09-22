# Signing through the REST API

The REST API is the preferred integration for remote CI systems because it preserves SignZone policy, identity, approvals and audit semantics.

## 1. Authenticate

Preferred: OIDC workload identity exchanged for a short-lived SignZone token, or mTLS for fixed internal automation. Do not embed administrator credentials in CI.

## 2. Create request

```bash
curl --fail-with-body \
  -H "Authorization: Bearer $SZ_TOKEN" \
  -H "Idempotency-Key: $CI_PIPELINE_ID-$ARTIFACT_SHA256" \
  -H 'Content-Type: application/json' \
  https://signzone.example/api/v1/signing-requests \
  -d @request.json
```

Example `request.json`:

```json
{
  "repository": "platform/agent",
  "ref": "refs/tags/v1.8.4",
  "commit": "945ec701...",
  "buildId": "78231",
  "artifact": {
    "name": "agent-win-x64.exe",
    "sha256": "7b46...",
    "size": 10485760
  },
  "profile": "production-authenticode"
}
```

The server must recompute the digest from the uploaded/fetched artifact.

## 3. Artifact transfer

Use either a streaming upload endpoint with strict size/content controls or an immutable object-store reference previously registered with SignZone. Never accept a pathname from the client for the signer to open.

## 4. Approval

If policy requires human approval the request returns `awaiting_approval`. Approvers can use web/PWA. Approvals are bound to the exact digest and profile.

## 5. Poll/status

```bash
curl -H "Authorization: Bearer $SZ_TOKEN" \
  https://signzone.example/api/v1/signing-requests/$REQUEST_ID
```

## 6. Download and verify

Retrieve only when state is `completed`, then independently verify Authenticode/signature and compare the signed SHA-256 returned by SignZone.

See `docs/api/openapi.yaml` and `examples/curl/`.
