# schema/migrations/ — canonical migration ladder (Apple schema authority)

This directory is the **single authoritative source** for post-launch schema
migrations, exactly as `../schema.sql` is the single authoritative source for
the baseline schema. The Apple app derives its embedded migration registry from
here; its bundled copy is never edited independently. The ladder governs the
**Apple app's own** schema evolution for post-launch Apple↔Apple multi-device
rolling upgrades — the Tauri app is only directionally aligned via `spec/`, not
byte-locked to this directory.

## Version space

The ladder shares one version space with the `schema_migrations` bookkeeping
table the Apple app stamps:

| version | content                                | lives at                          |
|--------:|----------------------------------------|-----------------------------------|
| `001`   | the consolidated baseline (`schema`)   | `../schema.sql` (no file here)    |
| `002`+  | one numbered migration per version     | `NNN_<name>.sql` in this directory|

Version `001` is reserved for the baseline and never appears as a SQL file in
this directory. Real migrations are `NNN_<name>.sql` with `NNN` a zero-padded
three-digit version starting at `002`, **contiguous** (no gaps, no duplicates),
and `<name>` in `snake_case` (`[a-z0-9_]+`). A migration's recorded
`schema_migrations.name` is the bare `<name>`; its lock/file name is
`NNN_<name>.sql` — so `002_add_widgets.sql` stamps `(2, 'add_widgets', <sha>)`.

## checksums.lock

`checksums.lock` pins the canonical SHA-256 of every entry — key `NNN`, value
`{"name": "NNN_<name>.sql", "sha256": "<hex>"}` (entry `001` names the baseline
embed `001_schema.sql`). The hash is computed over **normalized** SQL:

1. strip a UTF-8 BOM if present;
2. replace CRLF with LF;
3. strip SQL comments (`-- line` and `/* block */`), drop lines left
   whitespace-only, and trim trailing whitespace an inline comment leaves
   behind — so comment-only edits never change the hash;
4. trim leading/trailing whitespace.

The Apple app owns this normalization: it computes the digest in Swift
(`apps/apple/core/Sources/LorvexStore/MigrationSqlChecksum.swift`, the runtime
authority) and both seeds and verifies the lock in Python
(`apps/apple/script/verify_migration_ladder.py --seed` and its plain verify run),
each pinned against the same lock entries by its own test suite. Tauri's Node and
Rust implementations (`apps/tauri/scripts/verify/migration_checksums.mjs`,
`apps/tauri/lorvex-store/src/migration/checksum`) use the same algorithm but are
a separate, directionally-aligned realization — not a byte-locked contract with
Apple, and never run by the Apple gate.

The Apple app records the bare migration name plus this normalized hash into
`schema_migrations` when applying a migration and verifies both on every
subsequent open, so an Apple database's recorded ladder stays self-consistent
across app versions.

## Immutability

A migration becomes **released and frozen when `verify_schema_freeze.py --arm`
captures its lock identity** for a public build. From then on, never edit,
rename, renumber, or delete it. Shipped installs verify its recorded name and
checksum on every open; mutating either locks users out of healthy data or
erases trustworthy provenance. To change course, append a new migration that
alters the schema further. Before the first public arm, the documented
pre-launch re-seed workflow may still replace the unshipped baseline identity.

Migrations are **one-way**. There are no down migrations; a database whose
recorded max version exceeds what a binary registers refuses to open
("database is newer than this build"), it is never downgraded.

## SQL dialect constraints

Each migration runs as plain SQLite SQL through GRDB (`Database.execute(sql:)`)
on Apple and rusqlite (`execute_batch`) on Tauri, inside a single
`BEGIN IMMEDIATE` transaction the runner owns. Therefore a migration:

- may contain multiple statements and SQL comments (comments don't affect the
  checksum);
- must not contain `BEGIN`/`COMMIT`/`ROLLBACK` (the runner wraps it);
- must not contain statements that cannot run inside a transaction:
  `PRAGMA journal_mode`, `VACUUM`, `ATTACH`/`DETACH`;
- must be UTF-8 with LF line endings;
- must use only SQLite features the Apple app compiles (FTS5 is available; no
  loadable extensions);
- need not be idempotent — the runner applies each version exactly once and
  verifies the checksum thereafter;
- may drop or rename objects the baseline created, provided the ladder stays
  *closed*: after each migration no surviving index, trigger, or foreign key may
  reference a dropped table or column (`verify_migration_ladder.py` enforces
  this). The Apple open path applies the baseline only to a fresh/unversioned
  database; a versioned database verifies the baseline checksum and then runs the
  numbered ladder as the sole author of post-baseline schema, so a dropped object
  is never resurrected. This closure requirement is an Apple-only concern: the
  Tauri app is directionally aligned, not byte-locked to this ladder, and evolves
  its own schema independently.

## How the Apple app derives its registry

Each `NNN_<name>.sql` is copied byte-identically to
`apps/apple/Sources/LorvexCore/Resources/Migrations/NNN_<name>.sql` (bundled the
same way as `schema.sql`), and `checksums.lock` there is a byte-identical copy of
this directory's lock. `SwiftLorvexCoreService` loads the bundled files, verifies
each against the bundled lock, and passes the ladder to `LorvexStore.open`; a
checksum or numbering violation refuses the open.

The Tauri app maintains its own copy under `apps/tauri/lorvex-store/src/schema/`,
but it is only directionally aligned via `spec/`: the monorepo does not enforce
byte-equality against it, and it may diverge freely.

Enforcement (Apple-only):

- `apps/apple/script/verify_schema_embed.sh` — byte-equality of the Apple bundled
  lock and every Apple migration embed against this canonical directory.
- `apps/apple/script/verify_migration_ladder.py` — numbering contiguity,
  lock/file checksum agreement, baseline (`001`) agreement with
  `../schema.sql`, and the launch-regime rules below.
- `apps/apple/script/verify_schema_freeze.py` — once launched, released lock
  entries are immutable (append-only).
- The Apple test suite asserts its embedded registry matches its embedded
  lock exactly.

## Launch regimes (`../migration_policy.json`)

- **Pre-launch (`launched: false`, current)**: this directory holds **no**
  migration files. The schema evolves by editing `../schema.sql` directly and
  regenerating the lock (`apps/apple/script/verify_migration_ladder.py --seed`,
  which rewrites this `checksums.lock` and the Apple embed byte-identically).
  `verify_migration_ladder.py` rejects migration files while pre-launch.
- **Post-launch (`launched: true`)**: `../schema.sql` and every released lock
  entry are frozen forever. A schema change is expressed **only** as a new
  migration:
  1. add `NNN_<name>.sql` here (`NNN` = current max + 1);
  2. append its `NNN` entry to `checksums.lock` (normalized SHA-256; never
     touch an existing entry);
  3. copy the file and the lock byte-identically into the Apple embed location
     (`apps/apple/Sources/LorvexCore/Resources/`);
  4. re-run the Apple test suite and the verifiers above.

  Direct edits to `../schema.sql` are rejected by the armed verifiers.
