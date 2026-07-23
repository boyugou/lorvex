use super::*;
use lorvex_domain::naming::TaskStatus;
use lorvex_store::test_support::test_conn;

fn tid(s: &str) -> lorvex_domain::TaskId {
    lorvex_domain::TaskId::from_trusted(s.to_string())
}

fn insert_task(conn: &Connection, id: &str, status: &str) {
    conn.execute(
        "INSERT INTO tasks (id, title, status, version, created_at, updated_at)
         VALUES (?1, ?1, ?2, '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
        rusqlite::params![id, status],
    ).unwrap();
}

#[test]
fn complete_cancels_reminders() {
    let conn = test_conn();
    insert_task(&conn, "t1", "completed");
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES ('r1', 't1', '2026-04-01T09:00:00Z', '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')",
        [],
    ).unwrap();

    let result = apply_status_transition_side_effects(
        &conn,
        &tid("t1"),
        TaskStatus::Open,
        TaskStatus::Completed,
        "2026-03-26T10:00:00Z",
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
    )
    .unwrap();

    assert_eq!(result.cancelled_reminder_ids, vec!["r1"]);
    assert!(result.affected_dependent_ids.is_empty());
}

#[test]
fn cancel_removes_deps_and_cancels_reminders() {
    let conn = test_conn();
    insert_task(&conn, "t1", "cancelled");
    insert_task(&conn, "t2", "open");
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at)
         VALUES ('t2', 't1', '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();

    let result = apply_status_transition_side_effects(
        &conn,
        &tid("t1"),
        TaskStatus::Open,
        TaskStatus::Cancelled,
        "2026-03-26T10:00:00Z",
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
    )
    .unwrap();

    assert_eq!(result.affected_dependent_ids, vec!["t2"]);

    let dep_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_dependencies WHERE depends_on_task_id = 't1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(dep_count, 0);
}

#[test]
fn reopen_is_noop() {
    let conn = test_conn();
    insert_task(&conn, "t1", "open");

    let result = apply_status_transition_side_effects(
        &conn,
        &tid("t1"),
        TaskStatus::Completed,
        TaskStatus::Open,
        "2026-03-26T10:00:00Z",
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
    )
    .unwrap();

    assert!(result.cancelled_reminder_ids.is_empty());
    assert!(result.affected_dependent_ids.is_empty());
}
