use super::*;

#[test]
fn import_rejects_tombstone_missing_deleted_at() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[],
        &[],
        &[],
        &[],
        &[serde_json::json!({
            "entity_type": ENTITY_TASK,
            "entity_id": "task-1",
            "version": "1711234567890_0001_deadbeefdeadbeef"
        })],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("deleted_at"),
        "expected deleted_at error, got: {err}"
    );
}

#[test]
fn import_rejects_tombstone_redirect_missing_redirect_entity_type() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[],
        &[],
        &[],
        &[],
        &[serde_json::json!({
            "entity_type": "tag",
            "entity_id": "tag-merged-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "deleted_at": "2026-03-29T00:00:00Z",
            "redirect_entity_id": "tag-target-1"
        })],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("redirect_entity_type"),
        "expected redirect_entity_type error, got: {err}"
    );
}

#[test]
fn import_rejects_tombstone_redirect_type_without_redirect_entity_id() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    write_import_zip(
        &zip_path,
        &[],
        &[],
        &[],
        &[],
        &[serde_json::json!({
            "entity_type": "tag",
            "entity_id": "tag-merged-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "deleted_at": "2026-03-29T00:00:00Z",
            "redirect_entity_type": "tag"
        })],
    );

    let conn = open_db_in_memory().unwrap();
    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        err.to_string().contains("redirect_entity_id"),
        "expected redirect_entity_id error, got: {err}"
    );
}

#[test]
fn import_tombstone_deletes_live_row_that_loses_to_tombstone_version() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    let older_version = "1711234560000_0000_deadbeefdeadbeef";
    let tombstone_version = "1711234569999_0000_deadbeefdeadbeef";

    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_TASK,
            "entity_id": "task-1",
            "version": older_version,
            "payload": {
                "id": "task-1",
                "title": "stale import copy",
                "status": "open",
                "list_id": "list-1",
                "defer_count": 0,
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z"
            }
        })],
        &[],
        &[],
        &[],
        &[serde_json::json!({
            "entity_type": ENTITY_TASK,
            "entity_id": "task-1",
            "version": tombstone_version,
            "deleted_at": "2026-03-29T00:10:00Z"
        })],
    );

    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO lists (id, name, created_at, updated_at, version)
         VALUES ('list-1', 'Inbox', '2026-03-01T00:00:00Z', '2026-03-01T00:00:00Z', ?1)",
        [older_version],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO tasks (id, title, status, list_id, defer_count, created_at, updated_at, version)
         VALUES ('task-1', 'local stale live row', 'open', 'list-1', 0,
                 '2026-03-01T00:00:00Z', '2026-03-01T00:00:00Z', ?1)",
        [older_version],
    )
    .unwrap();

    import_from_zip(&conn, &zip_path).unwrap();

    let live_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM tasks WHERE id = 'task-1'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(
        live_count, 0,
        "a newer imported tombstone must remove a stale live row"
    );

    let stored_tombstone: String = conn
        .query_row(
            "SELECT version FROM sync_tombstones WHERE entity_type = ?1 AND entity_id = 'task-1'",
            [ENTITY_TASK],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(stored_tombstone, tombstone_version);
}

#[test]
fn import_tombstone_replaces_tainted_existing_version_with_canonical_hlc() {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("import.zip");
    let tombstone_version = "1711234569999_0000_deadbeefdeadbeef";

    write_import_zip(
        &zip_path,
        &[],
        &[],
        &[],
        &[],
        &[serde_json::json!({
            "entity_type": ENTITY_TASK,
            "entity_id": "task-tainted",
            "version": tombstone_version,
            "deleted_at": "2026-03-29T00:10:00Z"
        })],
    );

    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO sync_tombstones (entity_type, entity_id, version, deleted_at)
         VALUES (?1, 'task-tainted', 'v1', '2026-03-01T00:00:00Z')",
        [ENTITY_TASK],
    )
    .unwrap();

    import_from_zip(&conn, &zip_path).unwrap();

    let (stored_version, deleted_at): (String, String) = conn
        .query_row(
            "SELECT version, deleted_at FROM sync_tombstones
             WHERE entity_type = ?1 AND entity_id = 'task-tainted'",
            [ENTITY_TASK],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    assert_eq!(stored_version, tombstone_version);
    assert_eq!(deleted_at, "2026-03-29T00:10:00.000Z");
}
