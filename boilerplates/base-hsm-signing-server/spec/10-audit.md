# Audit

Events are canonical JSON with event ID, timestamp, actor, assurance, source, action, target, outcome, request ID, previous hash and event hash. Secrets are redacted before canonicalization. Periodic signed checkpoints permit tamper detection. PostgreSQL indexes events; optionally ship canonical records to remote syslog/SIEM/WORM storage.
