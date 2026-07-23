use super::*;

#[test]
fn import_rejects_task_tag_missing_created_at() {
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
                    "defer_count": 0,
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00Z"
                }
            }),
            serde_json::json!({
                "entity_type": ENTITY_TAG,
                "entity_id": "tag-1",
                "version": "1711234567890_0001_deadbeefdeadbeef",
                "payload": {
                    "id": "tag-1",
                    "display_name": "Urgent",
                    "lookup_key": "urgent",
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00Z"
                }
            }),
        ],
        &[serde_json::json!({
            "entity_type": EDGE_TASK_TAG,
            "entity_id": "task-1:tag-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "task_id": "task-1",
                "tag_id": "tag-1"
            }
        })],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("created_at"),
        "expected created_at error, got: {err}"
    );
}

#[test]
fn import_rejects_task_dependency_missing_created_at() {
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
                    "title": "Task 1",
                    "status": "open",
                    "list_id": "list-1",
                    "defer_count": 0,
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00Z"
                }
            }),
            serde_json::json!({
                "entity_type": ENTITY_TASK,
                "entity_id": "task-2",
                "version": "1711234567890_0001_deadbeefdeadbeef",
                "payload": {
                    "id": "task-2",
                    "title": "Task 2",
                    "status": "open",
                    "list_id": "list-1",
                    "defer_count": 0,
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00Z"
                }
            }),
        ],
        &[serde_json::json!({
            "entity_type": EDGE_TASK_DEPENDENCY,
            "entity_id": "task-1:task-2",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "task_id": "task-1",
                "depends_on_task_id": "task-2"
            }
        })],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("created_at"),
        "expected created_at error, got: {err}"
    );
}

#[test]
fn import_rejects_habit_completion_missing_created_at() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_HABIT,
            "entity_id": "habit-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "habit-1",
                "name": "Walk",
                "frequency_type": "daily",
                "target_count": 1,
                "archived": false,
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[serde_json::json!({
            "entity_type": EDGE_HABIT_COMPLETION,
            "entity_id": "habit-1:2026-03-29",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "habit_id": "habit-1",
                "completed_date": "2026-03-29",
                "value": 1,
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("created_at"),
        "expected created_at error, got: {err}"
    );
}

#[test]
fn import_rejects_habit_completion_non_string_note_when_present() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_HABIT,
            "entity_id": "habit-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "habit-1",
                "name": "Walk",
                "frequency_type": "daily",
                "target_count": 1,
                "archived": false,
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[serde_json::json!({
            "entity_type": EDGE_HABIT_COMPLETION,
            "entity_id": "habit-1:2026-03-29",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "habit_id": "habit-1",
                "completed_date": "2026-03-29",
                "value": 1,
                "note": 7,
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("note"),
        "expected note error, got: {err}"
    );
}

#[test]
fn import_rejects_task_calendar_event_link_missing_created_at() {
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
                    "title": "Task 1",
                    "status": "open",
                    "list_id": "list-1",
                    "defer_count": 0,
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00Z"
                }
            }),
            serde_json::json!({
                "entity_type": ENTITY_CALENDAR_EVENT,
                "entity_id": "evt-1",
                "version": "1711234567890_0001_deadbeefdeadbeef",
                "payload": {
                    "id": "evt-1",
                    "title": "Event",
                    "start_date": "2026-03-29",
                    "all_day": false,
                    "event_type": "event",
                    "created_at": "2026-03-29T00:00:00Z",
                    "updated_at": "2026-03-29T00:00:00Z"
                }
            }),
        ],
        &[serde_json::json!({
            "entity_type": EDGE_TASK_CALENDAR_EVENT_LINK,
            "entity_id": "task-1:evt-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "task_id": "task-1",
                "calendar_event_id": "evt-1",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("created_at"),
        "expected created_at error, got: {err}"
    );
}
