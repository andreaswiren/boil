# PWA and Mobile Approval

PWA can subscribe to Web Push. Push payloads contain no secrets and minimal metadata. Opening a request shows requester, repo/ref, artifact, digest suffix, profile, policy and expiry. Acceptance requires step-up. For number matching, desktop/API request displays a short random transaction code and the phone approval must select/enter the matching code; code is request-bound, expires quickly and is one-use. WebAuthn is preferred for higher assurance.
