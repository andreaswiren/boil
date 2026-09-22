#!/usr/bin/env bash
set -Eeuo pipefail
ARTIFACT="${1:?artifact}"; PROFILE="${2:?profile}"; : "${SZ_URL:?}"; : "${SZ_TOKEN:?}"
SHA="$(sha256sum "$ARTIFACT" | awk '{print $1}')"; SIZE="$(stat -c %s "$ARTIFACT")"; NAME="$(basename "$ARTIFACT")"
cat > /tmp/sz-request.$$ <<JSON
{"repository":"${CI_REPOSITORY:-unknown}","ref":"${CI_REF:-unknown}","commit":"${CI_COMMIT_SHA:-unknown}","buildId":"${CI_BUILD_ID:-unknown}","artifact":{"name":"$NAME","sha256":"$SHA","size":$SIZE},"profile":"$PROFILE"}
JSON
curl --fail-with-body -H "Authorization: Bearer $SZ_TOKEN" -H "Idempotency-Key: ${CI_BUILD_ID:-local}-$SHA" -H 'Content-Type: application/json' "$SZ_URL/api/v1/signing-requests" -d @/tmp/sz-request.$$
rm -f /tmp/sz-request.$$
