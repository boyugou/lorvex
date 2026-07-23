use super::super::*;
use super::support::*;

#[test]
fn import_rejects_task_with_malformed_due_date() {
    // malformed due_date strings must be rejected at
    // import time. Previously they round-tripped into the DB and
    // silently hid the row from every date-bucketed read path.
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("bad-due.zip");
    write_import_zip(
        &zip_path,
        &[
            serde_json::json!({
                "entity_type": ENTITY_LIST,
                "entity_id": "list-1",
                "version": "1711234567890_0001_deadbeefdeadbeef",
                "payload": {
                    "id": "list-1",
                    "name": "Inbox",
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00Z",
                }
            }),
            serde_json::json!({
                "entity_type": ENTITY_TASK,
                "entity_id": "task-1",
                "version": "1711234567890_0002_deadbeefdeadbeef",
                "payload": {
                    "id": "task-1",
                    "title": "Do thing",
                    "status": "open",
                    "list_id": "list-1",
                    "due_date": "not-a-date",
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00Z",
                    "defer_count": 0,
                }
            }),
        ],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().to_lowercase().contains("due_date"),
        "expected due_date validation error, got: {err}"
    );
}

#[test]
fn import_rejects_task_non_integer_priority_when_present() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[
            serde_json::json!({
                "entity_type": ENTITY_LIST,
                "entity_id": "list-1",
                "version": "1711234567890_0000_deadbeefdeadbeef",
                "payload": {
                    "id": "list-1",
                    "name": "Test List",
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00Z"
                }
            }),
            serde_json::json!({
                "entity_type": ENTITY_TASK,
                "entity_id": "task-1",
                "version": "1711234567890_0001_deadbeefdeadbeef",
                "payload": {
                    "id": "task-1",
                    "title": "Task",
                    "status": "open",
                    "list_id": "list-1",
                    "priority": "high",
                    "defer_count": 0,
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00Z"
                }
            }),
        ],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("priority"),
        "expected priority error, got: {err}"
    );
}

#[test]
fn import_rejects_task_with_unknown_status() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_task_import_zip(
        &zip_path,
        serde_json::json!({
            "id": "task-1",
            "title": "Task",
            "status": "deferred",
            "list_id": "list-1",
            "defer_count": 0,
            "created_at": "2026-03-29T00:00:00Z",
            "updated_at": "2026-03-29T00:00:00Z"
        }),
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("status") && err.to_string().contains("open|completed"),
        "expected typed status validation error, got: {err}"
    );
}

#[test]
fn import_rejects_task_with_negative_estimated_minutes() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_task_import_zip(
        &zip_path,
        serde_json::json!({
            "id": "task-1",
            "title": "Task",
            "status": "open",
            "list_id": "list-1",
            "estimated_minutes": -1,
            "defer_count": 0,
            "created_at": "2026-03-29T00:00:00Z",
            "updated_at": "2026-03-29T00:00:00Z"
        }),
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    let msg = err.to_string();
    assert!(
        msg.contains("estimated_minutes") && msg.contains("out of range"),
        "expected estimated_minutes range validation error, got: {err}"
    );
}

#[test]
fn import_rejects_task_with_negative_defer_count() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_task_import_zip(
        &zip_path,
        serde_json::json!({
            "id": "task-1",
            "title": "Task",
            "status": "open",
            "list_id": "list-1",
            "defer_count": -1,
            "created_at": "2026-03-29T00:00:00Z",
            "updated_at": "2026-03-29T00:00:00Z"
        }),
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("defer_count") && err.to_string().contains("non-negative"),
        "expected defer_count validation error, got: {err}"
    );
}
