//! Retry helper for SQLite `BUSY` / `LOCKED` errors.
//!
//! Frontend-triggered writes go through `withBusyRetry` in the Tauri IPC
//! layer (`app/src/lib/ipc/core.ts`). Backend-direct writes — MCP-bridge
//! invocations, sync runtime pushes, startup tasks — do not, so any
//! cross-process write contention (app + MCP sibling both attempting to
//! take the write lock on the shared WAL database) surfaces as an opaque
//! `SqliteFailure(DatabaseBusy, _)` rusqlite error.
//!
//! The `PRAGMA busy_timeout=5000` applied at connection open handles
//! *intra-statement* contention already, but a `BEGIN IMMEDIATE`
//! competing with another writer still returns `SQLITE_BUSY` once the
//! timeout elapses. This helper adds a small retry budget on top of the
//! pragma for the narrow window where two writers race.
//!
//! Wired into `transaction::with_immediate_transaction` so every caller
//! that uses the central helper inherits retry without opting in.
//! Callers that need their own retry boundary (e.g., a raw single-shot
//! write outside a transaction) can invoke `with_busy_retry` directly.
//!
//! See GitHub issue #2388 for the investigation + design decision.
//!
//! # Regression guard for future contributors
//!
//! Any new backend-direct write path MUST route through one of the
//! central helpers so it inherits the busy-retry budget. Concretely:
//!
//! * A multi-statement write (or a single statement that takes the
//!   writer lock implicitly via `INSERT`/`UPDATE`/`DELETE` outside an
//!   existing transaction) should be wrapped in
//!   [`crate::transaction::with_immediate_transaction`].
//! * A nested unit of work inside an already-open BEGIN IMMEDIATE
//!   should use [`crate::transaction::with_savepoint`] or
//!   [`crate::transaction::with_savepoint_mapped`].
//! * A raw `execute_batch("BEGIN IMMEDIATE;")` / `"SAVEPOINT ..."` /
//!   single `conn.execute(...)` that for schema-pragma reasons cannot
//!   go through the transaction helper (e.g., `data_reset.rs`, which
//!   must pair `foreign_keys = OFF` with BEGIN on the same connection)
//!   MUST call [`with_busy_retry`] directly around the statement.
//!
//! closed five real gaps where raw writes bypassed these
//! helpers and surfaced `SQLITE_BUSY` under app+MCP sibling
//! contention. Grep for `execute_batch("BEGIN` / `execute_batch("SAVEPOINT`
//! when adding new write paths; every hit outside this module and
//! `transaction.rs` should be paired with a `with_busy_retry` call.

use crate::maintenance::disk_full::{is_disk_full_error, trip_disk_full};
use rusqlite::{Error, ErrorCode};
use std::thread;
use std::time::{Duration, Instant};

/// Default number of attempts when the caller does not specify one. An
/// attempt count of 5 gives cumulative backoff of roughly 10+20+30+40 ms
/// worth of sleeps before the final try, which is long enough to ride
/// through most contention and short enough not to make the UI feel
/// unresponsive.
pub const DEFAULT_RETRY_BUDGET: u32 = 5;

const JITTER_STEP_MS: u64 = 10;
const JITTER_CAP_MS: u64 = 200;

/// Run `f` under a busy-retry budget.
///
/// Retries when `f` returns `SqliteFailure` with `ErrorCode::DatabaseBusy`
/// or `ErrorCode::DatabaseLocked`. Every other `rusqlite::Error` is
/// surfaced immediately. Between attempts we sleep
/// `min(10ms * attempt_count + jitter, 200ms)`.
///
/// `retry_budget` is the total number of attempts, not the number of
/// *re*tries — `retry_budget = 1` calls `f` exactly once and never
/// retries. A budget of `0` is treated as `1` for safety (we always run
/// the closure at least once).
///
/// # Errors
///
/// Surfaces the final `rusqlite::Error` from `f` once the budget is
/// exhausted, or the first non-busy error encountered.
pub fn with_busy_retry<T, F>(retry_budget: u32, mut f: F) -> Result<T, Error>
where
    F: FnMut() -> Result<T, Error>,
{
    let budget = retry_budget.max(1);
    let mut attempt: u32 = 0;
    loop {
        attempt += 1;
        match f() {
            Ok(value) => return Ok(value),
            Err(err) if is_busy_error(&err) && attempt < budget => {
                sleep_with_jitter(attempt);
            }
            Err(err) => {
                // #2386: DiskFull is not retryable (no amount of waiting
                // frees disk space), but every write path we serve here
                // is a candidate surface for ENOSPC. Trip the process-
                // wide circuit breaker as a side-effect so subsequent
                // transactions short-circuit instead of all piling onto
                // the full disk. The error is still surfaced verbatim
                // so callers with a typed error layer
                // (`StoreError::from_rusqlite`) can classify it into
                // `StoreError::DiskFull`.
                if is_disk_full_error(&err) {
                    trip_disk_full();
                }
                return Err(err);
            }
        }
    }
}

/// Classifies a `rusqlite::Error` as a transient busy / locked condition
/// that is worth retrying.
pub(crate) fn is_busy_error(error: &Error) -> bool {
    matches!(
        error,
        Error::SqliteFailure(code, _)
            if code.code == ErrorCode::DatabaseBusy
                || code.code == ErrorCode::DatabaseLocked
    )
}

fn sleep_with_jitter(attempt: u32) {
    let base_ms = u64::from(attempt).saturating_mul(JITTER_STEP_MS);
    let jitter_ms = jitter_ms();
    let total_ms = base_ms.saturating_add(jitter_ms).min(JITTER_CAP_MS);
    thread::sleep(Duration::from_millis(total_ms));
}

/// Cheap pseudo-random jitter in `0..JITTER_STEP_MS` ms. We don't need
/// cryptographic randomness here — just enough entropy to stagger two
/// racers that both woke up on the same BUSY. Using the nanosecond
/// component of `Instant::now()` avoids pulling `rand` into the store
/// crate.
fn jitter_ms() -> u64 {
    // `Instant` is monotonic, so elapsed nanoseconds change every call
    // and the low bits are effectively random across threads.
    let now = Instant::now();
    let reference = *JITTER_REFERENCE;
    let nanos = u64::from(now.saturating_duration_since(reference).subsec_nanos());
    nanos % JITTER_STEP_MS
}

// Captured once at module load so `jitter_ms` has a stable reference
// point for `duration_since`. The absolute value doesn't matter — only
// the low-bit entropy of the delta.
static JITTER_REFERENCE: std::sync::LazyLock<Instant> = std::sync::LazyLock::new(Instant::now);

#[cfg(test)]
mod tests;
