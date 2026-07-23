use super::*;
use crate::connection::open_db_in_memory;
use crate::export_scope::{ExportCategory, ExportDependencyMode, ExportScope, ExportScopeKind};
use lorvex_domain::naming::{
    EDGE_TASK_CALENDAR_EVENT_LINK, EDGE_TASK_DEPENDENCY, EDGE_TASK_PROVIDER_EVENT_LINK,
    EDGE_TASK_TAG, ENTITY_LIST, ENTITY_TAG, ENTITY_TASK,
};
use lorvex_domain::version::EXPORT_FORMAT_VERSION;
use rusqlite::Connection;
use std::cell::Cell;
use std::io::{Cursor, Read as _};
use tempfile::tempdir;

#[cfg(unix)]
fn create_file_symlink(target: &std::path::Path, link: &std::path::Path) {
    std::os::unix::fs::symlink(target, link).expect("create symlink");
}

/// Helper: create a fully migrated in-memory DB with some seed data.
fn seed_db() -> Connection {
    let conn = open_db_in_memory().unwrap();

    // Insert a list.
    conn.execute(
        "INSERT INTO lists (id, name, color, created_at, updated_at, version, archived_at, position)
         VALUES ('list-1', 'Work', '#FF0000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z',
                 '0000000000000_0000_test0001', '2026-01-03T00:00:00.000Z', 12)",
        [],
    )
    .unwrap();

    // Insert tasks.
    conn.execute(
        "INSERT INTO tasks (id, title, status, list_id, priority, created_at, updated_at, version)
         VALUES ('task-1', 'Buy milk', 'open', 'list-1', 2, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '0000000000000_0000_test0001')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO tasks (id, title, status, created_at, updated_at, version)
         VALUES ('task-2', 'Read book', 'completed', '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z', '0000000000000_0000_test0002')",
        [],
    )
    .unwrap();

    // Insert a tag.
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, color, created_at, updated_at, version)
         VALUES ('tag-1', 'urgent', 'urgent', '#FF0000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '0000000000000_0000_test0001')",
        [],
    )
    .unwrap();

    // Insert a task_tag edge.
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, created_at, version)
         VALUES ('task-1', 'tag-1', '2026-01-01T00:00:00Z', '0000000000000_0000_test0001')",
        [],
    )
    .unwrap();

    conn
}

fn export_to_memory(conn: &Connection) -> (ExportManifest, Vec<u8>) {
    let dir = tempdir().unwrap();
    let output_path = dir.path().join("export.zip");

    let manifest = export_to_zip(conn, &output_path, "test-device").unwrap();
    let data = std::fs::read(&output_path).unwrap();
    (manifest, data)
}

struct CancelAfterChecks {
    remaining: Cell<usize>,
}

impl CancelAfterChecks {
    const fn new(remaining: usize) -> Self {
        Self {
            remaining: Cell::new(remaining),
        }
    }
}

impl crate::CancellationToken for CancelAfterChecks {
    fn is_cancelled(&self) -> bool {
        let remaining = self.remaining.get();
        if remaining == 0 {
            return true;
        }
        self.remaining.set(remaining - 1);
        false
    }
}

#[test]
fn export_cancellation_removes_partial_temp_zip() {
    let conn = seed_db();
    for idx in 0..200 {
        conn.execute(
            "INSERT INTO tasks (id, title, status, created_at, updated_at, version)
             VALUES (?1, ?2, 'open', '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z', '0000000000000_0000_test0002')",
            rusqlite::params![format!("task-extra-{idx:03}"), format!("Extra {idx}")],
        )
        .unwrap();
    }

    let dir = tempdir().unwrap();
    let output_path = dir.path().join("export.zip");
    let cancellation = CancelAfterChecks::new(8);

    let error = export_to_zip_with_cancellation(&conn, &output_path, "test-device", &cancellation)
        .expect_err("export should stop once cancellation trips");

    assert!(matches!(error, ExportError::Cancelled));
    assert!(
        !output_path.exists(),
        "cancelled export must not publish final zip"
    );
    assert!(
        !output_path.with_extension("zip.tmp").exists(),
        "cancelled export must remove partial temp zip"
    );
}

#[test]
fn export_creates_valid_zip_with_manifest() {
    let conn = seed_db();
    let (manifest, data) = export_to_memory(&conn);

    // Open the ZIP and verify manifest.json exists.
    let cursor = Cursor::new(data);
    let mut archive = zip::ZipArchive::new(cursor).unwrap();

    let mut manifest_file = archive.by_name("manifest.json").unwrap();
    let mut manifest_str = String::new();
    manifest_file.read_to_string(&mut manifest_str).unwrap();
    let parsed: serde_json::Value = serde_json::from_str(&manifest_str).unwrap();

    assert_eq!(
        parsed["format_version"].as_u64().unwrap(),
        u64::from(EXPORT_FORMAT_VERSION)
    );
    assert_eq!(parsed["device_id"].as_str().unwrap(), "test-device");
    assert_eq!(manifest.format_version, EXPORT_FORMAT_VERSION);
}

#[test]
fn manifest_has_correct_edge_counts() {
    let conn = seed_db();
    let (manifest, _data) = export_to_memory(&conn);

    assert_eq!(manifest.edge_counts.get(EDGE_TASK_TAG), Some(&1));
}

#[test]
fn entities_jsonl_uses_canonical_names() {
    let conn = seed_db();
    let (_manifest, data) = export_to_memory(&conn);

    let cursor = Cursor::new(data);
    let mut archive = zip::ZipArchive::new(cursor).unwrap();
    let mut entities_file = archive.by_name("entities.jsonl").unwrap();
    let mut entities_str = String::new();
    entities_file.read_to_string(&mut entities_str).unwrap();

    let lines: Vec<&str> = entities_str.trim().lines().collect();
    assert!(!lines.is_empty());

    // Check that list entities use the canonical name. The first list entity
    // may be the schema-seeded 'inbox' or the explicit 'list-1' depending on
    // export order, so find any list entity and verify its structure.
    let list_line = lines
        .iter()
        .map(|l| serde_json::from_str::<serde_json::Value>(l).unwrap())
        .find(|v| {
            v["entity_type"].as_str() == Some(ENTITY_LIST)
                && v["entity_id"].as_str() == Some("list-1")
        })
        .expect("should contain list-1 entity");
    assert!(list_line["payload"].is_object());
    assert_eq!(
        list_line["payload"]["archived_at"].as_str(),
        Some("2026-01-03T00:00:00.000Z")
    );
    assert_eq!(list_line["payload"]["position"].as_i64(), Some(12));
}

#[test]
fn edges_jsonl_uses_canonical_names() {
    let conn = seed_db();
    let (_manifest, data) = export_to_memory(&conn);

    let cursor = Cursor::new(data);
    let mut archive = zip::ZipArchive::new(cursor).unwrap();
    let mut edges_file = archive.by_name("edges.jsonl").unwrap();
    let mut edges_str = String::new();
    edges_file.read_to_string(&mut edges_str).unwrap();

    let lines: Vec<&str> = edges_str.trim().lines().collect();
    assert_eq!(lines.len(), 1);

    let edge: serde_json::Value = serde_json::from_str(lines[0]).unwrap();
    assert_eq!(edge["entity_type"].as_str().unwrap(), EDGE_TASK_TAG);
    assert_eq!(edge["payload"]["task_id"].as_str().unwrap(), "task-1");
    assert_eq!(edge["payload"]["tag_id"].as_str().unwrap(), "tag-1");
}

#[test]
fn versioned_jsonl_streams_emit_required_non_empty_versions() {
    let conn = seed_db();
    let (_manifest, data) = export_to_memory(&conn);

    let cursor = Cursor::new(data);
    let mut archive = zip::ZipArchive::new(cursor).unwrap();

    for name in ["entities.jsonl", "edges.jsonl", "children.jsonl"] {
        let mut file = archive.by_name(name).unwrap();
        let mut content = String::new();
        file.read_to_string(&mut content).unwrap();

        for line in content.lines().filter(|line| !line.trim().is_empty()) {
            let row: serde_json::Value = serde_json::from_str(line).unwrap();
            let version = row["version"].as_str().unwrap();
            assert!(
                !version.is_empty(),
                "{name} emitted an empty version for row: {row}",
            );
        }
    }
}

#[test]
fn zip_contains_all_expected_files() {
    let conn = seed_db();
    let (_manifest, data) = export_to_memory(&conn);

    let cursor = Cursor::new(data);
    let archive = zip::ZipArchive::new(cursor).unwrap();
    let names: Vec<&str> = archive.file_names().collect();

    assert!(names.contains(&"manifest.json"));
    assert!(names.contains(&"entities.jsonl"));
    assert!(names.contains(&"edges.jsonl"));
    assert!(names.contains(&"children.jsonl"));
    assert!(names.contains(&"audit.jsonl"));
    assert!(names.contains(&"tombstones.jsonl"));
    assert!(names.contains(&"payload_shadows.jsonl"));
    assert!(names.contains(&"provider_links.jsonl"));
}

#[test]
fn export_includes_local_provider_links_in_full_and_scoped_archives() {
    let conn = seed_db();
    conn.execute(
        "INSERT INTO task_provider_event_links
            (task_id, provider_kind, provider_scope, provider_event_key, created_at, updated_at)
         VALUES ('task-1', 'eventkit', 'default', 'event-1',
                 '2026-03-29T00:00:00Z', '2026-03-29T00:00:01Z')",
        [],
    )
    .unwrap();

    let (_manifest, data) = export_to_memory(&conn);
    let full_rows = provider_link_rows_from_zip_bytes(data);
    assert_eq!(full_rows.len(), 1);
    assert_eq!(
        full_rows[0]["entity_type"].as_str(),
        Some(EDGE_TASK_PROVIDER_EVENT_LINK)
    );
    assert_eq!(full_rows[0]["payload"]["task_id"].as_str(), Some("task-1"));

    let dir = tempdir().unwrap();
    let scoped_path = dir.path().join("scoped-provider-links.zip");
    export_to_zip_scoped(
        &conn,
        &scoped_path,
        "test-device",
        &ExportScope::scoped([ExportCategory::Tasks]),
    )
    .unwrap();
    let scoped_rows = provider_link_rows_from_zip_bytes(std::fs::read(scoped_path).unwrap());
    assert_eq!(scoped_rows.len(), 1);
    assert_eq!(
        scoped_rows[0]["payload"]["task_id"].as_str(),
        Some("task-1")
    );
}

fn provider_link_rows_from_zip_bytes(data: Vec<u8>) -> Vec<serde_json::Value> {
    let cursor = Cursor::new(data);
    let mut archive = zip::ZipArchive::new(cursor).unwrap();
    let mut provider_links_file = archive.by_name("provider_links.jsonl").unwrap();
    let mut provider_links_str = String::new();
    provider_links_file
        .read_to_string(&mut provider_links_str)
        .unwrap();
    provider_links_str
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(|line| serde_json::from_str::<serde_json::Value>(line).unwrap())
        .collect()
}

#[test]
fn export_rejects_malformed_payload_shadow_json() {
    let conn = seed_db();
    conn.execute(
        "INSERT INTO sync_payload_shadow (
            entity_type, entity_id, base_version, payload_schema_version,
            raw_payload_json, updated_at
         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
        rusqlite::params![
            ENTITY_TASK,
            "task-1",
            "1711234567000_0000_a1b2c3d4a1b2c3d4",
            2,
            r#"{"id":"task-1","title":"Broken""#,
            "2026-01-01T00:00:00Z",
        ],
    )
    .unwrap();

    let dir = tempdir().unwrap();
    let output_path = dir.path().join("export.zip");

    let result = export_to_zip(&conn, &output_path, "test-device");

    assert!(
        matches!(
            result,
            Err(ExportError::Store(crate::error::StoreError::Serialization(
                _
            )))
        ),
        "expected malformed payload shadow to surface as export store serialization error",
    );
}

#[cfg(unix)]
#[test]
fn full_export_rejects_symlinked_temp_path_without_touching_target() {
    let conn = seed_db();
    let dir = tempdir().unwrap();

    let output_path = dir.path().join("backup.zip");
    let temp_path = output_path.with_extension("zip.tmp");
    let sentinel_path = dir.path().join("sentinel.txt");
    let sentinel = b"do not clobber";
    std::fs::write(&sentinel_path, sentinel).unwrap();
    create_file_symlink(&sentinel_path, &temp_path);

    let result = export_to_zip(&conn, &output_path, "test-device");

    assert!(
        result.is_err(),
        "export must reject a pre-planted symlink at its temp path"
    );
    assert_eq!(
        std::fs::read(&sentinel_path).unwrap(),
        sentinel,
        "export must not follow the temp symlink and modify its target",
    );
    assert!(
        !output_path.exists(),
        "failed export must not publish a final output path"
    );
}

#[cfg(unix)]
#[test]
fn scoped_export_rejects_symlinked_temp_path_without_touching_target() {
    let conn = seed_db();
    let dir = tempdir().unwrap();

    let output_path = dir.path().join("backup.zip");
    let temp_path = output_path.with_extension("zip.tmp");
    let sentinel_path = dir.path().join("sentinel.txt");
    let sentinel = b"do not clobber";
    std::fs::write(&sentinel_path, sentinel).unwrap();
    create_file_symlink(&sentinel_path, &temp_path);

    let result = export_to_zip_scoped(
        &conn,
        &output_path,
        "test-device",
        &ExportScope::scoped([ExportCategory::Tasks]),
    );

    assert!(
        result.is_err(),
        "scoped export must reject a pre-planted symlink at its temp path"
    );
    assert_eq!(
        std::fs::read(&sentinel_path).unwrap(),
        sentinel,
        "scoped export must not follow the temp symlink and modify its target",
    );
    assert!(
        !output_path.exists(),
        "failed scoped export must not publish a final output path"
    );
}

#[test]
fn edge_entity_id_rejects_missing_task_id() {
    let payload = serde_json::json!({
        "tag_id": "tag-1",
    });

    let err = edge_entity_id(EDGE_TASK_TAG, payload.as_object().unwrap()).unwrap_err();
    assert!(
        err.to_string().contains("task_id"),
        "expected task_id error, got: {err}"
    );
}

#[test]
fn edge_entity_id_rejects_missing_calendar_event_id() {
    let payload = serde_json::json!({
        "task_id": "task-1",
    });

    let err =
        edge_entity_id(EDGE_TASK_CALENDAR_EVENT_LINK, payload.as_object().unwrap()).unwrap_err();
    assert!(
        err.to_string().contains("calendar_event_id"),
        "expected calendar_event_id error, got: {err}"
    );
}

#[test]
fn edge_entity_id_preserves_canonical_composite_key() {
    let payload = serde_json::json!({
        "task_id": "task-1",
        "depends_on_task_id": "task-2",
    });

    let entity_id = edge_entity_id(EDGE_TASK_DEPENDENCY, payload.as_object().unwrap()).unwrap();
    assert_eq!(entity_id, "task-1:task-2");
}

#[test]
fn scoped_export_filters_records_and_sets_manifest_scope() {
    let conn = seed_db();
    let dir = tempdir().unwrap();
    let output_path = dir.path().join("scoped-export.zip");

    let manifest = export_to_zip_scoped(
        &conn,
        &output_path,
        "test-device",
        &ExportScope::scoped([ExportCategory::Tasks]),
    )
    .unwrap();

    assert_eq!(manifest.scope_kind, ExportScopeKind::Scoped);
    assert_eq!(manifest.scope_categories, vec![ExportCategory::Tasks]);
    assert_eq!(manifest.dependency_mode, ExportDependencyMode::Closure);
    assert_eq!(manifest.entity_counts.get(ENTITY_TASK), Some(&2));
    // task-2 defaults to 'inbox' list, which is dependency-closure'd along with 'list-1'
    assert_eq!(manifest.entity_counts.get(ENTITY_LIST), Some(&2));
    assert_eq!(manifest.entity_counts.get(ENTITY_TAG), Some(&1));
    assert_eq!(manifest.edge_counts.get(EDGE_TASK_TAG), Some(&1));

    let data = std::fs::read(&output_path).unwrap();
    let cursor = Cursor::new(data);
    let mut archive = zip::ZipArchive::new(cursor).unwrap();
    let mut manifest_file = archive.by_name("manifest.json").unwrap();
    let mut manifest_str = String::new();
    manifest_file.read_to_string(&mut manifest_str).unwrap();
    let parsed: serde_json::Value = serde_json::from_str(&manifest_str).unwrap();
    assert_eq!(parsed["scope_kind"], serde_json::json!("scoped"));
    assert_eq!(parsed["scope_categories"], serde_json::json!(["tasks"]));
}

#[test]
fn scoped_export_includes_category_tombstones_even_without_live_records() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO sync_tombstones (entity_type, entity_id, version, deleted_at)
         VALUES (?1, 'task-deleted-only', '1711234567890_0001_deadbeefdeadbeef',
                 '2026-03-29T00:00:00Z')",
        rusqlite::params![ENTITY_TASK],
    )
    .unwrap();

    let dir = tempdir().unwrap();
    let output_path = dir.path().join("scoped-tombstone-export.zip");

    let manifest = export_to_zip_scoped(
        &conn,
        &output_path,
        "test-device",
        &ExportScope::scoped([ExportCategory::Tasks]),
    )
    .unwrap();

    assert_eq!(manifest.scope_kind, ExportScopeKind::Scoped);
    assert_eq!(manifest.entity_counts.get(ENTITY_TASK), None);

    let data = std::fs::read(&output_path).unwrap();
    let cursor = Cursor::new(data);
    let mut archive = zip::ZipArchive::new(cursor).unwrap();
    let mut tombstones_file = archive.by_name("tombstones.jsonl").unwrap();
    let mut tombstones_str = String::new();
    tombstones_file.read_to_string(&mut tombstones_str).unwrap();

    let tombstones = tombstones_str
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(|line| serde_json::from_str::<serde_json::Value>(line).unwrap())
        .collect::<Vec<_>>();
    assert_eq!(tombstones.len(), 1);
    assert_eq!(tombstones[0]["entity_type"].as_str(), Some(ENTITY_TASK));
    assert_eq!(
        tombstones[0]["entity_id"].as_str(),
        Some("task-deleted-only")
    );
}
