use super::super::*;
use super::support::*;

#[test]
fn import_rejects_task_with_oversized_title() {
    // imports must reject fields that exceed domain
    // validation bounds. A malicious ZIP could otherwise smuggle
    // in a 10 MB title that OOMs every read path.
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("oversize-title.zip");
    let giant_title = "a".repeat(1_001);
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
                    "title": giant_title,
                    "status": "open",
                    "list_id": "list-1",
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
    // `ValidationError::TooLong` Display was unified
    // on the `"exceeds maximum length"` wording every Tauri / MCP /
    // Tauri-habit surface already used (issue #2994 H1 unification).
    // The store-side import path now sees the same wording when it
    // re-emits the typed error.
    let lower = err.to_string().to_lowercase();
    assert!(
        lower.contains("title") && lower.contains("exceeds maximum length"),
        "expected title-exceeds-max-length error, got: {err}"
    );
}

#[test]
fn import_rejects_task_with_oversized_ai_notes() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_task_import_zip(
        &zip_path,
        serde_json::json!({
            "id": "task-1",
            "title": "Task",
            "status": "open",
            "list_id": "list-1",
            "ai_notes": "a".repeat(lorvex_domain::validation::MAX_BODY_LENGTH + 1),
            "defer_count": 0,
            "created_at": "2026-03-29T00:00:00Z",
            "updated_at": "2026-03-29T00:00:00Z"
        }),
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("ai_notes") && err.to_string().contains("maximum length"),
        "expected ai_notes validation error, got: {err}"
    );
}

#[test]
fn import_rejects_task_with_oversized_raw_input() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_task_import_zip(
        &zip_path,
        serde_json::json!({
            "id": "task-1",
            "title": "Task",
            "status": "open",
            "list_id": "list-1",
            "raw_input": "a".repeat(lorvex_domain::validation::MAX_BODY_LENGTH + 1),
            "defer_count": 0,
            "created_at": "2026-03-29T00:00:00Z",
            "updated_at": "2026-03-29T00:00:00Z"
        }),
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("raw_input") && err.to_string().contains("maximum length"),
        "expected raw_input validation error, got: {err}"
    );
}
