use super::*;
use crate::db::open_database_for_path;
use tempfile::tempdir;

fn open_temp_db_with_task(task_id: &str, title: &str) -> Connection {
    let dir = tempdir().expect("create temp dir");
    let db_path = dir.path().join("db.sqlite");
    let conn = open_database_for_path(&db_path).expect("open temp db");
    let _leaked = Box::leak(Box::new(dir));
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(task_id)
        .title(title)
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-04-18T09:00:00.000000Z")
        .list_id(Some("inbox"))
        .insert(&conn);
    conn
}

/// pre-fix the audit row carried
/// `operation: "batch_update"`, indistinguishable from a generic
/// batch field edit. Sister surfaces use `batch_cancel`; this
/// test pins the corrected label so a future refactor can't
/// silently regress the classification.
#[test]
#[serial_test::serial(hlc)]
fn batch_cancel_tasks_in_list_logs_batch_cancel_operation() {
    let conn = open_temp_db_with_task("01966a3f-7c8b-7d4e-8f3a-000000000e01", "First");
    // The shared lifecycle helper enforces a transaction wrap;
    // mirror the router's BEGIN IMMEDIATE here so the test can
    // exercise the in-list cancel path directly.
    conn.execute("BEGIN", []).unwrap();

    batch_cancel_tasks_in_list(
        &conn,
        BatchCancelTasksInListArgs {
            list_id: "inbox".to_string(),
            statuses: None,
            cancel_series: None,
            dry_run: false,
            idempotency_key: None,
        },
    )
    .expect("batch_cancel_tasks_in_list");
    conn.execute("COMMIT", []).unwrap();

    let operation: String = conn
        .query_row(
            "SELECT operation FROM ai_changelog
             WHERE mcp_tool = 'batch_cancel_tasks_in_list'
             ORDER BY timestamp DESC LIMIT 1",
            [],
            |row| row.get(0),
        )
        .expect("query batch_cancel_tasks_in_list changelog");
    assert_eq!(operation, "batch_cancel");
}
