use super::super::*;
use super::support::*;

#[test]
fn import_scrubs_task_text_fields_before_storage() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_task_import_zip(
        &zip_path,
        serde_json::json!({
            "id": "task-1",
            "title": "Ta\u{202E}sk",
            "body": "Bo\u{200B}dy",
            "raw_input": "Raw\u{0000}Input",
            "ai_notes": "AI\u{001B}[31m",
            "status": "open",
            "list_id": "list-1",
            "defer_count": 0,
            "created_at": "2026-03-29T00:00:00Z",
            "updated_at": "2026-03-29T00:00:00Z"
        }),
    );

    let conn = open_db_in_memory().unwrap();
    import_from_zip(&conn, &zip_path).unwrap();

    let stored: (String, Option<String>, Option<String>, Option<String>) = conn
        .query_row(
            "SELECT title, body, raw_input, ai_notes FROM tasks WHERE id = 'task-1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .unwrap();
    assert_eq!(
        stored,
        (
            "Task".to_string(),
            Some("Body".to_string()),
            Some("RawInput".to_string()),
            Some("AI[31m".to_string()),
        )
    );
}

#[test]
fn import_scrubs_standalone_task_checklist_item_text_before_storage() {
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
        ],
        &[],
        &[serde_json::json!({
            "entity_type": ENTITY_TASK_CHECKLIST_ITEM,
            "entity_id": "item-1",
            "version": "1711234567890_0002_deadbeefdeadbeef",
            "payload": {
                "id": "item-1",
                "task_id": "task-1",
                "position": 0,
                "text": "Ca\u{200B}ll",
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
    );

    let conn = open_db_in_memory().unwrap();
    import_from_zip(&conn, &zip_path).unwrap();

    let stored: String = conn
        .query_row(
            "SELECT text FROM task_checklist_items WHERE id = 'item-1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(stored, "Call");
}

#[test]
fn import_scrubs_embedded_task_checklist_item_text_before_storage() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_task_import_zip(
        &zip_path,
        serde_json::json!({
            "id": "task-1",
            "title": "Task",
            "status": "open",
            "list_id": "list-1",
            "checklist_items": [{
                "id": "item-1",
                "position": 0,
                "text": "Em\u{202E}bed"
            }],
            "defer_count": 0,
            "created_at": "2026-03-29T00:00:00Z",
            "updated_at": "2026-03-29T00:00:00Z"
        }),
    );

    let conn = open_db_in_memory().unwrap();
    import_from_zip(&conn, &zip_path).unwrap();

    let stored: String = conn
        .query_row(
            "SELECT text FROM task_checklist_items WHERE id = 'item-1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(stored, "Embed");
}
