use super::super::{ApplyRemoteSyncResult, Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct FilesystemBridgeSyncResult {
    pub filesystem_bridge_root_path: String,
    pub attempted_push: i64,
    pub pushed: i64,
    pub push_write_errors: i64,
    pub pulled_files: i64,
    pub pulled_remote_events: i64,
    pub pull_parse_errors: i64,
    pub lookback_known_id_skipped: i64,
    pub pull_limit_hit: bool,
    pub apply_result: ApplyRemoteSyncResult,
    /// When true, incremental sync was skipped because a full reseed is required.
    pub reseed_paused: bool,
}

pub(super) const fn empty_apply_remote_sync_result() -> ApplyRemoteSyncResult {
    ApplyRemoteSyncResult {
        received: 0,
        processed: 0,
        applied: 0,
        skipped_duplicate: 0,
        skipped_stale: 0,
        skipped_deferred: 0,
        skipped_malformed: 0,
        diagnostics_log_failures: 0,
    }
}

pub(super) struct FilesystemBridgeSyncCounts {
    pub(super) attempted_push: i64,
    pub(super) pushed: i64,
    pub(super) push_write_errors: i64,
    pub(super) pulled_files: i64,
    pub(super) pulled_remote_events: i64,
    pub(super) pull_parse_errors: i64,
    pub(super) lookback_known_id_skipped: i64,
    pub(super) pull_limit_hit: bool,
}

#[allow(clippy::needless_pass_by_value)] // const fn cannot move; struct field absorbs ownership
pub(super) const fn build_filesystem_bridge_sync_result(
    filesystem_bridge_root_path: String,
    counts: FilesystemBridgeSyncCounts,
    apply_result: ApplyRemoteSyncResult,
    reseed_paused: bool,
) -> FilesystemBridgeSyncResult {
    FilesystemBridgeSyncResult {
        filesystem_bridge_root_path,
        attempted_push: counts.attempted_push,
        pushed: counts.pushed,
        push_write_errors: counts.push_write_errors,
        pulled_files: counts.pulled_files,
        pulled_remote_events: counts.pulled_remote_events,
        pull_parse_errors: counts.pull_parse_errors,
        lookback_known_id_skipped: counts.lookback_known_id_skipped,
        pull_limit_hit: counts.pull_limit_hit,
        apply_result,
        reseed_paused,
    }
}

pub(super) const fn filesystem_bridge_sync_skipped_result(
    filesystem_bridge_root_path: String,
) -> FilesystemBridgeSyncResult {
    build_filesystem_bridge_sync_result(
        filesystem_bridge_root_path,
        FilesystemBridgeSyncCounts {
            attempted_push: 0,
            pushed: 0,
            push_write_errors: 0,
            pulled_files: 0,
            pulled_remote_events: 0,
            pull_parse_errors: 0,
            lookback_known_id_skipped: 0,
            pull_limit_hit: false,
        },
        empty_apply_remote_sync_result(),
        false,
    )
}
