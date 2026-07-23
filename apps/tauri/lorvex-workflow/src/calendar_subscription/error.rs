//! Error shape for the cross-surface `calendar_subscription` primitives.
//!
//! Every workflow-level subscription primitive — TZID parsing, URL
//! safety / SSRF validation, the sync orchestrator that drives a single
//! feed refresh — surfaces failure through
//! [`CalendarSubscriptionError`]. Surface adapters map it back into
//! their surface-local error (e.g. `AppError` on the Tauri side,
//! `CliError` on the CLI) through a one-shot `From` impl.
//!
//! Variants:
//!
//! - `Validation` — caller-controllable failures (bad URL, malformed
//!   input). Surface verbatim to the user.
//! - `Store` — a typed [`StoreError`] propagated from a repository
//!   call. Preserves the disk-full / stale-version / not-found
//!   discriminant so surface adapters can render an actionable typed
//!   error envelope instead of an opaque string.
//! - `Db` — a raw `rusqlite::Error` from inline SQL. Construction
//!   routes through [`StoreError::from_rusqlite`] first so disk-full
//!   errors are classified into [`StoreError::DiskFull`] (and trip the
//!   process-wide breaker) before they ever surface as `Db`; the `Db`
//!   variant therefore only carries non-disk-full SQL faults.
//! - `Internal` — an internal failure that cannot be expressed as
//!   `Store` / `Db` (e.g. a malformed canonical timestamp, a stringly
//!   propagated rollback failure). Distinct from `Validation` so the
//!   surface adapter can decide whether to retry vs. show the message
//!   verbatim.
//!
//! [`lorvex_store::with_immediate_transaction`] requires
//! `From<rusqlite::Error> + From<String>` on the error type; the
//! `From<rusqlite::Error>` impl routes through the classifier, and
//! `From<String>` lands in `Internal`.

use lorvex_store::StoreError;
use thiserror::Error;

/// Errors produced by the shared calendar-subscription primitives.
#[derive(Debug, Error)]
pub enum CalendarSubscriptionError {
    /// A caller-supplied URL failed safety / SSRF validation: wrong
    /// scheme (must be `https://`), missing host, points at a
    /// loopback / link-local / private / cloud-metadata literal,
    /// matches the local-network hostname denylist
    /// (`localhost`, `*.local`, `host.docker.internal`,
    /// `metadata.google.internal`), or DNS-resolves to any denied
    /// address. The message is user-facing and explains what the
    /// caller can do (e.g. "Use a public https:// URL").
    #[error("{0}")]
    Validation(String),

    /// A typed store-layer failure. Carries the full
    /// [`StoreError`] discriminant so surface adapters can render
    /// disk-full / stale-version / not-found envelopes verbatim
    /// instead of collapsing to a generic internal-string.
    #[error(transparent)]
    Store(StoreError),

    /// A non-disk-full `rusqlite::Error`. Construction is routed
    /// through [`StoreError::from_rusqlite`] in
    /// `From<rusqlite::Error>`, which intercepts disk-full failures
    /// and routes them into [`CalendarSubscriptionError::Store`] with
    /// a [`StoreError::DiskFull`] payload; only generic SQL failures
    /// (constraint violations, busy retries, malformed statements)
    /// land here.
    #[error("database error: {0}")]
    Db(rusqlite::Error),

    /// An internal failure that cannot be expressed through the
    /// typed `Store` / `Db` variants — e.g. a malformed canonical
    /// timestamp the orchestrator itself produced, an OS-level DNS
    /// resolution that returned a malformed answer, or a stringly
    /// propagated transaction-rollback failure. Kept distinct from
    /// `Validation` so the surface adapter can decide whether to
    /// retry vs. show the message verbatim.
    #[error("{0}")]
    Internal(String),
}

impl From<rusqlite::Error> for CalendarSubscriptionError {
    /// Route every raw `rusqlite::Error` through
    /// [`StoreError::from_rusqlite`] so the disk-full classifier and
    /// the process-wide circuit breaker fire exactly once at the
    /// boundary. A disk-full `rusqlite::Error` lands in
    /// `Store(StoreError::DiskFull)`; everything else lands in
    /// `Db(rusqlite::Error)`.
    fn from(err: rusqlite::Error) -> Self {
        match StoreError::from_rusqlite(err) {
            store_err @ StoreError::DiskFull { .. } => CalendarSubscriptionError::Store(store_err),
            StoreError::Sql(sql_err) => CalendarSubscriptionError::Db(sql_err),
            // `from_rusqlite` only ever returns `DiskFull` or `Sql`,
            // but the match is exhaustive over `StoreError` so any
            // hypothetical future variant falls through into `Store`
            // and keeps its typed discriminant.
            other => CalendarSubscriptionError::Store(other),
        }
    }
}

impl From<String> for CalendarSubscriptionError {
    /// Required by [`lorvex_store::with_immediate_transaction`] /
    /// `with_savepoint` so the rollback-failure path can synthesize
    /// a stringy error. Lands in `Internal` because the wrapper
    /// only emits this for cases that cannot be expressed
    /// structurally.
    fn from(msg: String) -> Self {
        CalendarSubscriptionError::Internal(msg)
    }
}

impl From<StoreError> for CalendarSubscriptionError {
    /// Preserve the typed [`StoreError`] discriminant so disk-full
    /// / stale-version / not-found failures keep their structured
    /// shape across the workflow boundary.
    fn from(err: StoreError) -> Self {
        CalendarSubscriptionError::Store(err)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// : a generic `rusqlite::Error` lands in the `Db` variant,
    /// not the catch-all `Internal(String)`. The classifier path
    /// runs but does not match disk-full so the inner error is
    /// preserved verbatim.
    #[test]
    fn from_rusqlite_routes_generic_sql_into_db_variant() {
        let err: CalendarSubscriptionError = rusqlite::Error::QueryReturnedNoRows.into();
        assert!(
            matches!(err, CalendarSubscriptionError::Db(_)),
            "generic SQL must land in Db, got {err:?}",
        );
    }

    /// : a `StoreError::StaleVersion` (LWW conflict) crosses
    /// the workflow boundary intact in the `Store` variant rather
    /// than collapsing to `Internal(String)`. Surface adapters can
    /// then pattern-match and surface a typed re-stamp prompt.
    #[test]
    fn from_store_error_preserves_stale_version_discriminant() {
        let store_err = StoreError::StaleVersion {
            entity: "calendar_subscription",
            id: "sub-1".to_string(),
        };
        let wrapped: CalendarSubscriptionError = store_err.into();
        match wrapped {
            CalendarSubscriptionError::Store(StoreError::StaleVersion { entity, id }) => {
                assert_eq!(entity, "calendar_subscription");
                assert_eq!(id, "sub-1");
            }
            other => panic!("expected Store(StaleVersion), got {other:?}"),
        }
    }

    /// : a `StoreError::DiskFull` propagated through `From`
    /// stays in the `Store` variant carrying the typed DiskFull
    /// payload, not a stringified `Internal`.
    #[test]
    fn from_store_error_preserves_disk_full_discriminant() {
        let store_err = StoreError::DiskFull {
            details: "SQLITE_FULL: out of disk space".to_string(),
        };
        let wrapped: CalendarSubscriptionError = store_err.into();
        assert!(
            matches!(
                wrapped,
                CalendarSubscriptionError::Store(StoreError::DiskFull { .. })
            ),
            "DiskFull must round-trip through Store, got {wrapped:?}",
        );
    }

    /// `From<String>` exists only to satisfy the
    /// `with_immediate_transaction` trait bound. It must land in
    /// `Internal` (the catch-all) rather than masquerading as a
    /// validation failure.
    #[test]
    fn from_string_lands_in_internal() {
        let err: CalendarSubscriptionError = "rollback failed".to_string().into();
        assert!(matches!(err, CalendarSubscriptionError::Internal(_)));
    }
}
