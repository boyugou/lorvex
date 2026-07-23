//! Subscription sync orchestration.
//!
//! Owns the per-subscription refresh pipeline:
//!
//! 1. Load metadata, briefly releasing the writer lock so the network
//!    fetch never holds it across an HTTP round-trip.
//! 2. Honor server-provided rate-limit cooldowns before
//!    issuing a new request.
//! 3. Fetch the `.ics` body through the surface-supplied
//!    [`FetchBackend`], classifying [`FetchedIcsError`] into
//!    rate-limited / truncated / other failure flows.
//! 4. Parse the body and apply the diff (upserts + diff-deletes +
//!    success mark) inside a single transaction so a crash never
//!    leaves the cache in a half-applied state.
//!
//! The fetch surface is intentionally injected — the workflow crate
//! has no network primitives of its own. The Tauri surface wires
//! `TauriFetchBackend` (which carries the reqwest-based `.ics`
//! fetcher); the CLI wires a `reqwest::blocking` flavour over the
//! same trait; tests inject deterministic in-memory backends so the
//! orchestrator's preservation contracts (cached events survive
//! parse errors and truncation rejections) are exercisable without
//! standing up a real HTTP server.
//!
//! Per-concern sibling layout:
//!
//! - [`types`] — IPC / wire types ([`FetchedIcs`], [`FetchedIcsError`],
//!   [`SubscriptionSyncResult`]), the [`FetchBackend`] trait, and the
//!   `sync.ics.truncated` log-source constant.
//! - [`single`] — per-subscription orchestrator
//!   ([`sync_calendar_subscription`], [`retry_calendar_subscription_now`]):
//!   metadata load, 429 cooldown, fetch, error classification.
//! - [`content`] — parsed-body apply ([`sync_subscription_content`]):
//!   upsert each VEVENT, diff-delete cached events the publisher
//!   dropped, all inside one immediate transaction.
//! - [`truncation_reject`] — truncation-rejection short-circuit
//!   ([`record_ics_truncation_rejection`]).
//! - [`batch`] — batch driver
//!   ([`sync_all_calendar_subscriptions`], [`is_terminal_batch_error`])
//!   that walks every eligible subscription with per-feed graceful
//!   failure.

pub mod batch;
pub mod content;
pub mod single;
pub mod truncation_reject;
pub mod types;

pub use batch::sync_all_calendar_subscriptions;
#[cfg(test)]
pub(crate) use batch::{is_terminal_batch_error, run_batch_loop};
pub use content::sync_subscription_content;
pub use single::{retry_calendar_subscription_now, sync_calendar_subscription};
pub use truncation_reject::record_ics_truncation_rejection;
pub use types::{
    FetchBackend, FetchedIcs, FetchedIcsError, SubscriptionSyncResult, ICS_TRUNCATION_LOG_SOURCE,
};
