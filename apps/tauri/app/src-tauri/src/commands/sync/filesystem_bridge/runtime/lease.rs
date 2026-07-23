use super::super::get_conn;
use crate::error::{AppError, AppResult};
use lorvex_runtime::renew_sync_owner_now;

pub(super) const FILESYSTEM_BRIDGE_SYNC_LEASE_NAME: &str = "filesystem_bridge";
pub(super) const SYNC_OWNER_LEASE_TTL_MS: i64 = 30_000;

/// Per-process unique owner_id for desktop-app lease acquisition.
///
/// Routes through [`lorvex_runtime::process_owner_id`] so two app
/// instances racing across an OS update or wake-from-sleep cannot
/// both bind the same static string — a
/// stale `Drop` from process A would otherwise delete a freshly-
/// reacquired row that process B owns.
pub(super) fn desktop_app_sync_owner_id() -> &'static str {
    lorvex_runtime::process_owner_id("desktop_app")
}

pub(super) fn renew_filesystem_bridge_lease_or_abort() -> AppResult<()> {
    let conn = get_conn()?;
    let renewed = renew_sync_owner_now(
        &conn,
        FILESYSTEM_BRIDGE_SYNC_LEASE_NAME,
        desktop_app_sync_owner_id(),
        SYNC_OWNER_LEASE_TTL_MS,
    )
    .map_err(AppError::from)?;
    if !renewed {
        return Err(AppError::Internal(
            "filesystem bridge sync lease lost or expired mid-flight; aborting cycle".to_string(),
        ));
    }
    Ok(())
}
