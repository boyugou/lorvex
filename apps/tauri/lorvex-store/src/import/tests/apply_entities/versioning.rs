use super::super::*;

#[test]
fn import_rejects_missing_entity_version() {
    let conn = open_db_in_memory().unwrap();
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("missing-entity-version.zip");

    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_LIST,
            "entity_id": "list-1",
            "payload": {
                "id": "list-1",
                "name": "Inbox",
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z",
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    assert!(
        matches!(err, ImportError::Json(_)),
        "expected missing required version field to fail JSON decode, got {err:?}",
    );
}

#[test]
fn import_rejects_entity_with_non_hlc_version() {
    let conn = open_db_in_memory().unwrap();
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("bad-entity-version.zip");

    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_LIST,
            "entity_id": "list-1",
            "version": "not-an-hlc",
            "payload": {
                "id": "list-1",
                "name": "Inbox",
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z",
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    match err {
        ImportError::InvalidPayload(message) => {
            assert!(message.contains("entities.jsonl"));
            assert!(message.contains("valid HLC version"));
        }
        other => panic!("expected InvalidPayload for bad entity version, got {other:?}"),
    }
}

#[test]
fn import_rejects_existing_entity_with_non_hlc_local_version() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
            "INSERT INTO lists (id, name, created_at, updated_at, version)
             VALUES ('list-1', 'Existing', '2026-03-29T00:00:00Z', '2026-03-29T00:00:00Z', 'bad-local-version')",
            [],
        )
        .unwrap();

    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("bad-local-entity-version.zip");

    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_LIST,
            "entity_id": "list-1",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "list-1",
                "name": "Incoming",
                "created_at": "2026-03-29T00:00:00Z",
                "updated_at": "2026-03-29T00:00:00Z",
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    let err = import_from_zip(&conn, &zip_path).unwrap_err();
    match err {
        ImportError::InvalidPayload(message) => {
            assert!(message.contains("local lists.id"));
            assert!(message.contains("invalid HLC version"));
        }
        other => panic!("expected InvalidPayload for bad local version, got {other:?}"),
    }
}

#[test]
fn import_skips_newer_existing_entities() {
    let source = open_db_in_memory().unwrap();
    source
            .execute(
                "INSERT INTO lists (id, name, color, created_at, updated_at, version)
                 VALUES ('list-1', 'Old Name', '#000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '1711234567890_0001_deadbeefdeadbeef')",
                [],
            )
            .unwrap();

    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("export.zip");
    export_to_zip(&source, &zip_path, "dev-1").unwrap();

    // Target DB has a NEWER version of the same list.
    let target = open_db_in_memory().unwrap();
    target
            .execute(
                "INSERT INTO lists (id, name, color, created_at, updated_at, version)
                 VALUES ('list-1', 'Newer Name', '#FFF', '2026-02-01T00:00:00Z', '2026-02-01T00:00:00Z', '1711234567890_0009_deadbeefdeadbeef')",
                [],
            )
            .unwrap();

    let summary = import_from_zip(&target, &zip_path).unwrap();

    // The list should NOT be overwritten — the target has a newer version.
    let name: String = target
        .query_row("SELECT name FROM lists WHERE id = 'list-1'", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(name, "Newer Name");
    assert!(summary.entities_skipped >= 1);
}

#[test]
fn import_restores_list_archive_and_position_fields() {
    let conn = open_db_in_memory().unwrap();
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("list-archive-position.zip");

    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_LIST,
            "entity_id": "list-sync-fields",
            "version": "1711234567890_0001_deadbeefdeadbeef",
            "payload": {
                "id": "list-sync-fields",
                "name": "Archived List",
                "created_at": "2026-03-29T00:00:00.000Z",
                "updated_at": "2026-03-29T00:00:00.000Z",
                "archived_at": "2026-03-30T00:00:00.000Z",
                "position": 42
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    import_from_zip(&conn, &zip_path).unwrap();
    let (archived_at, position): (Option<String>, i64) = conn
        .query_row(
            "SELECT archived_at, position FROM lists WHERE id = 'list-sync-fields'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(archived_at.as_deref(), Some("2026-03-30T00:00:00.000Z"));
    assert_eq!(position, 42);
}

#[test]
fn import_list_explicit_null_archive_clears_without_resetting_absent_position() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO lists (id, name, created_at, updated_at, version, archived_at, position)
         VALUES ('list-clear-archive', 'Existing', '2026-03-29T00:00:00.000Z',
                 '2026-03-29T00:00:00.000Z', '1711234567890_0001_deadbeefdeadbeef',
                 '2026-03-30T00:00:00.000Z', 77)",
        [],
    )
    .unwrap();

    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("list-clear-archive.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_LIST,
            "entity_id": "list-clear-archive",
            "version": "1711234567890_0002_deadbeefdeadbeef",
            "payload": {
                "id": "list-clear-archive",
                "name": "Incoming",
                "created_at": "2026-03-29T00:00:00.000Z",
                "updated_at": "2026-03-31T00:00:00.000Z",
                "archived_at": null
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    import_from_zip(&conn, &zip_path).unwrap();
    let (archived_at, position): (Option<String>, i64) = conn
        .query_row(
            "SELECT archived_at, position FROM lists WHERE id = 'list-clear-archive'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(archived_at, None);
    assert_eq!(position, 77);
}

#[test]
fn import_older_list_payload_preserves_missing_archive_and_position_fields() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO lists (id, name, created_at, updated_at, version, archived_at, position)
         VALUES ('list-old-shape', 'Existing', '2026-03-29T00:00:00.000Z',
                 '2026-03-29T00:00:00.000Z', '1711234567890_0001_deadbeefdeadbeef',
                 '2026-03-30T00:00:00.000Z', 88)",
        [],
    )
    .unwrap();

    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("list-old-shape.zip");
    write_import_zip(
        &zip_path,
        &[serde_json::json!({
            "entity_type": ENTITY_LIST,
            "entity_id": "list-old-shape",
            "version": "1711234567890_0002_deadbeefdeadbeef",
            "payload": {
                "id": "list-old-shape",
                "name": "Incoming",
                "created_at": "2026-03-29T00:00:00.000Z",
                "updated_at": "2026-03-31T00:00:00.000Z"
            }
        })],
        &[],
        &[],
        &[],
        &[],
    );

    import_from_zip(&conn, &zip_path).unwrap();
    let (archived_at, position): (Option<String>, i64) = conn
        .query_row(
            "SELECT archived_at, position FROM lists WHERE id = 'list-old-shape'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(archived_at.as_deref(), Some("2026-03-30T00:00:00.000Z"));
    assert_eq!(position, 88);
}
