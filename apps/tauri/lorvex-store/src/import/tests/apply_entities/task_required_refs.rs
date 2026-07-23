use super::super::*;

#[test]
fn import_rejects_task_with_null_list_id() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_TASK,
            "entity_id": "task-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "task-1",
                "title": "Broken legacy task",
                "status": "open",
                "list_id": null,
                "defer_count": 0,
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("real list_id"),
        "expected real list_id error, got: {err}"
    );
}

#[test]
fn import_rejects_task_with_missing_list_reference() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_TASK,
            "entity_id": "task-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "task-1",
                "title": "Broken legacy task",
                "status": "open",
                "list_id": "missing-list",
                "defer_count": 0,
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("does not exist"),
        "expected missing list error, got: {err}"
    );
}

#[test]
fn import_rejects_task_missing_defer_count() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_TASK,
            "entity_id": "task-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "task-1",
                "title": "Task",
                "status": "open",
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("defer_count"),
        "expected defer_count error, got: {err}"
    );
}

#[test]
fn import_rejects_task_missing_status() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_TASK,
            "entity_id": "task-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "task-1",
                "title": "Task",
                "defer_count": 0,
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("status"),
        "expected status error, got: {err}"
    );
}
