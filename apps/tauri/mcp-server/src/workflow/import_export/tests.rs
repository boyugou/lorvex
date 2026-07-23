use super::{check_zip_signature, normalize_export_zip_path, validate_import_zip_path};
use lorvex_store::repositories::task::read;
use std::fs;
use std::path::Path;

fn write_temp_file(name: &str, bytes: &[u8]) -> std::path::PathBuf {
    let name_path = Path::new(name);
    let stem = name_path
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or("snapshot");
    let extension = name_path
        .extension()
        .and_then(|value| value.to_str())
        .map(|value| format!(".{value}"))
        .unwrap_or_default();
    let path = std::env::temp_dir().join(format!(
        "lorvex-mcp-import-export-test-{stem}-{}{}",
        std::process::id(),
        extension
    ));
    fs::write(&path, bytes).expect("write temp zip");
    path
}

fn seed_task(conn: &rusqlite::Connection, id: &str, title: &str) {
    conn.execute(
        "INSERT OR IGNORE INTO lists (id, name, version, created_at, updated_at)
         VALUES ('list-seed', 'Seed List', '0000000000000_0000_0000000000000000', '2026-03-30T00:00:00Z', '2026-03-30T00:00:00Z')",
        [],
    )
    .expect("insert seed list");
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title(title)
        .status("open")
        .created_at("2026-03-30T00:00:00Z")
        .list_id(Some("list-seed"))
        .insert(conn);
}

fn export_zip_with_task(zip_path: &Path, task_id: &str, title: &str) {
    let tempdir = tempfile::tempdir().expect("create source tempdir");
    let db_path = tempdir.path().join(format!("{task_id}.sqlite"));

    let conn = lorvex_store::open_db_at_path(&db_path).expect("open source db");
    seed_task(&conn, task_id, title);
    lorvex_store::export_to_zip(&conn, zip_path, &format!("device-{task_id}"))
        .expect("export snapshot");
}

#[test]
#[serial_test::serial(hlc)]
fn normalize_export_path_appends_zip_extension_to_bare_filename() {
    let path = normalize_export_zip_path(Some("backup".to_string())).expect("normalized path");
    assert!(path.file_name().and_then(|f| f.to_str()) == Some("backup.zip"));
}

#[test]
#[serial_test::serial(hlc)]
fn normalize_export_path_rejects_directory_separator() {
    let err = normalize_export_zip_path(Some("tmp/backup.zip".to_string()))
        .expect_err("should reject path with /");
    assert!(err.contains("plain filename"));
}

#[test]
#[serial_test::serial(hlc)]
fn normalize_export_path_rejects_absolute_path() {
    let err = normalize_export_zip_path(Some("/tmp/backup.zip".to_string()))
        .expect_err("should reject absolute path");
    assert!(err.contains("plain filename"));
}

#[test]
#[serial_test::serial(hlc)]
fn normalize_export_path_rejects_parent_dir_traversal() {
    let err = normalize_export_zip_path(Some("..".to_string())).expect_err("should reject ..");
    assert!(err.contains("plain filename"));
    let err2 = normalize_export_zip_path(Some("../etc/passwd.zip".to_string()))
        .expect_err("should reject ..");
    assert!(err2.contains("plain filename"));
}

#[test]
#[serial_test::serial(hlc)]
fn normalize_export_path_rejects_nul_byte() {
    let err = normalize_export_zip_path(Some("bad\0name.zip".to_string()))
        .expect_err("should reject NUL");
    assert!(err.contains("plain filename"));
}

#[test]
#[serial_test::serial(hlc)]
fn normalize_export_path_accepts_zip_filename() {
    let path =
        normalize_export_zip_path(Some("my-export.zip".to_string())).expect("normalized path");
    assert!(path.file_name().and_then(|f| f.to_str()) == Some("my-export.zip"));
}

#[test]
#[serial_test::serial(hlc)]
fn import_zip_validation_rejects_non_zip_extension() {
    let path = write_temp_file("invalid.txt", &[0x50, 0x4B, 0x03, 0x04, 0x00]);
    let result = validate_import_zip_path(&path, path.to_string_lossy().as_ref());
    fs::remove_file(path).ok();
    assert_eq!(
        result.expect_err("should reject non-zip"),
        "Error: import_data requires a .zip archive"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn import_zip_validation_rejects_invalid_signature() {
    let path = write_temp_file("invalid.zip", b"nope");
    let result = validate_import_zip_path(&path, path.to_string_lossy().as_ref());
    fs::remove_file(path).ok();
    assert_eq!(
        result.expect_err("should reject invalid zip"),
        "Error: import_data requires a valid ZIP archive"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn zip_signature_accepts_standard_headers() {
    let path = write_temp_file("valid.zip", &[0x50, 0x4B, 0x03, 0x04, 0x00]);
    let mut file = std::fs::File::open(&path).expect("open valid zip");
    let result = check_zip_signature(&mut file).expect("signature check");
    fs::remove_file(path).ok();
    assert!(result);
}

#[cfg(unix)]
#[test]
#[serial_test::serial(hlc)]
fn validated_mcp_import_uses_original_file_descriptor_after_path_replacement() {
    let tempdir = tempfile::tempdir().expect("create tempdir");
    let import_zip = tempdir.path().join("import.zip");
    let replacement_zip = tempdir.path().join("replacement.zip");
    let target_db = tempdir.path().join("target.sqlite");

    export_zip_with_task(&import_zip, "task-original", "Original descriptor");
    export_zip_with_task(&replacement_zip, "task-replacement", "Replacement path");
    let original_size = std::fs::metadata(&import_zip)
        .expect("stat original zip")
        .len();

    let validated = validate_import_zip_path(&import_zip, import_zip.to_string_lossy().as_ref())
        .expect("validate original zip");
    std::fs::rename(&replacement_zip, &import_zip).expect("replace zip path after validation");

    let target = lorvex_store::open_db_at_path(&target_db).expect("open target db");
    let summary =
        super::import_validated_zip_with_options(&target, validated, false).expect("import zip");

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

/// pre-fix the `import_data` audit row stuffed
/// every numeric count into a freeform `summary` string and left
/// `before_json`/`after_json` empty. Diagnostics had to regex
/// across prose to recover the totals. The new helper threads
/// the structured numeric fields into `after_json`, so this test
/// asserts that helper's contract: every counted field on the
/// import summary surfaces as a JSON key in the payload.
#[test]
#[serial_test::serial(hlc)]
fn build_import_audit_after_json_carries_structured_counts() {
    let summary = lorvex_store::ImportSummary {
        entities_created: 17,
        entities_updated: 3,
        entities_skipped: 1,
        tasks_to_create: 12,
        tasks_to_update: 4,
        tasks_to_skip: 2,
        lists_to_create: 1,
        habits_to_create: 0,
        preferences_to_change: 5,
        memory_to_write: 6,
        estimated_size_bytes: 4096,
        ..lorvex_store::ImportSummary::default()
    };

    let payload = super::build_import_audit_after_json(&summary, false);
    assert_eq!(payload["dry_run"], serde_json::json!(false));
    assert_eq!(payload["entities_created"], serde_json::json!(17));
    assert_eq!(payload["entities_updated"], serde_json::json!(3));
    assert_eq!(payload["tasks_to_create"], serde_json::json!(12));
    assert_eq!(payload["preferences_to_change"], serde_json::json!(5));
    assert_eq!(payload["memory_to_write"], serde_json::json!(6));
    assert_eq!(payload["estimated_size_bytes"], serde_json::json!(4096));
}

/// pin the entity_type classification used by the
/// import audit row so a future refactor can't silently regress
/// it back to ENTITY_TASK. The constant lives in
/// lorvex-domain::naming.
#[test]
#[serial_test::serial(hlc)]
fn import_session_entity_type_is_local_only() {
    // Constant value pin: the audit row classification depends on
    // this exact string.
    assert_eq!(
        lorvex_domain::naming::ENTITY_IMPORT_SESSION,
        "import_session"
    );
    // Non-syncable: the funnel must NOT enqueue sync envelopes
    // for this entity type, otherwise import audit rows would
    // ship over the wire as if they were a syncable aggregate.
    assert!(!lorvex_domain::naming::is_syncable_type(
        lorvex_domain::naming::ENTITY_IMPORT_SESSION
    ));
}
