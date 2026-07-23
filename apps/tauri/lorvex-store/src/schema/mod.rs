//! Schema registry — the consolidated baseline plus the versioned-migration
//! ladder.
//!
//! `001_schema.sql` (schema version 1) is the complete baseline database
//! layout; `NNN_<name>.sql` files (versions 2+) are post-launch migrations.
//! Every file in this directory is a byte-identical copy of its canonical
//! source in the monorepo `schema/` tree (`schema/schema.sql` for the
//! baseline, `schema/migrations/NNN_<name>.sql` for the ladder) — see this
//! directory's README for the derivation contract.

use crate::migration::{checksum::sha256_hex, Migration, MigrationError};

const SCHEMA_SQL: &str = include_str!("001_schema.sql");
/// Embed the lock file at compile time so the runtime can verify its
/// schema bytes match the recorded canonical hash without depending
/// on a workspace-relative file path. This is the runtime half of
/// the H3 enforcement contract — the matching CI script lives at
/// `scripts/verify/migration_checksums.mjs`.
const CHECKSUMS_LOCK_JSON: &str = include_str!("checksums.lock");

/// Return the full ordered list of migrations: the baseline (version 1,
/// name `schema`) followed by the numbered ladder.
///
/// The SQL is embedded at compile time via `include_str!`, so the binary
/// carries no external file dependencies at runtime.
pub fn all_migrations() -> Vec<Migration> {
    let mut migrations = vec![Migration {
        version: 1,
        name: "schema".to_string(),
        sql: SCHEMA_SQL.to_string(),
    }];
    migrations.extend(ladder_migrations());
    migrations
}

/// The versioned-migration ladder (versions 2+), derived from the canonical
/// `schema/migrations/` directory at the monorepo root.
///
/// Adding a post-launch migration means: copy the canonical
/// `NNN_<name>.sql` byte-identically into this directory, append a
/// `Migration { version: NNN, name: "<name>", sql: include_str!("NNN_<name>.sql") }`
/// entry here, and append the file's `NNN` entry to `checksums.lock`. This Tauri
/// copy tracks the canonical `schema/migrations/` but is only directionally
/// aligned — the monorepo no longer enforces byte-equality against it, so it may
/// diverge. `registry_matches_embedded_lock_exactly` (tests) enforces
/// registry<->lock agreement, and `enforce_embedded_lock_checksums` re-verifies
/// it at every boot.
///
/// Empty while `schema/migration_policy.json` has `launched: false` — the
/// pre-launch regime evolves the baseline directly and ships no migrations.
fn ladder_migrations() -> Vec<Migration> {
    Vec::new()
}

/// Enforce the embedded `checksums.lock` against the embedded migration
/// registry at boot: every registered migration's normalized SHA-256 must
/// match its lock entry, the lock entry's recorded file name must match the
/// migration's `NNN_<name>.sql` naming, and the lock must carry exactly one
/// entry per registered migration (an extra lock entry means a migration file
/// was recorded but never registered).
///
/// Without runtime enforcement, the migration runner would consult only
/// `schema_migrations.checksum` (the per-DB recorded hash) — a developer who
/// edited an embedded SQL file without regenerating `checksums.lock` and ran
/// the binary against a fresh DB would silently install the edited schema,
/// because the lock file is otherwise only consulted by
/// `scripts/verify/migration_checksums.mjs` (CI/dev path, not the runtime).
///
/// On mismatch we surface a typed `MigrationError::LockChecksumMismatch` /
/// `MigrationError::LockRegistryMismatch` so the caller
/// (`ConnectionPool::new`, `open_db_at_path`) can route it through the same
/// fatal-dialog path as `ChecksumMismatch` on existing DBs. The errors include
/// both sides so the developer can see exactly what drifted.
pub fn enforce_embedded_lock_checksums(migrations: &[Migration]) -> Result<(), MigrationError> {
    let locked = lock_entry_count(CHECKSUMS_LOCK_JSON);
    if locked != migrations.len() {
        return Err(MigrationError::LockRegistryMismatch {
            registered: migrations.len(),
            locked,
        });
    }

    for migration in migrations {
        let key = format!("{:03}", migration.version);
        let expected_file = format!("{:03}_{}.sql", migration.version, migration.name);
        let actual_hash = sha256_hex(&migration.sql);

        let recorded_hash =
            parse_recorded_field(CHECKSUMS_LOCK_JSON, &key, "sha256").ok_or_else(|| {
                MigrationError::LockChecksumMismatch {
                    version: migration.version,
                    name: expected_file.clone(),
                    expected: "<missing from checksums.lock>".to_string(),
                    actual: actual_hash.clone(),
                }
            })?;

        let recorded_name = parse_recorded_field(CHECKSUMS_LOCK_JSON, &key, "name")
            .unwrap_or_else(|| "<missing name>".to_string());
        if recorded_name != expected_file {
            return Err(MigrationError::LockChecksumMismatch {
                version: migration.version,
                name: expected_file,
                expected: format!("file name {recorded_name}"),
                actual: actual_hash,
            });
        }

        if recorded_hash != actual_hash {
            return Err(MigrationError::LockChecksumMismatch {
                version: migration.version,
                name: expected_file,
                expected: recorded_hash,
                actual: actual_hash,
            });
        }
    }
    Ok(())
}

/// Minimal JSON shape parser for `checksums.lock`. The file format is
/// a flat object keyed by zero-padded migration version, each entry
/// containing `name` and `sha256` strings. Avoids pulling serde_json
/// into the schema module just for this — `sha256_hex` already lives
/// here and the lock layout is fixed.
fn parse_recorded_field(lock_json: &str, version_key: &str, field: &str) -> Option<String> {
    // Find the version key in the JSON, then find the requested field
    // in the immediately-following object. Tolerant to whitespace and
    // key ordering, refuses to be fooled by a field-name substring that
    // appears outside the version's object (rejects everything before
    // the version key opens its block).
    let key_marker = format!("\"{version_key}\"");
    let after_key = lock_json.split_once(&key_marker)?.1;
    let object_start = after_key.find('{')?;
    let object_body = &after_key[object_start..];
    let object_end = object_body.find('}')?;
    let object_inner = &object_body[..=object_end];
    let field_marker = format!("\"{field}\"");
    let after_field = object_inner.split_once(&field_marker)?.1;
    // Skip the `:`, optional whitespace, then capture a quoted string.
    let quote_open = after_field.find('"')?;
    let after_open = &after_field[quote_open + 1..];
    let quote_close = after_open.find('"')?;
    Some(after_open[..quote_close].to_string())
}

/// The number of entries in the lock: one `"sha256"` field per entry. The
/// values in the lock are hex digests and `NNN_<name>.sql` file names, so the
/// literal `"sha256"` cannot appear inside a value.
fn lock_entry_count(lock_json: &str) -> usize {
    lock_json.matches("\"sha256\"").count()
}

#[cfg(test)]
mod tests;
