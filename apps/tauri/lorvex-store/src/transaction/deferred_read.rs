//! `BEGIN DEFERRED` snapshot-pinning read wrapper.
//!
//! Multi-statement read paths (e.g. MCP aggregate reads that run several
//! sequential SELECTs) call [`with_deferred_read_transaction`] to pin a
//! single WAL snapshot across the whole sequence. Without the wrapping
//! transaction every individual SELECT would see a fresh snapshot and a
//! concurrent writer could produce self-contradictory aggregate responses
//! (see #2239).

use crate::busy_retry::{with_busy_retry, DEFAULT_RETRY_BUDGET};
use rusqlite::Connection;
use std::panic::{catch_unwind, resume_unwind, AssertUnwindSafe};

/// Execute `body` inside a `BEGIN DEFERRED` read transaction.
///
/// `BEGIN DEFERRED` pins a single WAL snapshot for the duration of the
/// transaction, so every SELECT issued through `body` observes the same
/// consistent view of the database — a concurrent writer committing
/// between statements cannot make the aggregate response self-contradictory
/// (see #2239). Unlike `IMMEDIATE`, deferred read transactions acquire no
/// write lock, so they will not contend with the app's writer connection.
///
/// If `body` returns `Ok`, the transaction is committed. If it returns
/// `Err`, the transaction is rolled back and the error is propagated. If
/// `body` panics, the transaction is rolled back *before* the panic is
/// resumed so the underlying connection does not retain a dangling
/// `BEGIN DEFERRED` — matching the panic-safety contract of
/// [`with_immediate_transaction`].
///
/// If the connection is already inside a transaction (`is_autocommit() ==
/// false`), `body` runs directly on the existing snapshot. This makes the
/// helper safe to use at both outer and inner handler layers — e.g.
/// `get_session_context` wraps the entire composite read, and each nested
/// handler it calls (such as `get_overview_compact`) can independently
/// request snapshot pinning without conflicting with the outer `BEGIN`.
///
/// # Errors
///
/// Returns the error from `body` or a SQLite error from `BEGIN` (mapped
/// via `E::from(rusqlite::Error)`). `COMMIT` and `ROLLBACK` failures are
/// intentionally swallowed for the read path: a deferred read transaction
/// holds no locks beyond the WAL reader mark, and there is no write state
/// to reconcile on cleanup failure.
///
/// [`with_immediate_transaction`]: super::with_immediate_transaction
pub fn with_deferred_read_transaction<T, E, F>(conn: &Connection, body: F) -> Result<T, E>
where
    F: FnOnce(&Connection) -> Result<T, E>,
    E: From<rusqlite::Error>,
{
    // If a transaction is already active on this connection, a nested BEGIN
    // would fail with "cannot start a transaction within a transaction".
    // Reuse the caller's snapshot — composite MCP handlers legitimately nest
    // sub-handler reads (e.g. get_session_context → get_overview_compact).
    if !conn.is_autocommit() {
        return body(conn);
    }

    // `BEGIN DEFERRED` itself does not take the shared lock — the first
    // SELECT does. SQLITE_BUSY can therefore surface on the BEGIN when the
    // schema is locked by a concurrent writer. `with_busy_retry` mirrors
    // the treatment given to `BEGIN IMMEDIATE` in #2388.
    with_busy_retry(DEFAULT_RETRY_BUDGET, || {
        conn.execute_batch("BEGIN DEFERRED;")
    })
    .map_err(E::from)?;

    // `Connection` is not UnwindSafe (it holds interior mutability), but
    // the only state we mutate through it here is SQLite's transaction
    // state, which we explicitly reset below. `AssertUnwindSafe` is sound
    // for the panic-then-rollback contract.
    let closure_result = catch_unwind(AssertUnwindSafe(|| body(conn)));

    match closure_result {
        Ok(Ok(value)) => {
            // A failed COMMIT on a read transaction is effectively a no-op
            // (no write state to preserve). Swallow the error rather than
            // masking a successful read — the data the caller already
            // received from `body` is valid under the snapshot it read.
            let _ = conn.execute_batch("COMMIT;");
            Ok(value)
        }
        Ok(Err(err)) => {
            let _ = conn.execute_batch("ROLLBACK;");
            Err(err)
        }
        Err(panic_payload) => {
            // Clean up before resuming the unwind so the connection does
            // not retain a dangling `BEGIN DEFERRED`. Cleanup errors are
            // swallowed — the panic takes precedence.
            let _ = conn.execute_batch("ROLLBACK;");
            resume_unwind(panic_payload);
        }
    }
}
