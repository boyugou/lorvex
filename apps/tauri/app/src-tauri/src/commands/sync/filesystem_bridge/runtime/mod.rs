mod backoff;
pub(crate) mod command;
mod finalize;
mod lease;
mod naming;
mod orchestration;
mod push;
mod result;

// #3441 phase-2 collapsed `tests/` into flat `tests_*` siblings here
// (sharing `tests_support.rs`) to keep `commands/` depth ≤3.
#[cfg(test)]
mod tests_backoff;
#[cfg(test)]
mod tests_classifier;
#[cfg(test)]
mod tests_finalize;
#[cfg(test)]
mod tests_gc;
#[cfg(test)]
mod tests_heartbeat;
#[cfg(test)]
mod tests_naming;
#[cfg(test)]
mod tests_push;
#[cfg(test)]
mod tests_read_state;
#[cfg(test)]
mod tests_roundtrip;
#[cfg(test)]
mod tests_support;

pub use command::run_filesystem_bridge_sync;
pub use result::FilesystemBridgeSyncResult;

#[cfg(test)]
use super::{collect_remote_filesystem_bridge_envelopes, fs, params, sync_timestamp_now};
#[cfg(test)]
use backoff::{outbox_backoff_seconds, should_skip_outbox_for_backoff};
#[cfg(test)]
use finalize::{gc_stale_sync_files, phase_apply_and_finalize};
#[cfg(test)]
use lorvex_sync::outbox;
#[cfg(test)]
use naming::{filesystem_bridge_file_stem, filesystem_bridge_local_file_prefix};
#[cfg(test)]
use orchestration::{
    ensure_filesystem_bridge_full_sync_seeded_after_pull, phase_read_outbox_and_pull_state,
    record_filesystem_bridge_completion_status, refresh_dispatchable_pending_outbox, usize_to_i64,
};
#[cfg(test)]
use push::{
    classify_existing_sync_file, phase_push_to_filesystem,
    phase_push_to_filesystem_with_cancel_probe, phase_record_push_results,
    ExistingSyncFileClassification, PushPhaseOutcome,
};
#[cfg(test)]
use result::{build_filesystem_bridge_sync_result, FilesystemBridgeSyncCounts};
