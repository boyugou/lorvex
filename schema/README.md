# schema/ — Apple SQLite schema authority

`schema.sql` is the **authoritative** SQLite schema for Lorvex (tables,
triggers, FTS5) and the **Apple app's schema authority**:

- **Apple** (`apps/apple`) realizes it byte-for-byte, bundling its runtime copy
  at `apps/apple/Sources/LorvexCore/Resources/schema.sql`. Development and tests
  may pass an explicit DDL string to `LorvexStore.open(at:schemaSQL:)`, but
  packaged app builds use the bundled resource.
`apps/apple/script/verify_schema_embed.sh` asserts the Apple bundled resource is
byte-identical to this authoritative `schema/schema.sql`. Drift there is a red
Apple build, not silent rot.

The baseline is frozen: `migration_policy.json` carries `launched: true` and a
`frozen_baseline` holding every released `checksums.lock` entry and sync-payload
contract hash. `schema.sql` (migration version `001`) and those entries never
change; a schema change is an appended numbered migration, mirrored into the
Apple embedded copy and re-validated. The `launched` sentinel selects the
regime: with `launched: false` the baseline is edited in place and the lock
regenerated with `apps/apple/script/verify_migration_ladder.py --seed`, which
refuses to run once `launched` is `true`.
`apps/apple/script/verify_schema_freeze.py` enforces the armed regime.
See `../docs/design/SCHEMA_OPTIMALITY.md` → "Migration model".

The sibling `sync_payload/` directory versions the Apple sync wire's exact JSON
operation shapes. It is deliberately separate from SQLite migrations: a payload
field or delete-marker change can be a compatibility change even when
`schema.sql` is unchanged. `apps/apple/script/verify_sync_payload_contract.py`
checks the canonical numbered manifest ladder, while Swift core tests execute
the real builders/loaders and final outbox transform before comparing emitted
upsert/delete envelopes with the current contract. The same `--arm` operation
freezes both the SQLite baseline and every shipped payload-contract manifest.

Post-launch migrations have a single canonical source too: `migrations/` in this
directory holds the numbered `NNN_<name>.sql` ladder plus its
`migrations/checksums.lock` (normalized SHA-256 per entry; entry `001` pins the
baseline `schema.sql`). The Apple app embeds a byte-identical copy of the ladder
and the lock under `apps/apple/Sources/LorvexCore/Resources/` and refuses to open
a database when its embedded copy disagrees with its embedded lock.
`apps/apple/script/verify_schema_embed.sh` enforces the Apple embed's
byte-equality with this directory and
`apps/apple/script/verify_migration_ladder.py` enforces the ladder contract
(contiguous numbering, checksum agreement, launch-regime rules). The full
contract is `migrations/README.md`.
