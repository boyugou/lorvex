//! `BEGIN IMMEDIATE` transaction wrappers.
//!
//! [`with_immediate_transaction`] is the live-write surface — handlers and
//! sync-apply routes go through it and inherit the DiskFull circuit-breaker
//! short-circuit. [`with_immediate_transaction_breaker_exempt`] is reserved
//! for cold-DB-open paths (migration runner, markdown-checklist promotion,
//! schema audits) that must run regardless of breaker state on every process
//! start.

use super::disk_full::disk_full_short_circuit;
use crate::busy_retry::{with_busy_retry, DEFAULT_RETRY_BUDGET};
use crate::maintenance::disk_full::{is_tripped as is_disk_full_tripped, DiskFullError};
use rusqlite::Connection;
use std::panic::{catch_unwind, resume_unwind, AssertUnwindSafe};

/// Execute `f` inside a `BEGIN IMMEDIATE` transaction.
///
/// If `f` returns `Ok`, the transaction is committed.
/// If `f` returns `Err`, the transaction is rolled back and the error is
/// returned. If `f` panics, the transaction is rolled back *before* the
/// panic is resumed — this keeps the outer `Mutex<Connection>` in a clean
/// state (no dangling `BEGIN IMMEDIATE`) even though the mutex will still
/// be poisoned by the panic.
///
/// # Errors
///
/// Returns the error from `f`, a SQLite error if BEGIN/COMMIT fails, or a
/// combined transaction-cleanup error if rollback itself fails.
pub fn with_immediate_transaction<T, E>(
    conn: &Connection,
    f: impl FnOnce(&Connection) -> Result<T, E>,
) -> Result<T, E>
where
    E: From<rusqlite::Error> + From<String> + std::fmt::Display,
{
    // #2386: if the DiskFull circuit breaker is tripped, short-circuit
    // BEFORE even attempting `BEGIN IMMEDIATE`. Hammering a full disk
    // turns every write into a slow failure and spams the user with
    // retry-storm toasts; the synthetic rusqlite error is routed through
    // the caller's `From<rusqlite::Error>` so `StoreError::DiskFull` is
    // produced identically to the live ENOSPC path.
    if is_disk_full_tripped() {
        return Err(disk_full_short_circuit(DiskFullError {
            details: "Local storage is full. Free up space and retry.".to_string(),
        }));
    }

    with_immediate_transaction_breaker_exempt(conn, f)
}

/// Like [`with_immediate_transaction`] but does not consult the disk-full
/// circuit breaker.
///
/// cold-DB-open paths (migration runner, markdown-checklist
/// promotion, schema audits) must run regardless of the breaker — those
/// paths execute on every process start, and a transient breaker hit
/// elsewhere in the process would silently block all future opens.
/// Catching `SQLITE_FULL` from the underlying `BEGIN IMMEDIATE` is the
/// correct failure mode at startup; the user-facing breaker is meaningful
/// only at the live-write surface (handlers, sync apply) where retries
/// would otherwise hammer a known-bad disk.
pub fn with_immediate_transaction_breaker_exempt<T, E>(
    conn: &Connection,
    f: impl FnOnce(&Connection) -> Result<T, E>,
) -> Result<T, E>
where
    E: From<rusqlite::Error> + From<String> + std::fmt::Display,
{
    // `BEGIN IMMEDIATE` is the primary surface for cross-process
    // contention (app + MCP sibling both claiming the write lock). The
    // connection-level `busy_timeout` handles the single-statement
    // wait, but once the timeout elapses SQLite still surfaces BUSY to
    // the caller. `with_busy_retry` sleeps with jitter and re-attempts
    // the BEGIN before we commit to invoking `f`. See #2388.
    with_busy_retry(DEFAULT_RETRY_BUDGET, || {
        conn.execute_batch("BEGIN IMMEDIATE;")
    })?;

    // `Connection` is not UnwindSafe by default (it contains `Cell`s and
    // other interior mutability), but the only state we mutate through it
    // here is SQLite's transaction state — which we explicitly reset below.
    // Using `AssertUnwindSafe` is sound for our panic-then-rollback contract.
    let closure_result = catch_unwind(AssertUnwindSafe(|| f(conn)));

    match closure_result {
        Ok(Ok(value)) => {
            conn.execute_batch("COMMIT;")?;
            Ok(value)
        }
        Ok(Err(e)) => match conn.execute_batch("ROLLBACK;") {
            Ok(()) => Err(e),
            Err(rollback_error) => Err(E::from(format!("{e}; rollback failed: {rollback_error}"))),
        },
        Err(panic_payload) => {
            // Clean up the transaction BEFORE resuming the unwind so the
            // underlying connection doesn't retain an open `BEGIN IMMEDIATE`.
            // Rollback errors are intentionally swallowed here — the panic
            // takes precedence and must be propagated faithfully.
            let _ = conn.execute_batch("ROLLBACK;");
            resume_unwind(panic_payload);
        }
    }
}
