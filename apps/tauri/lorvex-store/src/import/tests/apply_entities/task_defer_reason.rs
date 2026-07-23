use super::super::*;
use super::support::*;

#[test]
fn import_rejects_task_with_invalid_last_defer_reason() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_task_import_zip(
        &zip_path,
        serde_json::json!({
            "id": "task-1",
            "title": "Task",
            "status": "open",
            "list_id": "list-1",
            "last_defer_reason": "later_maybe",
            "defer_count": 0,
            "created_at": "2026-03-29T00:00:00Z",
            "updated_at": "2026-03-29T00:00:00Z"
        }),
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("last_defer_reason") && err.to_string().contains("not_today"),
        "expected last_defer_reason validation error, got: {err}"
    );
}

#[test]
fn import_treats_empty_task_last_defer_reason_as_clear() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_task_import_zip(
        &zip_path,
        serde_json::json!({
            "id": "task-1",
            "title": "Task",
            "status": "open",
            "list_id": "list-1",
            "last_defer_reason": "",
            "defer_count": 0,
            "created_at": "2026-03-29T00:00:00Z",
            "updated_at": "2026-03-29T00:00:00Z"
        }),
    );

    let conn = open_db_in_memory().unwrap();
    let summary = import_from_zip(&conn, &zip_path).unwrap();
    assert!(summary.entities_created >= 1);

    let stored: Option<String> = conn
        .query_row(
            "SELECT last_defer_reason FROM tasks WHERE id = 'task-1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(stored, None);
}

#[test]
fn import_sanitizes_task_last_defer_reason_before_validation() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_task_import_zip(
        &zip_path,
        serde_json::json!({
            "id": "task-1",
            "title": "Task",
            "status": "open",
            "list_id": "list-1",
            "last_defer_reason": "not_\u{200B}today",
            "defer_count": 0,
            "created_at": "2026-03-29T00:00:00Z",
            "updated_at": "2026-03-29T00:00:00Z"
        }),
    );

    let conn = open_db_in_memory().unwrap();
    import_from_zip(&conn, &zip_path).unwrap();

    let stored: Option<String> = conn
        .query_row(
            "SELECT last_defer_reason FROM tasks WHERE id = 'task-1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(stored, Some("not_today".to_string()));
}

#[test]
fn import_treats_sanitized_empty_task_last_defer_reason_as_clear() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_task_import_zip(
        &zip_path,
        serde_json::json!({
            "id": "task-1",
            "title": "Task",
            "status": "open",
            "list_id": "list-1",
            "last_defer_reason": "\u{200B}",
            "defer_count": 0,
            "created_at": "2026-03-29T00:00:00Z",
            "updated_at": "2026-03-29T00:00:00Z"
        }),
    );

    let conn = open_db_in_memory().unwrap();
    import_from_zip(&conn, &zip_path).unwrap();

    let stored: Option<String> = conn
        .query_row(
            "SELECT last_defer_reason FROM tasks WHERE id = 'task-1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(stored, None);
}
