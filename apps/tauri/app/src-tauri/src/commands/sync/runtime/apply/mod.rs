use super::*;

mod matching;
mod ordering;
// remote-apply pipeline. #3441 phase-2 collapsed the former
// `apply/remote/` directory into flat siblings prefixed `remote_*`.
// `remote.rs` is the public facade that re-exports the surface used by
// the rest of the crate; the prefixed siblings are private impl detail.
mod remote;
mod remote_core;
mod remote_cursors;
mod remote_diagnostics;
pub(crate) mod remote_events;
mod remote_model;
mod remote_pending;
mod remote_wrappers;
mod sync_checkpoint;

#[cfg(test)]
pub(crate) use matching::incoming_records_match_for_file_idempotency;
pub(crate) use matching::is_supported_incoming_record;
pub(crate) use ordering::{compare_sync_versions, compare_sync_versions_with_outbox_id};
#[cfg(test)]
pub(crate) use ordering::{latest_entity_sync_version, sync_entity_apply_priority};
// `apply_remote_sync_envelopes` (the renderer IPC)
// was removed. The filesystem bridge and future remote transports call
// `apply_remote_sync_records_with_checkpoint_writer` directly.
// The two thin wrappers below — `_internal` and
// `_with_filesystem_bridge_cursor` — exist only for tests.
#[cfg(test)]
pub(crate) use remote::apply_remote_sync_envelopes_internal;
#[cfg(test)]
pub(crate) use remote::apply_remote_sync_envelopes_with_filesystem_bridge_cursor;
pub(crate) use remote::emit_data_changed_for_entity_types;
pub(crate) use remote::{apply_remote_sync_records_with_checkpoint_writer, RemoteApplyMode};
pub(crate) use sync_checkpoint::upsert_sync_checkpoint_timestamp_if_newer;

/// An incoming sync record pairs a transport-level identifier (file stem,
/// outbox row ID, remote record name) with a `SyncEnvelope`.
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct IncomingSyncRecord {
    /// Transport-level identifier (not part of the envelope itself).
    pub id: String,
    /// The sync envelope payload.
    #[serde(flatten)]
    pub envelope: lorvex_sync::envelope::SyncEnvelope,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct ApplyRemoteSyncResult {
    pub received: i64,
    pub processed: i64,
    pub applied: i64,
    pub skipped_duplicate: i64,
    pub skipped_stale: i64,
    pub skipped_deferred: i64,
    pub skipped_malformed: i64,
    /// Per-record `error_logs` writes that themselves failed during the
    /// sync apply pass. Counted separately from `skipped_malformed` so
    /// the user-facing summary in Settings → Sync can disclose that
    /// some malformed-row detail was lost (rather than implying every
    /// failure has a corresponding entry in Settings → Diagnostics).
    /// Counted so a discarded diagnostics-log failure cannot
    /// silently hide that some malformed-row detail was lost.
    #[serde(default)]
    pub diagnostics_log_failures: i64,
}
