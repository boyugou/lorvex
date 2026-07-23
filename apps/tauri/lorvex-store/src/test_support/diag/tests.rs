use super::*;

#[test]
fn happy_path_returns_connection_and_context() {
    let (conn, ctx) =
        open_test_db_with_diag().expect("in-memory DB opens on a healthy test runner");
    // DB is usable.
    let n: i64 = conn.query_row("SELECT 1", [], |row| row.get(0)).unwrap();
    assert_eq!(n, 1);
    // Context is populated — tmpdir is always a real path, even if
    // the platform-specific free-bytes probe isn't implemented.
    assert!(ctx.tmpdir.is_absolute());
    assert_eq!(ctx.attempted_path, PathBuf::from("<in-memory>"));
}

#[test]
fn on_disk_happy_path_returns_real_file() {
    let (conn, path, ctx) = open_test_db_at_temp_path_with_diag("diag-happy")
        .expect("on-disk DB opens on a healthy runner");
    assert!(path.exists(), "db file should exist at {}", path.display());
    assert!(matches!(ctx.writability, WritabilityProbe::Writable));
    drop(conn);
    // Cleanup is best-effort.
    if let Some(parent) = path.parent() {
        let _ = fs::remove_dir_all(parent);
    }
}

#[test]
fn simulated_permission_failure_surfaces_rich_diagnostic() {
    // Inject an EACCES-equivalent outcome. The on-disk helper
    // should bail out at the writability probe — not at SQLite —
    // and the rendered error should include the path, tmpdir,
    // free-bytes field, and the playbook pointer.
    let _guard = fault::WritabilityGuard::new(WritabilityProbe::Rejected {
        reason: "Permission denied (simulated, errno: Some(13))".to_string(),
    });

    let err = open_test_db_at_temp_path_with_diag("diag-denied")
        .expect_err("forced writability failure must produce Err");

    assert!(
        matches!(err.kind, TestSetupErrorKind::NotWritable(_)),
        "expected NotWritable kind, got {:?}",
        err.kind
    );

    let rendered = format!("{err}");
    assert!(rendered.contains("diag-denied"), "msg: {rendered}");
    assert!(rendered.contains("Permission denied"), "msg: {rendered}");
    assert!(rendered.contains(PLAYBOOK_POINTER), "msg: {rendered}");
}

#[test]
fn simulated_low_disk_propagates_into_context() {
    // Zero free bytes — mimics ENOSPC detection on a crowded runner.
    let _probe_guard = fault::WritabilityGuard::new(WritabilityProbe::Rejected {
        reason: "No space left on device (simulated, errno: Some(28))".to_string(),
    });
    let _free_guard = fault::FreeBytesGuard::new(Some(0));

    let err = open_test_db_at_temp_path_with_diag("diag-enospc")
        .expect_err("forced ENOSPC must produce Err");

    let rendered = format!("{err}");
    assert!(rendered.contains("free_bytes=0"), "msg: {rendered}");
    assert!(
        rendered.contains("No space left on device"),
        "msg: {rendered}"
    );
}

#[test]
fn unique_test_dir_with_diag_happy_path_returns_writable_dir() {
    let (dir, ctx) = unique_test_dir_with_diag("diag-unique-dir").expect("happy-path allocation");
    assert!(dir.exists(), "dir should exist");
    assert!(
        matches!(ctx.writability, WritabilityProbe::Writable),
        "expected Writable, got {}",
        ctx.writability
    );
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn unique_test_dir_with_diag_simulated_permission_surfaces_error() {
    let _guard = fault::WritabilityGuard::new(WritabilityProbe::Rejected {
        reason: "simulated EACCES".to_string(),
    });
    let err = unique_test_dir_with_diag("diag-unique-dir-denied").expect_err("forced failure");
    let rendered = format!("{err}");
    assert!(rendered.contains("simulated EACCES"), "msg: {rendered}");
    assert!(rendered.contains(PLAYBOOK_POINTER), "msg: {rendered}");
}

#[test]
fn error_source_chain_exposes_underlying_io_error() {
    let _guard = fault::WritabilityGuard::new(WritabilityProbe::Rejected {
        reason: "simulated".to_string(),
    });
    let err = open_test_db_at_temp_path_with_diag("diag-source")
        .expect_err("forced failure must produce Err");
    let src = std::error::Error::source(&err);
    assert!(src.is_some(), "TestSetupError must expose a source()");
}
