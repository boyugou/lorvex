//! Scoped export entry point.
//!
//! Materializes a `ScopedExportDataset` from the connection, then
//! delegates to `write_export_archive` for the actual ZIP writing. The
//! split between collection and writing keeps the writer-side logic
//! testable against any pre-built dataset without touching the DB.

use super::super::dataset::collect_export_dataset;
use super::super::{scope_export_dataset, ExportError, ExportManifest};
use super::archive_writer::write_export_archive;
use crate::export_scope::ExportScope;
use crate::CancellationToken;
use rusqlite::Connection;
use std::path::Path;

pub(in crate::export) fn export_to_zip_scoped_inner(
    conn: &Connection,
    output_path: &Path,
    device_id: &str,
    scope: &ExportScope,
    cancellation: &dyn CancellationToken,
) -> Result<ExportManifest, ExportError> {
    let dataset = collect_export_dataset(conn, cancellation)?;
    let scoped = scope_export_dataset(&dataset, scope)?;
    write_export_archive(output_path, device_id, scope, &scoped, cancellation)
}
