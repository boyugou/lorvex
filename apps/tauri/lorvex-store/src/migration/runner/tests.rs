//! Tests for `runner`. Extracted from the parent file
//! to keep the production module focused.

use super::*;

fn open_memory_db() -> Connection {
    let conn = Connection::open_in_memory().unwrap();
    conn.execute_batch("PRAGMA foreign_keys = ON;").unwrap();
    conn
}

#[test]
fn creates_schema_migrations_table() {
    let conn = open_memory_db();
    apply_migrations(&conn, &[]).unwrap();

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='schema_migrations'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count, 1);
}

#[test]
fn single_migration() {
    let conn = open_memory_db();
    let m = Migration {
        version: 1,
        name: "create_foo".into(),
        sql: "CREATE TABLE foo (id INTEGER PRIMARY KEY);".into(),
    };
    apply_migrations(&conn, &[m]).unwrap();

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='foo'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count, 1);

    // Verify recorded in schema_migrations.
    let recorded_version: u32 = conn
        .query_row(
            "SELECT version FROM schema_migrations WHERE version = 1",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(recorded_version, 1);
}

#[test]
fn idempotent_apply() {
    let conn = open_memory_db();
    let m = Migration {
        version: 1,
        name: "create_bar".into(),
        sql: "CREATE TABLE bar (id INTEGER PRIMARY KEY);".into(),
    };
    apply_migrations(&conn, std::slice::from_ref(&m)).unwrap();
    // Applying the same migration again should succeed (no-op).
    apply_migrations(&conn, std::slice::from_ref(&m)).unwrap();
}

#[test]
fn checksum_mismatch_errors() {
    let conn = open_memory_db();
    let m1 = Migration {
        version: 1,
        name: "create_baz".into(),
        sql: "CREATE TABLE baz (id INTEGER PRIMARY KEY);".into(),
    };
    apply_migrations(&conn, &[m1]).unwrap();

    // Now try to apply version 1 with different SQL.
    let m1_tampered = Migration {
        version: 1,
        name: "create_baz".into(),
        sql: "CREATE TABLE baz (id TEXT PRIMARY KEY);".into(),
    };
    let result = apply_migrations(&conn, &[m1_tampered]);
    assert!(result.is_err());
    match result.unwrap_err() {
        MigrationError::ChecksumMismatch { version, .. } => assert_eq!(version, 1),
        other => panic!("expected ChecksumMismatch, got: {other}"),
    }
}

#[test]
fn corrupt_schema_migration_checksum_type_errors_instead_of_reapplying() {
    let conn = open_memory_db();
    conn.execute_batch(
        "CREATE TABLE schema_migrations (
            version INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            checksum INTEGER NOT NULL
        );",
    )
    .unwrap();
    conn.execute(
        "INSERT INTO schema_migrations (version, name, checksum) VALUES (1, 'create_corrupt', 123)",
        [],
    )
    .unwrap();

    let migration = Migration {
        version: 1,
        name: "create_corrupt".into(),
        sql: "CREATE TABLE should_not_run (id INTEGER PRIMARY KEY);".into(),
    };

    let error = apply_migrations(&conn, &[migration]).unwrap_err();
    assert!(
        matches!(error, MigrationError::Sql(_)),
        "expected SQL error for corrupt checksum row, got {error}"
    );

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='should_not_run'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count, 0, "migration should not have been re-applied");
}

#[test]
fn sequential_migrations() {
    let conn = open_memory_db();
    let migrations = vec![
        Migration {
            version: 1,
            name: "create_alpha".into(),
            sql: "CREATE TABLE alpha (id INTEGER PRIMARY KEY);".into(),
        },
        Migration {
            version: 2,
            name: "create_beta".into(),
            sql: "CREATE TABLE beta (id INTEGER PRIMARY KEY);".into(),
        },
        Migration {
            version: 3,
            name: "add_col".into(),
            sql: "ALTER TABLE alpha ADD COLUMN name TEXT;".into(),
        },
    ];
    apply_migrations(&conn, &migrations).unwrap();

    // All three tables/columns should exist.
    let alpha_cols: Vec<String> = conn
        .prepare("PRAGMA table_info(alpha)")
        .unwrap()
        .query_map([], |row| row.get::<_, String>(1))
        .unwrap()
        .filter_map(std::result::Result::ok)
        .collect();
    assert!(alpha_cols.contains(&"id".to_string()));
    assert!(alpha_cols.contains(&"name".to_string()));

    let beta_exists: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='beta'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(beta_exists, 1);

    // All three recorded.
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM schema_migrations", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(count, 3);
}

/// Renumbered/reordered frozen migrations — the SQL of two applied versions
/// swapped — are rejected as a checksum mismatch at the first drifted
/// version. The ladder's history is immutable, not just its contents.
#[test]
fn swapped_versions_of_applied_migrations_are_rejected() {
    let conn = open_memory_db();
    let alpha_sql = "CREATE TABLE alpha (id INTEGER PRIMARY KEY);";
    let beta_sql = "CREATE TABLE beta (id INTEGER PRIMARY KEY);";
    let applied = vec![
        Migration {
            version: 1,
            name: "create_alpha".into(),
            sql: alpha_sql.into(),
        },
        Migration {
            version: 2,
            name: "create_beta".into(),
            sql: beta_sql.into(),
        },
    ];
    apply_migrations(&conn, &applied).unwrap();

    let swapped = vec![
        Migration {
            version: 1,
            name: "create_beta".into(),
            sql: beta_sql.into(),
        },
        Migration {
            version: 2,
            name: "create_alpha".into(),
            sql: alpha_sql.into(),
        },
    ];
    let error = apply_migrations(&conn, &swapped).expect_err("swapped ladder must be rejected");
    match error {
        MigrationError::ChecksumMismatch { version, .. } => assert_eq!(version, 1),
        other => panic!("expected ChecksumMismatch, got {other:?}"),
    }
}

#[test]
fn migration_sql_failure_surfaces_rollback_failures() {
    let conn = open_memory_db();
    let migration = Migration {
        version: 1,
        name: "broken_after_manual_rollback".into(),
        sql: "ROLLBACK; THIS IS BAD SQL;".into(),
    };

    let error = apply_migrations(&conn, &[migration]).expect_err("broken migration should fail");
    let message = error.to_string();
    assert!(
        message.contains("rollback failed"),
        "unexpected error: {message}"
    );
}

/// Regression for a build that knows migrations 1..2
/// must refuse to open a DB that already recorded migration 3.
/// Prior to the fix the runner just returned Ok and let the app
/// read/write against a schema with constraints it didn't
/// understand.
#[test]
fn apply_migrations_refuses_downgrade_when_db_is_newer_than_binary() {
    let conn = open_memory_db();
    // Simulate a newer build applying migrations up to v3.
    let v1_to_v3 = vec![
        Migration {
            version: 1,
            name: "baseline".into(),
            sql: "CREATE TABLE t (id INTEGER PRIMARY KEY);".into(),
        },
        Migration {
            version: 2,
            name: "v2".into(),
            sql: "CREATE TABLE u (id INTEGER PRIMARY KEY);".into(),
        },
        Migration {
            version: 3,
            name: "v3".into(),
            sql: "CREATE TABLE v (id INTEGER PRIMARY KEY);".into(),
        },
    ];
    apply_migrations(&conn, &v1_to_v3).expect("newer build applies all migrations");

    // Now an older build that only knows migrations 1..2 opens the
    // same DB. The recorded max is 3, the binary max is 2 — refuse.
    let v1_to_v2 = &v1_to_v3[..2];
    let error = apply_migrations(&conn, v1_to_v2).expect_err("older build must refuse a newer DB");
    match error {
        MigrationError::DowngradeDetected {
            binary_max_version,
            db_max_version,
        } => {
            assert_eq!(binary_max_version, 2);
            assert_eq!(db_max_version, 3);
        }
        other => panic!("expected DowngradeDetected, got {other:?}"),
    }
}

/// coverage, adapted to the consolidated
/// single-file schema: assert that the critical expression and
/// partial indexes survive a fresh `apply_migrations` run. Pre-
/// consolidation, table-rebuild migrations dropped indexes as a
/// side effect and a sibling migration had to restore them.
/// That whole class of error is structurally impossible now
/// (there are no rebuild migrations), but the index set still
/// drives hot-path queries — if `001_schema.sql` ever forgets
/// one, this test catches it before the planner silently falls
/// back to table scans.
#[test]
fn critical_indexes_survive_full_migration_stack() {
    let conn = open_memory_db();
    apply_migrations(&conn, &crate::schema::all_migrations())
        .expect("full migration stack applies cleanly");

    let required_indexes = [
        "idx_error_logs_created_at",
        "idx_error_logs_source",
        "idx_sync_outbox_unsynced",
        "idx_focus_schedule_blocks_task",
        "idx_sync_tombstones_version",
        "idx_sync_tombstones_deleted_at",
        "idx_sync_conflict_log_resolved_at",
        "idx_sync_conflict_log_type_id",
        "idx_sync_pending_inbox_drain",
        "idx_sync_pending_inbox_first_attempted",
        "idx_tasks_action_date_open",
        "idx_tasks_action_date_non_cancelled",
    ];

    let actual: std::collections::HashSet<String> = conn
        .prepare("SELECT name FROM sqlite_master WHERE type='index'")
        .unwrap()
        .query_map([], |row| row.get::<_, String>(0))
        .unwrap()
        .filter_map(std::result::Result::ok)
        .collect();

    let missing: Vec<&str> = required_indexes
        .iter()
        .copied()
        .filter(|idx| !actual.contains(*idx))
        .collect();
    assert!(
        missing.is_empty(),
        "critical indexes missing from 001_schema.sql: {missing:?}"
    );
}

/// Fresh DB (schema_migrations exists but is empty) must not
/// trigger the downgrade path.
#[test]
fn apply_migrations_does_not_trip_downgrade_on_empty_schema_migrations() {
    let conn = open_memory_db();
    // Pre-create the bookkeeping table empty — simulates a scenario
    // where the table exists but has no rows.
    ensure_schema_migrations_table(&conn).unwrap();
    let migrations = vec![Migration {
        version: 1,
        name: "baseline".into(),
        sql: "CREATE TABLE t (id INTEGER PRIMARY KEY);".into(),
    }];
    apply_migrations(&conn, &migrations)
        .expect("empty schema_migrations should not trip downgrade detection");
}

/// Regression for #2260: when a migration's SQL hits an error
/// *after* some DDL has already executed inside the migration's
/// transaction, the runner must surface the error AND roll back
/// the partial DDL so the DB is left exactly as it was before the
/// migration started. This pins the core crash-recovery invariant:
/// a killed/erroring mid-apply never leaves a half-applied schema.
#[test]
fn mid_migration_panic_leaves_db_clean() {
    let conn = open_memory_db();

    // Two statements: the first succeeds inside the transaction
    // (so there *is* something to roll back), the second errors
    // and forces the runner down its rollback path. This mimics
    // the real-world "SIGKILL at 5s of a 10s migration" scenario
    // at the SQL boundary available to a unit test.
    let migration = Migration {
        version: 42,
        name: "partial_then_boom".into(),
        sql: "CREATE TABLE partial_ddl (id INTEGER PRIMARY KEY); \
              THIS IS NOT VALID SQL;"
            .into(),
    };

    let error =
        apply_migrations(&conn, &[migration]).expect_err("broken migration must surface an error");
    assert!(
        matches!(error, MigrationError::Sql(_)),
        "expected Sql error for mid-migration failure, got {error}"
    );

    // Invariant 1: no bookkeeping row for the failed version.
    let recorded: Option<u32> = conn
        .query_row(
            "SELECT version FROM schema_migrations WHERE version = 42",
            [],
            |row| row.get(0),
        )
        .optional()
        .unwrap();
    assert!(
        recorded.is_none(),
        "schema_migrations must not record a failed migration"
    );

    // Invariant 2: the partial DDL was rolled back — no ghost table.
    let ddl_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master \
             WHERE type='table' AND name='partial_ddl'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        ddl_count, 0,
        "partial DDL must be rolled back when a mid-migration statement fails"
    );

    // Invariant 3: connection is back in autocommit mode (no dangling
    // transaction the next call would stumble over).
    assert!(
        conn.is_autocommit(),
        "connection must be in autocommit after rollback path"
    );
}

/// Regression for #2260 / fixed by #2740: models the worst-case
/// crash — a prior `apply_migrations` run recorded a
/// `schema_migrations` row whose checksum matches the current code,
/// but the actual DDL side effects are missing (e.g. the writer
/// crashed after the bookkeeping INSERT but before COMMIT, or a
/// developer dropped the table out-of-band during debugging).
///
/// Previously the runner silently treated the row as "already
/// applied" and `continue`d. #2740 closes that gap with a post-
/// checksum audit: every DDL object declared by the migration file
/// must be present in `sqlite_schema`, else we fail with a typed
/// `CorruptedSchema` error pointing at the missing object.
#[test]
fn reopen_after_crashed_migration_returns_corrupted_schema() {
    let conn = open_memory_db();
    ensure_schema_migrations_table(&conn).unwrap();

    // The migration the caller believes has already been applied.
    let migration = Migration {
        version: 7,
        name: "ghost_apply".into(),
        sql: "CREATE TABLE ghost (id INTEGER PRIMARY KEY);".into(),
    };
    let checksum = sha256_hex(&migration.sql);

    // Simulate the corruption: row present, DDL absent.
    conn.execute(
        "INSERT INTO schema_migrations (version, name, checksum) VALUES (?1, ?2, ?3)",
        rusqlite::params![migration.version, migration.name, checksum],
    )
    .unwrap();

    let error = apply_migrations(&conn, &[migration])
        .expect_err("runner must refuse to open a corrupted DB");
    match error {
        MigrationError::CorruptedSchema {
            version,
            missing_kind,
            missing_object,
            ..
        } => {
            assert_eq!(version, 7);
            assert_eq!(missing_kind, "table");
            assert_eq!(missing_object, "ghost");
        }
        other => panic!("expected CorruptedSchema, got {other:?}"),
    }

    // Invariant: the runner did NOT heal the DB (no DDL re-apply
    // fallback — the fix is detect-and-fail, not re-run).
    let ghost_exists: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master \
             WHERE type='table' AND name='ghost'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        ghost_exists, 0,
        "audit must not silently re-create missing DDL; failure is the contract"
    );
}

/// Regression for #2260: the `INSERT INTO schema_migrations`
/// bookkeeping row must be applied atomically with the DDL. If the
/// bookkeeping INSERT itself fails (e.g. because the
/// `schema_migrations` table was pre-created with a stricter
/// constraint that rejects the row), the runner must roll back the
/// DDL too — never leave the DB with a CREATE TABLE committed but
/// no record of it having been applied.
///
/// an earlier revision of the runner
/// relied on the next `BEGIN IMMEDIATE` (or connection close) to
/// clean up a half-open transaction after a failed bookkeeping
/// INSERT. Today's runner explicitly issues `ROLLBACK;` from the
/// `Ok(Err(..))` arm of `catch_unwind` (see the per-migration
/// transaction body above) so the DDL roll back is observable on
/// the same connection without waiting for the next migration's
/// `BEGIN`. This test pins the observable invariant the caller
/// cares about: *after* `apply_migrations` returns, the DDL is
/// gone and the connection is usable.
#[test]
fn migration_step_between_ddl_and_bookkeeping_is_atomic() {
    let conn = open_memory_db();

    // Pre-create schema_migrations with a CHECK constraint that
    // rejects any version the runner tries to record. `CREATE TABLE
    // IF NOT EXISTS` in the runner will leave this table alone, so
    // the DDL step succeeds inside the migration's transaction but
    // the subsequent bookkeeping INSERT fails the CHECK.
    conn.execute_batch(
        "CREATE TABLE schema_migrations (
            version  INTEGER PRIMARY KEY CHECK(version < 0),
            name     TEXT NOT NULL,
            checksum TEXT NOT NULL,
            applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
        ) STRICT;",
    )
    .unwrap();

    let migration = Migration {
        version: 1,
        name: "atomic_ddl".into(),
        sql: "CREATE TABLE atomic_ddl (id INTEGER PRIMARY KEY);".into(),
    };

    let result = apply_migrations(&conn, &[migration]);
    assert!(
        result.is_err(),
        "bookkeeping INSERT should fail the CHECK constraint, \
         surfacing a runner error"
    );

    // Core atomicity invariant: the DDL must NOT be visible — the
    // migration either fully committed (DDL + bookkeeping row) or
    // fully reverted. A visible CREATE TABLE with no matching
    // schema_migrations row is the "orphan schema" bug #2260 is
    // guarding against.
    let ddl_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master \
             WHERE type='table' AND name='atomic_ddl'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        ddl_count, 0,
        "DDL must roll back when bookkeeping INSERT fails — \
         otherwise the DB has an orphan schema the runner will \
         never know about"
    );

    // And no bookkeeping row was recorded either.
    let bookkept: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM schema_migrations WHERE version = 1",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(bookkept, 0, "no schema_migrations row for a failed apply");
}
