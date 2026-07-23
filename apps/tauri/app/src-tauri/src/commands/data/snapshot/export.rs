use crate::commands::shared::reject_traversing_or_relative_path;
use crate::db::get_conn;
use serde::Serialize;
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

/// Result returned by the export command.
#[derive(Debug, Serialize)]
pub struct ExportResult {
    pub export_path: String,
    pub format_version: u32,
    pub scope_kind: lorvex_store::ExportScopeKind,
    pub scope_categories: Vec<lorvex_store::ExportCategory>,
    pub dependency_mode: lorvex_store::ExportDependencyMode,
    pub entity_counts: BTreeMap<String, u64>,
    pub edge_counts: BTreeMap<String, u64>,
}

fn resolve_export_scope(
    scope_categories: Option<Vec<lorvex_store::ExportCategory>>,
) -> lorvex_store::ExportScope {
    match scope_categories {
        Some(categories) if !categories.is_empty() => lorvex_store::ExportScope::scoped(categories),
        _ => lorvex_store::ExportScope::full(),
    }
}

struct SnapshotExportCancellation;

impl lorvex_store::CancellationToken for SnapshotExportCancellation {
    fn is_cancelled(&self) -> bool {
        crate::commands::sync::runtime::is_sync_cancelled_for(
            crate::commands::sync::runtime::SyncKind::SnapshotExport,
        )
    }
}

/// Resolve the exports directory under the data directory. Creates it if needed.
fn resolve_exports_dir() -> Result<PathBuf, String> {
    let db = crate::db::db_path();
    let parent = db
        .parent()
        .ok_or("Cannot resolve exports dir: db_path has no parent")?;
    let exports_dir = parent.join("exports");
    std::fs::create_dir_all(&exports_dir)
        .map_err(|e| format!("Failed to create exports directory: {e}"))?;
    Ok(exports_dir)
}

fn path_has_zip_extension(path: &Path) -> bool {
    path.extension()
        .and_then(|ext| ext.to_str())
        .is_some_and(|ext| ext.eq_ignore_ascii_case("zip"))
}

fn reject_export_zip_symlinks(output: &Path) -> Result<(), String> {
    crate::commands::shared::reject_symlinked_path(output, "Export path")?;
    crate::commands::shared::reject_symlinked_path(
        &output.with_extension("zip.tmp"),
        "Export temp path",
    )
}

fn normalize_export_zip_path(output_path: Option<String>) -> Result<PathBuf, String> {
    let output = if let Some(path) = output_path {
        let trimmed = path.trim();
        if trimmed.is_empty() {
            return Err("Export path cannot be empty".to_string());
        }

        let output = PathBuf::from(trimmed);
        reject_traversing_or_relative_path(&output, "Export path")?;
        let output = if path_has_zip_extension(&output) {
            output
        } else {
            let file_name = output
                .file_name()
                .and_then(|name| name.to_str())
                .ok_or_else(|| "Export path must include a file name".to_string())?;
            output.with_file_name(format!("{file_name}.zip"))
        };
        output
    } else {
        let exports_dir = resolve_exports_dir()?;
        let stamp = chrono::Utc::now().format("%Y%m%dT%H%M%SZ");
        exports_dir.join(format!("lorvex-export-v1-{stamp}.zip"))
    };
    reject_export_zip_symlinks(&output)?;
    Ok(output)
}

#[tauri::command]
pub fn export_data_snapshot(
    output_path: Option<String>,
    scope_categories: Option<Vec<lorvex_store::ExportCategory>>,
) -> Result<ExportResult, String> {
    // arm the global cancel signal so a `cancel_sync`
    // call mid-export is observed both at the IPC boundary and inside
    // the store export pipeline.
    let _cancel_guard = crate::commands::sync::runtime::CancelGuard::arm(
        crate::commands::sync::runtime::SyncKind::SnapshotExport,
    );

    let conn = get_conn()?;

    // Resolve the device ID for the export manifest.
    let device_id = crate::hlc::device_id_result()?.to_string();

    let output = normalize_export_zip_path(output_path)?;
    let scope = resolve_export_scope(scope_categories);

    if crate::commands::sync::runtime::is_sync_cancelled_for(
        crate::commands::sync::runtime::SyncKind::SnapshotExport,
    ) {
        return Err("Snapshot export cancelled by user before write".to_string());
    }

    let manifest = lorvex_store::export_to_zip_scoped_with_cancellation(
        &conn,
        &output,
        &device_id,
        &scope,
        &SnapshotExportCancellation,
    )
    .map_err(|e| {
        // Clean up temp file on failure (store writes to .zip.tmp, renames on success).
        // secondary remove_file failures (e.g. another
        // process holding the tmp open on Windows, the path having
        // vanished due to a concurrent `lorvex` invocation) are not
        // actionable — the original export error is the user-visible
        // signal, and the next successful export reuses the deterministic
        // `.zip.tmp` slot.
        let _ = std::fs::remove_file(output.with_extension("zip.tmp"));
        // route the raw store error through
        // `redact_diagnostic_text` before returning to the IPC
        // boundary. The store layer's `ExportError` `Display` impl
        // routinely embeds the absolute db path / temp
        // file path in its message, and the IPC envelope hands the
        // string verbatim to the renderer (which displays it in a
        // toast and logs it to the renderer console). Without
        // redaction a backup-failed surface would leak the user's
        // home directory to any extension or devtools observer; the
        // redactor masks home paths, bearer tokens, emails, and
        // similar PII at every diagnostic boundary and is the
        // standard for command-result error strings.
        if matches!(e, lorvex_store::ExportError::Cancelled) {
            "Snapshot export cancelled by user".to_string()
        } else {
            lorvex_domain::diagnostics::redact_diagnostic_text(&format!("Export failed: {e}"))
        }
    })?;

    Ok(ExportResult {
        export_path: output.to_string_lossy().to_string(),
        format_version: manifest.format_version,
        scope_kind: manifest.scope_kind,
        scope_categories: manifest.scope_categories,
        dependency_mode: manifest.dependency_mode,
        entity_counts: manifest.entity_counts,
        edge_counts: manifest.edge_counts,
    })
}

#[cfg(test)]
mod tests {
    use super::normalize_export_zip_path;
    use std::path::PathBuf;

    fn abs_tmp(filename: &str) -> PathBuf {
        std::env::temp_dir().join(filename)
    }

    #[test]
    fn custom_export_path_keeps_zip_extension() {
        let expected = abs_tmp("backup.zip");
        let path = normalize_export_zip_path(Some(expected.to_string_lossy().to_string()))
            .expect("normalized path");
        assert_eq!(path, expected);
    }

    #[test]
    fn custom_export_path_appends_zip_extension_when_missing() {
        let source = abs_tmp("backup");
        let path = normalize_export_zip_path(Some(source.to_string_lossy().to_string()))
            .expect("normalized path");
        assert_eq!(path, abs_tmp("backup.zip"));
    }

    #[test]
    fn custom_export_path_preserves_existing_name_and_adds_zip_suffix() {
        let source = abs_tmp("backup.data");
        let path = normalize_export_zip_path(Some(source.to_string_lossy().to_string()))
            .expect("normalized path");
        assert_eq!(path, abs_tmp("backup.data.zip"));
    }

    /// Regression: defense-in-depth rejection of `..` components so
    /// a frontend bug can't accidentally trigger an export into a
    /// directory the user didn't deliberately select via the save
    /// dialog. The native save dialog always returns a canonicalized
    /// absolute path, so this branch is unreachable in the legitimate
    /// flow — it only fires on malformed IPC calls.
    #[test]
    fn normalize_export_zip_path_rejects_parent_dir_components() {
        let input = PathBuf::from("/tmp")
            .join("..")
            .join("..")
            .join("etc")
            .join("backup.zip");
        let error =
            normalize_export_zip_path(Some(input.to_string_lossy().to_string())).unwrap_err();
        assert!(
            error.contains("'..'"),
            "expected '..' rejection, got: {error}"
        );
    }

    /// Regression: reject relative paths that would resolve against
    /// the process's CWD (unpredictable and unsafe).
    #[test]
    fn normalize_export_zip_path_rejects_relative_paths() {
        let error = normalize_export_zip_path(Some("backup.zip".to_string())).unwrap_err();
        assert!(
            error.contains("absolute"),
            "expected absolute-path rejection, got: {error}"
        );
    }

    #[cfg(unix)]
    #[test]
    fn normalize_export_zip_path_rejects_post_append_symlink() {
        let dir = tempfile::tempdir().unwrap();
        let picked = dir.path().join("backup");
        let final_path = dir.path().join("backup.zip");
        let sentinel = dir.path().join("sentinel.txt");
        std::fs::write(&sentinel, b"sentinel").unwrap();
        std::os::unix::fs::symlink(&sentinel, &final_path).unwrap();

        let error =
            normalize_export_zip_path(Some(picked.to_string_lossy().to_string())).unwrap_err();

        assert!(
            error.contains("symbolic link"),
            "expected post-append symlink rejection, got: {error}"
        );
    }

    #[cfg(unix)]
    #[test]
    fn normalize_export_zip_path_rejects_temp_sibling_symlink() {
        let dir = tempfile::tempdir().unwrap();
        let picked = dir.path().join("backup");
        let temp_path = dir.path().join("backup.zip.tmp");
        let sentinel = dir.path().join("sentinel.txt");
        std::fs::write(&sentinel, b"sentinel").unwrap();
        std::os::unix::fs::symlink(&sentinel, &temp_path).unwrap();

        let error =
            normalize_export_zip_path(Some(picked.to_string_lossy().to_string())).unwrap_err();

        assert!(
            error.contains("symbolic link"),
            "expected temp-sibling symlink rejection, got: {error}"
        );
    }
}
