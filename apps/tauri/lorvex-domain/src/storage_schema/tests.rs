use super::*;

#[test]
fn identifies_all_external_payload_bool_columns() {
    for (table, column) in SQLITE_BOOL_COLUMNS {
        assert!(
            is_sqlite_bool_column(table, column),
            "{table}.{column} should be marked as an external JSON bool",
        );
    }
}

#[test]
fn rejects_non_bool_columns() {
    assert!(!is_sqlite_bool_column("tasks", "priority"));
    assert!(!is_sqlite_bool_column(
        "habit_reminder_policies",
        "reminder_time"
    ));
    assert!(!is_sqlite_bool_column("calendar_events", "title"));
}
