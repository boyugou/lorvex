use super::*;
use crate::connection::open_db_in_memory;
use crate::export::export_to_zip;
pub(super) use lorvex_domain::naming::{
    EDGE_HABIT_COMPLETION, EDGE_TASK_CALENDAR_EVENT_LINK, EDGE_TASK_DEPENDENCY,
    EDGE_TASK_PROVIDER_EVENT_LINK, EDGE_TASK_TAG, ENTITY_AI_CHANGELOG, ENTITY_CALENDAR_EVENT,
    ENTITY_CALENDAR_SUBSCRIPTION, ENTITY_CURRENT_FOCUS, ENTITY_DAILY_REVIEW, ENTITY_FOCUS_SCHEDULE,
    ENTITY_HABIT, ENTITY_HABIT_REMINDER_POLICY, ENTITY_LIST, ENTITY_MEMORY, ENTITY_MEMORY_REVISION,
    ENTITY_PREFERENCE, ENTITY_TAG, ENTITY_TASK, ENTITY_TASK_CHECKLIST_ITEM, ENTITY_TASK_REMINDER,
};
pub(super) use lorvex_domain::version::EXPORT_FORMAT_VERSION;
pub(super) use std::io::{Read, Write};
pub(super) use tempfile::tempdir;
pub(super) use zip::write::SimpleFileOptions;
pub(super) use zip::ZipWriter;

mod apply_children;
mod apply_edges;
mod apply_entities;
mod apply_entities_misc;
mod apply_timestamps;
mod apply_tombstones;
mod archive_io;
mod manifest;
mod scoped;
mod type_validation;

/// Seed a DB with test data, export it, then import into a fresh DB.
pub(super) fn roundtrip_test() -> (Connection, Connection, ImportSummary) {
    let source = open_db_in_memory().unwrap();

    // Seed source data.
    source
            .execute(
                "INSERT INTO lists (id, name, color, created_at, updated_at, version)
                 VALUES ('list-1', 'Work', '#FF0000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '1711234567890_0001_deadbeefdeadbeef')",
                [],
            )
            .unwrap();
    source
            .execute(
                "INSERT INTO tasks (id, title, status, list_id, priority, created_at, updated_at, version)
                 VALUES ('task-1', 'Buy milk', 'open', 'list-1', 2, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '1711234567890_0001_deadbeefdeadbeef')",
                [],
            )
            .unwrap();
    source
            .execute(
                "INSERT INTO tasks (id, title, status, list_id, created_at, updated_at, version)
                 VALUES ('task-2', 'Read book', 'completed', 'list-1', '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z', '1711234567890_0002_deadbeefdeadbeef')",
                [],
            )
            .unwrap();
    source
            .execute(
                "INSERT INTO tags (id, display_name, lookup_key, color, created_at, updated_at, version)
                 VALUES ('tag-1', 'urgent', 'urgent', '#FF0000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '1711234567890_0001_deadbeefdeadbeef')",
                [],
            )
            .unwrap();
    source
        .execute(
            "INSERT INTO task_tags (task_id, tag_id, created_at, version)
                 VALUES ('task-1', 'tag-1', '2026-01-01T00:00:00Z', '1711234567890_0001_deadbeefdeadbeef')",
            [],
        )
        .unwrap();

    // Export.
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("export.zip");
    export_to_zip(&source, &zip_path, "dev-1").unwrap();

    // Import into fresh DB.
    let target = open_db_in_memory().unwrap();
    let summary = import_from_zip(&target, &zip_path).unwrap();

    (source, target, summary)
}

#[test]
fn roundtrip_preserves_ai_changelog_undo_token_and_preview_flag() {
    let source = open_db_in_memory().unwrap();
    source
        .execute(
            "INSERT INTO ai_changelog (
                id, timestamp, operation, entity_type, entity_id,
                summary, initiated_by, mcp_tool, source_device_id, before_json,
                after_json, undo_token, is_preview
             )
             VALUES (
                'audit-preview-1', '2026-05-09T00:00:00Z', 'delete_habit_preview',
                ?1, 'habit-1', '[preview] Would delete habit',
                'ai', 'delete_habit', 'device-a', NULL, NULL, ?2, 1
            )",
            [
                ENTITY_HABIT,
                r#"{"kind":"delete_habit","habit_id":"habit-1"}"#,
            ],
        )
        .unwrap();
    // Mirror the join-table registry the canonical writer would
    // populate; the export side reads the wire-form JSON via the
    // `ai_changelog_entities` subquery in `columns::AI_CHANGELOG`.
    crate::changelog::replace_changelog_entities(
        &source,
        "audit-preview-1",
        &["habit-1".to_string()],
    )
    .unwrap();

    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("export.zip");
    export_to_zip(&source, &zip_path, "dev-1").unwrap();

    let target = open_db_in_memory().unwrap();
    import_from_zip(&target, &zip_path).unwrap();

    let (undo_token, is_preview): (Option<String>, i64) = target
        .query_row(
            "SELECT undo_token, is_preview FROM ai_changelog WHERE id = 'audit-preview-1'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(
        undo_token.as_deref(),
        Some(r#"{"kind":"delete_habit","habit_id":"habit-1"}"#)
    );
    assert_eq!(is_preview, 1);
}

pub(super) fn write_import_zip(
    zip_path: &Path,
    entities: &[serde_json::Value],
    edges: &[serde_json::Value],
    children: &[serde_json::Value],
    audit: &[serde_json::Value],
    tombstones: &[serde_json::Value],
) {
    write_import_zip_with_manifest(
        zip_path,
        default_import_manifest(),
        entities,
        edges,
        children,
        audit,
        tombstones,
    );
}

pub(super) fn write_import_zip_with_provider_links(
    zip_path: &Path,
    provider_links: &[serde_json::Value],
) {
    write_import_zip_with_sections_inner(
        zip_path,
        default_import_manifest(),
        ImportZipSectionRows {
            provider_links,
            ..ImportZipSectionRows::empty()
        },
    );
}

pub(super) fn default_import_manifest() -> serde_json::Value {
    serde_json::json!({
        "format_version": EXPORT_FORMAT_VERSION,
        "schema_version": 1,
        "payload_schema_version": 1,
        "created_at": "2026-03-29T00:00:00Z",
        "device_id": "test-device",
        "scope_kind": "full",
        "scope_categories": [],
        "dependency_mode": "closure",
    })
}

// Test-only helper: positional slice args map directly to JSONL
// sections and avoid an allocation-heavy struct per call.
#[allow(clippy::too_many_arguments)]
pub(super) fn write_import_zip_with_manifest(
    zip_path: &Path,
    manifest: serde_json::Value,
    entities: &[serde_json::Value],
    edges: &[serde_json::Value],
    children: &[serde_json::Value],
    audit: &[serde_json::Value],
    tombstones: &[serde_json::Value],
) {
    write_import_zip_with_sections(
        zip_path,
        manifest,
        entities,
        edges,
        children,
        audit,
        tombstones,
        &[],
    );
}

#[allow(clippy::too_many_arguments)]
pub(super) fn write_import_zip_with_sections(
    zip_path: &Path,
    manifest: serde_json::Value,
    entities: &[serde_json::Value],
    edges: &[serde_json::Value],
    children: &[serde_json::Value],
    audit: &[serde_json::Value],
    tombstones: &[serde_json::Value],
    shadows: &[serde_json::Value],
) {
    write_import_zip_with_sections_inner(
        zip_path,
        manifest,
        ImportZipSectionRows {
            entities,
            edges,
            children,
            audit,
            tombstones,
            shadows,
            ..ImportZipSectionRows::empty()
        },
    );
}

struct ImportZipSectionRows<'a> {
    entities: &'a [serde_json::Value],
    edges: &'a [serde_json::Value],
    children: &'a [serde_json::Value],
    audit: &'a [serde_json::Value],
    tombstones: &'a [serde_json::Value],
    provider_links: &'a [serde_json::Value],
    shadows: &'a [serde_json::Value],
}

impl<'a> ImportZipSectionRows<'a> {
    fn empty() -> Self {
        Self {
            entities: &[],
            edges: &[],
            children: &[],
            audit: &[],
            tombstones: &[],
            provider_links: &[],
            shadows: &[],
        }
    }
}

fn write_import_zip_with_sections_inner(
    zip_path: &Path,
    manifest: serde_json::Value,
    sections: ImportZipSectionRows<'_>,
) {
    let section_bodies: Vec<(&str, Vec<u8>)> = REQUIRED_JSONL_FILES
        .iter()
        .map(|&name| {
            let rows = match name {
                "entities.jsonl" => sections.entities,
                "edges.jsonl" => sections.edges,
                "children.jsonl" => sections.children,
                "audit.jsonl" => sections.audit,
                "payload_shadows.jsonl" => sections.shadows,
                "tombstones.jsonl" => sections.tombstones,
                "provider_links.jsonl" => sections.provider_links,
                other => panic!("unhandled JSONL section in test helper: {other}"),
            };
            (name, jsonl_bytes(rows))
        })
        .collect();
    let manifest = manifest_with_file_digests(manifest, &section_bodies);

    let file = std::fs::File::create(zip_path).unwrap();
    let mut writer = ZipWriter::new(file);
    let options = SimpleFileOptions::default();

    writer.start_file("manifest.json", options).unwrap();
    writer
        .write_all(serde_json::to_string_pretty(&manifest).unwrap().as_bytes())
        .unwrap();

    for (name, body) in &section_bodies {
        writer.start_file(*name, options).unwrap();
        writer.write_all(body).unwrap();
    }
    writer.finish().unwrap();
}

fn jsonl_bytes(rows: &[serde_json::Value]) -> Vec<u8> {
    let mut body = Vec::new();
    for row in rows {
        body.write_all(serde_json::to_string(row).unwrap().as_bytes())
            .unwrap();
        body.write_all(b"\n").unwrap();
    }
    body
}

fn sha256_hex(data: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(data);
    hex::encode(hasher.finalize())
}

fn manifest_with_file_digests(
    mut manifest: serde_json::Value,
    section_bodies: &[(&str, Vec<u8>)],
) -> serde_json::Value {
    let file_digests: std::collections::BTreeMap<String, crate::export::FileDigest> =
        section_bodies
            .iter()
            .map(|(name, body)| {
                (
                    (*name).to_string(),
                    crate::export::FileDigest {
                        sha256: sha256_hex(body),
                        bytes: body.len() as u64,
                    },
                )
            })
            .collect();
    manifest
        .as_object_mut()
        .expect("test import manifest must be an object")
        .insert(
            "file_digests".to_string(),
            serde_json::to_value(file_digests).unwrap(),
        );
    manifest
}
