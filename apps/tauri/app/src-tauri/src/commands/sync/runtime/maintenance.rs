use crate::error::{AppError, AppResult};

pub(crate) fn flag_reseed_required_due_to_pending_horizon_in_transaction(
    conn: &rusqlite::Connection,
) -> AppResult<()> {
    lorvex_sync::startup_maintenance::flag_reseed_required_due_to_pending_horizon_in_transaction(
        conn,
    )
    .map_err(AppError::from)
}

pub(crate) fn gc_expired_pending_queues_best_effort(conn: &rusqlite::Connection) {
    let warnings = lorvex_sync::startup_maintenance::gc_expired_pending_queues_best_effort(conn);
    lorvex_sync::startup_maintenance::persist_startup_maintenance_warnings(conn, &warnings);
}
