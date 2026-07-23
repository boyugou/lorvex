//! Durable pending inbox — holds envelopes that cannot be applied immediately.
//!
//! Two deferral reasons are active:
//! - `SchemaTooNew`: payload_schema_version is >1 ahead of local
//! - `MissingDependency`: a required FK target (parent entity, tag, etc.)
//!   doesn't exist locally yet — the apply pipeline preflight checks FK
//!   targets before INSERT and defers with typed `missing_entity_type`/`id`
//!
//! Pending entries are re-attempted after each successful batch apply.

mod diagnostics;
mod drain;
mod enqueue;
mod quarantine;
mod remap;
mod store;
mod types;

pub use drain::drain_pending_inbox;
pub use enqueue::{enqueue_deferred, enqueue_pending};
pub use store::{
    count_pending, gc_expired_entries, get_all_pending, has_expired_entries,
    has_pending_for_target, record_reattempt, record_reattempt_busy, record_reattempt_with_error,
    remove_pending,
};
pub use types::{PendingDrainSummary, PendingInboxEntry};

#[cfg(test)]
use crate::apply::{ApplyError, DeferralReason};
#[cfg(test)]
use crate::envelope::SyncEnvelope;
#[cfg(test)]
use drain::is_transient_busy_or_locked;
#[cfg(test)]
use quarantine::{is_quarantined, record_quarantine};
#[cfg(test)]
use store::MAX_PENDING_INBOX_ATTEMPTS;

#[cfg(test)]
mod tests;
