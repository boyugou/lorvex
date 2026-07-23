pub(crate) mod bundle;
pub(crate) mod changelog;
pub(crate) mod error_logs;
pub(crate) mod sync_conflicts;
pub(crate) mod undo_token_cache;

#[allow(unused_imports)]
pub use changelog::get_changelog;
#[cfg(test)]
pub(crate) use changelog::read_ai_changelog_entries;
#[cfg(test)]
pub(crate) use changelog::read_ai_changelog_entries_for_entity;
pub(crate) use changelog::read_changelog_retention_days;
#[cfg(test)]
pub(crate) use changelog::read_retention_days;
#[cfg(test)]
pub(crate) use changelog::run_data_retention_cleanup_with_conn;
pub(crate) use error_logs::{
    append_diagnostic_log_with_conn, append_error_log_best_effort, append_error_log_internal,
    try_append_error_log_best_effort,
};
#[allow(unused_imports)]
pub use error_logs::{append_error_log, clear_error_logs, get_error_logs};
#[cfg(test)]
pub(crate) use error_logs::{read_error_logs, read_unseen_error_log_count};
#[cfg(test)]
pub(crate) use sync_conflicts::{read_diagnostics_device_ids, read_sync_conflict_log};
