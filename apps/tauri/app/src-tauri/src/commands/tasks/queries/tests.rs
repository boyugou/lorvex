use super::*;
use crate::error::AppError;
use rusqlite::params;

use crate::test_support::test_conn;

fn seed_list(conn: &rusqlite::Connection, list_id: &str) {
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES (?1, 'Inbox', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-04T00:00:00Z', '2026-04-04T00:00:00Z')",
        params![list_id],
    )
    .expect("seed list");
}

fn seed_task(conn: &rusqlite::Connection, task_id: &str, list_id: Option<&str>, status: &str) {
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(task_id)
        .title("Task")
        .status(status)
        .list_id(list_id)
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-04-04T00:00:00Z")
        .insert(conn);
}

fn seed_dated_task(
    conn: &rusqlite::Connection,
    task_id: &str,
    list_id: &str,
    due_date: Option<&str>,
    planned_date: Option<&str>,
) {
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(task_id)
        .title("Task")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-04-04T00:00:00Z")
        .list_id(Some(list_id))
        .due_date(due_date)
        .planned_date(planned_date)
        .insert(conn);
}

#[test]
fn get_task_with_conn_returns_none_for_missing_task() {
    let conn = test_conn();

    let task = get_task_with_conn(&conn, "missing-task").expect("missing task should not error");
    assert!(task.is_none());
}

#[test]
fn get_task_ipc_with_conn_rejects_malformed_id_before_lookup() {
    let conn = test_conn();

    let error = get_task_ipc_with_conn(&conn, "not-a-uuid")
        .expect_err("malformed IPC task id should be rejected");

    match error {
        AppError::Validation(message) => {
            assert!(
                message.contains("id is not a valid UUID"),
                "unexpected validation message: {message}"
            );
            assert!(
                message.contains("not-a-uuid"),
                "validation message should include rejected id: {message}"
            );
        }
        other => panic!("expected validation error, got {other:?}"),
    }
}

#[test]
fn get_task_ipc_with_conn_preserves_valid_uuid_missing_as_none() {
    let conn = test_conn();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-000000000340";

    let task = get_task_ipc_with_conn(&conn, task_id).expect("valid missing id should not error");

    assert!(task.is_none());
}

#[test]
fn get_tasks_blocked_by_ipc_with_conn_rejects_malformed_task_id_before_trusted_wrap() {
    let conn = test_conn();

    let error = get_tasks_blocked_by_ipc_with_conn(&conn, "not-a-uuid")
        .expect_err("malformed IPC task_id should be rejected");

    match error {
        AppError::Validation(message) => {
            assert!(
                message.contains("task_id is not a valid UUID"),
                "unexpected validation message: {message}"
            );
            assert!(
                message.contains("not-a-uuid"),
                "validation message should include rejected id: {message}"
            );
        }
        other => panic!("expected validation error, got {other:?}"),
    }
}

#[test]
fn get_tasks_blocked_by_ipc_with_conn_preserves_valid_uuid_missing_as_empty() {
    let conn = test_conn();
    let task_id = "01966a3f-7c8b-7d4e-8f3a-000000000342";

    let tasks = get_tasks_blocked_by_ipc_with_conn(&conn, task_id)
        .expect("valid missing id should not error");

    assert!(tasks.is_empty());
}

#[test]
fn get_task_with_conn_propagates_database_errors() {
    let conn = test_conn();
    conn.execute("DROP TABLE tasks", [])
        .expect("drop tasks table");

    let error = get_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000001")
        .expect_err("database errors should propagate");

    match error {
        AppError::Sql(_) => {}
        other => panic!("expected sql error, got {other:?}"),
    }
}

#[test]
fn get_recurring_tasks_with_conn_filters_by_recurrence_and_archive() {
    let conn = test_conn();
    seed_list(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000024");

    // Two recurring, one archived, one plain task. The schema CHECK
    // constraint requires a recurrence rule to carry a due_date,
    // recurrence_group_id, and canonical_occurrence_date so the
    // sync merge path has a stable anchor per instance (see
    // migration 009_priority_effective + aggregate merge).
    // Stays raw: TaskBuilder doesn't expose
    // `canonical_occurrence_date`, which is required by the CHECK.
    conn.execute(
        "INSERT INTO tasks (
            id, title, status, list_id, recurrence, due_date,
            recurrence_group_id, canonical_occurrence_date,
            version, created_at, updated_at
         ) VALUES (
            '01966a3f-7c8b-7d4e-8f3a-000000000017', 'Weekly', 'open', '01966a3f-7c8b-7d4e-8f3a-000000000024',
            '{\"FREQ\":\"WEEKLY\"}', '2026-04-06',
            'grp-weekly', '2026-04-06',
            '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-04T00:00:00Z', '2026-04-04T00:00:00Z'
         )",
        [],
    )
    .expect("seed weekly task");
    conn.execute(
        "INSERT INTO tasks (
            id, title, status, list_id, recurrence, due_date,
            recurrence_group_id, canonical_occurrence_date,
            version, created_at, updated_at
         ) VALUES (
            '01966a3f-7c8b-7d4e-8f3a-000000000016', 'Daily', 'open', '01966a3f-7c8b-7d4e-8f3a-000000000024',
            '{\"FREQ\":\"DAILY\"}', '2026-04-05',
            'grp-daily', '2026-04-05',
            '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-03T00:00:00Z', '2026-04-03T00:00:00Z'
         )",
        [],
    )
    .expect("seed daily task");
    conn.execute(
        "INSERT INTO tasks (
            id, title, status, list_id, recurrence, due_date,
            recurrence_group_id, canonical_occurrence_date,
            archived_at, version, created_at, updated_at
         ) VALUES (
            '01966a3f-7c8b-7d4e-8f3a-000000000010', 'Archived', 'open', '01966a3f-7c8b-7d4e-8f3a-000000000024',
            '{\"FREQ\":\"MONTHLY\"}', '2026-05-01',
            'grp-monthly', '2026-05-01',
            '2026-04-04T00:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0',
            '2026-04-02T00:00:00Z', '2026-04-02T00:00:00Z'
         )",
        [],
    )
    .expect("seed archived recurring task");
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000018",
        Some("01966a3f-7c8b-7d4e-8f3a-000000000024"),
        "open",
    );

    let tasks = get_recurring_tasks_with_conn(&conn).expect("load recurring tasks");
    let ids: Vec<&str> = tasks.iter().map(|task| task.id.as_str()).collect();
    // Archived rules are excluded by the archived_at guard;
    // non-recurring tasks are excluded by the recurrence predicate.
    assert!(ids.contains(&"01966a3f-7c8b-7d4e-8f3a-000000000017"));
    assert!(ids.contains(&"01966a3f-7c8b-7d4e-8f3a-000000000016"));
    assert!(!ids.contains(&"01966a3f-7c8b-7d4e-8f3a-000000000010"));
    assert!(!ids.contains(&"01966a3f-7c8b-7d4e-8f3a-000000000018"));
    assert_eq!(ids.len(), 2);
}

#[test]
fn get_task_with_conn_derives_canonical_lateness_state() {
    let conn = test_conn();
    seed_list(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000024");

    let today = lorvex_workflow::timezone::today_ymd_for_conn(&conn).expect("resolve today");
    let today_date = chrono::NaiveDate::parse_from_str(&today, "%Y-%m-%d").expect("parse today");
    let yesterday = (today_date - chrono::Duration::days(1))
        .format("%Y-%m-%d")
        .to_string();
    let tomorrow = (today_date + chrono::Duration::days(1))
        .format("%Y-%m-%d")
        .to_string();

    seed_dated_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000019",
        "01966a3f-7c8b-7d4e-8f3a-000000000024",
        Some(&tomorrow),
        Some(&yesterday),
    );
    seed_dated_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000001a",
        "01966a3f-7c8b-7d4e-8f3a-000000000024",
        Some(&yesterday),
        None,
    );
    seed_dated_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000001b",
        "01966a3f-7c8b-7d4e-8f3a-000000000024",
        Some(&yesterday),
        Some(&today),
    );

    let past_planned = get_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000019")
        .expect("load past planned task")
        .expect("task should exist");
    assert_eq!(
        past_planned.lateness_state,
        Some(lorvex_domain::TaskLateness::PastPlanned)
    );

    let overdue_unhandled = get_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000001a")
        .expect("load overdue unhandled task")
        .expect("task should exist");
    assert_eq!(
        overdue_unhandled.lateness_state,
        Some(lorvex_domain::TaskLateness::OverdueUnhandled)
    );

    let overdue_acknowledged = get_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000001b")
        .expect("load overdue acknowledged task")
        .expect("task should exist");
    assert_eq!(
        overdue_acknowledged.lateness_state,
        Some(lorvex_domain::TaskLateness::OverdueAcknowledged)
    );
}
