use crate::error::{AppError, AppResult};

/// Re-attempt all entries in sync_pending_inbox. Entries that succeed are
/// removed; entries that still fail are updated with attempt count/timestamp.
/// Called after every batch apply (doc 03 req 25).
///
/// Returns the typed drain summary so callers can fan out
/// `data-changed` events for the entity types the drain just
/// unblocked. Without that summary the drain would mutate state
/// silently and the UI would stay on the pre-drain snapshot until
/// the next sync tick or a manual refresh.
pub(crate) fn drain_pending_inbox(
    conn: &rusqlite::Connection,
) -> AppResult<lorvex_sync::pending_inbox::PendingDrainSummary> {
    lorvex_sync::pending_inbox::drain_pending_inbox(conn).map_err(AppError::from)
}
