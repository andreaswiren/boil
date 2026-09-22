# Windows CI using SignZone REST

PowerShell example:

```powershell
$headers = @{
  Authorization = "Bearer $env:SZ_TOKEN"
  "Idempotency-Key" = "$env:BUILD_BUILDID-$env:ARTIFACT_SHA256"
}
$body = Get-Content .\request.json -Raw
$request = Invoke-RestMethod -Method Post -Uri "https://signzone.example/api/v1/signing-requests" -Headers $headers -ContentType "application/json" -Body $body
$request
```

Upload the artifact through the API/object-storage mechanism defined by the deployment, then wait for `completed`. Do not export the code-signing private key to the Windows runner.
