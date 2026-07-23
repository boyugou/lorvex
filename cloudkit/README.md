# cloudkit/ - Apple Swift CloudKit schema template

`schema.ckdb` is the authoritative CloudKit record-type template. Domain data
uses the end-to-end-encrypted `LorvexEntity` envelope. Transport metadata uses
separate record types for generation control, immutable generation root/seal
witnesses, nil-token traversal proof, audit-retention authority, and wakeups.
The fixed-name `LorvexAuditRetentionMetadata` record is identity-fetched and
stores all of its custom fields as CloudKit encrypted values; no policy or
activity-cutoff metadata is intentionally exposed as plaintext.

The fixed-name `LorvexZoneEpoch` record lives in the private database's default
zone and implements the protocol-v3 `rebuilding` / `ready` / `deleted` state
machine. It CAS-serializes a unique custom zone for every generation, records
the active descriptor, server-derived tombstone-compaction cutoff, and bounded
retirement ledger, and carries a canonical server-derived lease activity
timestamp while rebuilding. Foreign takeover uses only that timestamp, never a
device wall clock. A separate fixed-name `LorvexServerClock` singleton in the
private default zone supplies server time by upserting a fresh random nonce and
validating the saved record's CloudKit modification date. Both singletons are
bounded plaintext recovery-control metadata and contain no user content. The
epoch record preserves a fleet-visible deletion barrier across custom-zone
loss; user domain data remains in encrypted `LorvexEntity` fields.
`deploy-schema.sh` deploys the template to the Development environment of
`iCloud.com.lorvex.apple` by default. Run it with no arguments for a normal
validate-and-import pass, or with `--reset` to reset Development to Production's
schema and delete its data before validating and importing the template. The
script rejects every other argument and every non-Development environment;
Production promotion remains a manual CloudKit Console operation.

The checked-in schema is necessary but not sufficient release evidence. Before
submission, deploy the exact Development schema, exercise the multi-device
protocol there, promote it to Production in CloudKit Console, and preserve the
exported Production schema plus the signed archive's container entitlement as
release evidence.

The Apple Swift app is the only Apple-ecosystem product path. Tauri no longer
owns an iCloud container or App Store sync path; future Windows/Linux/Android
sync should use a non-iCloud backend.
