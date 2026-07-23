use super::*;
use crate::db::open_database_for_path;
use chrono::Duration;
use rusqlite::Connection;
use tempfile::tempdir;

fn open_temp_db() -> Connection {
    let dir = tempdir().expect("create temp dir");
    let db_path = dir.path().join("db.sqlite");
    let conn = open_database_for_path(&db_path).expect("open temp db");
    let _leaked = Box::leak(Box::new(dir));
    conn
}

fn seed_ui_view_state(conn: &Connection, value: &Value) {
    let canonical = serde_json::to_string(value).expect("serialize ui_view_state");
    conn.execute(
        "INSERT INTO device_state (key, value) VALUES (?1, ?2)
         ON CONFLICT(key) DO UPDATE SET value = ?2",
        params![UI_VIEW_STATE_KEY, canonical],
    )
    .expect("seed ui_view_state row");
}

#[test]
#[serial_test::serial(hlc)]
fn get_ui_view_state_returns_not_available_when_row_missing() {
    let conn = open_temp_db();

    let response = get_ui_view_state(&conn).expect("tool response");
    let payload: Value = serde_json::from_str(&response).expect("parse payload");

    assert_eq!(payload.get("available"), Some(&Value::Bool(false)));
    assert_eq!(
        payload.get("reason").and_then(Value::as_str),
        Some("never_written"),
    );
}

#[test]
#[serial_test::serial(hlc)]
fn get_ui_view_state_projects_known_fields_when_fresh() {
    let conn = open_temp_db();
    // "Now" for the tool call.
    let now = Utc::now();
    // Snapshot written a few seconds ago — well within the freshness
    // window.
    let stamped = (now - Duration::seconds(30)).to_rfc3339();

    seed_ui_view_state(
        &conn,
        &json!({
            "last_updated_at": stamped,
            "active_view": "list:list-work",
            "selected_task_id": "task-abc",
            "search_query": null,
            "list_filter_id": "list-work",
            "tag_filters": ["focus", "deep"],
            "priority_filter": 1,
            "focus_mode_active": false,
            "focus_mode_task_id": null,
            // Forward-compat field that the frontend might add later.
            "undocumented_extra": {"nested": true},
        }),
    );

    let response = get_ui_view_state_at(&conn, now).expect("tool response");
    let payload: Value = serde_json::from_str(&response).expect("parse payload");

    assert_eq!(payload.get("available"), Some(&Value::Bool(true)));
    assert_eq!(
        payload.get("active_view").and_then(Value::as_str),
        Some("list:list-work"),
    );
    assert_eq!(
        payload.get("selected_task_id").and_then(Value::as_str),
        Some("task-abc"),
    );
    assert_eq!(
        payload.get("list_filter_id").and_then(Value::as_str),
        Some("list-work"),
    );
    assert_eq!(
        payload
            .get("tag_filters")
            .and_then(Value::as_array)
            .map(Vec::len),
        Some(2),
    );
    assert_eq!(
        payload.get("priority_filter").and_then(Value::as_i64),
        Some(1),
    );
    assert_eq!(payload.get("focus_mode_active"), Some(&Value::Bool(false)),);
    // Unknown / forward-compat fields must NOT leak into the tool
    // contract — only the documented shape is surfaced.
    assert!(payload.get("undocumented_extra").is_none());
}

#[test]
#[serial_test::serial(hlc)]
fn get_ui_view_state_flags_snapshot_older_than_threshold_as_stale() {
    let conn = open_temp_db();
    let now = Utc::now();
    // Eleven minutes ago — one minute past the 10-minute threshold.
    let stamped = (now - Duration::seconds(STALE_THRESHOLD_SECS + 60)).to_rfc3339();

    seed_ui_view_state(
        &conn,
        &json!({
            "last_updated_at": stamped,
            "active_view": "today",
            "selected_task_id": "task-xyz",
        }),
    );

    let response = get_ui_view_state_at(&conn, now).expect("tool response");
    let payload: Value = serde_json::from_str(&response).expect("parse payload");

    assert_eq!(payload.get("available"), Some(&Value::Bool(false)));
    assert_eq!(payload.get("reason").and_then(Value::as_str), Some("stale"),);
    // Payload fields must NOT leak when stale — the assistant
    // shouldn't be able to inspect a day-old filter.
    assert!(payload.get("active_view").is_none());
    assert!(payload.get("selected_task_id").is_none());
}
