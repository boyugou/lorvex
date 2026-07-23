use super::support::{column_exists, table_exists};
use lorvex_store::open_db_in_memory;

#[test]
fn fresh_db_applies_all_migrations() {
    let conn = open_db_in_memory().unwrap();

    // Core tables from the consolidated schema.
    assert!(table_exists(&conn, "tasks"));
    assert!(table_exists(&conn, "lists"));
    assert!(table_exists(&conn, "ai_changelog"));
    assert!(table_exists(&conn, "habits"));
    assert!(table_exists(&conn, "tags"));
    assert!(table_exists(&conn, "task_tags"));

    // Schema migrations bookkeeping table.
    assert!(table_exists(&conn, "schema_migrations"));

    // All migrations applied. Asserts the recorded count matches the
    // authoritative migration list so adding a new migration to
    // `src/schema/mod.rs::all_migrations()` without updating this test
    // can't silently regress — see audit finding re: stale `6`
    // literal while the list had grown to 8.
    let recorded_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM schema_migrations", [], |row| {
            row.get(0)
        })
        .unwrap();
    let expected_count = lorvex_store::schema::all_migrations().len() as i64;
    assert_eq!(recorded_count, expected_count);
}

#[test]
fn convergence_tables_exist() {
    let conn = open_db_in_memory().unwrap();

    // Convergence tables (now part of the single schema).
    assert!(table_exists(&conn, "sync_tombstones"));
    assert!(table_exists(&conn, "sync_conflict_log"));
    assert!(table_exists(&conn, "sync_pending_inbox"));
    assert!(table_exists(&conn, "sync_payload_shadow"));
    assert!(table_exists(&conn, "task_reminder_delivery_state"));
    assert!(table_exists(&conn, "provider_scope_runtime_state"));

    // Sync outbox (now part of the single schema).
    assert!(table_exists(&conn, "sync_outbox"));
}

#[test]
fn version_columns_exist() {
    let conn = open_db_in_memory().unwrap();

    let tables_with_version = [
        "tasks",
        "lists",
        "habits",
        "tags",
        "calendar_events",
        "calendar_subscriptions",
        "preferences",
        "memories",
        "daily_reviews",
        "current_focus",
        "focus_schedule",
        "task_reminders",
        "habit_reminder_policies",
        "task_tags",
        "task_dependencies",
        "task_calendar_event_links",
        "habit_completions",
    ];

    for table in &tables_with_version {
        assert!(
            column_exists(&conn, table, "version"),
            "table '{table}' should have a 'version' column"
        );
    }
}

#[test]
fn convergence_columns_exist() {
    let conn = open_db_in_memory().unwrap();

    // tasks.recurrence_instance_key
    assert!(column_exists(&conn, "tasks", "recurrence_instance_key"));

    // tags.display_name and tags.lookup_key
    assert!(column_exists(&conn, "tags", "display_name"));
    assert!(column_exists(&conn, "tags", "lookup_key"));

    // ai_changelog.source_device_id
    assert!(column_exists(&conn, "ai_changelog", "source_device_id"));

    // provider_calendar_events.attendees_json (migration 002)
    assert!(column_exists(
        &conn,
        "provider_calendar_events",
        "attendees_json"
    ));
}

#[test]
fn idempotent_double_apply() {
    // First open creates and applies all migrations.
    let conn = open_db_in_memory().unwrap();

    // Re-apply migrations on the same connection (simulates restart).
    lorvex_store::apply_migrations(&conn, &lorvex_store::schema::all_migrations()).unwrap();

    // Everything should still be intact.
    assert!(table_exists(&conn, "sync_tombstones"));
    assert!(column_exists(&conn, "tasks", "version"));

    let recorded_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM schema_migrations", [], |row| {
            row.get(0)
        })
        .unwrap();
    let expected_count = lorvex_store::schema::all_migrations().len() as i64;
    assert_eq!(recorded_count, expected_count);
}

#[test]
fn fts_table_exists() {
    let conn = open_db_in_memory().unwrap();

    // tasks_fts is a virtual table; it appears in sqlite_master as type='table'.
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE name='tasks_fts'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count, 1);
}
