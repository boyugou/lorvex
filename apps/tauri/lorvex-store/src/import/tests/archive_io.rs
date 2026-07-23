use super::*;

#[test]
fn handle_optional_archive_lookup_error_allows_missing_optional_sections() {
    let contents = handle_optional_archive_lookup_error(zip::result::ZipError::FileNotFound)
        .expect("missing optional section should map to empty content");
    assert!(contents.is_empty());
}
/// booleans and rejects lossy numeric/string encodings.
#[test]
fn required_bool_as_i64_field_accepts_bool_rejects_others() {
    // JSON bool true/false → 1/0
    let t = serde_json::json!({ "flag": true });
    assert_eq!(required_bool_as_i64_field(&t, "flag", "test").unwrap(), 1);
    let f = serde_json::json!({ "flag": false });
    assert_eq!(required_bool_as_i64_field(&f, "flag", "test").unwrap(), 0);

    // Integers are rejected; JSON booleans are the import/export contract.
    let one = serde_json::json!({ "flag": 1 });
    assert!(required_bool_as_i64_field(&one, "flag", "test").is_err());
    let zero = serde_json::json!({ "flag": 0 });
    assert!(required_bool_as_i64_field(&zero, "flag", "test").is_err());

    // Strings are still rejected (defense against typos in
    // hand-crafted JSON — "true" as string is a bug).
    let s = serde_json::json!({ "flag": "true" });
    assert!(required_bool_as_i64_field(&s, "flag", "test").is_err());

    // Null is rejected.
    let n = serde_json::json!({ "flag": null });
    assert!(required_bool_as_i64_field(&n, "flag", "test").is_err());

    // Missing field is rejected.
    let empty = serde_json::json!({});
    assert!(required_bool_as_i64_field(&empty, "flag", "test").is_err());
}

#[test]
fn handle_optional_archive_lookup_error_rejects_invalid_archives() {
    // zip 4.x: InvalidArchive now carries Cow<'static, str> (was &'static str in 2.x).
    let error = handle_optional_archive_lookup_error(zip::result::ZipError::InvalidArchive(
        std::borrow::Cow::Borrowed("broken archive"),
    ))
    .expect_err("invalid archive lookup failure should surface");
    let message = error.to_string();
    assert!(
        message.contains("ZIP error") || message.contains("broken archive"),
        "unexpected error: {message}"
    );
}

#[test]
fn roundtrip_preserves_lists() {
    let (_source, target, _summary) = roundtrip_test();

    let name: String = target
        .query_row("SELECT name FROM lists WHERE id = 'list-1'", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(name, "Work");
}

#[test]
fn roundtrip_preserves_tasks() {
    let (_source, target, _summary) = roundtrip_test();

    let count: i64 = target
        .query_row("SELECT COUNT(*) FROM tasks", [], |row| row.get(0))
        .unwrap();
    assert_eq!(count, 2);

    let title: String = target
        .query_row("SELECT title FROM tasks WHERE id = 'task-1'", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(title, "Buy milk");
}

#[test]
fn roundtrip_preserves_tags() {
    let (_source, target, _summary) = roundtrip_test();

    let display_name: String = target
        .query_row(
            "SELECT display_name FROM tags WHERE id = 'tag-1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(display_name, "urgent");
}

#[test]
fn roundtrip_preserves_edges() {
    let (_source, target, _summary) = roundtrip_test();

    let count: i64 = target
        .query_row(
            "SELECT COUNT(*) FROM task_tags WHERE task_id = 'task-1' AND tag_id = 'tag-1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count, 1);
}

#[test]
fn roundtrip_summary_counts() {
    let (_source, _target, summary) = roundtrip_test();

    // 1 list + 2 tasks + 1 tag = 4 entities created.
    // Plus the task_tag edge = 1 edge created.
    assert!(
        summary.entities_created >= 4,
        "expected at least 4 created, got {}",
        summary.entities_created
    );
}

#[test]
fn import_rejects_tampered_entities_jsonl_via_manifest_digest() {
    // flip a byte inside `entities.jsonl` after export
    // and the digest in manifest.json no longer matches the on-disk
    // content. Import must abort with a clear digest-mismatch error
    // instead of silently processing the half-corrupted file.
    let source = open_db_in_memory().unwrap();
    // Seed a single list so entities.jsonl isn't empty.
    source
        .execute(
            "INSERT INTO lists (id, name, version, created_at, updated_at) \
                 VALUES ('list-tamper', 'Tamper Target', 'tamper-v1', \
                 '2026-03-29T00:00:00Z', '2026-03-29T00:00:00Z')",
            [],
        )
        .unwrap();

    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("clean.zip");
    export_to_zip(&source, &zip_path, "dev-1").unwrap();

    // Read the original archive, swap `entities.jsonl` with
    // something whose SHA-256 doesn't match the manifest, keep the
    // rest of the archive identical.
    let file = std::fs::File::open(&zip_path).unwrap();
    let mut archive = zip::ZipArchive::new(file).unwrap();
    let mut contents: std::collections::BTreeMap<String, Vec<u8>> =
        std::collections::BTreeMap::new();
    for i in 0..archive.len() {
        let mut entry = archive.by_index(i).unwrap();
        let name = entry.name().to_string();
        let mut buf = Vec::new();
        entry.read_to_end(&mut buf).unwrap();
        contents.insert(name, buf);
    }
    drop(archive);

    // Flip: rewrite entities.jsonl with a different (but still
    // parseable) payload. The version is still "tamper-v1" so
    // scoped inventory validation still passes; only the digest
    // check can catch this.
    let tampered_entities = b"{\"entity_type\":\"list\",\"entity_id\":\"list-tamper\",\"version\":\"tamper-v1\",\"created_at\":\"2026-03-29T00:00:00Z\",\"updated_at\":\"2026-03-29T00:00:00Z\",\"payload\":{\"id\":\"list-tamper\",\"name\":\"POISONED\",\"created_at\":\"2026-03-29T00:00:00Z\",\"updated_at\":\"2026-03-29T00:00:00Z\"}}\n".to_vec();
    contents.insert("entities.jsonl".to_string(), tampered_entities);

    let tampered_path = dir.path().join("tampered.zip");
    let tampered_file = std::fs::File::create(&tampered_path).unwrap();
    let mut writer = ZipWriter::new(tampered_file);
    let options = SimpleFileOptions::default();
    for (name, body) in &contents {
        writer.start_file(name.clone(), options).unwrap();
        writer.write_all(body).unwrap();
    }
    writer.finish().unwrap();

    let target = open_db_in_memory().unwrap();
    let err = import_from_zip(&target, &tampered_path)
        .expect_err("tampered entities.jsonl must abort import");
    let msg = err.to_string();
    assert!(
        msg.contains("digest mismatch") || msg.contains("size mismatch"),
        "expected digest/size mismatch error, got: {msg}"
    );
    // Target DB must remain unchanged — the tampered payload must
    // never have been applied.
    let poisoned: i64 = target
        .query_row(
            "SELECT COUNT(*) FROM lists WHERE id = 'list-tamper'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        poisoned, 0,
        "tampered payload must not land in the target DB"
    );
}

#[test]
fn import_rejects_current_archive_without_file_digests_before_applying_rows() {
    let source = open_db_in_memory().unwrap();
    source
        .execute(
            "INSERT INTO lists (id, name, version, created_at, updated_at) \
                 VALUES ('list-no-digest', 'Clean Source', '1711234567890_0001_deadbeefdeadbeef', \
                 '2026-03-29T00:00:00Z', '2026-03-29T00:00:00Z')",
            [],
        )
        .unwrap();

    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("clean.zip");
    export_to_zip(&source, &zip_path, "dev-1").unwrap();

    let file = std::fs::File::open(&zip_path).unwrap();
    let mut archive = zip::ZipArchive::new(file).unwrap();
    let mut contents: std::collections::BTreeMap<String, Vec<u8>> =
        std::collections::BTreeMap::new();
    for i in 0..archive.len() {
        let mut entry = archive.by_index(i).unwrap();
        let name = entry.name().to_string();
        let mut buf = Vec::new();
        entry.read_to_end(&mut buf).unwrap();
        contents.insert(name, buf);
    }
    drop(archive);

    let manifest_bytes = contents
        .get("manifest.json")
        .expect("export must write manifest.json");
    let mut manifest: serde_json::Value = serde_json::from_slice(manifest_bytes).unwrap();
    manifest
        .as_object_mut()
        .expect("manifest must be an object")
        .remove("file_digests");
    contents.insert(
        "manifest.json".to_string(),
        serde_json::to_vec_pretty(&manifest).unwrap(),
    );

    let tampered_entities = b"{\"entity_type\":\"list\",\"entity_id\":\"list-no-digest\",\"version\":\"1711234567890_0001_deadbeefdeadbeef\",\"created_at\":\"2026-03-29T00:00:00Z\",\"updated_at\":\"2026-03-29T00:00:00Z\",\"payload\":{\"id\":\"list-no-digest\",\"name\":\"POISONED\",\"created_at\":\"2026-03-29T00:00:00Z\",\"updated_at\":\"2026-03-29T00:00:00Z\"}}\n".to_vec();
    contents.insert("entities.jsonl".to_string(), tampered_entities);

    let tampered_path = dir.path().join("missing-digests.zip");
    let tampered_file = std::fs::File::create(&tampered_path).unwrap();
    let mut writer = ZipWriter::new(tampered_file);
    let options = SimpleFileOptions::default();
    for (name, body) in &contents {
        writer.start_file(name.clone(), options).unwrap();
        writer.write_all(body).unwrap();
    }
    writer.finish().unwrap();

    let target = open_db_in_memory().unwrap();
    let err = import_from_zip(&target, &tampered_path)
        .expect_err("current-format archives without file_digests must be rejected");
    let msg = err.to_string();
    assert!(
        msg.contains("file_digests"),
        "expected missing file_digests error, got: {msg}"
    );
    let poisoned: i64 = target
        .query_row(
            "SELECT COUNT(*) FROM lists WHERE id = 'list-no-digest'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        poisoned, 0,
        "archive rows must not be applied when file_digests is missing"
    );
}

// ── #2368: dry-run preview regression tests ──────────────────────
//
// The dry-run contract is:
//   1. Return counts (both aggregate and per-entity-type) that match
//      what a real commit run would produce.
//   2. Leave the target DB untouched — no rows created, updated, or
//      deleted in any user-facing table.
//   3. Still surface validation_findings for malformed archives so
//      the preview reflects the payload validator (#2376) output.
fn seed_export_for_dry_run() -> (tempfile::TempDir, std::path::PathBuf) {
    let source = open_db_in_memory().unwrap();
    source
            .execute(
                "INSERT INTO lists (id, name, color, created_at, updated_at, version)
                 VALUES ('list-dr', 'DryRun', '#00FF00', '2026-03-01T00:00:00Z', '2026-03-01T00:00:00Z', '1711234567890_0001_deadbeefdeadbeef')",
                [],
            )
            .unwrap();
    source
            .execute(
                "INSERT INTO tasks (id, title, status, list_id, priority, created_at, updated_at, version)
                 VALUES ('task-dr-1', 'Preview me', 'open', 'list-dr', 1, '2026-03-01T00:00:00Z', '2026-03-01T00:00:00Z', '1711234567890_0001_deadbeefdeadbeef')",
                [],
            )
            .unwrap();
    source
            .execute(
                "INSERT INTO tasks (id, title, status, list_id, created_at, updated_at, version)
                 VALUES ('task-dr-2', 'Preview me too', 'open', 'list-dr', '2026-03-01T00:00:00Z', '2026-03-01T00:00:00Z', '1711234567890_0002_deadbeefdeadbeef')",
                [],
            )
            .unwrap();

    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("dry-run.zip");
    export_to_zip(&source, &zip_path, "dev-dry-run").unwrap();
    (dir, zip_path)
}
/// the same numbers the commit path would produce.
#[test]
fn dry_run_returns_counts() {
    let (_dir, zip_path) = seed_export_for_dry_run();

    let target = open_db_in_memory().unwrap();

    let summary =
        import_from_zip_with_options(&target, &zip_path, ImportOptions { dry_run: true }).unwrap();

    assert!(summary.dry_run, "summary.dry_run should be true");
    // Two tasks seeded + at least one list that would be created.
    assert!(
        summary.tasks_to_create >= 2,
        "expected >=2 tasks_to_create, got {}",
        summary.tasks_to_create
    );
    assert!(
        summary.lists_to_create >= 1,
        "expected >=1 lists_to_create, got {}",
        summary.lists_to_create
    );
    assert_eq!(
        summary.entities_created,
        summary.tasks_to_create
            + summary.lists_to_create
            + summary
                .entities_created
                .saturating_sub(summary.tasks_to_create + summary.lists_to_create),
        "per-type breakdown should not exceed aggregate entities_created",
    );
    assert!(
        summary.estimated_size_bytes > 0,
        "estimated_size_bytes should reflect archive size, got {}",
        summary.estimated_size_bytes
    );
    assert_eq!(summary.source_device_id.as_deref(), Some("dev-dry-run"));
}

/// stays at its migration-seeded baseline — no tasks, no user lists.
#[test]
fn dry_run_leaves_db_untouched() {
    let (_dir, zip_path) = seed_export_for_dry_run();
    let target = open_db_in_memory().unwrap();

    // Baseline row counts BEFORE any import call. `open_db_in_memory`
    // may seed fixture rows via migrations
    // so we compare pre vs post rather than assert == 0.
    let baseline_tasks: i64 = target
        .query_row("SELECT COUNT(*) FROM tasks", [], |row| row.get(0))
        .unwrap();
    let baseline_lists: i64 = target
        .query_row("SELECT COUNT(*) FROM lists", [], |row| row.get(0))
        .unwrap();

    let _summary =
        import_from_zip_with_options(&target, &zip_path, ImportOptions { dry_run: true }).unwrap();

    let after_tasks: i64 = target
        .query_row("SELECT COUNT(*) FROM tasks", [], |row| row.get(0))
        .unwrap();
    let after_lists: i64 = target
        .query_row("SELECT COUNT(*) FROM lists", [], |row| row.get(0))
        .unwrap();
    assert_eq!(
        after_tasks, baseline_tasks,
        "dry-run must not create task rows"
    );
    assert_eq!(
        after_lists, baseline_lists,
        "dry-run must not create list rows"
    );

    // Sanity check: a subsequent commit-mode import on the same
    // target DOES add rows. Confirms the dry-run rollback didn't
    // poison the connection for later writes.
    let summary = import_from_zip(&target, &zip_path).unwrap();
    assert!(!summary.dry_run);
    let committed_tasks: i64 = target
        .query_row("SELECT COUNT(*) FROM tasks", [], |row| row.get(0))
        .unwrap();
    assert!(
        committed_tasks > baseline_tasks,
        "commit-mode import after dry-run must still add rows"
    );
}
/// the preview must bubble them up without touching the DB.
#[test]
fn dry_run_surfaces_validation_findings() {
    // A scoped manifest with `scope_categories: []` is invalid —
    // `preflight_validate_scoped_import` rejects it with an
    // `empty_scoped_categories` ERROR finding. Good regression
    // target because no entity work is needed to trigger it.
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("bad-scope.zip");

    write_import_zip_with_manifest(
        &zip_path,
        serde_json::json!({
            "format_version": EXPORT_FORMAT_VERSION,
            "schema_version": 1,
            "payload_schema_version": 1,
            "created_at": "2026-03-29T00:00:00Z",
            "device_id": "dev-validation-test",
            "scope_kind": "scoped",
            "scope_categories": [],
            "dependency_mode": "closure",
        }),
        &[],
        &[],
        &[],
        &[],
        &[],
    );

    let target = open_db_in_memory().unwrap();
    let summary =
        import_from_zip_with_options(&target, &zip_path, ImportOptions { dry_run: true }).unwrap();

    assert!(summary.dry_run);
    assert!(
        summary
            .validation_findings
            .iter()
            .any(|finding| finding.code == "empty_scoped_categories"
                && finding.severity == crate::export_scope::ImportValidationSeverity::Error),
        "expected empty_scoped_categories error finding, got: {:?}",
        summary.validation_findings
    );
    // Manifest provenance still round-trips even on early-exit
    // (error) findings — the preview UI needs them.
    assert_eq!(
        summary.source_device_id.as_deref(),
        Some("dev-validation-test")
    );
    assert_eq!(summary.schema_version, Some(1));
}
