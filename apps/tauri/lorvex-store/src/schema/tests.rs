use super::*;
use rusqlite::Connection;

#[test]
fn migrations_are_sequential() {
    let migrations = all_migrations();
    for (i, m) in migrations.iter().enumerate() {
        assert_eq!(
            m.version as usize,
            i + 1,
            "migration at index {i} has version {} but expected {}",
            m.version,
            i + 1
        );
    }
}

#[test]
fn migrations_have_non_empty_sql() {
    for m in all_migrations() {
        assert!(
            !m.sql.trim().is_empty(),
            "migration {} ({}) has empty SQL",
            m.version,
            m.name
        );
    }
}

/// The embedded `checksums.lock` must agree with the embedded registry
/// (baseline + ladder) at every commit. This test fires on every
/// `cargo test` run so a developer who forgets to regenerate the lock —
/// or forgets to register a locked ladder file in `ladder_migrations()` —
/// catches the drift locally before the runtime boot gate trips for users.
#[test]
fn registry_matches_embedded_lock_exactly() {
    let migrations = all_migrations();
    enforce_embedded_lock_checksums(&migrations).expect(
        "checksums.lock must agree with the embedded migration registry — \
         regenerate the lock (`node scripts/verify/migration_checksums.mjs --seed` \
         pre-launch) or register the missing ladder entry",
    );
    assert_eq!(
        lock_entry_count(CHECKSUMS_LOCK_JSON),
        migrations.len(),
        "the lock must carry exactly one entry per registered migration"
    );
    for m in &migrations {
        let key = format!("{:03}", m.version);
        assert_eq!(
            parse_recorded_field(CHECKSUMS_LOCK_JSON, &key, "name").as_deref(),
            Some(format!("{:03}_{}.sql", m.version, m.name).as_str()),
            "lock entry {key} must record the canonical NNN_<name>.sql file name"
        );
        assert_eq!(
            parse_recorded_field(CHECKSUMS_LOCK_JSON, &key, "sha256").as_deref(),
            Some(sha256_hex(&m.sql).as_str()),
            "lock entry {key} must record the canonical normalized sha"
        );
    }
}

/// A registered migration the lock does not record (or vice versa) refuses
/// boot with a typed registry mismatch, not a silent partial verify.
#[test]
fn unlocked_registry_entry_is_a_registry_mismatch() {
    let mut migrations = all_migrations();
    migrations.push(Migration {
        version: (migrations.len() + 1) as u32,
        name: "phantom".into(),
        sql: "CREATE TABLE phantom (id TEXT);".into(),
    });
    match enforce_embedded_lock_checksums(&migrations) {
        Err(MigrationError::LockRegistryMismatch { registered, locked }) => {
            assert_eq!(registered, migrations.len());
            assert_eq!(locked, lock_entry_count(CHECKSUMS_LOCK_JSON));
        }
        other => panic!("expected LockRegistryMismatch, got {other:?}"),
    }
}

/// An embedded migration whose bytes drift from its lock entry refuses boot.
#[test]
fn edited_embedded_schema_is_a_lock_checksum_mismatch() {
    let mut migrations = all_migrations();
    migrations[0]
        .sql
        .push_str("\nCREATE TABLE drift (id TEXT);\n");
    match enforce_embedded_lock_checksums(&migrations) {
        Err(MigrationError::LockChecksumMismatch { version, .. }) => assert_eq!(version, 1),
        other => panic!("expected LockChecksumMismatch, got {other:?}"),
    }
}

/// End-to-end: applying the full embedded registry to a fresh database
/// records exactly the lock's entries in `schema_migrations` — the currently
/// empty ladder is a no-op beyond the baseline row — and re-applying is
/// idempotent.
#[test]
fn fresh_database_records_the_locked_registry() {
    let conn = Connection::open_in_memory().unwrap();
    let migrations = all_migrations();
    crate::migration::apply_migrations(&conn, &migrations).unwrap();

    let rows: Vec<(u32, String, String)> = conn
        .prepare("SELECT version, name, checksum FROM schema_migrations ORDER BY version")
        .unwrap()
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))
        .unwrap()
        .collect::<Result<_, _>>()
        .unwrap();
    assert_eq!(rows.len(), migrations.len());
    for (recorded, registered) in rows.iter().zip(&migrations) {
        assert_eq!(recorded.0, registered.version);
        assert_eq!(recorded.1, registered.name);
        let key = format!("{:03}", registered.version);
        assert_eq!(
            Some(recorded.2.as_str()),
            parse_recorded_field(CHECKSUMS_LOCK_JSON, &key, "sha256").as_deref(),
            "the recorded per-DB checksum must equal the canonical lock entry"
        );
    }

    // Idempotent no-op on re-apply.
    crate::migration::apply_migrations(&conn, &migrations).unwrap();
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM schema_migrations", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(count as usize, migrations.len());
}

#[test]
fn parse_recorded_field_extracts_values() {
    let lock = r#"{
          "001": {
            "name": "001_schema.sql",
            "sha256": "abcdef0123456789"
          }
        }"#;
    assert_eq!(
        parse_recorded_field(lock, "001", "sha256"),
        Some("abcdef0123456789".to_string())
    );
    assert_eq!(
        parse_recorded_field(lock, "001", "name"),
        Some("001_schema.sql".to_string())
    );
}

#[test]
fn parse_recorded_field_returns_none_for_missing_version() {
    assert!(parse_recorded_field("{}", "001", "sha256").is_none());
}
