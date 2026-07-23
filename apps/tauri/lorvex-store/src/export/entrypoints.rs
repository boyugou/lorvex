use std::path::Path;

use rusqlite::Connection;

use super::{archive, ExportError, ExportManifest};
use crate::cancellation::check_export_cancelled;
use crate::export_scope::ExportScope;
use crate::{CancellationToken, NeverCancelled};

/// Export all data to a ZIP file at the given path.
///
/// The `device_id` is recorded in the manifest for provenance.
///
/// Returns the export manifest with entity/edge counts.
pub fn export_to_zip(
    conn: &Connection,
    output_path: &Path,
    device_id: &str,
) -> Result<ExportManifest, ExportError> {
    export_to_zip_with_cancellation(conn, output_path, device_id, &NeverCancelled)
}

/// Export all data to a ZIP file and cooperatively stop if cancelled.
pub fn export_to_zip_with_cancellation(
    conn: &Connection,
    output_path: &Path,
    device_id: &str,
    cancellation: &dyn CancellationToken,
) -> Result<ExportManifest, ExportError> {
    check_export_cancelled(cancellation)?;
    // Begin a read transaction so all SELECTs see a consistent WAL snapshot.
    // Without this, concurrent writes between queries could produce an export
    // where edges reference entities that weren't captured.
    //
    // a deferred BEGIN itself cannot return BUSY, but the
    // first SELECT that upgrades it to a real read snapshot can contend
    // with a concurrent writer that just committed. Wrap in
    // `with_busy_retry` so the open-transaction step participates in the
    // same retry budget as every other write path. The inner SELECTs
    // continue to rely on the connection-level `busy_timeout`.
    crate::busy_retry::with_busy_retry(crate::busy_retry::DEFAULT_RETRY_BUDGET, || {
        conn.execute_batch("BEGIN DEFERRED;")
    })
    .map_err(ExportError::Sql)?;

    // Panic-safety: if the inner body panics (zip writer I/O panic, OOM,
    // future code change that can panic), we MUST release the open read
    // transaction before unwinding — otherwise the connection is left in
    // an open TX that blocks WAL checkpointing and VACUUM until the
    // process restarts. Mirror the `with_immediate_transaction` pattern
    // in `commands/shared/task_rows.rs`.
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        archive::export_to_zip_inner(conn, output_path, device_id, cancellation)
    }));

    // Always end the read transaction (ROLLBACK is fine since we only read).
    // a ROLLBACK failure here is non-actionable — the
    // underlying snapshot will be released either way once the
    // connection is dropped or the next BEGIN supersedes it. The
    // export error (if any) propagated via `result` is the signal a
    // caller can act on; suppressing this Result keeps unwind paths
    // single-source.
    let _ = conn.execute_batch("ROLLBACK;");

    match result {
        Ok(inner) => inner,
        Err(payload) => std::panic::resume_unwind(payload),
    }
}

/// Export data to a ZIP file with an explicit scope.
pub fn export_to_zip_scoped(
    conn: &Connection,
    output_path: &Path,
    device_id: &str,
    scope: &ExportScope,
) -> Result<ExportManifest, ExportError> {
    export_to_zip_scoped_with_cancellation(conn, output_path, device_id, scope, &NeverCancelled)
}

/// Export data to a ZIP file with an explicit scope and cancellation hook.
pub fn export_to_zip_scoped_with_cancellation(
    conn: &Connection,
    output_path: &Path,
    device_id: &str,
    scope: &ExportScope,
    cancellation: &dyn CancellationToken,
) -> Result<ExportManifest, ExportError> {
    check_export_cancelled(cancellation)?;
    // see rationale in `export_to_zip` — the deferred BEGIN
    // goes through `with_busy_retry` so the first-SELECT snapshot
    // upgrade shares the same retry budget as other writers.
    crate::busy_retry::with_busy_retry(crate::busy_retry::DEFAULT_RETRY_BUDGET, || {
        conn.execute_batch("BEGIN DEFERRED;")
    })
    .map_err(ExportError::Sql)?;

    // Same panic-safety contract as `export_to_zip` — see comment there.
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        if scope.is_full() {
            archive::export_to_zip_inner(conn, output_path, device_id, cancellation)
        } else {
            archive::export_to_zip_scoped_inner(conn, output_path, device_id, scope, cancellation)
        }
    }));

    // same ROLLBACK rationale as `export_to_zip` — the
    // read-snapshot release is best-effort; the inner export result
    // carries the actionable error.
    let _ = conn.execute_batch("ROLLBACK;");

    match result {
        Ok(inner) => inner,
        Err(payload) => std::panic::resume_unwind(payload),
    }
}
