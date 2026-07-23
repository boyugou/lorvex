//! One-click diagnostic bundle export (#2183).
//!
//! Produces a single ZIP archive that collects the signals a maintainer
//! needs to triage a bug report — `error_logs`, the last 30 days of
//! `ai_changelog`, the local `sync_conflict_log`, and a small
//! `system_info.json` header — without the user having to visit five
//! panels and stitch fragments together by hand.
//!
//! ## Redaction + PII scope
//!
//! - `error_logs.message` / `.details` are already passed through
//!   `lorvex_domain::diagnostics::redact_diagnostic_text` at write time
//!   (see `error_logs.rs`), so the rows read back here are safe by
//!   construction.
//! - `ai_changelog.summary` is re-run through the redactor here because
//!   historical rows predate the redact-at-write contract and fresh
//!   summaries can still interpolate absolute paths or task titles
//!   that mention secrets.
//! - We deliberately do NOT include task bodies, checklist items,
//!   `ai_notes`, or any other user-authored content. This bundle is for
//!   diagnostics, not for backup.
//!
//! ## Archive layout
//!
//! ```text
//!   error_logs.jsonl           last 30 days, newest-first, one JSON obj/line
//!   ai_changelog_recent.jsonl  last 30 days, newest-first
//!   sync_conflict_log.jsonl    up to 1_000 most recent rows
//!   system_info.json           app + schema versions, OS/arch, runtime paths
//!   README.txt                 human-readable index + redaction policy
//! ```
//!
//! The caller supplies the destination path; the frontend routes that
//! path through a user-gated native file-save dialog so no diagnostic
//! bundle is ever written without an explicit user action.
//!
//! #3303 P2 split — the previous 551-LOC `bundle.rs` mixed four
//! concerns into one file (path validation, DB row collection,
//! ZIP emission, the public IPC orchestrator). Each concern now
//! lives in its own sibling:
//!
//!   * `path` — `normalize_zip_path` + the two-pass symlink /
//!     extension-append validation.
//!   * `readers` — `build_system_info`, `read_recent_error_logs`,
//!     `read_recent_changelog`, `read_conflict_log`, plus the
//!     private `SystemInfo` / `RuntimePaths` / `ChangelogBundleRow` types.
//!   * `archive` — `write_bundle_zip` Deflate emitter +
//!     `rows_to_jsonl` newline-delimited serializer.
//!   * `tests` — the existing `#[cfg(test)]` regression.

use serde::{Deserialize, Serialize};

use crate::db::get_read_conn;
use crate::error::{AppError, AppResult};

mod archive;
mod path;
mod readers;

#[cfg(test)]
mod tests;

/// Retention window applied to both `error_logs` and `ai_changelog`.
/// Matches the default changelog retention so the bundle never exceeds
/// what the retention cron would keep anyway, and keeps the ZIP small
/// enough to attach to a GitHub issue.
const BUNDLE_RETENTION_DAYS: i64 = 30;

/// Hard cap on the conflict-log rows bundled. `sync_conflict_log` has a
/// fixed 30-day retention in the sync module, so this is only a belt-
/// and-suspenders bound.
const MAX_CONFLICT_LOG_ROWS: i64 = 1_000;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ExportDiagnosticsBundleResult {
    /// Absolute path the ZIP was written to (same as the caller's
    /// `dest_path` after any `.zip` extension normalization).
    pub path: String,
    /// Row counts for each bundled section so the UI can confirm the
    /// export actually contained something.
    pub error_log_count: usize,
    pub changelog_count: usize,
    pub conflict_log_count: usize,
}

/// Tauri IPC entry point.
///
/// `dest_path` must be a user-selected absolute path returned by the
/// native file-save dialog (see `DiagnosticsPanel.tsx`). A `.zip`
/// extension is appended if missing so the OS recognizes the archive.
#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn export_diagnostics_bundle(
    dest_path: String,
) -> Result<ExportDiagnosticsBundleResult, String> {
    let conn = get_read_conn()?;
    export_diagnostics_bundle_with_conn(&conn, &dest_path).map_err(String::from)
}

/// Assemble and write the diagnostic bundle. Kept as a testable
/// function that takes a [`rusqlite::Connection`] so it can be
/// exercised without the global pool / Tauri runtime.
pub(crate) fn export_diagnostics_bundle_with_conn(
    conn: &rusqlite::Connection,
    dest_path: &str,
) -> AppResult<ExportDiagnosticsBundleResult> {
    let normalized = path::normalize_zip_path(dest_path)?;

    let error_logs = readers::read_recent_error_logs(conn)?;
    let changelog = readers::read_recent_changelog(conn)?;
    let conflict_log = readers::read_conflict_log(conn)?;
    let system_info = readers::build_system_info(conn)?;

    let system_info_json = serde_json::to_string_pretty(&system_info).map_err(AppError::from)?;
    let error_logs_jsonl = archive::rows_to_jsonl(&error_logs)?;
    let changelog_jsonl = archive::rows_to_jsonl(&changelog)?;
    let conflict_log_jsonl = archive::rows_to_jsonl(&conflict_log)?;

    archive::write_bundle_zip(
        &normalized,
        &system_info_json,
        &error_logs_jsonl,
        &changelog_jsonl,
        &conflict_log_jsonl,
    )?;

    Ok(ExportDiagnosticsBundleResult {
        path: normalized.to_string_lossy().to_string(),
        error_log_count: error_logs.len(),
        changelog_count: changelog.len(),
        conflict_log_count: conflict_log.len(),
    })
}
