//! Thin dispatch wrappers for entity-specific apply handlers.

use rusqlite::Connection;

use super::super::{dispatch, ApplyError, LwwTieBreak};
use crate::envelope::SyncEnvelope;

/// Dispatch to the appropriate entity-specific handler.
///
/// Returns `true` if the mutation was applied, `false` if it was
/// intentionally skipped (e.g., last-list guard).  The caller uses
/// this to decide whether to create a tombstone after a delete.
///
/// `apply_ts` is the once-per-envelope captured wall
/// clock; threaded through to the dispatcher so cascading-children
/// helpers, recurrence/tag merges, and conflict-log inserts all share
/// the same atomic moment of apply.
pub(super) fn apply_entity(
    conn: &Connection,
    envelope: &SyncEnvelope,
    apply_ts: &str,
) -> Result<dispatch::EntityApplyOutcome, ApplyError> {
    apply_entity_with_version_mode(conn, envelope, LwwTieBreak::RejectEqual, apply_ts)
}

/// Dispatch the envelope to its registered handler.
///
/// replaces the previous ~340-line megamatch with a
/// table-driven dispatch (see `dispatch.rs`). Adding a new sync entity
/// type is now a one-line registration in `ENTITY_HANDLERS` rather
/// than wedging another arm into the per-fix-prone megamatch.
///
/// `tie_break: LwwTieBreak` replaces the prior
/// `allow_equal_versions: bool` flag.
pub(crate) fn apply_entity_with_version_mode(
    conn: &Connection,
    envelope: &SyncEnvelope,
    tie_break: LwwTieBreak,
    apply_ts: &str,
) -> Result<dispatch::EntityApplyOutcome, ApplyError> {
    dispatch::dispatch(conn, envelope, tie_break, apply_ts)
}
