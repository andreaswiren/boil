# Architecture

Trust zones: untrusted CI/build systems -> HTTPS API/nginx -> unprivileged Next.js -> Unix RPC -> signer daemon or privileged OS daemon. PostgreSQL is application state, not secret storage. `signerd` is the only HSM consumer. `osd` is the only root service. `dcui` is local-console only. No generic exec primitive may cross a boundary.
