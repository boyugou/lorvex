//! Typed error enum for the `lorvex-store` crate.
//!
//! Internal crate functions return `Result<T, StoreError>` instead of
//! `Result<T, rusqlite::Error>`. Boundary layers (Tauri commands, MCP
//! handlers) convert to `String` via `Display` at the protocol edge.

use thiserror::Error;

use crate::maintenance::disk_full::{is_disk_full_error, trip_disk_full, DiskFullError};

pub mod log;
pub mod sanitize;

/// Canonical error type for `lorvex-store` operations.
#[derive(Debug, Error)]
pub enum StoreError {
    /// The local disk is full (SQLite `SQLITE_FULL` or `ENOSPC` from the
    /// underlying I/O layer). Carried as a distinct variant so the
    /// Tauri / MCP boundary can surface a typed, actionable error to the
    /// user instead of a generic "database error" string. See
    /// `disk_full.rs` for the classifier and the process-wide circuit
    /// breaker that short-circuits future writes once this fires.
    #[error("local storage is full: {details}")]
    DiskFull { details: String },

    /// A `rusqlite` error propagated from the database layer.
    ///
    /// Note: no `#[from]` here — `From<rusqlite::Error>` is implemented
    /// manually below so the DiskFull classifier
    /// (`StoreError::from_rusqlite`) sits on the only path that
    /// constructs this variant. `#[from]` would generate a conflicting
    /// auto-impl that bypasses the classifier.
    #[error("database error: {0}")]
    Sql(rusqlite::Error),

    /// An I/O error from filesystem-backed storage helpers.
    #[error("io error: {0}")]
    Io(#[from] std::io::Error),

    /// The requested entity was not found.
    #[error("not found: {entity} {id}")]
    NotFound { entity: &'static str, id: String },

    /// A caller-supplied value failed validation.
    #[error("validation error: {0}")]
    Validation(String),

    /// An internal invariant was violated.
    #[error("invariant violation: {0}")]
    Invariant(String),

    /// A serialization or deserialization error (e.g. serde_json).
    #[error("serialization error: {0}")]
    Serialization(String),

    /// A LWW-gated UPDATE matched zero rows even though the entity exists,
    /// because the caller's version stamp lost to an in-flight peer write
    /// or a concurrent local update. Surfaced as a typed variant so the
    /// boundary layers (Tauri / MCP / CLI) can decide whether to re-stamp
    /// HLC and retry, instead of treating the no-op as success.
    #[error(
        "stale version on {entity} {id}: attempted version is not strictly newer than \
         the row's current version. Re-stamp HLC and retry."
    )]
    StaleVersion { entity: &'static str, id: String },
}

impl StoreError {
    /// Classify a `rusqlite::Error` into a `StoreError`, routing
    /// disk-full failures into [`StoreError::DiskFull`] and tripping
    /// the process-wide circuit breaker. Other errors fall through to
    /// [`StoreError::Sql`].
    ///
    /// This is the canonical `From<rusqlite::Error>` path — the impl
    /// below delegates here so every `?` conversion goes through the
    /// classifier exactly once.
    pub fn from_rusqlite(error: rusqlite::Error) -> Self {
        if is_disk_full_error(&error) {
            trip_disk_full();
            return Self::DiskFull {
                details: error.to_string(),
            };
        }
        Self::Sql(error)
    }
}

// Manual `From<rusqlite::Error>` so the classifier above is always the
// single entry point — `#[from]` on the `Sql` variant would bypass it.
impl From<rusqlite::Error> for StoreError {
    fn from(error: rusqlite::Error) -> Self {
        Self::from_rusqlite(error)
    }
}

impl From<DiskFullError> for StoreError {
    fn from(error: DiskFullError) -> Self {
        Self::DiskFull {
            details: error.details,
        }
    }
}

impl From<serde_json::Error> for StoreError {
    fn from(e: serde_json::Error) -> Self {
        Self::Serialization(e.to_string())
    }
}

/// Required by [`crate::transaction::with_immediate_transaction`] /
/// [`crate::transaction::with_savepoint`] so they can synthesize a
/// "transaction cleanup failed: <inner>; rollback failed: <reason>"
/// error string when both `f` and the rollback fail. The free-form
/// shape lands in `StoreError::Invariant` because it is, by
/// definition, an unexpected internal-state failure rather than a
/// caller-validation issue.
impl From<String> for StoreError {
    fn from(message: String) -> Self {
        Self::Invariant(message)
    }
}

/// `lorvex_domain::ValidationError` is the canonical typed carrier
/// for validation failures across every surface. The store boundary
/// mirrors `AppError` / `McpError` so a store-layer caller that
/// produces a typed `ValidationError` can `?`-propagate it straight
/// through. Without this `From` impl, every callsite would have to
/// stringify the error before constructing `StoreError::Validation`,
/// losing the structured discriminant before the boundary layer
/// (Tauri / MCP) could attempt to recover it.
impl From<lorvex_domain::validation::ValidationError> for StoreError {
    fn from(error: lorvex_domain::validation::ValidationError) -> Self {
        Self::Validation(error.to_string())
    }
}

impl From<lorvex_runtime::RuntimeError> for StoreError {
    fn from(error: lorvex_runtime::RuntimeError) -> Self {
        match error {
            lorvex_runtime::RuntimeError::Sqlite(sql_error) => Self::from_rusqlite(sql_error),
            other => Self::Invariant(other.to_string()),
        }
    }
}

/// `PayloadError` is the slim error type returned by
/// [`lorvex_sync_payload`] CRUD helpers. The shadow crate sits
/// below `lorvex-store` in the dep graph (#4350) and therefore can't
/// reach the disk-full classifier itself — its `Sql` variant carries
/// the raw `rusqlite::Error`. Re-route through `from_rusqlite` here
/// so a disk-full failure inside a shadow write still trips the
/// process-wide breaker the same way a direct store-side write would.
impl From<lorvex_sync_payload::PayloadError> for StoreError {
    fn from(error: lorvex_sync_payload::PayloadError) -> Self {
        match error {
            lorvex_sync_payload::PayloadError::Sql(sql_error) => Self::from_rusqlite(sql_error),
            lorvex_sync_payload::PayloadError::Validation(msg) => Self::Validation(msg),
            lorvex_sync_payload::PayloadError::Invariant(msg) => Self::Invariant(msg),
            lorvex_sync_payload::PayloadError::Serialization(msg) => Self::Serialization(msg),
        }
    }
}

#[cfg(test)]
mod tests;
