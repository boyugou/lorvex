use super::*;

use crate::test_support::test_conn;

fn setup() -> rusqlite::Connection {
    test_conn()
}

fn seed_recurring_task(conn: &rusqlite::Connection) {
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at) \
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000000024', 'Test List', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-20T00:00:00Z', '2026-03-20T00:00:00Z')",
        [],
    )
    .expect("seed list");

    // Stays raw: TaskBuilder doesn't expose
    // `canonical_occurrence_date`, which the schema CHECK requires
    // alongside `recurrence`.
    conn.execute(
        "INSERT INTO tasks (
            id, title, status, list_id, priority, due_date, recurrence,
            recurrence_group_id, canonical_occurrence_date, version, created_at, updated_at
         ) VALUES (
            '01966a3f-7c8b-7d4e-8f3a-000000000004', 'Daily Task', 'open', '01966a3f-7c8b-7d4e-8f3a-000000000024', 2, '2026-03-20',
            ?1, 'group-1', '2026-03-20', '0000000000000_0000_a0a0a0a0a0a0a0a0',
            '2026-03-20T08:00:00Z', '2026-03-20T08:00:00Z'
         )",
        rusqlite::params![r#"{"FREQ":"DAILY","INTERVAL":1}"#],
    )
    .expect("seed recurring task");
}

#[test]
fn add_task_exception_with_conn_enqueues_updated_task_snapshot() {
    let conn = setup();
    seed_recurring_task(&conn);

    let task = add_task_exception_with_conn(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000004",
        "2026-03-22",
        "2026-03-22T12:00:00Z",
    )
    .expect("add task exception");

    assert_eq!(
        task.recurrence_exceptions.as_deref(),
        Some(r#"["2026-03-22"]"#)
    );

    // Verify sync outbox entry was created
    let (operation, payload): (String, String) = conn
        .query_row(
            "SELECT operation, payload
             FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2
             ORDER BY id DESC
             LIMIT 1",
            rusqlite::params![ENTITY_TASK, "01966a3f-7c8b-7d4e-8f3a-000000000004"],
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
        )
        .expect("load task outbox payload");
    let payload: serde_json::Value =
        serde_json::from_str(&payload).expect("task payload should be valid json");

    assert_eq!(operation, "upsert");
    assert_eq!(payload["id"], "01966a3f-7c8b-7d4e-8f3a-000000000004");
    assert_eq!(payload["recurrence_exceptions"], r#"["2026-03-22"]"#);
}

#[test]
fn remove_task_exception_with_conn_enqueues_updated_task_snapshot() {
    let conn = setup();
    seed_recurring_task(&conn);

    // First add an exception
    add_task_exception_with_conn(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000004",
        "2026-03-22",
        "2026-03-22T12:00:00Z",
    )
    .expect("add task exception");

    // Now remove it
    let task = remove_task_exception_with_conn(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000004",
        "2026-03-22",
        "2026-03-22T12:30:00Z",
    )
    .expect("remove task exception");

    assert_eq!(task.recurrence_exceptions, None);

    let payload: String = conn
        .query_row(
            "SELECT payload
             FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2
             ORDER BY id DESC
             LIMIT 1",
            rusqlite::params![ENTITY_TASK, "01966a3f-7c8b-7d4e-8f3a-000000000004"],
            |row| row.get::<_, String>(0),
        )
        .expect("load task outbox payload");
    let payload: serde_json::Value =
        serde_json::from_str(&payload).expect("task payload should be valid json");

    assert!(payload["recurrence_exceptions"].is_null());
}
