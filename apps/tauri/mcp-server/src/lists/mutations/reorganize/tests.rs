use super::*;
use crate::contract::{ReorganizeListArgs, ReorganizeListStrategy};
use crate::db::open_database_for_path;
use rusqlite::params;
use tempfile::tempdir;

fn open_temp_db_for_reorganize() -> Connection {
    let dir = tempdir().expect("create temp dir");
    let db_path = dir.path().join("db.sqlite");
    let conn = open_database_for_path(&db_path).expect("open temp db");
    let _leaked = Box::leak(Box::new(dir));
    let now = "2026-04-22T12:00:00.000000Z";
    let version = "0000000000000_0000_a0a0a0a0a0a0a0a0";
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at) VALUES ('list-reorg', 'Reorg', ?1, ?2, ?2)",
        params![version, now],
    )
    .unwrap();
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new("task-open")
        .title("Open task")
        .version(version)
        .created_at(now)
        .list_id(Some("list-reorg"))
        .insert(&conn);
    lorvex_store::test_support::fixtures::TaskBuilder::new("task-completed")
        .title("Completed task")
        .status("completed")
        .version(version)
        .created_at(now)
        .list_id(Some("list-reorg"))
        .completed_at(Some(now))
        .insert(&conn);
    conn
}

#[test]
#[serial_test::serial(hlc)]
fn manual_reorganize_rejects_missing_task_ids() {
    let conn = open_temp_db_for_reorganize();
    let err = reorganize_list(
        &conn,
        ReorganizeListArgs {
            id: "list-reorg".to_string(),
            strategy: ReorganizeListStrategy::Manual,
            task_ids: Some(vec!["task-open".to_string(), "task-missing".to_string()]),
            dry_run: false,
            idempotency_key: None,
        },
    )
    .expect_err("missing task id should fail");

    match err {
        McpError::Validation(message) => {
            assert!(message.contains("task-missing"));
            assert!(message.contains("not found"));
        }
        other => panic!("expected validation error, got {other:?}"),
    }
}

#[test]
#[serial_test::serial(hlc)]
fn manual_reorganize_requires_task_ids_argument() {
    let conn = open_temp_db_for_reorganize();
    let err = reorganize_list(
        &conn,
        ReorganizeListArgs {
            id: "list-reorg".to_string(),
            strategy: ReorganizeListStrategy::Manual,
            task_ids: None,
            dry_run: false,
            idempotency_key: None,
        },
    )
    .expect_err("missing task_ids should fail");

    match err {
        McpError::Validation(message) => {
            assert!(message.contains("task_ids required for manual strategy"));
        }
        other => panic!("expected validation error, got {other:?}"),
    }
}

#[test]
#[serial_test::serial(hlc)]
fn manual_reorganize_allows_empty_array_when_list_has_no_open_tasks() {
    let conn = open_temp_db_for_reorganize();
    conn.execute("DELETE FROM tasks WHERE list_id = 'list-reorg'", [])
        .unwrap();

    let payload = reorganize_list(
        &conn,
        ReorganizeListArgs {
            id: "list-reorg".to_string(),
            strategy: ReorganizeListStrategy::Manual,
            task_ids: Some(vec![]),
            dry_run: false,
            idempotency_key: None,
        },
    )
    .expect("empty manual reorder should succeed when there are no open tasks");

    let value: Value = serde_json::from_str(&payload).unwrap();
    assert_eq!(value["tasks"], Value::Array(vec![]));
}

#[test]
#[serial_test::serial(hlc)]
fn manual_reorganize_rejects_non_open_tasks() {
    let conn = open_temp_db_for_reorganize();
    let err = reorganize_list(
        &conn,
        ReorganizeListArgs {
            id: "list-reorg".to_string(),
            strategy: ReorganizeListStrategy::Manual,
            task_ids: Some(vec!["task-open".to_string(), "task-completed".to_string()]),
            dry_run: false,
            idempotency_key: None,
        },
    )
    .expect_err("completed task id should fail");

    match err {
        McpError::Validation(message) => {
            assert!(message.contains("task-completed"));
            assert!(message.contains("are not open"));
        }
        other => panic!("expected validation error, got {other:?}"),
    }
}

#[test]
#[serial_test::serial(hlc)]
fn manual_reorganize_rejects_duplicate_task_ids() {
    let conn = open_temp_db_for_reorganize();
    let err = reorganize_list(
        &conn,
        ReorganizeListArgs {
            id: "list-reorg".to_string(),
            strategy: ReorganizeListStrategy::Manual,
            task_ids: Some(vec!["task-open".to_string(), "task-open".to_string()]),
            dry_run: false,
            idempotency_key: None,
        },
    )
    .expect_err("duplicate task ids should fail");

    match err {
        McpError::Validation(message) => {
            assert!(message.contains("duplicate ids"));
            assert!(message.contains("task-open"));
        }
        other => panic!("expected validation error, got {other:?}"),
    }
}

#[test]
#[serial_test::serial(hlc)]
fn manual_reorganize_rejects_incomplete_open_task_set() {
    let conn = open_temp_db_for_reorganize();
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new("task-open-2")
        .title("Second open task")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-04-22T12:00:00.000000Z")
        .list_id(Some("list-reorg"))
        .insert(&conn);

    let err = reorganize_list(
        &conn,
        ReorganizeListArgs {
            id: "list-reorg".to_string(),
            strategy: ReorganizeListStrategy::Manual,
            task_ids: Some(vec!["task-open".to_string()]),
            dry_run: false,
            idempotency_key: None,
        },
    )
    .expect_err("incomplete open task set should fail");

    match err {
        McpError::Validation(message) => {
            assert!(message.contains("must include every open task"));
            assert!(message.contains("task-open-2"));
        }
        other => panic!("expected validation error, got {other:?}"),
    }
}
