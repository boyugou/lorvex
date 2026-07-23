//! Error type for `lorvex-sync-payload`.
//!
//! The payload-shadow / attendee-shadow CRUD helpers run before
//! lorvex-store's disk-full classifier sees the rusqlite error, so
//! this crate carries a slim error enum that the consuming crates
//! ([`lorvex_store`] and [`lorvex_sync`]) convert into their own
//! richer error types at the call boundary. The store-side
//! `From<PayloadError> for StoreError` impl re-classifies disk-full
//! `Sql` variants so the process-wide breaker still trips.

use thiserror::Error;

/// Slim error type for payload-shadow + attendee-shadow operations.
#[derive(Debug, Error)]
pub enum PayloadError {
    /// A `rusqlite` error propagated from the database layer.
    /// Carried unclassified — store-side boundary code re-runs the
    /// disk-full classifier when converting to `StoreError`.
    #[error("database error: {0}")]
    Sql(#[from] rusqlite::Error),

    /// A caller-supplied value failed validation (e.g. payload
    /// exceeds the size cap, or an HLC string failed to parse).
    #[error("validation error: {0}")]
    Validation(String),

    /// An internal invariant was violated (e.g. an unknown
    /// `EntityKind` value was found in a stored row).
    #[error("invariant violation: {0}")]
    Invariant(String),

    /// A serialization or deserialization error.
    #[error("serialization error: {0}")]
    Serialization(String),
}

impl From<serde_json::Error> for PayloadError {
    fn from(e: serde_json::Error) -> Self {
        Self::Serialization(e.to_string())
    }
}
