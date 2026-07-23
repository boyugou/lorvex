use super::super::*;

#[test]
fn import_rejects_list_with_oversized_name() {
    // list names must also be capped at import time.
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("oversize-list.zip");
    let giant = "b".repeat(1_001);
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_LIST,
            "entity_id": "list-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "list-1",
                "name": giant,
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z",
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
        err.to_string().to_lowercase().contains("too long"),
        "expected list-too-long error, got: {err}"
    );
}

#[test]
fn import_rejects_list_missing_name() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_LIST,
            "entity_id": "list-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "list-1",
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
        err.to_string().contains("name"),
        "expected name error, got: {err}"
    );
}

#[test]
fn import_rejects_tag_payload_missing_lookup_key() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_TAG,
            "entity_id": "tag-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "tag-1",
                "display_name": "Urgent",
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
        err.to_string().contains("lookup_key"),
        "expected lookup_key error, got: {err}"
    );
}

#[test]
fn import_rejects_tag_missing_created_at() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_TAG,
            "entity_id": "tag-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "tag-1",
                "display_name": "Urgent",
                "lookup_key": "urgent",
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
        err.to_string().contains("created_at"),
        "expected created_at error, got: {err}"
    );
}
