use super::support::index_exists;
use lorvex_store::open_db_in_memory;

#[test]
fn error_logs_indexes_survive_table_rebuild() {
    // Regression for R15: migration 004 rebuilds the `error_logs` table
    // via `DROP TABLE; RENAME TO`, which in SQLite cascades through
    // indexes. Before migration 006 was added, the two `error_logs`
    // indexes defined in 001_schema.sql were silently wiped on every
    // install. Ensure both are present after full migration.
    let conn = open_db_in_memory().unwrap();
    assert!(
        index_exists(&conn, "idx_error_logs_created_at"),
        "idx_error_logs_created_at must exist after all migrations"
    );
    assert!(
        index_exists(&conn, "idx_error_logs_source"),
        "idx_error_logs_source must exist after all migrations"
    );
}

#[test]
fn restore_missing_indexes_migration_adds_expected_indexes() {
    // Regression for R15: verify migration 006 installs every index
    // the R15 audit identified as missing from hot query paths.
    let conn = open_db_in_memory().unwrap();

    // sync_outbox: partial index on unsynced rows for get_pending.
    assert!(
        index_exists(&conn, "idx_sync_outbox_unsynced"),
        "idx_sync_outbox_unsynced missing — get_pending will full-scan"
    );

    // focus_schedule_blocks.task_id for DELETE-by-task on task removal.
    assert!(
        index_exists(&conn, "idx_focus_schedule_blocks_task"),
        "idx_focus_schedule_blocks_task missing — hard delete will full-scan"
    );

    // sync_tombstones GC by version and deleted_at.
    assert!(
        index_exists(&conn, "idx_sync_tombstones_version"),
        "idx_sync_tombstones_version missing — watermark GC full-scans"
    );
    assert!(
        index_exists(&conn, "idx_sync_tombstones_deleted_at"),
        "idx_sync_tombstones_deleted_at missing — fallback GC full-scans"
    );

    // sync_conflict_log GC and type filter.
    assert!(
        index_exists(&conn, "idx_sync_conflict_log_resolved_at"),
        "idx_sync_conflict_log_resolved_at missing — gc_conflicts full-scans"
    );
    assert!(
        index_exists(&conn, "idx_sync_conflict_log_type_id"),
        "idx_sync_conflict_log_type_id missing — get_conflicts_by_type full-scans"
    );
}
