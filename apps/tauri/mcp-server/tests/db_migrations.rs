use lorvex_mcp_server::db::open_database_for_path;
use tempfile::tempdir;

#[test]
fn open_db_applies_minimal_schema() {
    let dir = tempdir().expect("create temp dir");
    let db_path = dir.path().join("nested").join("db.sqlite");

    let conn = open_database_for_path(&db_path).expect("open db");

    // Verify all core tables exist
    let mut stmt = conn
        .prepare(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
        )
        .expect("prepare");

    let names = stmt
        .query_map([], |row| row.get::<_, String>(0))
        .expect("query")
        .map(|x| x.expect("row"))
        // Filter out FTS5 shadow tables (e.g. tasks_fts_config, tasks_fts_data, etc.)
        // for the porter-tokenized FTS table only. The trigram FTS table
        // (`tasks_fts_trigram`) is asserted explicitly in `expected` below
        // so a regression that drops it from the schema surfaces here —
        // pre-fix this filter swallowed both the shadow tables AND the
        // trigram virtual table, hiding CJK-substring-search regressions.
        .filter(|name| {
            !(name.starts_with("tasks_fts_") && name != "tasks_fts" && name != "tasks_fts_trigram")
        })
        .collect::<Vec<_>>();

    let expected = vec![
        "ai_changelog",
        "ai_changelog_entities",
        "calendar_event_attendee_shadow",
        "calendar_event_attendees",
        "calendar_event_recurrence_exceptions",
        "calendar_events",
        "calendar_events_fts",
        "calendar_events_fts_config",
        "calendar_events_fts_data",
        "calendar_events_fts_docsize",
        "calendar_events_fts_idx",
        "calendar_subscriptions",
        "current_focus",
        "current_focus_items",
        "daily_review_list_links",
        "daily_review_task_links",
        "daily_reviews",
        "device_state",
        "error_logs",
        "focus_schedule",
        "focus_schedule_blocks",
        "habit_completions",
        "habit_reminder_delivery_state",
        "habit_reminder_policies",
        "habit_weekdays",
        "habits",
        "lists",
        "local_counters",
        "local_sync_owner",
        "mcp_host_authority",
        "mcp_idempotency",
        "memories",
        "memory_revisions",
        "preferences",
        "provider_calendar_events",
        "provider_scope_runtime_state",
        "schema_migrations",
        "sync_checkpoints",
        "sync_conflict_log",
        "sync_device_cursors",
        "sync_outbox",
        "sync_payload_shadow",
        "sync_pending_inbox",
        "sync_quarantine_blocklist",
        "sync_tombstones",
        "tags",
        "task_calendar_event_links",
        "task_checklist_items",
        "task_dependencies",
        "task_provider_event_links",
        "task_recurrence_exceptions",
        "task_reminder_delivery_state",
        "task_reminders",
        "task_tags",
        "tasks",
        "tasks_fts",
        "tasks_fts_trigram",
    ];

    assert_eq!(
        names, expected,
        "All tables should be created by the consolidated schema"
    );

    // Verify is_pinned column does NOT exist (removed)
    let has_is_pinned = conn
        .prepare("SELECT COUNT(*) FROM pragma_table_info('tasks') WHERE name = 'is_pinned'")
        .expect("prepare is_pinned check")
        .query_row([], |row| row.get::<_, i64>(0))
        .expect("query is_pinned");
    assert_eq!(has_is_pinned, 0, "is_pinned column should not exist");

    // Verify depends_on column does NOT exist (migrated to task_dependencies edge table)
    let has_depends_on = conn
        .prepare("SELECT COUNT(*) FROM pragma_table_info('tasks') WHERE name = 'depends_on'")
        .expect("prepare depends_on check")
        .query_row([], |row| row.get::<_, i64>(0))
        .expect("query depends_on");
    assert_eq!(
        has_depends_on, 0,
        "depends_on column should not exist on tasks (migrated to task_dependencies)"
    );

    // Verify tags column does NOT exist (migrated to task_tags join table)
    let has_tags = conn
        .prepare("SELECT COUNT(*) FROM pragma_table_info('tasks') WHERE name = 'tags'")
        .expect("prepare tags check")
        .query_row([], |row| row.get::<_, i64>(0))
        .expect("query tags");
    assert_eq!(
        has_tags, 0,
        "tags column should not exist on tasks (migrated to task_tags)"
    );

    // Verify timezone columns exist on day-scoped tables
    for table in &["current_focus", "focus_schedule", "daily_reviews"] {
        let has_tz = conn
            .prepare(&format!(
                "SELECT COUNT(*) FROM pragma_table_info('{table}') WHERE name = 'timezone'"
            ))
            .expect("prepare tz check")
            .query_row([], |row| row.get::<_, i64>(0))
            .expect("query tz");
        assert_eq!(has_tz, 1, "{table} should have timezone column");
    }
}
