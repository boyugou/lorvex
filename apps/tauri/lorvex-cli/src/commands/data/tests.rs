use crate::cli::OutputFormat;
use crate::error::CliError;
use lorvex_runtime::{get_or_create_device_id, read_local_change_seq, with_db_path_env_for_test};
use lorvex_store::repositories::task::read;
use rusqlite::Connection;
use std::io::Write;
use std::path::Path;
use zip::write::SimpleFileOptions;
use zip::ZipWriter;

const REQUIRED_JSONL_FILES: [&str; 7] = [
    "entities.jsonl",
    "edges.jsonl",
    "children.jsonl",
    "audit.jsonl",
    "payload_shadows.jsonl",
    "tombstones.jsonl",
    "provider_links.jsonl",
];

fn seed_task(conn: &Connection, id: &str, title: &str, status: &str) {
    conn.execute(
        "INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at)
         VALUES ('list-seed', 'Seed List', '0000000000000_0000_0000000000000000', '2026-03-30T00:00:00Z', '2026-03-30T00:00:00Z')",
        [],
    )
    .expect("insert seed list");
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title(title)
        .status(status)
        .created_at("2026-03-30T00:00:00Z")
        .list_id(Some("list-seed"))
        .insert(conn);
}

fn export_zip_with_task(zip_path: &Path, task_id: &str, title: &str) {
    let tempdir = tempfile::tempdir().expect("create source tempdir");
    let db_path = tempdir.path().join(format!("{task_id}.sqlite"));

    let conn = lorvex_store::open_db_at_path(&db_path).expect("open source db");
    seed_task(&conn, task_id, title, "open");
    let device_id = get_or_create_device_id(&conn).expect("get source device id");
    lorvex_store::export_to_zip(&conn, zip_path, &device_id).expect("export snapshot");
}

fn sha256_hex(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    hasher
        .finalize()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

fn write_invalid_scoped_zip(zip_path: &Path) {
    let section_bodies: Vec<(&str, Vec<u8>)> = REQUIRED_JSONL_FILES
        .iter()
        .map(|&name| (name, Vec::new()))
        .collect();
    let mut manifest = serde_json::json!({
        "format_version": lorvex_domain::version::EXPORT_FORMAT_VERSION,
        "schema_version": 1,
        "payload_schema_version": 1,
        "created_at": "2026-03-29T00:00:00Z",
        "device_id": "cli-invalid-scope-test",
        "scope_kind": "scoped",
        "scope_categories": [],
        "dependency_mode": "closure",
    });
    let file_digests = section_bodies
        .iter()
        .map(|(name, body)| {
            (
                (*name).to_string(),
                serde_json::json!({
                    "sha256": sha256_hex(body),
                    "bytes": body.len(),
                }),
            )
        })
        .collect();
    manifest
        .as_object_mut()
        .expect("test manifest must be an object")
        .insert(
            "file_digests".to_string(),
            serde_json::Value::Object(file_digests),
        );

    let file = std::fs::File::create(zip_path).expect("create invalid scoped zip");
    let mut writer = ZipWriter::new(file);
    let options = SimpleFileOptions::default();
    writer
        .start_file("manifest.json", options)
        .expect("start manifest");
    writer
        .write_all(
            serde_json::to_string_pretty(&manifest)
                .expect("serialize manifest")
                .as_bytes(),
        )
        .expect("write manifest");
    for (name, body) in section_bodies {
        writer.start_file(name, options).expect("start section");
        writer.write_all(&body).expect("write section");
    }
    writer.finish().expect("finish invalid scoped zip");
}

#[cfg(unix)]
#[test]
fn validated_cli_import_uses_original_file_descriptor_after_path_replacement() {
    let tempdir = tempfile::tempdir().expect("create tempdir");
    let import_zip = tempdir.path().join("import.zip");
    let replacement_zip = tempdir.path().join("replacement.zip");
    let target_db = tempdir.path().join("target.sqlite");

    export_zip_with_task(&import_zip, "task-original", "Original descriptor");
    export_zip_with_task(&replacement_zip, "task-replacement", "Replacement path");
    let original_size = std::fs::metadata(&import_zip)
        .expect("stat original zip")
        .len();

    let validated = super::validate_import_zip_path(&import_zip).expect("validate original zip");
    std::fs::rename(&replacement_zip, &import_zip).expect("replace zip path after validation");

    let target = lorvex_store::open_db_at_path(&target_db).expect("open target db");
    let summary = super::import_validated_zip(&target, validated).expect("import zip");

    assert_eq!(summary.estimated_size_bytes, original_size);
    let original = read::get_task(
        &target,
        &lorvex_domain::TaskId::from_trusted("task-original".to_string()),
    )
    .expect("load original task");
    assert!(
        original.is_some(),
        "import must read the originally validated descriptor"
    );
    let replacement = read::get_task(
        &target,
        &lorvex_domain::TaskId::from_trusted("task-replacement".to_string()),
    )
    .expect("load replacement task");
    assert!(
        replacement.is_none(),
        "import must not reopen the swapped path"
    );
}

#[test]
fn export_and_import_roundtrip_restores_tasks_and_bumps_local_change_seq() {
    let tempdir = tempfile::tempdir().expect("create tempdir");
    let export_zip = tempdir.path().join("backup.zip");
    let source_db = tempdir.path().join("source.sqlite");
    let target_db = tempdir.path().join("target.sqlite");

    let source = lorvex_store::open_db_at_path(&source_db).expect("open source db");
    seed_task(&source, "task-export", "Export me", "open");

    let device_id = get_or_create_device_id(&source).expect("get source device id");
    let manifest =
        lorvex_store::export_to_zip(&source, &export_zip, &device_id).expect("export snapshot");
    assert_eq!(manifest.device_id, device_id);

    let target = lorvex_store::open_db_at_path(&target_db).expect("open target db");
    let before_seq = read_local_change_seq(&target).expect("read pre-import change seq");
    assert_eq!(before_seq, 0);
    lorvex_runtime::sync_checkpoint_set(&target, lorvex_runtime::KEY_FULL_SYNC_SEEDED, "1")
        .expect("seed pre-import full sync checkpoint");

    let output = with_db_path_env_for_test(Some(target_db.to_string_lossy().as_ref()), || {
        super::run_import(export_zip.to_string_lossy().as_ref(), OutputFormat::Text)
            .expect("run CLI import")
    });
    assert!(output.contains("Imported Lorvex snapshot"));

    let imported = read::get_task(
        &target,
        &lorvex_domain::TaskId::from_trusted("task-export".to_string()),
    )
    .expect("load imported task")
    .expect("task should exist after import");
    assert_eq!(imported.core().title(), "Export me");

    let after_seq = read_local_change_seq(&target).expect("read post-import change seq");
    assert_eq!(after_seq, 1);
    assert_eq!(
        lorvex_runtime::sync_checkpoint_get(&target, lorvex_runtime::KEY_FULL_SYNC_SEEDED)
            .expect("read full sync checkpoint"),
        None
    );
    assert_eq!(
        lorvex_runtime::sync_checkpoint_get(&target, lorvex_runtime::KEY_RESEED_REQUIRED)
            .expect("read reseed checkpoint")
            .as_deref(),
        Some("true")
    );
    let conflict: (String, String, String) = target
        .query_row(
            "SELECT entity_type, entity_id, resolution_type
             FROM sync_conflict_log
             WHERE entity_type = 'snapshot_import'
               AND entity_id = 'cli_import'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("read CLI reseed marker");
    assert_eq!(conflict.0, "snapshot_import");
    assert_eq!(conflict.1, "cli_import");
    assert_eq!(
        conflict.2,
        lorvex_domain::naming::RESOLUTION_RESEED_REQUIRED
    );
}

#[test]
fn import_rejects_invalid_scoped_archive_before_sync_finalization() {
    let tempdir = tempfile::tempdir().expect("create tempdir");
    let import_zip = tempdir.path().join("invalid-scoped.zip");
    let target_db = tempdir.path().join("target.sqlite");
    write_invalid_scoped_zip(&import_zip);

    let target = lorvex_store::open_db_at_path(&target_db).expect("open target db");
    assert_eq!(
        read_local_change_seq(&target).expect("read pre-import change seq"),
        0
    );
    lorvex_runtime::sync_checkpoint_set(&target, lorvex_runtime::KEY_FULL_SYNC_SEEDED, "1")
        .expect("seed pre-import full sync checkpoint");

    let err = with_db_path_env_for_test(Some(target_db.to_string_lossy().as_ref()), || {
        super::run_import(import_zip.to_string_lossy().as_ref(), OutputFormat::Text)
            .expect_err("invalid scoped import must fail")
    });
    match err {
        CliError::Import(import_err)
            if matches!(*import_err, lorvex_store::ImportError::InvalidPayload(_)) =>
        {
            let lorvex_store::ImportError::InvalidPayload(message) = *import_err else {
                unreachable!()
            };
            assert!(
                message.contains("scoped import validation failed"),
                "expected scoped validation failure message, got: {message}"
            );
            assert!(
                message.contains("empty_scoped_categories"),
                "expected validation finding code, got: {message}"
            );
        }
        other => panic!("expected scoped import validation error, got {other:?}"),
    }

    assert_eq!(
        read_local_change_seq(&target).expect("read post-import change seq"),
        0,
        "failed import must not bump local change sequence"
    );
    assert_eq!(
        lorvex_runtime::sync_checkpoint_get(&target, lorvex_runtime::KEY_FULL_SYNC_SEEDED)
            .expect("read full sync checkpoint")
            .as_deref(),
        Some("1"),
        "failed import must not clear full sync seeded checkpoint"
    );
    let reseed_markers: i64 = target
        .query_row(
            "SELECT COUNT(*)
             FROM sync_conflict_log
             WHERE entity_type = 'snapshot_import'
               AND entity_id = 'cli_import'",
            [],
            |row| row.get(0),
        )
        .expect("count CLI reseed markers");
    assert_eq!(reseed_markers, 0);
}
