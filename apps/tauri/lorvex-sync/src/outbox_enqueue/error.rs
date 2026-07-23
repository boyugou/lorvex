//! Typed error surface for the outbox-enqueue path.
//!
//! Split out of `outbox_enqueue/mod.rs` so the enum, its `Display` /
//! `std::error::Error` impls, and the seven `From` lifters live in
//! their own ~230 LOC module — the parent then only carries the
//! enqueue helpers themselves.
//!
//! Internal callers reach `EnqueueError` through `super::EnqueueError`
//! via the `pub use` in the parent module; downstream crates keep
//! their existing `lorvex_sync::EnqueueError` import path because the
//! enum's public re-export at the crate root is unchanged.

use std::fmt;

use lorvex_domain::naming::EntityKind;

use crate::canonicalize::CanonError;

/// Errors from the enqueue helper.
#[derive(Debug)]
pub enum EnqueueError {
    /// The entity type is not recognized or not supported for snapshot reading.
    UnknownEntityType(String),
    /// The entity was not found in the database.
    EntityNotFound {
        entity_type: String,
        entity_id: String,
    },
    /// A store-layer invariant / validation / serialization failure occurred.
    Store(lorvex_store::StoreError),
    /// A SQLite error occurred.
    Sqlite(rusqlite::Error),
    /// Version stamping failed before the envelope could be queued.
    VersionStamp(crate::version_stamp::VersionStampError),
    /// a concurrent writer stamped a strictly newer
    /// version than the one this enqueue attempt brought. The caller
    /// MUST NOT treat this as success — the payload they constructed
    /// reflects pre-superseding state, and enqueueing at the
    /// attempted version would push an envelope whose HLC disagrees
    /// with the row's `version`. Surfaced as a typed variant so
    /// callers can re-read + re-enqueue, log a structured retry
    /// event, or fail loudly instead of silently shipping a stale
    /// envelope.
    VersionSuperseded {
        entity_type: &'static str,
        entity_id: String,
        attempted_version: String,
        existing_version: String,
    },
    /// Payload canonicalization failed (e.g. nesting exceeds MAX_JSON_DEPTH).
    Canonicalization(CanonError),
    /// callers reached the enqueue helper with an operation variant
    /// this local enqueue path does not support. Local writers must
    /// construct explicit `Upsert` / `Delete`.
    UnsupportedOperation {
        entity_type: EntityKind,
        entity_id: String,
    },
    /// the outbox coalesce surface refused the
    /// envelope because the incoming `version` failed `Hlc::parse`.
    /// Caller MUST re-stamp with a canonical HLC (or fix the upstream
    /// bug minting the tainted version) before retrying — letting an
    /// unparseable version drive the LWW gate would either lex-flip
    /// against `'v1'`/`'seed'` style fixtures or silently lose the
    /// write. Mirrors the tainted-version refusal pattern; surfaced as
    /// a typed variant so callers can branch on the failure without
    /// re-parsing the inner display string.
    TaintedVersion {
        entity_type: EntityKind,
        entity_id: String,
        version: String,
    },
    /// the coalesced-enqueue retry loop exhausted its retry budget
    /// against the `(entity_type, entity_id)` UNIQUE-partial-index
    /// race between concurrent writers. The attempt's savepoint has
    /// been rolled back; the caller's mutation transaction is gone.
    /// Surfaced as a typed variant so the surface adapter can show a
    /// retry-the-write affordance instead of letting the underlying
    /// SQL constraint violation collapse into a generic toast (#4583
    /// B20).
    ContentionExhausted {
        entity_type: EntityKind,
        entity_id: String,
        attempts: u32,
    },
    /// Post-write pending-inbox target lookup failed. The enqueue
    /// helper treats this as part of the same atomic write surface:
    /// if it cannot prove whether a deferred child is waiting on the
    /// just-written entity, the local envelope must not commit alone.
    PendingDrainTargetLookup {
        entity_type: String,
        entity_id: String,
        source: crate::error::SyncError,
    },
    /// Post-write pending-inbox drain failed. Surfaced as a hard
    /// enqueue failure so callers using an autocommit connection get
    /// the parent enqueue and child apply rolled back together.
    PendingDrain {
        entity_type: String,
        entity_id: String,
        source: crate::error::SyncError,
    },
}

impl fmt::Display for EnqueueError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EnqueueError::UnknownEntityType(t) => {
                write!(f, "unknown entity type for snapshot: {t}")
            }
            EnqueueError::EntityNotFound {
                entity_type,
                entity_id,
            } => {
                write!(f, "entity not found: {entity_type}/{entity_id}")
            }
            EnqueueError::Store(e) => write!(f, "store error: {e}"),
            EnqueueError::Sqlite(e) => write!(f, "sqlite error: {e}"),
            EnqueueError::VersionStamp(e) => write!(f, "version stamp error: {e}"),
            EnqueueError::VersionSuperseded {
                entity_type,
                entity_id,
                attempted_version,
                existing_version,
            } => write!(
                f,
                "enqueue superseded for {entity_type}:{entity_id} \
                 (attempted {attempted_version}, existing {existing_version})"
            ),
            EnqueueError::Canonicalization(e) => write!(f, "canonicalization error: {e}"),
            EnqueueError::UnsupportedOperation {
                entity_type,
                entity_id,
            } => write!(
                f,
                "enqueue called with unsupported operation for {entity_type}/{entity_id} \
                 (only Upsert / Delete are supported on the local enqueue path)"
            ),
            EnqueueError::TaintedVersion {
                entity_type,
                entity_id,
                version,
            } => write!(
                f,
                "outbox refused tainted incoming version for {entity_type}/{entity_id}: \
                 version={version:?} failed Hlc::parse — caller must re-stamp"
            ),
            EnqueueError::ContentionExhausted {
                entity_type,
                entity_id,
                attempts,
            } => write!(
                f,
                "outbox coalesce retry budget exhausted for {entity_type}/{entity_id} \
                 after {attempts} attempts; the write was rolled back and must be retried"
            ),
            EnqueueError::PendingDrainTargetLookup {
                entity_type,
                entity_id,
                source,
            } => write!(
                f,
                "post-write pending-inbox target lookup failed for {entity_type}:{entity_id}: \
                 {source}"
            ),
            EnqueueError::PendingDrain {
                entity_type,
                entity_id,
                source,
            } => write!(
                f,
                "post-write pending-inbox drain failed for {entity_type}:{entity_id}: {source}"
            ),
        }
    }
}

impl std::error::Error for EnqueueError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            EnqueueError::Store(e) => Some(e),
            EnqueueError::Sqlite(e) => Some(e),
            EnqueueError::VersionStamp(e) => Some(e),
            EnqueueError::Canonicalization(e) => Some(e),
            EnqueueError::PendingDrainTargetLookup { source, .. }
            | EnqueueError::PendingDrain { source, .. } => Some(source),
            EnqueueError::VersionSuperseded { .. }
            | EnqueueError::UnknownEntityType(_)
            | EnqueueError::EntityNotFound { .. }
            | EnqueueError::UnsupportedOperation { .. }
            | EnqueueError::TaintedVersion { .. }
            | EnqueueError::ContentionExhausted { .. } => None,
        }
    }
}

impl From<crate::outbox::OutboxError> for EnqueueError {
    fn from(e: crate::outbox::OutboxError) -> Self {
        match e {
            crate::outbox::OutboxError::Sql(sql) => EnqueueError::Sqlite(sql),
            crate::outbox::OutboxError::TaintedVersion {
                entity_type,
                entity_id,
                version,
            } => EnqueueError::TaintedVersion {
                entity_type,
                entity_id,
                version,
            },
            crate::outbox::OutboxError::UnsupportedOperation {
                entity_type,
                entity_id,
            } => EnqueueError::UnsupportedOperation {
                entity_type,
                entity_id,
            },
            crate::outbox::OutboxError::ContentionExhausted {
                entity_type,
                entity_id,
                attempts,
            } => EnqueueError::ContentionExhausted {
                entity_type,
                entity_id,
                attempts,
            },
            // `OutboxError::Internal` carries an internal-bookkeeping
            // failure message (e.g. savepoint helper rejecting an
            // unsafe prefix). It's not retryable and not exposed to
            // peers; route it through `Store`+`Invariant` so the
            // existing diagnostic surfaces (Settings → Diagnostics)
            // capture it without inventing a parallel enum variant.
            crate::outbox::OutboxError::Internal(message) => EnqueueError::Store(
                lorvex_store::StoreError::Invariant(format!("outbox internal error: {message}")),
            ),
        }
    }
}

impl From<lorvex_store::StoreError> for EnqueueError {
    fn from(e: lorvex_store::StoreError) -> Self {
        EnqueueError::Store(e)
    }
}

/// `PayloadError` originates from [`lorvex_sync_payload`] (#4350).
/// Route through `StoreError` so the disk-full reclassifier runs on
/// `Sql` variants before they reach the outbox-enqueue surface.
impl From<lorvex_sync_payload::PayloadError> for EnqueueError {
    fn from(e: lorvex_sync_payload::PayloadError) -> Self {
        EnqueueError::Store(lorvex_store::StoreError::from(e))
    }
}

impl From<rusqlite::Error> for EnqueueError {
    fn from(e: rusqlite::Error) -> Self {
        EnqueueError::Sqlite(e)
    }
}

impl From<crate::version_stamp::VersionStampError> for EnqueueError {
    fn from(error: crate::version_stamp::VersionStampError) -> Self {
        // lift the typed `Superseded` variant into a
        // top-level enqueue error so callers can pattern-match on it
        // without reaching through the wrapped error. The other
        // variants stay nested under `VersionStamp` because they
        // represent enqueue-time invariants the caller cannot
        // reasonably recover from.
        match error {
            crate::version_stamp::VersionStampError::Superseded {
                entity_type,
                entity_id,
                existing_version,
            } => EnqueueError::VersionSuperseded {
                entity_type,
                entity_id,
                // The `attempted_version` is filled by the lifter in
                // `enqueue_payload_internal_body` because the
                // VersionStampError doesn't carry it. Until that lift
                // runs, this default placeholder makes the typed
                // shape uniform; the lifter overwrites it before the
                // error escapes the enqueue helper.
                attempted_version: String::new(),
                existing_version,
            },
            other => EnqueueError::VersionStamp(other),
        }
    }
}

impl From<CanonError> for EnqueueError {
    fn from(e: CanonError) -> Self {
        EnqueueError::Canonicalization(e)
    }
}

/// required by
/// `lorvex_store::transaction::with_savepoint`'s `E: From<String>`
/// bound. The wrapper lifts a stringified rollback-side failure
/// (e.g. "ROLLBACK TO failed: …") through this arm so the original
/// error propagates while the transaction wrapper still surfaces
/// any cleanup-side trouble. Routed into `Sqlite(...)` via a synthetic
/// `rusqlite::Error::ToSqlConversionFailure` so the existing source-
/// chain readers see a real `dyn Error` rather than a fresh string-only
/// variant on `EnqueueError` (every other variant carries structured
/// fields).
impl From<String> for EnqueueError {
    fn from(message: String) -> Self {
        EnqueueError::Sqlite(rusqlite::Error::ToSqlConversionFailure(
            // The pre-existing `Sqlite` arm is the conventional bag
            // for rollback-wrapper failures across the workspace.
            // Box a one-line stderr-friendly message in.
            Box::new(std::io::Error::other(message)),
        ))
    }
}
