//! Apply-cycle status.
//!
//! `sync_apply_cycles` is no longer part of the shared schema. Keep the status
//! fields populated with default values so existing UI/IPC shapes remain
//! stable while the database stops depending on the removed table.

use rusqlite::Connection;

use crate::StoreError;

#[derive(Default)]
pub(super) struct ApplyCycleStatus {
    pub(super) count: i64,
    pub(super) last_started_at: Option<String>,
    pub(super) last_completed_at: Option<String>,
    pub(super) last_duration_ms: Option<i64>,
    pub(super) last_received: i64,
    pub(super) last_processed: i64,
    pub(super) last_applied: i64,
    pub(super) last_skipped_duplicate: i64,
    pub(super) last_skipped_stale: i64,
    pub(super) last_skipped_deferred: i64,
    pub(super) last_skipped_malformed: i64,
    pub(super) last_error: Option<String>,
    pub(super) retained_received: i64,
    pub(super) retained_processed: i64,
    pub(super) retained_applied: i64,
    pub(super) retained_skipped_duplicate: i64,
    pub(super) retained_skipped_stale: i64,
    pub(super) retained_skipped_deferred: i64,
    pub(super) retained_skipped_malformed: i64,
}

pub(super) fn load_apply_cycle_status(_conn: &Connection) -> Result<ApplyCycleStatus, StoreError> {
    Ok(ApplyCycleStatus::default())
}
