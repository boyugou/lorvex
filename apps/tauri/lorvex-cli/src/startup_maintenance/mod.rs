use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

use rusqlite::Connection;

use crate::error::CliError;

static STARTUP_MAINTENANCE_PATHS: OnceLock<Mutex<HashSet<PathBuf>>> = OnceLock::new();

/// CLI's canonical DB-open entry point: wraps `lorvex_store::open_db_at_path`
/// with the once-per-process startup maintenance pass (pending queue
/// retention sweep, sync warnings) and the persistent diagnostic
/// drain. Every CLI command goes through this; tests that need the
/// raw `lorvex_store::open_db_at_path` (no maintenance) reach for the
/// fully-qualified name in `lorvex_store` directly.
pub(crate) fn open_db_at_path(path: &Path) -> Result<Connection, CliError> {
    let conn = lorvex_store::open_db_at_path(path)?;
    lorvex_store::persist_pending_db_location_diagnostics(&conn);
    run_cli_startup_maintenance_once(&conn, path);
    Ok(conn)
}

fn run_cli_startup_maintenance_once(conn: &Connection, db_path: &Path) {
    if startup_maintenance_completed(db_path) {
        return;
    }

    let mut succeeded = true;
    match lorvex_sync::startup_maintenance::run_startup_sync_maintenance(conn) {
        Ok(report) => {
            persist_cli_startup_sync_warnings(conn, &report.warnings);
            if let Some(err) = report.pending_queue_retention_error {
                succeeded = false;
                record_startup_warning(
                    conn,
                    "cli.startup.pending_queue_retention_failed",
                    "CLI pending queue retention failed",
                    &err,
                );
            }
        }
        Err(err) => {
            succeeded = false;
            record_startup_warning(
                conn,
                "cli.startup.sync_maintenance_failed",
                "CLI sync startup maintenance failed",
                &err.to_string(),
            );
        }
    }
    if let Err(err) = lorvex_store::run_startup_preferences_integrity(conn) {
        succeeded = false;
        record_startup_warning(
            conn,
            "cli.startup.preferences_integrity_failed",
            "CLI preferences startup integrity pass failed",
            &err.to_string(),
        );
    }
    match lorvex_sync::startup_trash_purge::run_startup_trash_purge(
        conn,
        lorvex_sync::startup_trash_purge::TRASH_RETENTION_DAYS,
        |conn| {
            crate::hlc_guard::next_hlc_version(conn).map_err(|err| {
                lorvex_sync::error::SyncError::Envelope(format!(
                    "CLI HLC generation failed during trash purge: {err}"
                ))
            })
        },
    ) {
        Ok(report) if report.deleted > 0 => {
            record_startup_info(
                conn,
                "cli.startup.trash_purge_deleted",
                "CLI startup trash purge hard-deleted expired tasks",
                &format!("deleted={}", report.deleted),
            );
        }
        Ok(_) => {}
        Err(err) => {
            succeeded = false;
            record_startup_warning(
                conn,
                "cli.startup.trash_purge_failed",
                "CLI startup trash purge failed",
                &err.to_string(),
            );
        }
    }
    if succeeded {
        mark_startup_maintenance_completed(db_path);
    }
}

fn persist_cli_startup_sync_warnings(
    conn: &Connection,
    warnings: &[lorvex_sync::startup_maintenance::StartupMaintenanceWarning],
) {
    for warning in warnings {
        if warning.source == "sync.startup.pending_queue_retention_failed" {
            continue;
        }
        lorvex_store::error_log::append_error_log_best_effort(
            conn,
            warning.source,
            &warning.message,
            warning.details.as_deref(),
            Some(warning.level),
        );
    }
}

/// Best-effort periodic retention sweep entry point for long-running CLI
/// surfaces (`lorvex tui-watch`). Gated on
/// [`lorvex_sync::retention_sweep::should_run_retention_sweep`] so a
/// session that respawns inside the 6-hour interval is a no-op. Failures
/// are logged to `error_logs` and never propagated — the watch loop
/// must not abort because a maintenance pass tripped.
pub(crate) fn run_retention_sweep_if_due(conn: &Connection) {
    match lorvex_sync::retention_sweep::should_run_retention_sweep(conn) {
        Ok(true) => match lorvex_sync::retention_sweep::run_periodic_retention_sweep(conn) {
            Ok(outcome) => {
                if let Err(err) =
                    lorvex_sync::retention_sweep::record_retention_sweep_completed(conn)
                {
                    record_startup_warning(
                        conn,
                        "cli.startup.retention_sweep_watermark_failed",
                        "CLI retention sweep watermark stamp failed",
                        &err.to_string(),
                    );
                }
                if outcome.changelog_deleted
                    + outcome.error_logs_deleted
                    + outcome.memory_revisions_deleted
                    > 0
                {
                    record_startup_info(
                        conn,
                        "cli.startup.retention_sweep_reaped",
                        "CLI retention sweep reaped rows",
                        &format!(
                            "changelog={} error_logs={} memory_revisions={}",
                            outcome.changelog_deleted,
                            outcome.error_logs_deleted,
                            outcome.memory_revisions_deleted,
                        ),
                    );
                }
            }
            Err(err) => {
                record_startup_warning(
                    conn,
                    "cli.startup.retention_sweep_failed",
                    "CLI retention sweep failed",
                    &err.to_string(),
                );
            }
        },
        Ok(false) => {}
        Err(err) => {
            record_startup_warning(
                conn,
                "cli.startup.retention_sweep_watermark_check_failed",
                "CLI retention sweep watermark check failed",
                &err.to_string(),
            );
        }
    }
}

fn record_startup_warning(conn: &Connection, source: &str, message: &str, details: &str) {
    record_startup_diagnostic(conn, source, message, details, "warn");
}

fn record_startup_info(conn: &Connection, source: &str, message: &str, details: &str) {
    record_startup_diagnostic(conn, source, message, details, "info");
}

fn record_startup_diagnostic(
    conn: &Connection,
    source: &str,
    message: &str,
    details: &str,
    level: &str,
) {
    lorvex_store::error_log::append_error_log_best_effort(
        conn,
        source,
        message,
        Some(details),
        Some(level),
    );
}

fn startup_maintenance_completed(db_path: &Path) -> bool {
    let paths = STARTUP_MAINTENANCE_PATHS.get_or_init(|| Mutex::new(HashSet::new()));
    let paths = paths
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    paths.contains(db_path)
}

fn mark_startup_maintenance_completed(db_path: &Path) {
    let paths = STARTUP_MAINTENANCE_PATHS.get_or_init(|| Mutex::new(HashSet::new()));
    let mut paths = paths
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    paths.insert(db_path.to_path_buf());
}

#[cfg(test)]
mod tests;
