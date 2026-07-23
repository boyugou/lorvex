//! Settings/Diagnostics surface that aggregates every sync-related
//! invariant into a single [`SyncStatusSnapshot`].
//!
//! The orchestration lives in [`snapshot`]; per-concern helpers are
//! split into:
//!   - [`apply_cycle`] — default apply-cycle projection; the backing table was removed
//!   - [`loaders`] — `sync_checkpoints` and `preferences` row reads
//!   - [`parsers`] — `(value, malformed, reason)` projection helpers
//!     wrapping `lorvex_domain::parsing::*`
//!
//! `pub` re-exports below pin the canonical `lorvex_store::sync_status::*`
//! surface that downstream crates and the `tests` module consume.

mod apply_cycle;
mod loaders;
mod parsers;
mod snapshot;

#[cfg(test)]
mod tests;

pub const SYNC_CHECKPOINT_DEVICE_ID_KEY: &str = "device_id";
pub const SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LAST_PULL_CURSOR_KEY: &str =
    "filesystem_bridge_last_pull_cursor";
pub const SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LOOKBACK_KNOWN_ID_SKIPPED_LAST_RUN_KEY: &str =
    "filesystem_bridge_lookback_known_id_skipped_last_run";
pub const SYNC_CHECKPOINT_FILESYSTEM_BRIDGE_LOOKBACK_KNOWN_ID_SKIPPED_LAST_RUN_AT_KEY: &str =
    "filesystem_bridge_lookback_known_id_skipped_last_run_at";

pub use snapshot::{load_sync_status_snapshot, SyncStatusSnapshot};
