use super::super::*;

pub(super) fn write_task_import_zip(zip_path: &std::path::Path, task_payload: serde_json::Value) {
    write_import_zip(
        zip_path,
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
                "payload": task_payload
            }),
        ],
        &[],
        &[],
        &[],
        &[],
    );
}
