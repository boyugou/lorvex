use super::quoted_task_title;
use crate::contract::BatchCancelTasksArgs;
use serde_json::json;
use tempfile::tempdir;

fn open_temp_db() -> rusqlite::Connection {
    let dir = tempdir().expect("create temp dir");
    let db_path = dir.path().join("db.sqlite");
    let conn = crate::db::open_database_for_path(&db_path).expect("open temp db");
    let _leaked = Box::leak(Box::new(dir));
    conn
}

#[test]
#[serial_test::serial(hlc)]
fn quoted_task_title_rejects_missing_title() {
    let task = json!({ "id": "task-1" });
    let err = quoted_task_title(&task, "batch_cancel_tasks before-task")
        .unwrap_err()
        .to_string();
    assert!(err.contains("expected string field 'title'"));
}

#[test]
#[serial_test::serial(hlc)]
fn batch_cancel_reason_writes_ai_notes() {
    let conn = open_temp_db();
    let now = "2026-04-20T00:00:00Z";
    lorvex_store::test_support::TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-00000000012d")
        .title("Batch reason cancel")
        .status("open")
        .version("0000000000000_0000_0000000000000000")
        .created_at(now)
        .insert(&conn);

    conn.execute_batch("BEGIN IMMEDIATE;")
        .expect("begin immediate");
    super::batch_cancel_tasks(
        &conn,
        BatchCancelTasksArgs {
            task_ids: vec!["01966a3f-7c8b-7d4e-8f3a-00000000012d".to_string()],
            reason: Some("no longer needed".to_string()),
            cancel_series: None,
            dry_run: false,
            idempotency_key: None,
        },
    )
    .expect("batch cancel with reason");
    conn.execute_batch("COMMIT;").expect("commit batch cancel");

    let ai_notes: Option<String> = conn
        .query_row(
            "SELECT ai_notes
             FROM tasks
             WHERE id = '01966a3f-7c8b-7d4e-8f3a-00000000012d'",
            [],
            |row| row.get(0),
        )
        .expect("load batch-cancelled task notes");

    assert_eq!(ai_notes.as_deref(), Some("Cancelled: no longer needed"));
}
