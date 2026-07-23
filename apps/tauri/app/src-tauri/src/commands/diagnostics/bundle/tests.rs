use std::io::Read;

use super::export_diagnostics_bundle_with_conn;

#[test]
fn export_diagnostics_bundle_writes_expected_zip_entries() {
    let conn = crate::test_support::test_conn();

    // Seed one of each signal so the bundle has non-empty JSONL
    // entries to assert on.
    super::super::error_logs::append_error_log_internal(
        &conn,
        "frontend.test",
        "seed error",
        Some("stack".to_string()),
        Some("warn".to_string()),
    )
    .expect("seed error log");

    conn.execute(
        "INSERT INTO ai_changelog (id, timestamp, operation, entity_type, entity_id,
                                    summary, initiated_by, mcp_tool, source_device_id)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
        rusqlite::params![
            "test-id",
            // Use "now-ish" so the row falls inside the 30-day
            // retention window regardless of the wall clock.
            crate::commands::sync_timestamp_now(),
            "update",
            "task",
            "task-1",
            "seed changelog",
            "codex",
            "test_tool",
            "device-a",
        ],
    )
    .expect("seed changelog");
    conn.execute(
        "INSERT INTO ai_changelog (id, timestamp, operation, entity_type, entity_id,
                                    summary, initiated_by, mcp_tool, source_device_id)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
        rusqlite::params![
            "human-id",
            crate::commands::sync_timestamp_now(),
            "update",
            "task",
            "task-2",
            "human changelog",
            "human",
            "test_tool",
            "device-human",
        ],
    )
    .expect("seed human changelog");

    // Pick a writable temp destination.
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .expect("clock")
        .as_nanos();
    let dest = std::env::temp_dir().join(format!("lorvex-diag-bundle-test-{nanos}.zip"));

    let result =
        export_diagnostics_bundle_with_conn(&conn, &dest.to_string_lossy()).expect("bundle export");
    assert_eq!(result.path, dest.to_string_lossy());
    assert!(result.error_log_count >= 1, "error log seeded");
    assert!(result.changelog_count >= 1, "changelog seeded");

    // Open the ZIP and verify every expected entry is present.
    let file = std::fs::File::open(&dest).expect("open bundle");
    let mut archive = zip::ZipArchive::new(file).expect("parse zip");
    let names: Vec<String> = (0..archive.len())
        .map(|i| archive.by_index(i).expect("entry").name().to_string())
        .collect();
    for expected in [
        "system_info.json",
        "error_logs.jsonl",
        "ai_changelog_recent.jsonl",
        "sync_conflict_log.jsonl",
        "README.txt",
    ] {
        assert!(
            names.iter().any(|n| n == expected),
            "missing {expected} in {names:?}"
        );
    }

    // system_info.json must deserialize to a JSON object carrying
    // the app version + schema version so maintainers have a
    // baseline for triage.
    let mut sys = archive.by_name("system_info.json").expect("system_info");
    let mut buf = String::new();
    sys.read_to_string(&mut buf).expect("read system_info");
    let parsed: serde_json::Value = serde_json::from_str(&buf).expect("system_info is json");
    assert!(parsed.get("app_version").is_some());
    assert!(parsed.get("schema_version").is_some());
    assert!(parsed.get("os").is_some());
    drop(sys);

    let mut changelog = archive
        .by_name("ai_changelog_recent.jsonl")
        .expect("ai_changelog_recent");
    let mut changelog_buf = String::new();
    changelog
        .read_to_string(&mut changelog_buf)
        .expect("read ai_changelog_recent");
    assert!(
        changelog_buf.contains("\"id\":\"test-id\""),
        "assistant-originated changelog should be exported: {changelog_buf}"
    );
    assert!(
        !changelog_buf.contains("human-id"),
        "human-originated changelog must stay out of diagnostic bundles: {changelog_buf}"
    );
    assert!(
        !changelog_buf.contains("device-human"),
        "human-originated source device must stay out of diagnostic bundles: {changelog_buf}"
    );
    drop(changelog);

    std::fs::remove_file(&dest).ok();
}
