use super::*;
use crate::contract::{BatchCreateTaskInput, BatchCreateTasksArgs};
use crate::db::open_database_for_path;
use rusqlite::params;
use tempfile::tempdir;

fn open_temp_db() -> Connection {
    // The schema seeds the canonical 'inbox' list + default_list_id
    // preference, so no extra list insertion is needed here.
    let dir = tempdir().expect("create temp dir");
    let db_path = dir.path().join("db.sqlite");
    let conn = open_database_for_path(&db_path).expect("open temp db");
    let _leaked = Box::leak(Box::new(dir));
    conn
}

fn simple_task_input(title: &str) -> BatchCreateTaskInput {
    BatchCreateTaskInput {
        title: title.to_string(),
        list_id: Some("inbox".to_string()),
        priority: None,
        due_date: None,
        due_time: None,
        estimated_minutes: None,
        tags: None,
        body: None,
        raw_input: None,
        ai_notes: None,
        depends_on: None,
        reminders: None,
        recurrence: None,
        planned_date: None,
        completed: None,
    }
}

// batch_create_tasks returns an undo_token whose `created_ids` list
// matches the tasks emitted in the response. A reverse write uses
// that list to delete every freshly-minted row.
#[test]
#[serial_test::serial(hlc)]
fn batch_create_tasks_returns_undo_token_with_created_ids() {
    let _hlc_guard = crate::runtime::change_tracking::hlc_test_mutex()
        .lock()
        .expect("hlc test mutex");
    crate::runtime::change_tracking::reset_thread_hlc_for_tests();
    let conn = open_temp_db();
    let args = BatchCreateTasksArgs {
        tasks: vec![simple_task_input("Write tests"), simple_task_input("Ship")],
        include_advice: None,
        idempotency_key: None,
        dry_run: false,
    };
    let payload = batch_create_tasks(&conn, args).expect("batch_create_tasks");
    let value: serde_json::Value = serde_json::from_str(&payload).unwrap();

    let undo_raw = value["undo_token"].as_str().expect("undo_token present");
    let token: crate::runtime::undo::McpUndoToken =
        serde_json::from_str(undo_raw).expect("token parses");
    assert_eq!(
        token.kind,
        crate::runtime::undo::McpUndoKind::BatchCreateTasks
    );
    assert_eq!(token.created_ids.len(), 2, "token must list both ids");

    let response_ids: Vec<String> = value["tasks"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["id"].as_str().unwrap().to_string())
        .collect();
    for id in &response_ids {
        assert!(
            token.created_ids.contains(id),
            "token must include created id {id}"
        );
    }
}

#[test]
#[serial_test::serial(hlc)]
fn batch_create_tasks_with_offset_reminder_persists_canonical_utc_timestamp() {
    let _hlc_guard = crate::runtime::change_tracking::hlc_test_mutex()
        .lock()
        .expect("hlc test mutex");
    crate::runtime::change_tracking::reset_thread_hlc_for_tests();
    let conn = open_temp_db();
    let mut task = simple_task_input("Batch offset reminder");
    task.reminders = Some(vec!["2026-12-01T09:00:00-05:00".to_string()]);
    let args = BatchCreateTasksArgs {
        tasks: vec![task],
        include_advice: None,
        idempotency_key: None,
        dry_run: false,
    };

    let payload = batch_create_tasks(&conn, args).expect("batch_create_tasks");
    let value: serde_json::Value = serde_json::from_str(&payload).unwrap();
    let task_id = value["tasks"][0]["id"].as_str().expect("task id");
    assert_eq!(
        value["tasks"][0]["reminders"][0]["reminder_at"].as_str(),
        Some("2026-12-01T14:00:00.000Z")
    );

    let stored: String = conn
        .query_row(
            "SELECT reminder_at FROM task_reminders WHERE task_id = ?1",
            [task_id],
            |row| row.get(0),
        )
        .expect("load reminder_at");
    assert_eq!(stored, "2026-12-01T14:00:00.000Z");
    let due = lorvex_store::repositories::task::reminders::get_due_task_reminders(
        &conn,
        "2026-12-02T00:00:00.000Z",
        10,
    )
    .expect("canonical reminder should be readable by due-reminder query");
    assert_eq!(due.rows.len(), 1);
    assert_eq!(due.rows[0].task_id, task_id);
}

// The batch_create outbox envelopes are enqueued plain (immediately
// dispatchable); the response still carries the undo token whose
// created_ids identify the rows a reverse write would remove.
#[test]
#[serial_test::serial(hlc)]
fn batch_create_tasks_enqueues_plain_envelopes() {
    let _hlc_guard = crate::runtime::change_tracking::hlc_test_mutex()
        .lock()
        .expect("hlc test mutex");
    crate::runtime::change_tracking::reset_thread_hlc_for_tests();
    let conn = open_temp_db();
    let args = BatchCreateTasksArgs {
        tasks: vec![simple_task_input("One")],
        include_advice: None,
        idempotency_key: None,
        dry_run: false,
    };
    let payload = batch_create_tasks(&conn, args).expect("batch_create_tasks");
    let value: serde_json::Value = serde_json::from_str(&payload).unwrap();
    let token: crate::runtime::undo::McpUndoToken =
        serde_json::from_str(value["undo_token"].as_str().unwrap()).unwrap();

    let created_id = &token.created_ids[0];
    let envelope_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'task' AND entity_id = ?1",
            params![created_id],
            |row| row.get(0),
        )
        .expect("created task must have outbox envelope");
    assert!(
        envelope_count >= 1,
        "created task must enqueue an outbox envelope"
    );
}
