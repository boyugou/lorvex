use super::*;
use crate::contract::{BatchUpdateTaskPatch, BatchUpdateTasksArgs};
use crate::db::open_database_for_path;
use rusqlite::params;
use tempfile::tempdir;

fn open_temp_db_with_task(task_id: &str, title: &str, priority: Option<i64>) -> Connection {
    // Schema seeds the 'inbox' list.
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
        .priority(priority)
        .insert(&conn);
    conn
}

/// Build a patch that just sets the priority. Every Option field
/// defaults to None via JSON deserialization to avoid enumerating
/// the full ~20-field struct at every call site.
fn priority_patch(id: &str, priority: u8) -> BatchUpdateTaskPatch {
    let json = serde_json::json!({ "id": id, "priority": priority });
    serde_json::from_value(json).expect("patch must deserialize")
}

// batch_update_tasks returns an undo_token whose `pre_entities_json`
// carries the pre-mutation snapshot of every touched row so a reverse
// write can re-apply the prior state.
#[test]
#[serial_test::serial(hlc)]
fn batch_update_tasks_returns_undo_token_with_pre_snapshots() {
    let task_id = "01966a3f-7c8b-7d4e-8f3a-000000000331";
    let conn = open_temp_db_with_task(task_id, "Before", Some(3));

    let args = BatchUpdateTasksArgs {
        updates: vec![priority_patch(task_id, 1)],
        dry_run: false,
    };
    let payload = batch_update_tasks(&conn, args).expect("batch_update_tasks");
    let value: serde_json::Value = serde_json::from_str(&payload).unwrap();

    let undo_raw = value["undo_token"].as_str().expect("undo_token present");
    let token: crate::runtime::undo::McpUndoToken =
        serde_json::from_str(undo_raw).expect("token parses");
    assert_eq!(
        token.kind,
        crate::runtime::undo::McpUndoKind::BatchUpdateTasks
    );
    assert_eq!(token.pre_entities_json.len(), 1);
    let snapshot = &token.pre_entities_json[0];
    assert_eq!(snapshot["id"], serde_json::json!(task_id));
    assert_eq!(
        snapshot["priority"],
        serde_json::json!(3),
        "snapshot must capture the pre-mutation priority"
    );
}

// Every outbox envelope emitted for an updated task is enqueued plain
// (immediately dispatchable); the response still carries the undo
// token with the pre-mutation snapshots.
#[test]
#[serial_test::serial(hlc)]
fn batch_update_tasks_enqueues_plain_envelopes() {
    let task_id = "01966a3f-7c8b-7d4e-8f3a-000000000332";
    let conn = open_temp_db_with_task(task_id, "Task", None);

    let args = BatchUpdateTasksArgs {
        updates: vec![priority_patch(task_id, 2)],
        dry_run: false,
    };
    let payload = batch_update_tasks(&conn, args).expect("batch_update_tasks");
    let value: serde_json::Value = serde_json::from_str(&payload).unwrap();
    assert!(
        value["undo_token"].as_str().is_some(),
        "response must carry undo_token"
    );

    let envelope_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox \
             WHERE entity_type = 'task' AND entity_id = ?1",
            [task_id],
            |row| row.get(0),
        )
        .expect("task update envelope must exist");
    assert!(
        envelope_count >= 1,
        "task update must enqueue an outbox envelope"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn batch_update_tasks_status_cancelled_does_not_readd_dependency_patch() {
    let task_id = "01966a3f-7c8b-7d4e-8f3a-000000000210";
    let blocker_old = "01966a3f-7c8b-7d4e-8f3a-000000000211";
    let blocker_new = "01966a3f-7c8b-7d4e-8f3a-000000000212";
    let conn = open_temp_db_with_task(task_id, "Cancel deps", None);
    let now = "2026-04-18T09:00:00.000000Z";
    let ver = "0000000000000_0000_a0a0a0a0a0a0a0a0";
    for task_id in [blocker_old, blocker_new] {
        // lift to canonical TaskBuilder.
        lorvex_store::test_support::fixtures::TaskBuilder::new(task_id)
            .title(task_id)
            .version(ver)
            .created_at(now)
            .list_id(Some("inbox"))
            .insert(&conn);
    }
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at)
         VALUES (?1, ?2, ?3, ?4)",
        params![task_id, blocker_old, ver, now],
    )
    .expect("seed dependency");

    let patch: BatchUpdateTaskPatch = serde_json::from_value(serde_json::json!({
        "id": task_id,
        "status": "cancelled",
        "depends_on": [blocker_new]
    }))
    .expect("patch must deserialize");
    let payload = batch_update_tasks(
        &conn,
        BatchUpdateTasksArgs {
            updates: vec![patch],
            dry_run: false,
        },
    )
    .expect("batch_update_tasks");
    let value: serde_json::Value = serde_json::from_str(&payload).unwrap();
    assert_eq!(value["updated_count"], serde_json::json!(1));

    let dep_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_dependencies WHERE task_id = ?1",
            [task_id],
            |row| row.get(0),
        )
        .expect("count remaining dependencies");
    assert_eq!(
        dep_count, 0,
        "cancelled tasks must not keep or recreate dependency edges"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn batch_update_tasks_rejects_stale_task_version_without_field_changes() {
    let task_id = "01966a3f-7c8b-7d4e-8f3a-000000000333";
    let conn = open_temp_db_with_task(task_id, "Before", Some(3));
    let stale_barrier = "9999999999999_0000_ffffffffffffffff";
    conn.execute(
        "UPDATE tasks SET version = ?1 WHERE id = ?2",
        [stale_barrier, task_id],
    )
    .expect("force stale barrier");

    let patch: BatchUpdateTaskPatch = serde_json::from_value(serde_json::json!({
        "id": task_id,
        "title": "After",
        "priority": 1
    }))
    .expect("patch must deserialize");
    let err = batch_update_tasks(
        &conn,
        BatchUpdateTasksArgs {
            updates: vec![patch],
            dry_run: false,
        },
    )
    .expect_err("stale batch update must reject");

    match err {
        McpError::Store(store_err)
            if matches!(*store_err, lorvex_store::StoreError::StaleVersion { .. }) =>
        {
            let lorvex_store::StoreError::StaleVersion { entity, id } = *store_err else {
                unreachable!()
            };
            assert_eq!(entity, lorvex_domain::naming::ENTITY_TASK);
            assert_eq!(id, task_id);
        }
        other => panic!("expected stale-version error, got {other:?}"),
    }

    let (title, priority, version): (String, Option<i64>, String) = conn
        .query_row(
            "SELECT title, priority, version FROM tasks WHERE id = ?1",
            [task_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("read task after rejected batch update");
    assert_eq!(title, "Before");
    assert_eq!(priority, Some(3));
    assert_eq!(version, stale_barrier);
}

#[test]
#[serial_test::serial(hlc)]
fn batch_update_tasks_rejects_duplicate_ids_before_mutation() {
    let task_id = "01966a3f-7c8b-7d4e-8f3a-000000000330";
    let conn = open_temp_db_with_task(task_id, "Before", Some(3));

    let err = batch_update_tasks(
        &conn,
        BatchUpdateTasksArgs {
            updates: vec![priority_patch(task_id, 1), priority_patch(task_id, 2)],
            dry_run: false,
        },
    )
    .expect_err("duplicate batch update ids must be rejected");

    match err {
        McpError::Validation(message) => {
            assert!(message.contains("duplicate"), "unexpected error: {message}");
            assert!(
                message.contains(task_id),
                "error should name the duplicate id: {message}"
            );
        }
        other => panic!("expected duplicate-id validation error, got {other:?}"),
    }

    let (title, priority): (String, Option<i64>) = conn
        .query_row(
            "SELECT title, priority FROM tasks WHERE id = ?1",
            [task_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read task after rejected duplicate update");
    assert_eq!(title, "Before");
    assert_eq!(priority, Some(3));

    let changelog_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM ai_changelog", [], |row| row.get(0))
        .expect("count changelog rows");
    assert_eq!(
        changelog_count, 0,
        "validation must run before changelog writes"
    );

    let outbox_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM sync_outbox", [], |row| row.get(0))
        .expect("count sync outbox rows");
    assert_eq!(
        outbox_count, 0,
        "validation must run before sync outbox writes"
    );
}
