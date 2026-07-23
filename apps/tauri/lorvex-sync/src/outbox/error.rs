//! Typed errors raised by the outbox enqueue surfaces.
//!
//! The original enqueue helpers returned bare `rusqlite::Error`
//! because every failure mode bottomed out in a SQLite call. The
//! outbox boundary now has non-SQL failure classes too: unsupported
//! local operation variants introduced by future code, or a tainted
//! incoming HLC version that the LWW gate has no way to evaluate.
//! The previous fallback for tainted versions
//! (lex-compare against the existing version string) silently flipped
//! against `v1` / `seed` style fixture versions because letters sort
//! above digits, dropping a fresh canonical envelope as "stale".
//!
//! `OutboxError::TaintedVersion` lets the boundary refuse the write
//! cleanly so the caller can re-stamp with a canonical HLC instead of
//! letting an unparseable version drive a coalesce decision.

use std::fmt;

use lorvex_domain::naming::EntityKind;

/// Errors raised by the outbox enqueue surfaces.
#[derive(Debug)]
pub enum OutboxError {
    /// The envelope carries an operation variant that this enqueue
    /// surface does not support.
    UnsupportedOperation {
        entity_type: EntityKind,
        entity_id: String,
    },
    /// The incoming envelope's `version` failed `Hlc::parse`. The
    /// outbox refuses the write at the boundary so the caller can
    /// re-stamp with a canonical HLC. Carries the envelope identity
    /// for diagnostics.
    TaintedVersion {
        entity_type: EntityKind,
        entity_id: String,
        version: String,
    },
    /// The coalesced-enqueue retry loop exhausted its retry budget
    /// against the `(entity_type, entity_id)` UNIQUE-partial-index
    /// race. Surfaces a typed error so the caller can show a
    /// retry-this-write affordance to the user instead of seeing
    /// the underlying SQL constraint violation collapse into a
    /// generic "write failed" toast (#4583 B20).
    ContentionExhausted {
        entity_type: EntityKind,
        entity_id: String,
        attempts: u32,
    },
    /// A `rusqlite` error propagated from the database layer.
    Sql(rusqlite::Error),
    /// An internal-bookkeeping failure that doesn't bottom out in a
    /// `rusqlite` call — e.g. the savepoint helper rejecting an
    /// unsafe prefix, or a future state-machine assertion. Carries
    /// the human-readable message; not exposed to peers and not
    /// retryable.
    Internal(String),
}

impl fmt::Display for OutboxError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::UnsupportedOperation {
                entity_type,
                entity_id,
            } => write!(
                f,
                "outbox refused unsupported operation for {entity_type}/{entity_id}"
            ),
            Self::TaintedVersion {
                entity_type,
                entity_id,
                version,
            } => write!(
                f,
                "outbox refused tainted incoming version for {entity_type}/{entity_id}: \
                 version={version:?} failed Hlc::parse — caller must re-stamp"
            ),
            Self::ContentionExhausted {
                entity_type,
                entity_id,
                attempts,
            } => write!(
                f,
                "outbox coalesce retry budget exhausted for {entity_type}/{entity_id} \
                 after {attempts} attempts; the write was rolled back and must be retried"
            ),
            Self::Sql(e) => write!(f, "database error: {e}"),
            Self::Internal(message) => write!(f, "internal outbox error: {message}"),
        }
    }
}

impl std::error::Error for OutboxError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Sql(e) => Some(e),
            Self::TaintedVersion { .. }
            | Self::UnsupportedOperation { .. }
            | Self::ContentionExhausted { .. }
            | Self::Internal(_) => None,
        }
    }
}

impl From<rusqlite::Error> for OutboxError {
    fn from(e: rusqlite::Error) -> Self {
        Self::Sql(e)
    }
}
