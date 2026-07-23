use super::*;

use crate::test_support::test_conn;

fn setup() -> rusqlite::Connection {
    test_conn()
}

#[test]
fn clear_all_raw_input_with_conn_rolls_back_when_sync_enqueue_fails() {
    let conn = setup();
    // Stays raw: TaskBuilder doesn't expose `raw_input`, which is
    // the field this clear-all-raw-input test exercises.
    conn.execute(
        "INSERT INTO tasks (id, title, raw_input, status, version, created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000000001', 'Task 1', 'captured text', 'open', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T08:00:00Z', '2026-03-29T08:00:00Z')",
        [],
    )
    .expect("seed task with raw input");
    conn.execute("DROP TABLE sync_outbox", [])
        .expect("drop sync_outbox to force enqueue failure");

    let error = clear_all_raw_input_with_conn(&conn, "2026-03-29T09:00:00Z")
        .expect_err("enqueue failure should roll back raw_input clearing");

    let message = error.to_string();
    assert!(
        message.contains("database error") || message.contains("no such table"),
        "unexpected error: {message}"
    );

    let raw_input: Option<String> = conn
        .query_row(
            "SELECT raw_input FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000001'",
            [],
            |row| row.get(0),
        )
        .expect("read rolled-back raw_input");
    assert_eq!(raw_input.as_deref(), Some("captured text"));
}
