//! Transaction helpers.
//!
//! SQLite deferred transactions can fail with SQLITE_BUSY at the first write
//! statement, which is confusing. `IMMEDIATE` transactions acquire the write
//! lock up front so contention is surfaced immediately.
//!
//! For multi-statement *read* paths (e.g. MCP aggregate reads that run ten
//! sequential SELECTs), [`with_deferred_read_transaction`] pins a single WAL
//! snapshot across the whole sequence. Without the wrapping transaction every
//! individual SELECT would see a fresh snapshot and a concurrent writer could
//! produce self-contradictory aggregate responses (see #2239).
//!
//! ## Module layout
//!
//! - [`disk_full`] — the typed DiskFull short-circuit synthesizer used by the
//!   IMMEDIATE wrapper to surface a tripped circuit-breaker through the
//!   caller's `From<rusqlite::Error>` conversion.
//! - [`immediate`] — [`with_immediate_transaction`] +
//!   [`with_immediate_transaction_breaker_exempt`].
//! - [`savepoint`] — uniquely-named SAVEPOINT helpers with panic-safe
//!   rollback discipline ([`with_savepoint`], [`with_savepoint_mapped`],
//!   [`with_savepoint_then_rollback`]) and the savepoint-prefix sanitizer.
//! - [`deferred_read`] — [`with_deferred_read_transaction`], the
//!   snapshot-pinning read wrapper.
//!
//! Public surface is re-exported here so callers continue to write
//! `lorvex_store::transaction::with_savepoint` unchanged.

mod deferred_read;
mod disk_full;
mod immediate;
mod savepoint;

pub use deferred_read::with_deferred_read_transaction;
pub use immediate::{with_immediate_transaction, with_immediate_transaction_breaker_exempt};
pub use savepoint::{with_savepoint, with_savepoint_mapped, with_savepoint_then_rollback};

#[cfg(test)]
mod tests;
