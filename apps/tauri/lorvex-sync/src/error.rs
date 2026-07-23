//! Typed error enum for the `lorvex-sync` crate.
//!
//! Internal sync functions return `Result<T, SyncError>` instead of
//! `Result<T, rusqlite::Error>`. Boundary layers convert to `String`
//! via `Display` at the protocol edge.

use thiserror::Error;

/// Canonical error type for `lorvex-sync` operations.
#[derive(Debug, Error)]
pub enum SyncError {
    /// An error propagated from the store layer.
    #[error(transparent)]
    Store(#[from] lorvex_store::StoreError),

    /// A `rusqlite` error propagated from the database layer.
    #[error("database error: {0}")]
    Sql(#[from] rusqlite::Error),

    /// An error related to sync envelope processing — wraps any
    /// envelope-shape failure that isn't categorized JSON (use
    /// `SerializationCategorized` for serde_json failures so the
    /// parse-class discriminant survives) and isn't a SQL/store
    /// boundary error.
    #[error("envelope error: {0}")]
    Envelope(String),

    /// an in-flight sync cycle detected that the upstream
    /// connection has dropped (via the reactive connectivity probe)
    /// and aborted early rather than riding out the full per-request
    /// timeout. Distinct from `OperationFailure`-style timeouts so the
    /// runtime can surface "network lost" to the user and credit the
    /// outbox row with a retryable-but-non-burning failure class.
    #[error("network dropped mid-sync: {message}")]
    NetworkDropped { message: String },

    /// A serde_json failure with the parse / IO / EOF / data
    /// category preserved. The variant carries the `Category`
    /// discriminant alongside the message string so the apply /
    /// drain / outbox surfaces can route the failure without
    /// re-parsing flattened text — e.g. distinguishing "EOF mid-
    /// stream" (retryable transport truncation) from "syntax"
    /// (permanently corrupt envelope, no point retrying).
    ///
    /// the legacy free-form
    /// `Serialization(String)` variant is gone. Every site that
    /// constructed it either (a) routes through `From<serde_json::Error>`
    /// to land here, or (b) was an envelope-shape problem that now
    /// uses the `Envelope` variant.
    #[error("serialization error ({category:?}): {message}")]
    SerializationCategorized {
        category: SerdeJsonCategory,
        message: String,
    },
}

/// typed mirror of [`serde_json::error::Category`]
/// that crosses the lorvex-sync API boundary without leaking the
/// `serde_json` type. Preserves the structured discriminant so
/// callers can branch on parse-failure semantics (transport
/// truncation vs permanent corruption vs other) without reparsing
/// the flattened error string.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SerdeJsonCategory {
    /// Inputs not encoded as valid JSON — almost always a permanent
    /// corruption / wrong-format bug; retrying the same bytes will
    /// fail again.
    Syntax,
    /// Encoded JSON parsed but failed semantic validation against
    /// the target Rust shape (missing field, wrong type). Same
    /// "permanent" semantics as Syntax for our purposes.
    Data,
    /// Unexpected EOF — typically a truncated transport read; the
    /// transport layer should retry rather than burn budget.
    Eof,
    /// Underlying I/O error from the reader. Transport-level retry.
    Io,
}

impl From<serde_json::error::Category> for SerdeJsonCategory {
    fn from(c: serde_json::error::Category) -> Self {
        match c {
            serde_json::error::Category::Syntax => Self::Syntax,
            serde_json::error::Category::Data => Self::Data,
            serde_json::error::Category::Eof => Self::Eof,
            serde_json::error::Category::Io => Self::Io,
        }
    }
}

impl From<serde_json::Error> for SyncError {
    fn from(e: serde_json::Error) -> Self {
        Self::SerializationCategorized {
            category: e.classify().into(),
            message: e.to_string(),
        }
    }
}

impl From<String> for SyncError {
    fn from(message: String) -> Self {
        Self::Store(lorvex_store::StoreError::Invariant(message))
    }
}

/// `PayloadError` is the slim error type returned by the
/// [`lorvex_sync_payload`] CRUD helpers (#4350). Route it through
/// `lorvex_store::StoreError::from` so the disk-full reclassifier sees
/// any `Sql` variant before it lands inside `SyncError::Store`.
impl From<lorvex_sync_payload::PayloadError> for SyncError {
    fn from(error: lorvex_sync_payload::PayloadError) -> Self {
        Self::Store(lorvex_store::StoreError::from(error))
    }
}
