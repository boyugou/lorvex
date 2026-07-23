use super::super::{fs, get_conn, resolve_filesystem_bridge_root_path, MAX_SYNC_EVENTS_LIMIT};
use super::lease::{
    desktop_app_sync_owner_id, FILESYSTEM_BRIDGE_SYNC_LEASE_NAME, SYNC_OWNER_LEASE_TTL_MS,
};
use super::orchestration::run_filesystem_bridge_sync_inner;
use super::result::{filesystem_bridge_sync_skipped_result, FilesystemBridgeSyncResult};
use crate::error::{AppError, AppResult};
use lorvex_runtime::{release_sync_owner, try_acquire_sync_owner_with_guard_now, ReleasePanicHook};

#[tauri::command]
pub fn run_filesystem_bridge_sync(
    filesystem_bridge_root_path: String,
    max_events: Option<i64>,
) -> Result<FilesystemBridgeSyncResult, String> {
    // wrap the raw error string in a SyncErrorKind-tagged
    // JSON envelope so the frontend can surface an actionable toast
    // (Retry / path hint for EACCES) instead of a raw rusqlite / io::Error
    // message.
    //
    // filesystem-bridge Sync Now is the other manual path
    // — open a progress cycle so events emitted from the inner phases
    // land with a stable id the frontend can track.
    let _cycle_guard = crate::event_bus::begin_sync_cycle();
    // arm the process-global cancel signal so the
    // `cancel_sync` IPC can cleanly interrupt this run. The guard
    // resets the flag on drop regardless of how this function exits,
    // so a subsequent run starts with a clean slate.
    let _cancel_guard = crate::commands::sync::runtime::CancelGuard::arm(
        crate::commands::sync::runtime::SyncKind::FilesystemBridge,
    );
    let result = run_filesystem_bridge_sync_command(filesystem_bridge_root_path, max_events);
    crate::event_bus::emit_sync_progress(crate::event_bus::SyncProgressPhase::Idle, 0, 0);
    result.map_err(crate::commands::sync::error_kind::encode_app_error)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
fn run_filesystem_bridge_sync_command(
    filesystem_bridge_root_path: String,
    max_events: Option<i64>,
) -> AppResult<FilesystemBridgeSyncResult> {
    let sync_dir = resolve_filesystem_bridge_root_path(&filesystem_bridge_root_path)?;
    fs::create_dir_all(&sync_dir)
        .map_err(|error| AppError::Internal(format!("failed to create sync dir: {error}")))?;
    let cap = crate::commands::clamp_limit(max_events, 200, 1, MAX_SYNC_EVENTS_LIMIT);

    // acquire the lease and bind the guard in a
    // single statement so a panic between acquire and guard install
    // can no longer pin the lease for the full TTL (30 s here). The
    // runtime crate owns the release pattern; this surface only
    // provides the release closure that opens a fresh connection
    // and calls `release_sync_owner`. The drop intentionally only
    // logs release errors: stamping a rusqlite failure on top of
    // an already-failing path is unhelpful, and the lease
    // auto-expires via TTL anyway.
    //
    // route through the wall-clock-free guard
    // constructor so the runtime owns the timestamp and a transport
    // that woke from sleep with a stale `chrono::Utc::now()` snapshot
    // can't install a lease that's already past its expiry.
    let lease_guard = {
        let conn = get_conn()?;
        try_acquire_sync_owner_with_guard_now(
            &conn,
            FILESYSTEM_BRIDGE_SYNC_LEASE_NAME,
            desktop_app_sync_owner_id(),
            SYNC_OWNER_LEASE_TTL_MS,
            |lease_name, owner_id| match crate::db::get_conn() {
                Ok(conn) => {
                    if let Err(e) = release_sync_owner(&conn, lease_name, owner_id) {
                        record_filesystem_bridge_lease_release_failure(
                            &conn,
                            lease_name,
                            owner_id,
                            &e.to_string(),
                        );
                    }
                }
                Err(e) => {
                    crate::commands::diagnostics::append_error_log_best_effort(
                        "sync.filesystem_bridge.runtime.lease_release_open",
                        "Filesystem bridge lease release could not open database",
                        Some(format!(
                            "lease_name={lease_name}, owner_id={owner_id}, error={e}"
                        )),
                        Some("warn".to_string()),
                    );
                }
            },
            filesystem_bridge_release_panic_hook(),
        )
        .map_err(AppError::from)?
    }; // conn dropped — writer released before sync I/O
    let Some(_lease_guard) = lease_guard else {
        return Ok(filesystem_bridge_sync_skipped_result(
            sync_dir.to_string_lossy().to_string(),
        ));
    };

    run_filesystem_bridge_sync_inner(&sync_dir, cap)
}

fn record_filesystem_bridge_lease_release_failure(
    conn: &rusqlite::Connection,
    lease_name: &str,
    owner_id: &str,
    error: &str,
) {
    let _ = crate::commands::diagnostics::append_error_log_internal(
        conn,
        "sync.filesystem_bridge.runtime.lease_release",
        "Filesystem bridge lease release failed",
        Some(format!(
            "lease_name={lease_name}, owner_id={owner_id}, error={error}"
        )),
        Some("warn".to_string()),
    );
}

fn filesystem_bridge_release_panic_hook() -> ReleasePanicHook {
    std::sync::Arc::new(|lease_name, owner_id, panic_message| {
        crate::commands::diagnostics::append_error_log_best_effort(
            "sync.filesystem_bridge.runtime.lease_release_panic",
            "Filesystem bridge lease release panicked",
            Some(format!(
                "lease_name={lease_name}, owner_id={owner_id}, panic={panic_message}"
            )),
            Some("warn".to_string()),
        );
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn record_filesystem_bridge_lease_release_failure_persists_warn_log() {
        let conn = lorvex_store::open_db_in_memory().expect("open test db");

        record_filesystem_bridge_lease_release_failure(
            &conn,
            FILESYSTEM_BRIDGE_SYNC_LEASE_NAME,
            desktop_app_sync_owner_id(),
            "release failed",
        );

        let row: (String, String, String, String) = conn
            .query_row(
                "SELECT source, level, message, details
                 FROM error_logs
                 WHERE source = 'sync.filesystem_bridge.runtime.lease_release'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .expect("read persisted release diagnostic");

        assert_eq!(row.0, "sync.filesystem_bridge.runtime.lease_release");
        assert_eq!(row.1, "warn");
        assert_eq!(row.2, "Filesystem bridge lease release failed");
        assert!(row.3.contains(FILESYSTEM_BRIDGE_SYNC_LEASE_NAME));
        assert!(row.3.contains(desktop_app_sync_owner_id()));
        assert!(row.3.contains("release failed"));
    }
}
