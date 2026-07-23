use super::*;

#[test]
fn incompatible_version_rejected() {
    let source = open_db_in_memory().unwrap();
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("export.zip");
    export_to_zip(&source, &zip_path, "dev-1").unwrap();

    // Tamper with the manifest to have a different format_version.
    let file = std::fs::File::open(&zip_path).unwrap();
    let mut archive = zip::ZipArchive::new(file).unwrap();
    let mut manifest_str = String::new();
    archive
        .by_name("manifest.json")
        .unwrap()
        .read_to_string(&mut manifest_str)
        .unwrap();
    drop(archive);

    let mut manifest: serde_json::Value = serde_json::from_str(&manifest_str).unwrap();
    manifest["format_version"] = serde_json::json!(999);

    // Rewrite the ZIP with the tampered manifest.
    let tampered_path = dir.path().join("tampered.zip");
    let tampered_file = std::fs::File::create(&tampered_path).unwrap();
    let mut writer = ZipWriter::new(tampered_file);
    let options = SimpleFileOptions::default();
    writer.start_file("manifest.json", options).unwrap();
    writer
        .write_all(serde_json::to_string_pretty(&manifest).unwrap().as_bytes())
        .unwrap();
    writer.start_file("entities.jsonl", options).unwrap();
    writer.start_file("edges.jsonl", options).unwrap();
    writer.start_file("children.jsonl", options).unwrap();
    writer.start_file("audit.jsonl", options).unwrap();
    writer.start_file("tombstones.jsonl", options).unwrap();
    writer.finish().unwrap();

    let target = open_db_in_memory().unwrap();
    let result = import_from_zip(&target, &tampered_path);
    assert!(result.is_err());

    let err = result.unwrap_err();
    let msg = err.to_string();
    assert!(
        msg.contains("incompatible"),
        "expected incompatible version error, got: {msg}"
    );
}

#[test]
fn current_manifest_requires_exporter_metadata_fields() {
    let required_fields = [
        "schema_version",
        "payload_schema_version",
        "device_id",
        "created_at",
        "scope_kind",
        "dependency_mode",
    ];

    for missing_field in required_fields {
        let dir = tempdir().unwrap();
        let zip_path = dir.path().join(format!("missing-{missing_field}.zip"));
        let mut manifest = serde_json::json!({
            "format_version": EXPORT_FORMAT_VERSION,
            "schema_version": 1,
            "payload_schema_version": 1,
            "created_at": "2026-03-29T00:00:00Z",
            "device_id": "test-device",
            "scope_kind": "full",
            "scope_categories": [],
            "dependency_mode": "closure",
        });
        manifest
            .as_object_mut()
            .expect("manifest fixture must be an object")
            .remove(missing_field);

        write_import_zip_with_manifest(&zip_path, manifest, &[], &[], &[], &[], &[]);

        let target = open_db_in_memory().unwrap();
        let result = import_from_zip(&target, &zip_path);
        let err = result.unwrap_err();
        let msg = err.to_string();
        assert!(
            msg.contains(missing_field),
            "missing {missing_field} should be named in the error, got: {msg}"
        );
    }
}
