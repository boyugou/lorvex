//! Public entry points for the import pipeline.
//!
//! [`import_from_zip`] and [`import_from_zip_with_options`] open a path
//! into a `File` handle and forward to
//! [`super::zip_pipeline::import_from_zip_file_with_options`]. Callers
//! that validate before import should use the `_file_with_options`
//! overload directly so validation and decode share one descriptor.

use std::path::Path;

use rusqlite::Connection;

use super::error::ImportError;
use super::types::{ImportOptions, ImportSummary};
use super::zip_pipeline::import_from_zip_file_with_options_and_cancellation;
use crate::{CancellationToken, NeverCancelled};

/// Import data from a ZIP archive using default options (commit mode).
///
/// Convenience wrapper over [`import_from_zip_with_options`] that
/// preserves the historical commit-everything behavior for callers that
/// don't need the #2368 dry-run preview.
pub fn import_from_zip(conn: &Connection, zip_path: &Path) -> Result<ImportSummary, ImportError> {
    import_from_zip_with_options(conn, zip_path, ImportOptions::default())
}

/// Import data from a ZIP archive with explicit options.
///
/// When `options.dry_run` is true the full parse + validation pipeline
/// runs (manifest integrity, per-file SHA-256 digests, scoped-import
/// purity checks, payload validation per #2376), a preview
/// [`ImportSummary`] is produced, and every SQLite mutation is rolled
/// back before returning. No sync envelopes are emitted — the MCP/Tauri
/// caller is responsible for skipping their post-import sync reseed on
/// dry-run.
///
/// Returns an `ImportSummary` with counts of created/updated/skipped
/// entities.
pub fn import_from_zip_with_options(
    conn: &Connection,
    zip_path: &Path,
    options: ImportOptions,
) -> Result<ImportSummary, ImportError> {
    import_from_zip_with_options_and_cancellation(conn, zip_path, options, &NeverCancelled)
}

/// Import data from a ZIP archive with explicit options and cancellation.
pub fn import_from_zip_with_options_and_cancellation(
    conn: &Connection,
    zip_path: &Path,
    options: ImportOptions,
    cancellation: &dyn CancellationToken,
) -> Result<ImportSummary, ImportError> {
    // #2368: record the archive size on disk for the preview summary.
    // Done before open so a missing file yields the usual IO error.
    let estimated_size_bytes = std::fs::metadata(zip_path).map_or(0, |m| m.len());

    let file = std::fs::File::open(zip_path)?;
    import_from_zip_file_with_options_and_cancellation(
        conn,
        file,
        estimated_size_bytes,
        options,
        cancellation,
    )
}
