use super::{db_path, with_db_path_env_for_test};
use lorvex_store::migration::apply_migrations;
use lorvex_store::schema::all_migrations;
use rusqlite::Connection;

#[test]
fn db_path_ignores_empty_db_path_env_override() {
    with_db_path_env_for_test("", || {
        let resolved = db_path();
        assert!(
            !resolved.as_os_str().is_empty(),
            "Expected empty DB_PATH env var to be ignored"
        );
        assert_eq!(
            resolved.file_name().and_then(|value| value.to_str()),
            Some("db.sqlite"),
            "Expected default db filename when DB_PATH override is empty"
        );
        assert_eq!(
            resolved
                .parent()
                .and_then(|parent| parent.file_name())
                .and_then(|value| value.to_str()),
            Some("Lorvex"),
            "Expected default Lorvex data directory when DB_PATH override is empty"
        );
    });
}

#[test]
fn db_path_trims_db_path_env_override() {
    with_db_path_env_for_test("  /tmp/lorvex-spaced-path.sqlite  ", || {
        let resolved = db_path();
        assert_eq!(
            resolved.to_string_lossy(),
            "/tmp/lorvex-spaced-path.sqlite",
            "Expected DB_PATH override to be trimmed before path conversion"
        );
    });
}

fn column_names(conn: &Connection, table: &str) -> Vec<String> {
    let sql = format!("SELECT name FROM pragma_table_info('{table}') ORDER BY cid");
    let mut stmt = conn.prepare(&sql).expect("prepare pragma_table_info");
    stmt.query_map([], |row| row.get::<_, String>(0))
        .expect("query column names")
        .collect::<Result<Vec<_>, _>>()
        .expect("collect column names")
}

#[test]
fn apply_migrations_creates_final_schema_from_empty_database() {
    let conn = Connection::open_in_memory().expect("open in-memory db");

    apply_migrations(&conn, &all_migrations()).expect("apply migrations");

    let task_columns = column_names(&conn, "tasks");
    assert!(!task_columns.contains(&"tags".to_string()));

    let list_columns = column_names(&conn, "lists");
    assert!(
        !list_columns.contains(&"sort_order".to_string()),
        "lists.sort_order should not exist"
    );

    let habit_columns = column_names(&conn, "habits");
    assert!(
        !habit_columns.contains(&"sort_order".to_string()),
        "habits.sort_order should not exist"
    );

    let focus_columns = column_names(&conn, "current_focus");
    assert!(!focus_columns.contains(&"task_ids".to_string()));

    let schedule_columns = column_names(&conn, "focus_schedule");
    for forbidden in [
        "id",
        "blocks",
        "proposed_at",
        "accepted_at",
        "modified",
        "completion_rate",
    ] {
        assert!(
            !schedule_columns.contains(&forbidden.to_string()),
            "focus_schedule.{forbidden} should not exist in the canonical schema"
        );
    }

    let review_columns = column_names(&conn, "daily_reviews");
    for forbidden in ["linked_task_ids", "linked_list_ids"] {
        assert!(
            !review_columns.contains(&forbidden.to_string()),
            "daily_reviews.{forbidden} should not exist in the canonical schema"
        );
    }

    let event_columns = column_names(&conn, "calendar_events");
    assert!(!event_columns.contains(&"attendees".to_string()));

    let changelog_columns = column_names(&conn, "ai_changelog");
    for forbidden in [
        "before_state",
        "after_state",
        "is_undone",
        "undone_at",
        "undone_by",
    ] {
        assert!(
            !changelog_columns.contains(&forbidden.to_string()),
            "ai_changelog.{forbidden} should not exist in the canonical schema"
        );
    }
}
