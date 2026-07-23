//! MCP server startup steps.
//!
//! Each `run_*_step` lifts one inline concern out of
//! `LorvexMcpServer::new()`. The constructor threads several
//! independent maintenance passes (sync, preferences, trash,
//! idempotency, retention) through one block; splitting them
//! makes the per-step error contract (fatal vs. log-only) and the
//! diagnostic source names easier to audit.
//!
//! Step 2 (`get_or_create_sync_device_id`) stays inline in the
//! constructor — it's a single `?`-propagating call with no
//! surrounding logging.

use super::record_diagnostic;
use crate::runtime::change_tracking::generate_hlc_version;
use rusqlite::Connection;

/// Step 1 — sync startup maintenance.
///
/// Failure here is fatal: the constructor returns Err and the MCP
/// server refuses to start. Everything else (warnings, payload shadow
/// promotions, pending queue retention errors) is logged via
/// `error_log` so the diagnostic surface still records it.
pub(super) fn run_sync_startup_maintenance_step(conn: &Connection) -> Result<(), String> {
    let startup_report = match lorvex_sync::startup_maintenance::run_startup_sync_maintenance(conn)
    {
        Ok(report) => report,
        Err(e) => {
            record_startup_warning(
                conn,
                "mcp.startup.sync_maintenance_failed",
                "MCP sync startup maintenance failed",
                &e.to_string(),
            );
            return Err(format!("sync startup maintenance failed: {e}"));
        }
    };
    persist_mcp_startup_sync_warnings(conn, &startup_report.warnings);
    if startup_report.payload_shadows_promoted > 0 {
        record_startup_info(
            conn,
            "mcp.startup.payload_shadows_promoted",
            "MCP startup maintenance promoted payload shadow rows",
            &format!(
                "payload_shadows_promoted={}",
                startup_report.payload_shadows_promoted
            ),
        );
    }
    if let Some(err) = startup_report.pending_queue_retention_error {
        record_startup_warning(
            conn,
            "mcp.startup.pending_queue_retention_failed",
            "MCP pending queue retention failed during startup",
            &err,
        );
    }
    Ok(())
}

/// Step 4 — preferences integrity pass. Log-only.
pub(super) fn run_preferences_integrity_step(conn: &Connection) {
    if let Err(e) = lorvex_store::run_startup_preferences_integrity(conn) {
        record_startup_warning(
            conn,
            "mcp.startup.preferences_integrity_failed",
            "MCP preferences startup integrity pass failed",
            &e.to_string(),
        );
    }
}

/// Step 5 — startup trash purge (hard-delete tasks past TRASH_RETENTION_DAYS).
///
/// Log-only. Uses `generate_hlc_version` to stamp the tombstones
/// emitted by the purge so peers replay the deletion deterministically.
pub(super) fn run_trash_purge_step(conn: &Connection) {
    match lorvex_sync::startup_trash_purge::run_startup_trash_purge(
        conn,
        lorvex_sync::startup_trash_purge::TRASH_RETENTION_DAYS,
        |conn| {
            generate_hlc_version(conn).map_err(|err| {
                lorvex_sync::error::SyncError::Envelope(format!(
                    "MCP HLC generation failed during trash purge: {err}"
                ))
            })
        },
    ) {
        Ok(report) if report.deleted > 0 => {
            record_startup_info(
                conn,
                "mcp.startup.trash_purge_deleted",
                "MCP startup trash purge hard-deleted expired tasks",
                &format!("deleted={}", report.deleted),
            );
        }
        Ok(_) => {}
        Err(e) => {
            record_startup_warning(
                conn,
                "mcp.startup.trash_purge_failed",
                "MCP startup trash purge failed",
                &e.to_string(),
            );
        }
    }
}

/// Step 6 — drop expired MCP idempotency rows. A stdio MCP child
/// process is short-lived enough that a sweep on every boot is
/// sufficient — no background thread needed. Log-only.
pub(super) fn run_idempotency_sweep_step(conn: &Connection) {
    match lorvex_store::mcp_idempotency::sweep_expired(conn) {
        Ok(0) => {}
        Ok(n) => record_startup_info(
            conn,
            "mcp.startup.idempotency_swept",
            "MCP idempotency startup sweep removed expired rows",
            &format!("expired_rows={n}"),
        ),
        Err(e) => {
            record_startup_warning(
                conn,
                "mcp.startup.idempotency_sweep_failed",
                "MCP idempotency startup sweep failed",
                &e.to_string(),
            );
        }
    }
}

/// Step 7 — periodic retention sweep (`ai_changelog`, `error_logs`,
/// `memory_revisions`, sync queues, periodic SQLite maintenance,
/// integrity checks). stranded inside the
/// Tauri renderer's 6-hour cron — headless MCP installs accumulated
/// diagnostic + sync rows forever. The watermark gate
/// (`KEY_LAST_RETENTION_SWEEP_AT`) ensures a long-lived assistant
/// session that reconnects every few minutes does not redo the work.
/// Log-only.
pub(super) fn run_retention_sweep_step(conn: &Connection) {
    match lorvex_sync::retention_sweep::should_run_retention_sweep(conn) {
        Ok(true) => match lorvex_sync::retention_sweep::run_periodic_retention_sweep(conn) {
            Ok(outcome) => {
                if let Err(err) =
                    lorvex_sync::retention_sweep::record_retention_sweep_completed(conn)
                {
                    record_startup_warning(
                        conn,
                        "mcp.startup.retention_sweep_watermark_failed",
                        "MCP retention sweep watermark stamp failed",
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
                        "mcp.startup.retention_sweep_reaped",
                        "MCP retention sweep reaped rows",
                        &format!(
                            "changelog={} error_logs={} memory_revisions={}",
                            outcome.changelog_deleted,
                            outcome.error_logs_deleted,
                            outcome.memory_revisions_deleted,
                        ),
                    );
                }
            }
            Err(e) => {
                record_startup_warning(
                    conn,
                    "mcp.startup.retention_sweep_failed",
                    "MCP retention sweep failed",
                    &e.to_string(),
                );
            }
        },
        Ok(false) => {}
        Err(e) => {
            record_startup_warning(
                conn,
                "mcp.startup.retention_sweep_watermark_check_failed",
                "MCP retention sweep watermark check failed",
                &e.to_string(),
            );
        }
    }
}

pub(super) fn persist_mcp_startup_sync_warnings(
    conn: &Connection,
    warnings: &[lorvex_sync::startup_maintenance::StartupMaintenanceWarning],
) {
    for warning in warnings {
        if warning.source == "sync.startup.pending_queue_retention_failed" {
            continue;
        }
        let source = mcp_startup_sync_warning_source(warning.source);
        lorvex_store::error_log::append_error_log_best_effort(
            conn,
            &source,
            &warning.message,
            warning.details.as_deref(),
            Some(warning.level),
        );
    }
}

fn mcp_startup_sync_warning_source(source: &str) -> String {
    source.strip_prefix("sync.startup.").map_or_else(
        || format!("mcp.startup.sync_{source}"),
        |suffix| format!("mcp.startup.sync_{suffix}"),
    )
}

pub(super) fn record_startup_warning(
    conn: &Connection,
    source: &str,
    message: &str,
    details: &str,
) {
    record_diagnostic(conn, source, message, details, "warn");
}

pub(super) fn record_startup_info(conn: &Connection, source: &str, message: &str, details: &str) {
    record_diagnostic(conn, source, message, details, "info");
}
