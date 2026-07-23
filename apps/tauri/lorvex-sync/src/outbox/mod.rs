//! Sync outbox operations — enqueue, consume, coalesce, and manage sync events.
//!
//! The `sync_outbox` table is the local staging area for changes that need to be
//! pushed to remote sync transports. Each entry contains a full `SyncEnvelope`
//! plus outbox-specific metadata (synced_at, retry state).

mod coalesce;
mod constants;
mod enqueue;
mod error;
mod gc;
mod mutation;
mod query;
mod retry;
mod types;

pub use coalesce::enqueue_coalesced;
pub use constants::{
    truncate_outbox_last_error, MAX_PENDING_FETCH, MAX_RETRIES, OUTBOX_LAST_ERROR_MAX_BYTES,
    SAME_ERROR_ESCALATION_THRESHOLD,
};
pub use enqueue::enqueue;
pub use error::OutboxError;
pub use gc::gc_synced;
#[cfg(test)]
pub(crate) use mutation::delete_entry;
pub use mutation::{mark_many_synced, mark_synced};
pub use query::{get_pending, retain_still_dispatchable};
pub use retry::{
    mark_permanently_failed, record_many_retries, record_retry,
    reset_retry_counts_for_transport_switch, reset_row_retry_count,
};
pub use types::{OutboxEntry, RecordRetryOutcome};

#[cfg(test)]
mod tests;
