#!/bin/sh
curl --fail-with-body -H "Authorization: Bearer $SZ_TOKEN" -H "Idempotency-Key: demo-1" -H "Content-Type: application/json" "$SZ_URL/api/v1/signing-requests" -d @create-request.json
