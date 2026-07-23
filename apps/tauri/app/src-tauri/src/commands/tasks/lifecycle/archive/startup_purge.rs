use super::TRASH_RETENTION_DAYS;

/// Called from the Tauri startup-maintenance thread. Logs + swallows
/// any error so a bad trash row never blocks app launch.
pub fn run_startup_trash_purge(conn: &rusqlite::Connection) {
    match lorvex_sync::startup_trash_purge::run_startup_trash_purge(
        conn,
        TRASH_RETENTION_DAYS,
        |_| {
            crate::hlc::generate_version_result().map_err(|err| {
                lorvex_sync::error::SyncError::Envelope(format!(
                    "app HLC generation failed during startup trash purge: {err}"
                ))
            })
        },
    ) {
        Ok(report) if report.deleted > 0 => {
            log_startup_trash_purge_report(conn, &report);
        }
        Ok(_) => {}
        Err(e) => {
            log_startup_trash_purge_failure(conn, e);
        }
    }
}

pub(super) fn log_startup_trash_purge_report(
    conn: &rusqlite::Connection,
    report: &lorvex_sync::startup_trash_purge::StartupTrashPurgeReport,
) {
    let _ = crate::commands::diagnostics::append_error_log_internal(
        conn,
        "maintenance.startup_trash_purge.purged",
        "Startup trash purge hard-deleted expired tasks",
        Some(format!(
            "deleted={}, remaining={}, deleted_ids={:?}",
            report.deleted, report.remaining, report.deleted_ids
        )),
        Some("info".to_string()),
    );
}

pub(super) fn log_startup_trash_purge_failure(
    conn: &rusqlite::Connection,
    error: impl std::fmt::Display,
) {
    let _ = crate::commands::diagnostics::append_error_log_internal(
        conn,
        "maintenance.startup_trash_purge.failed",
        "Startup trash purge failed",
        Some(format!("error={error}")),
        Some("warn".to_string()),
    );
}
