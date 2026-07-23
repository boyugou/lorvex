//! IPC test coverage for `reopen_task`. The reopen
//! transition is a destructive rewrite of the task's terminal
//! timestamps (completed_at, defer state) plus optional successor
//! cancel + reminder un-cancel — the audit flagged zero unit
//! coverage on the Tauri wrapper. These tests drive the
//! `_with_conn` entry point against an in-memory DB.
use super::*;

use crate::test_support::test_conn;

fn seed_task(conn: &rusqlite::Connection, id: &str, status: &str, completed_at: Option<&str>) {
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title("Reopen me")
        .status(status)
        .list_id(Some("inbox"))
        .completed_at(completed_at)
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-04-01T08:00:00Z")
        .insert(conn);
}

#[test]
fn reopen_task_with_conn_rejects_missing_task() {
    let conn = test_conn();
    let error = reopen_task_with_conn(&conn, "does-not-exist")
        .expect_err("missing task should be rejected");
    assert!(matches!(error, AppError::NotFound(_)));
}

#[test]
fn reopen_task_with_conn_rejects_already_open_without_side_effects() {
    let conn = test_conn();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000000f", "open", None);

    let error = reopen_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000000f")
        .expect_err("already-open task should not produce a reopen mutation");
    match error {
        AppError::Validation(message) => {
            assert!(message.contains("already open"), "unexpected: {message}");
        }
        other => panic!("expected Validation, got {other:?}"),
    }

    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = '01966a3f-7c8b-7d4e-8f3a-00000000000f'",
            [],
            |row| row.get(0),
        )
        .expect("count outbox rows");
    assert_eq!(
        outbox_count, 0,
        "already-open reopen must not enqueue a no-op task upsert"
    );
    let changelog_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE entity_id = '01966a3f-7c8b-7d4e-8f3a-00000000000f'",
            [],
            |row| row.get(0),
        )
        .expect("count changelog rows");
    assert_eq!(
        changelog_count, 0,
        "already-open reopen must not log a no-op reopen"
    );
}

#[test]
fn reopen_task_with_conn_reopens_completed_task_and_clears_completed_at() {
    let conn = test_conn();
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000000d",
        "completed",
        Some("2026-04-01T08:30:00Z"),
    );

    let task = reopen_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000000d")
        .expect("reopen completed task should succeed");

    assert_eq!(task.status, "open");
    assert!(
        task.completed_at.is_none(),
        "completed_at must be cleared on reopen, got {:?}",
        task.completed_at
    );

    // Sync outbox row emitted.
    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = '01966a3f-7c8b-7d4e-8f3a-00000000000d'",
            [],
            |row| row.get(0),
        )
        .expect("count outbox rows");
    assert!(outbox_count >= 1);
}

#[test]
fn reopen_task_with_conn_reopens_cancelled_task() {
    let conn = test_conn();
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000000e",
        "cancelled",
        None,
    );

    let task = reopen_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000000e")
        .expect("reopen cancelled task should succeed");

    assert_eq!(task.status, "open");
}
