//! Shared types and helpers for the coalesced-enqueue siblings.

/// Existing-row snapshot read from `sync_outbox` ahead of the coalesce
/// decision: `(version, operation)`. The version feeds the LWW gate;
/// the operation lets the audit hop detect an Upsert overwriting a
/// queued Delete.
pub(super) type ExistingOutboxRow = (String, String);

/// Detect SQLite UNIQUE constraint violations on the outbox so the
/// retry loop in `enqueue_coalesced` only re-runs for that specific
/// race condition. Other constraint shapes (CHECK, FK, NOT NULL)
/// propagate to the caller unchanged.
pub(super) const fn is_unique_constraint_violation(err: &rusqlite::Error) -> bool {
    match err {
        rusqlite::Error::SqliteFailure(ffi_err, _) => {
            matches!(ffi_err.code, rusqlite::ErrorCode::ConstraintViolation)
                && ffi_err.extended_code == rusqlite::ffi::SQLITE_CONSTRAINT_UNIQUE
        }
        _ => false,
    }
}
