use super::support::*;

#[test]
fn test_version_conflict_keeps_newer() {
    let dirs = setup_dirs();

    // Create source DB with version V1.
    let source = open_db_in_memory().unwrap();
    source
        .execute(
            "INSERT INTO lists (id, name, color, created_at, updated_at, version)
             VALUES ('list-1', 'Old Name', '#000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z',
                     '1711234567890_0000_aaaaaaaaaaaaaaaa')",
            [],
        )
        .unwrap();
    source
        .execute(
            "INSERT INTO tasks (id, title, status, list_id, priority, created_at, updated_at, version)
             VALUES ('task-1', 'Old Task Title', 'open', 'list-1', 2,
                     '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z',
                     '1711234567890_0001_aaaaaaaaaaaaaaaa')",
            [],
        )
        .unwrap();
    source
        .execute(
            "INSERT INTO tags (id, display_name, lookup_key, created_at, updated_at, version)
             VALUES ('tag-1', 'old-tag', 'old-tag', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z',
                     '1711234567890_0002_aaaaaaaaaaaaaaaa')",
            [],
        )
        .unwrap();

    // Export V1 data.
    export_to_zip(&source, &dirs.zip_path, "dev-1").unwrap();

    // Create target DB with NEWER version V2 of the same entities.
    let target = open_db_in_memory().unwrap();
    target
        .execute(
            "INSERT INTO lists (id, name, color, created_at, updated_at, version)
             VALUES ('list-1', 'Newer Name', '#FFF', '2026-02-01T00:00:00Z', '2026-02-01T00:00:00Z',
                     '1811234567890_0000_bbbbbbbbbbbbbbbb')",
            [],
        )
        .unwrap();
    target
        .execute(
            "INSERT INTO tasks (id, title, status, list_id, priority, created_at, updated_at, version)
             VALUES ('task-1', 'Newer Task Title', 'open', 'list-1', 1,
                     '2026-02-01T00:00:00Z', '2026-02-01T00:00:00Z',
                     '1811234567890_0001_bbbbbbbbbbbbbbbb')",
            [],
        )
        .unwrap();
    target
        .execute(
            "INSERT INTO tags (id, display_name, lookup_key, created_at, updated_at, version)
             VALUES ('tag-1', 'newer-tag', 'newer-tag', '2026-02-01T00:00:00Z', '2026-02-01T00:00:00Z',
                     '1811234567890_0002_bbbbbbbbbbbbbbbb')",
            [],
        )
        .unwrap();

    // Import the older ZIP — should NOT overwrite the newer data.
    let summary = import_from_zip(&target, &dirs.zip_path).unwrap();
    assert!(
        summary.entities_skipped >= 3,
        "expected at least 3 skipped entities (list + task + tag), got {}",
        summary.entities_skipped
    );

    // Verify the newer data is preserved.
    let list_name: String = target
        .query_row("SELECT name FROM lists WHERE id = 'list-1'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(list_name, "Newer Name");

    let task_title: String = target
        .query_row("SELECT title FROM tasks WHERE id = 'task-1'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(task_title, "Newer Task Title");

    let task_priority: Option<i64> = target
        .query_row("SELECT priority FROM tasks WHERE id = 'task-1'", [], |r| {
            r.get(0)
        })
        .unwrap();
    assert_eq!(task_priority, Some(1));

    let tag_display_name: String = target
        .query_row(
            "SELECT display_name FROM tags WHERE id = 'tag-1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(tag_display_name, "newer-tag");
}

// ---------------------------------------------------------------------------
// Tombstones survive round-trip
// ---------------------------------------------------------------------------

#[test]
fn test_tombstones_survive_roundtrip() {
    let dirs = setup_dirs();

    // Create source DB and insert a tombstone.
    let source = open_db_in_memory().unwrap();
    source
        .execute(
            "INSERT INTO sync_tombstones (entity_type, entity_id, version, deleted_at)
             VALUES ('task', 'task-deleted-1', '1711234567890_0099_deaddeaddeaddead', '2026-03-20T12:00:00Z')",
            [],
        )
        .unwrap();
    source
        .execute(
            "INSERT INTO sync_tombstones (entity_type, entity_id, version, deleted_at, redirect_entity_id, redirect_entity_type)
             VALUES ('tag', 'tag-merged-1', '1711234567890_0100_deaddeaddeaddead', '2026-03-21T12:00:00Z', 'tag-target-1', 'tag')",
            [],
        )
        .unwrap();

    // Export.
    export_to_zip(&source, &dirs.zip_path, "dev-1").unwrap();

    // Import into fresh DB.
    let target = open_db_in_memory().unwrap();
    import_from_zip(&target, &dirs.zip_path).unwrap();

    // Verify tombstones exist in target.
    let tombstone_count: i64 = target
        .query_row(
            "SELECT COUNT(*) FROM sync_tombstones WHERE entity_type = 'task' AND entity_id = 'task-deleted-1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(tombstone_count, 1);

    let tombstone_version: String = target
        .query_row(
            "SELECT version FROM sync_tombstones WHERE entity_type = 'task' AND entity_id = 'task-deleted-1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(tombstone_version, "1711234567890_0099_deaddeaddeaddead");

    // Verify tombstone with redirect fields.
    let redirect_id: Option<String> = target
        .query_row(
            "SELECT redirect_entity_id FROM sync_tombstones WHERE entity_type = 'tag' AND entity_id = 'tag-merged-1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(redirect_id, Some("tag-target-1".to_string()));

    let redirect_type: Option<String> = target
        .query_row(
            "SELECT redirect_entity_type FROM sync_tombstones WHERE entity_type = 'tag' AND entity_id = 'tag-merged-1'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(redirect_type, Some("tag".to_string()));
}

#[test]
fn test_payload_shadows_roundtrip_and_preserve_unknown_fields_in_export() {
    let dirs = setup_dirs();

    let source = open_db_in_memory().unwrap();
    source
        .execute(
            "INSERT INTO lists (id, name, version, created_at, updated_at)
             VALUES ('list-shadow', 'Shadow', '1711234567890_0199_5add5add5add5add', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
            [],
        )
        .unwrap();
    source
        .execute(
            "INSERT INTO tasks (id, title, status, list_id, created_at, updated_at, version)
             VALUES ('task-shadow-1', 'Shadowed task', 'open',
                     'list-shadow',
                     '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '1711234567890_0200_a1b2c3d4a1b2c3d4')",
            [],
        )
        .unwrap();
    source
        .execute(
            "INSERT INTO sync_payload_shadow
             (entity_type, entity_id, base_version, payload_schema_version, raw_payload_json,
              source_device_id, updated_at)
             VALUES ('task', 'task-shadow-1', '1711234567890_0201_deadbeefdeadbeef', 2,
                     '{\"id\":\"task-shadow-1\",\"title\":\"Shadowed task\",\"status\":\"open\",\"mystery_field\":{\"nested\":true}}',
                     'remote-shadow-device',
                     '2026-03-27T00:00:00Z')",
            [],
        )
        .unwrap();

    export_to_zip(&source, &dirs.zip_path, "dev-1").unwrap();

    let zip_bytes = std::fs::read(&dirs.zip_path).unwrap();
    let cursor = std::io::Cursor::new(zip_bytes);
    let mut archive = zip::ZipArchive::new(cursor).unwrap();
    let mut entities_jsonl = String::new();
    archive
        .by_name("entities.jsonl")
        .unwrap()
        .read_to_string(&mut entities_jsonl)
        .unwrap();

    let exported_task = entities_jsonl
        .lines()
        .filter_map(|line| serde_json::from_str::<serde_json::Value>(line).ok())
        .find(|line| line["entity_type"] == "task" && line["entity_id"] == "task-shadow-1")
        .expect("exported task-shadow-1 line");
    assert_eq!(exported_task["payload"]["mystery_field"]["nested"], true);

    let mut shadows_jsonl = String::new();
    archive
        .by_name("payload_shadows.jsonl")
        .unwrap()
        .read_to_string(&mut shadows_jsonl)
        .unwrap();
    let exported_shadow = shadows_jsonl
        .lines()
        .filter_map(|line| serde_json::from_str::<serde_json::Value>(line).ok())
        .find(|line| line["entity_type"] == "task" && line["entity_id"] == "task-shadow-1")
        .expect("exported task-shadow-1 shadow line");
    assert_eq!(
        exported_shadow["source_device_id"].as_str(),
        Some("remote-shadow-device")
    );

    let target = open_db_in_memory().unwrap();
    import_from_zip(&target, &dirs.zip_path).unwrap();

    let (restored_shadow, restored_source_device_id): (String, String) = target
        .query_row(
            "SELECT raw_payload_json, source_device_id FROM sync_payload_shadow
             WHERE entity_type = 'task' AND entity_id = 'task-shadow-1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    let restored_shadow: serde_json::Value = serde_json::from_str(&restored_shadow).unwrap();
    assert_eq!(restored_shadow["mystery_field"]["nested"], true);
    assert_eq!(restored_source_device_id, "remote-shadow-device");

    let reexport_path = dirs._dir.path().join("reexport.zip");
    export_to_zip(&target, &reexport_path, "dev-2").unwrap();
    let reexport_bytes = std::fs::read(&reexport_path).unwrap();
    let reexport_cursor = std::io::Cursor::new(reexport_bytes);
    let mut reexport_archive = zip::ZipArchive::new(reexport_cursor).unwrap();
    let mut reexport_entities = String::new();
    reexport_archive
        .by_name("entities.jsonl")
        .unwrap()
        .read_to_string(&mut reexport_entities)
        .unwrap();
    let reexported_task = reexport_entities
        .lines()
        .filter_map(|line| serde_json::from_str::<serde_json::Value>(line).ok())
        .find(|line| line["entity_type"] == "task" && line["entity_id"] == "task-shadow-1")
        .expect("reexported task-shadow-1 line");
    assert_eq!(reexported_task["payload"]["mystery_field"]["nested"], true);

    let mut reexported_shadows = String::new();
    reexport_archive
        .by_name("payload_shadows.jsonl")
        .unwrap()
        .read_to_string(&mut reexported_shadows)
        .unwrap();
    let reexported_shadow = reexported_shadows
        .lines()
        .filter_map(|line| serde_json::from_str::<serde_json::Value>(line).ok())
        .find(|line| line["entity_type"] == "task" && line["entity_id"] == "task-shadow-1")
        .expect("reexported task-shadow-1 shadow line");
    assert_eq!(
        reexported_shadow["source_device_id"].as_str(),
        Some("remote-shadow-device")
    );
}
