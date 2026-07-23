pub(super) use lorvex_store::{export_to_zip, import_from_zip, open_db_in_memory};
pub(super) use std::io::Read as _;
pub(super) use tempfile::tempdir;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Create a temp directory and a ZIP path for a roundtrip test.
pub(super) struct TestDirs {
    pub(super) _dir: tempfile::TempDir,
    pub(super) zip_path: std::path::PathBuf,
}

pub(super) fn setup_dirs() -> TestDirs {
    let dir = tempdir().unwrap();
    let zip_path = dir.path().join("export.zip");
    TestDirs {
        _dir: dir,
        zip_path,
    }
}
