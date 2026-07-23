use crate::db::get_conn;
use crate::event_bus;
use serde::Serialize;
use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};

/// Result returned by the import command.
#[derive(Debug, Serialize)]
pub struct ImportResult {
    pub entities_created: u64,
    pub entities_updated: u64,
    pub entities_skipped: u64,
    pub scope_kind: lorvex_store::ExportScopeKind,
    pub scope_categories: Vec<lorvex_store::ExportCategory>,
    pub dependency_mode: lorvex_store::ExportDependencyMode,
    pub validation_findings: Vec<lorvex_store::ImportValidationFinding>,

    // ── #2368: dry-run preview fields ─────────────────────────────────
    /// True when the caller asked for a dry-run and no DB mutation
    /// occurred. The preview counts below describe what the commit path
    /// *would* do.
    pub dry_run: bool,
    pub tasks_to_create: u64,
    pub tasks_to_update: u64,
    pub tasks_to_skip: u64,
    pub lists_to_create: u64,
    pub habits_to_create: u64,
    pub preferences_to_change: u64,
    pub memory_to_write: u64,
    pub blobs_hash_mismatch: u64,
    pub estimated_size_bytes: u64,
    pub schema_version: Option<u32>,
    pub source_device_id: Option<String>,
    pub export_timestamp: Option<String>,
}

struct SnapshotImportCancellation;

impl lorvex_store::CancellationToken for SnapshotImportCancellation {
    fn is_cancelled(&self) -> bool {
        crate::commands::sync::runtime::is_sync_cancelled_for(
            crate::commands::sync::runtime::SyncKind::SnapshotImport,
        )
    }
}

fn path_has_zip_extension(path: &Path) -> bool {
    path.extension()
        .and_then(|ext| ext.to_str())
        .is_some_and(|ext| ext.eq_ignore_ascii_case("zip"))
}

fn display_path_label(path: &Path, raw_path: &str) -> String {
    path.file_name()
        .and_then(|value| value.to_str())
        .map_or_else(|| raw_path.to_string(), ToString::to_string)
}

/// Read the first four bytes of `file` and decide if they look like a
/// ZIP local-file header. Rewinds the file handle to position 0 on
/// success so the caller can hand the same `File` to the importer.
fn check_zip_signature(file: &mut File, raw_path: &str) -> Result<bool, String> {
    use std::io::Seek;
    let mut header = [0_u8; 4];
    let read = file
        .read(&mut header)
        .map_err(|e| format!("Failed to inspect snapshot archive ({raw_path}): {e}"))?;
    file.seek(std::io::SeekFrom::Start(0))
        .map_err(|e| format!("Failed to rewind snapshot archive ({raw_path}): {e}"))?;
    if read < header.len() {
        return Ok(false);
    }
    Ok(matches!(
        header,
        [0x50, 0x4B, 0x03, 0x04] | [0x50, 0x4B, 0x05, 0x06] | [0x50, 0x4B, 0x07, 0x08]
    ))
}

/// #3053 M5: open the snapshot file ONCE during validation and hand
/// the same `File` handle to the importer. Any content-swap, symlink
/// flip, or rename between the validation pass and the importer's
/// own open() can no longer alter what gets parsed; the kernel
/// already pinned the inode behind our descriptor.
fn validate_snapshot_zip_path(zip_path: &Path, raw_path: &str) -> Result<(File, u64), String> {
    crate::commands::shared::reject_traversing_or_relative_path(zip_path, "Snapshot path")?;
    let display_path = display_path_label(zip_path, raw_path);
    if !path_has_zip_extension(zip_path) {
        return Err("Snapshot import requires a .zip archive".to_string());
    }
    let mut file = match File::open(zip_path) {
        Ok(f) => f,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            return Err(format!("File not found: {display_path}"));
        }
        Err(error) => {
            return Err(format!(
                "Failed to read snapshot archive ({display_path}): {error}"
            ));
        }
    };
    let metadata = file
        .metadata()
        .map_err(|e| format!("Failed to stat snapshot archive ({display_path}): {e}"))?;
    if !metadata.is_file() {
        return Err(format!("Snapshot archive is not a file: {display_path}"));
    }
    if !check_zip_signature(&mut file, &display_path)? {
        return Err("Snapshot import requires a valid ZIP archive".to_string());
    }
    Ok((file, metadata.len()))
}

fn mark_snapshot_import_full_sync_seed_required(
    conn: &rusqlite::Connection,
) -> Result<lorvex_sync::snapshot_import::SnapshotImportFinalizationReport, String> {
    lorvex_sync::snapshot_import::prepare_snapshot_import_reseed(conn).map_err(|error| {
        format!("Snapshot import committed, but marking full sync seed required failed: {error}")
    })
}

fn record_snapshot_import_reseed_cancelled(conn: &rusqlite::Connection) -> Result<(), String> {
    let report = lorvex_sync::snapshot_import::mark_snapshot_import_reseed_required(
        conn,
        "post_import_reseed_cancelled",
    )
    .map_err(|error| {
        format!("Snapshot import committed, but marking sync reseed required failed: {error}")
    })?;

    let _ = crate::commands::diagnostics::append_error_log_internal(
        conn,
        "snapshot_import.post_import_reseed.cancelled",
        "Snapshot import deferred post-import sync reseed",
        Some(format!(
            "full_sync_seeded_cleared={},reseed_required=true",
            report.full_sync_seeded_cleared
        )),
        Some("info".to_string()),
    );

    Ok(())
}

fn record_snapshot_import_reseed_failed(
    conn: &rusqlite::Connection,
    error: impl std::fmt::Display,
) -> Result<(), String> {
    let error = error.to_string();
    let marker_report = lorvex_sync::snapshot_import::mark_snapshot_import_reseed_required(
        conn,
        "post_import_reseed_failed",
    )
    .map_err(|marker_error| {
        format!(
            "Snapshot import committed, but post-import sync reseed failed ({error}) and marking reseed required also failed: {marker_error}"
        )
    })?;

    let _ = crate::commands::diagnostics::append_error_log_internal(
        conn,
        "snapshot_import.post_import_reseed.failed",
        "Snapshot import post-import sync reseed failed",
        Some(format!(
            "error={error},full_sync_seeded_cleared={},reseed_required=true",
            marker_report.full_sync_seeded_cleared
        )),
        Some("warn".to_string()),
    );

    Ok(())
}

fn log_snapshot_import_reseed_failure(conn: &rusqlite::Connection, error: impl std::fmt::Display) {
    let _ = crate::commands::diagnostics::append_error_log_internal(
        conn,
        "snapshot_import.post_import_reseed.failed",
        "Snapshot import post-import sync reseed failed",
        Some(format!("error={error}")),
        Some("warn".to_string()),
    );
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn import_data_snapshot(
    file_path: String,
    #[allow(non_snake_case)] dry_run: Option<bool>,
) -> Result<ImportResult, String> {
    // arm the global cancel signal so a `cancel_sync`
    // mid-run can stop the store import pipeline and, after a commit,
    // still short-circuit the post-import reseed phase.
    let _cancel_guard = crate::commands::sync::runtime::CancelGuard::arm(
        crate::commands::sync::runtime::SyncKind::SnapshotImport,
    );

    let zip_path = PathBuf::from(&file_path);
    let (zip_file, estimated_size_bytes) = validate_snapshot_zip_path(&zip_path, &file_path)?;

    if crate::commands::sync::runtime::is_sync_cancelled_for(
        crate::commands::sync::runtime::SyncKind::SnapshotImport,
    ) {
        return Err("Snapshot import cancelled by user before extraction".to_string());
    }

    let conn = get_conn()?;

    let dry_run = dry_run.unwrap_or(false);
    let summary = lorvex_store::import_from_zip_file_with_options_and_cancellation(
        &conn,
        zip_file,
        estimated_size_bytes,
        lorvex_store::ImportOptions { dry_run },
        &SnapshotImportCancellation,
    )
    .map_err(|e| {
        if matches!(e, lorvex_store::ImportError::Cancelled) {
            "Snapshot import cancelled by user".to_string()
        } else {
            format!("Import failed: {e}")
        }
    })?;

    // #2368: dry-run returns the summary without touching sync state or
    // the habit cache. The commit path below still runs unchanged.
    if !dry_run {
        // `import_from_zip` does not enqueue sync_outbox entries for the
        // restored rows. Clear the first-time seed checkpoint before the
        // post-import seed so the outbox can be rebuilt even on a device
        // that had already synced before the import. If the seed itself
        // fails after the checkpoint is cleared, the next sync cycle can
        // retry the full seed instead of treating the imported snapshot as
        // already propagated.
        //
        // If the user cancelled during the import, the store-level
        // transaction may already have committed and cannot be rolled
        // back from this boundary. Avoid starting a long full-sync
        // seed after an explicit cancel. Persist the full reseed
        // requirement instead of only logging the skipped work: the
        // import transaction already committed, and incremental sync
        // must not proceed as though the restored rows were already
        // propagated.
        let post_import_reseed_error = match mark_snapshot_import_full_sync_seed_required(&conn) {
            Err(err) => Some(err),
            Ok(_) => {
                if crate::commands::sync::runtime::is_sync_cancelled_for(
                    crate::commands::sync::runtime::SyncKind::SnapshotImport,
                ) {
                    record_snapshot_import_reseed_cancelled(&conn).err()
                } else if let Err(err) =
                    crate::commands::sync::runtime::seed_full_sync_internal(&conn)
                {
                    record_snapshot_import_reseed_failed(&conn, err).err()
                } else {
                    None
                }
            }
        };

        // an import can replace any number of habit
        // completions in one shot, so drop the in-memory best-streak
        // cache — the next Habits-view open recomputes.
        crate::commands::habits::queries::clear_best_streak_cache();

        event_bus::emit_data_changed(event_bus::Entity::DataImport);

        if let Some(error) = post_import_reseed_error {
            log_snapshot_import_reseed_failure(&conn, &error);
            return Err(error);
        }
    }

    Ok(ImportResult {
        entities_created: summary.entities_created,
        entities_updated: summary.entities_updated,
        entities_skipped: summary.entities_skipped,
        scope_kind: summary.scope_kind,
        scope_categories: summary.scope_categories,
        dependency_mode: summary.dependency_mode,
        validation_findings: summary.validation_findings,
        dry_run: summary.dry_run,
        tasks_to_create: summary.tasks_to_create,
        tasks_to_update: summary.tasks_to_update,
        tasks_to_skip: summary.tasks_to_skip,
        lists_to_create: summary.lists_to_create,
        habits_to_create: summary.habits_to_create,
        preferences_to_change: summary.preferences_to_change,
        memory_to_write: summary.memory_to_write,
        blobs_hash_mismatch: summary.blobs_hash_mismatch,
        estimated_size_bytes: summary.estimated_size_bytes,
        schema_version: summary.schema_version,
        source_device_id: summary.source_device_id,
        export_timestamp: summary.export_timestamp,
    })
}

#[cfg(test)]
mod tests {
    use super::{
        check_zip_signature, log_snapshot_import_reseed_failure,
        mark_snapshot_import_full_sync_seed_required, path_has_zip_extension,
        record_snapshot_import_reseed_cancelled, record_snapshot_import_reseed_failed,
        validate_snapshot_zip_path,
    };
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
            "lorvex-snapshot-import-test-{stem}-{}{}",
            std::process::id(),
            extension
        ));
        fs::write(&path, bytes).expect("write temp snapshot");
        path
    }

    #[test]
    fn zip_extension_check_is_case_insensitive() {
        assert!(path_has_zip_extension(std::path::Path::new("backup.zip")));
        assert!(path_has_zip_extension(std::path::Path::new("backup.ZIP")));
        assert!(!path_has_zip_extension(std::path::Path::new("backup.txt")));
    }

    #[test]
    fn zip_signature_accepts_standard_headers() {
        let path = write_temp_file("valid.zip", &[0x50, 0x4B, 0x03, 0x04, 0x00]);
        let mut file = std::fs::File::open(&path).expect("open temp zip");
        let result = check_zip_signature(&mut file, path.to_string_lossy().as_ref())
            .expect("signature check");
        fs::remove_file(path).ok();
        assert!(result);
    }

    #[test]
    fn zip_validation_rejects_non_zip_extension() {
        let path = write_temp_file("invalid.txt", &[0x50, 0x4B, 0x03, 0x04, 0x00]);
        let result = validate_snapshot_zip_path(&path, path.to_string_lossy().as_ref());
        fs::remove_file(path).ok();
        assert_eq!(
            result.expect_err("should reject non-zip"),
            "Snapshot import requires a .zip archive"
        );
    }

    #[test]
    fn zip_validation_rejects_invalid_signature() {
        let path = write_temp_file("invalid.zip", b"nope");
        let result = validate_snapshot_zip_path(&path, path.to_string_lossy().as_ref());
        fs::remove_file(path).ok();
        assert_eq!(
            result.expect_err("should reject invalid zip"),
            "Snapshot import requires a valid ZIP archive"
        );
    }

    /// Regression: defense-in-depth rejection of `..` components.
    /// The legitimate frontend flow uses the native file-open dialog
    /// which returns canonicalized absolute paths; any relative or
    /// dot-dot-laden path is a frontend bug (or worse) and must fail
    /// fast.
    #[test]
    fn zip_validation_rejects_parent_dir_components() {
        let traversing = std::path::PathBuf::from("/tmp")
            .join("..")
            .join("..")
            .join("etc")
            .join("secrets.zip");
        let error = validate_snapshot_zip_path(&traversing, traversing.to_string_lossy().as_ref())
            .expect_err("should reject '..' traversal");
        assert!(
            error.contains("'..'"),
            "expected '..' rejection, got: {error}"
        );
    }

    /// Regression: reject relative paths that would resolve against
    /// the process CWD. Relative input is ambiguous and can point
    /// anywhere depending on when the IPC call fires.
    #[test]
    fn zip_validation_rejects_relative_paths() {
        let relative = std::path::PathBuf::from("some/relative/backup.zip");
        let error = validate_snapshot_zip_path(&relative, relative.to_string_lossy().as_ref())
            .expect_err("should reject relative paths");
        assert!(
            error.contains("absolute"),
            "expected absolute-path rejection, got: {error}"
        );
    }

    #[test]
    fn post_import_reseed_cancelled_persists_structured_diagnostic() {
        let conn = crate::test_support::test_conn();
        lorvex_runtime::sync_checkpoint_set(&conn, lorvex_runtime::KEY_FULL_SYNC_SEEDED, "1")
            .expect("seed existing full-sync checkpoint");

        record_snapshot_import_reseed_cancelled(&conn).expect("record cancelled reseed");

        let full_seeded =
            lorvex_runtime::sync_checkpoint_get(&conn, lorvex_runtime::KEY_FULL_SYNC_SEEDED)
                .expect("read full-sync seeded marker");
        assert_eq!(full_seeded, None);

        let remote_reseed =
            lorvex_runtime::sync_checkpoint_get(&conn, lorvex_runtime::KEY_RESEED_REQUIRED)
                .expect("read remote reseed marker");
        assert_eq!(remote_reseed.as_deref(), Some("true"));

        let conflict: (String, String, String) = conn
            .query_row(
                "SELECT entity_type, entity_id, resolution_type
                 FROM sync_conflict_log
                 WHERE entity_type = 'snapshot_import'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .expect("read durable reseed-required marker");
        assert_eq!(conflict.0, "snapshot_import");
        assert_eq!(conflict.1, "post_import_reseed_cancelled");
        assert_eq!(
            conflict.2,
            lorvex_domain::naming::RESOLUTION_RESEED_REQUIRED
        );

        let row: (String, String, String, Option<String>) = conn
            .query_row(
                "SELECT source, level, message, details
                 FROM error_logs
                 WHERE source = 'snapshot_import.post_import_reseed.cancelled'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .expect("read cancelled reseed diagnostic");

        assert_eq!(row.0, "snapshot_import.post_import_reseed.cancelled");
        assert_eq!(row.1, "info");
        assert_eq!(row.2, "Snapshot import deferred post-import sync reseed");
        assert_eq!(
            row.3.as_deref(),
            Some("full_sync_seeded_cleared=true,reseed_required=true")
        );
    }

    #[test]
    fn post_import_reseed_preparation_allows_seed_when_already_seeded() {
        let conn = crate::test_support::test_conn();
        lorvex_runtime::sync_checkpoint_set(&conn, lorvex_runtime::KEY_FULL_SYNC_SEEDED, "1")
            .expect("seed existing full-sync checkpoint");

        let cleared =
            mark_snapshot_import_full_sync_seed_required(&conn).expect("mark seed required");

        assert!(cleared.full_sync_seeded_cleared);
        assert_eq!(cleared.local_change_seq, 1);
        assert_eq!(
            lorvex_runtime::read_local_change_seq(&conn).expect("read local_change_seq"),
            1
        );
        assert_eq!(
            lorvex_runtime::sync_checkpoint_get(&conn, lorvex_runtime::KEY_FULL_SYNC_SEEDED)
                .expect("read full-sync seeded checkpoint"),
            None
        );

        crate::commands::sync::runtime::seed_full_sync_internal(&conn)
            .expect("full seed should be allowed after snapshot import clears checkpoint");
        assert_eq!(
            lorvex_runtime::sync_checkpoint_get(&conn, lorvex_runtime::KEY_FULL_SYNC_SEEDED)
                .expect("read reseeded checkpoint")
                .as_deref(),
            Some("1")
        );
    }

    #[test]
    fn post_import_reseed_failure_persists_structured_diagnostic() {
        let conn = crate::test_support::test_conn();

        log_snapshot_import_reseed_failure(&conn, "reseed failed: fixture");

        let row: (String, String, String, String) = conn
            .query_row(
                "SELECT source, level, message, details
                 FROM error_logs
                 WHERE source = 'snapshot_import.post_import_reseed.failed'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .expect("read failed reseed diagnostic");

        assert_eq!(row.0, "snapshot_import.post_import_reseed.failed");
        assert_eq!(row.1, "warn");
        assert_eq!(row.2, "Snapshot import post-import sync reseed failed");
        assert!(row.3.contains("reseed failed: fixture"));
    }

    #[test]
    fn post_import_reseed_failure_marks_durable_reseed_required_without_second_seq_bump() {
        let conn = crate::test_support::test_conn();
        mark_snapshot_import_full_sync_seed_required(&conn).expect("prepare reseed");

        record_snapshot_import_reseed_failed(&conn, "reseed failed: fixture")
            .expect("record failed reseed");

        assert_eq!(
            lorvex_runtime::read_local_change_seq(&conn).expect("read local_change_seq"),
            1
        );
        assert_eq!(
            lorvex_runtime::sync_checkpoint_get(&conn, lorvex_runtime::KEY_RESEED_REQUIRED)
                .expect("read reseed checkpoint")
                .as_deref(),
            Some("true")
        );

        let conflict: (String, String, String) = conn
            .query_row(
                "SELECT entity_type, entity_id, resolution_type
                 FROM sync_conflict_log
                 WHERE entity_type = 'snapshot_import'
                   AND entity_id = 'post_import_reseed_failed'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .expect("read durable failed reseed marker");
        assert_eq!(conflict.0, "snapshot_import");
        assert_eq!(conflict.1, "post_import_reseed_failed");
        assert_eq!(
            conflict.2,
            lorvex_domain::naming::RESOLUTION_RESEED_REQUIRED
        );
    }
}
