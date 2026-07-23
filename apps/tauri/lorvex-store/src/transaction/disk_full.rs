//! DiskFull breaker short-circuit synthesizer.
//!
//! The transaction helpers are generic over `E: From<rusqlite::Error>`, so
//! the cleanest way to deliver a typed DiskFull error from the breaker
//! short-circuit is to construct the rusqlite-shaped error that the caller's
//! `From` already classifies (e.g. `StoreError::from_rusqlite` routes this
//! into `StoreError::DiskFull`). This keeps the breaker's short-circuit path
//! identical to the live ENOSPC error path from the caller's perspective.

use crate::maintenance::disk_full::DiskFullError;

/// Synthesize the DiskFull short-circuit error in the caller's error type.
pub(super) fn disk_full_short_circuit<E: From<rusqlite::Error>>(err: DiskFullError) -> E {
    let synthetic = rusqlite::Error::SqliteFailure(
        rusqlite::ffi::Error {
            code: rusqlite::ErrorCode::DiskFull,
            extended_code: 13, // SQLITE_FULL
        },
        Some(err.details),
    );
    E::from(synthetic)
}
