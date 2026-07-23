//! Disk-full (`SQLITE_FULL` / ENOSPC) classification + process-wide circuit
//! breaker.
//!
//! Every SQLite write path surface `rusqlite::Error::SqliteFailure`
//! verbatim when the disk filled up — the user got a cryptic toast
//! ("database or disk is full: ...") with no actionable next step and
//! subsequent writes kept attacking the full disk. This module adds three
//! pieces of protection:
//!
//! 1. [`is_disk_full_error`] classifies a `rusqlite::Error` as DiskFull
//!    (either the SQLite `SQLITE_FULL` extended code family or an I/O
//!    error that wraps `std::io::ErrorKind::StorageFull`). The classifier
//!    is deliberately conservative — a miss means the user sees the
//!    generic "database error" toast (today's behavior). A false positive
//!    would trip the circuit breaker inappropriately, so we match on
//!    precise conditions only.
//!
//! 2. A process-global [`DISK_FULL_TRIPPED`] flag. Once any write path
//!    observes DiskFull, the flag is set via [`trip_disk_full`]. Future
//!    writes consult [`is_tripped`] (e.g. from
//!    `transaction::with_immediate_transaction`) before even opening a
//!    transaction, so we stop hammering a full disk and give the user a
//!    fast, consistent error until they clear space.
//!
//! 3. A [`probe_and_reset`] helper that runs a tiny throw-away INSERT
//!    inside a rolled-back transaction on the supplied connection. If it
//!    succeeds, the breaker is reset. Callers invoke this when the user
//!    clicks "try again" from the toast surface.
//!
//! See GitHub issue #2386 for the investigation + design.

use rusqlite::{Connection, Error, ErrorCode};
#[cfg(test)]
use std::cell::Cell;
#[cfg(not(test))]
use std::sync::atomic::{AtomicBool, Ordering};

/// Process-wide circuit-breaker flag in production. `true` means a write path has
/// recently observed DiskFull; subsequent writes short-circuit with
/// [`DiskFullError`] until a probe clears the flag.
///
/// Test builds use a thread-local flag instead. Rust's unit-test
/// harness runs unrelated tests in parallel inside one process; a
/// test that intentionally trips the breaker must not cause an
/// unrelated write-path test on another worker thread to fail with a
/// synthetic DiskFull.
///
/// `Ordering::SeqCst` is
/// stronger than this flag strictly needs — there is no second
/// shared variable whose visibility we have to order against the
/// breaker bit. The reason we keep `SeqCst` rather than relaxing to
/// `Acquire`/`Release` is purely one of clarity: the breaker is read
/// from every write entry-point (e.g. `with_immediate_transaction`'s
/// `is_tripped` gate) and tripped from a small handful of points
/// scattered across the apply / outbox / blob crates. The race-audit
/// verified there is no correctness hazard at any ordering, but
/// `SeqCst` lets a future reviewer mentally treat the breaker as a
/// single global linearization point. The cost is one extra fence per
/// write entry, dwarfed by the SQLite `BEGIN IMMEDIATE` that follows.
#[cfg(not(test))]
static DISK_FULL_TRIPPED: AtomicBool = AtomicBool::new(false);

#[cfg(test)]
thread_local! {
    static DISK_FULL_TRIPPED: Cell<bool> = const { Cell::new(false) };
}

/// Returned by transaction entry points (and surfaced via
/// [`StoreError::DiskFull`](crate::error::StoreError::DiskFull)) when
/// the breaker is set. Carries a stable, human-readable message.
#[derive(Debug)]
pub struct DiskFullError {
    pub details: String,
}

impl std::fmt::Display for DiskFullError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.details)
    }
}

impl std::error::Error for DiskFullError {}

/// Classify a `rusqlite::Error` as a disk-full condition.
///
/// Matches:
///   * `SqliteFailure` with `ErrorCode::DiskFull` (`SQLITE_FULL`) — the
///     primary path. SQLite's VFS classifies most `write(2)` ENOSPC
///     hits this way regardless of locale, OR
///   * `SqliteFailure` with `SystemIoFailure` where we can recognize
///     ENOSPC via two locale-independent signals:
///       1. The Rust `std::io::Error` `Display` form
///          (`"…: foo (os error N)"`) when N ∈ {28 (Unix ENOSPC),
///          112 (Windows ERROR_DISK_FULL)}. Rust's `io::Error` always
///          appends `(os error N)` even when the kernel `strerror`
///          message is localized, so this string-match holds for any
///          POSIX/Win locale.
///       2. A small set of canonical English ENOSPC fragments as a
///          last-resort fallback for SQLite-level loggers that
///          stringified the OS error themselves and stripped the
///          `(os error N)` tail.
///
/// The `SystemIoFailure` arm is deliberately conservative: a generic
/// `SystemIoFailure` can also mean a permissions error, a read-only
/// filesystem, or a disconnected volume, so we refuse to trip on the
/// category alone.
///
/// the previous English-only substring set
/// (`"no space left"`, `"disk full"`, …) silently failed on
/// non-English macOS / Linux builds where the kernel `strerror` is
/// translated, leaving the `DiskFull` circuit-breaker untripped while
/// every subsequent write hammered the full disk. The OS-error code
/// embedded in `(os error N)` is locale-independent.
pub fn is_disk_full_error(error: &Error) -> bool {
    match error {
        Error::SqliteFailure(code, msg) => {
            if code.code == ErrorCode::DiskFull {
                return true;
            }
            if code.code == ErrorCode::SystemIoFailure {
                if let Some(m) = msg.as_deref() {
                    return message_indicates_disk_full(m);
                }
            }
            false
        }
        _ => false,
    }
}

/// Locale-independent ENOSPC / ERROR_DISK_FULL detector for the
/// `Display` form of an OS-level write failure.
///
/// Primary signal: the trailing `(os error N)` that Rust's
/// `std::io::Error` formatter always appends. The codes are stable
/// across every Unix (28 = ENOSPC) and Windows (112 = ERROR_DISK_FULL)
/// regardless of `LANG`/`LC_MESSAGES`, so this match holds when the
/// kernel `strerror` is translated.
///
/// Secondary signal: a curated set of English fragments for paths
/// that stringified the OS error before reaching us, dropping the
/// `(os error N)` tail. The set is kept small and unambiguous —
/// expanding it across every locale would be both impractical and
/// risk false positives.
fn message_indicates_disk_full(message: &str) -> bool {
    // The `(os error N)` formatting is ASCII-only and case-stable; do
    // a literal substring match on the canonical Rust output before
    // case-folding the rest. ENOSPC = 28 (Unix), ERROR_DISK_FULL = 112
    // (Windows).
    if message.contains("(os error 28)") || message.contains("(os error 112)") {
        return true;
    }
    let lower = message.to_ascii_lowercase();
    lower.contains("no space left")
        || lower.contains("disk full")
        || lower.contains("out of space")
        || lower.contains("storage full")
}

/// Trip the process-wide DiskFull circuit breaker. Idempotent.
pub(crate) fn trip_disk_full() {
    #[cfg(not(test))]
    DISK_FULL_TRIPPED.store(true, Ordering::SeqCst);
    #[cfg(test)]
    DISK_FULL_TRIPPED.with(|flag| flag.set(true));
}

/// Is the breaker currently tripped?
pub fn is_tripped() -> bool {
    #[cfg(not(test))]
    {
        DISK_FULL_TRIPPED.load(Ordering::SeqCst)
    }
    #[cfg(test)]
    {
        DISK_FULL_TRIPPED.with(Cell::get)
    }
}

/// Manually clear the breaker. Used by tests and (indirectly) by the
/// "try again" retry affordance via [`probe_and_reset`].
pub fn clear_tripped_for_tests() {
    #[cfg(not(test))]
    DISK_FULL_TRIPPED.store(false, Ordering::SeqCst);
    #[cfg(test)]
    DISK_FULL_TRIPPED.with(|flag| flag.set(false));
}

/// Serializes tests that make assertions about the test-only breaker
/// state. The production breaker is process-global, but unit tests use
/// thread-local state so intentional DiskFull trips do not leak into
/// unrelated worker threads.
#[cfg(test)]
pub(crate) fn breaker_test_mutex() -> &'static std::sync::Mutex<()> {
    use std::sync::{Mutex, OnceLock};
    static M: OnceLock<Mutex<()>> = OnceLock::new();
    M.get_or_init(|| Mutex::new(()))
}

/// Probe the DB with a throw-away write to decide whether to clear the
/// DiskFull breaker.
///
/// Runs a `BEGIN IMMEDIATE` → tiny `CREATE TEMP TABLE` + `INSERT` →
/// `ROLLBACK` on the supplied connection. If both the BEGIN and the
/// INSERT succeed (or if the caller isn't tripped to begin with), the
/// breaker is cleared and `Ok(())` is returned. If the probe hits
/// DiskFull again, the breaker stays tripped and the error is returned.
///
/// This is the minimal "can we write at all?" check — it does not need
/// schema access, and the `TEMP TABLE` is auto-dropped at rollback so
/// there's no persistent state.
pub fn probe_and_reset(conn: &Connection) -> Result<(), Error> {
    conn.execute_batch("BEGIN IMMEDIATE;")?;
    let probe = (|| -> Result<(), Error> {
        conn.execute_batch("CREATE TEMP TABLE IF NOT EXISTS lorvex_disk_full_probe (v INTEGER);")?;
        conn.execute("INSERT INTO lorvex_disk_full_probe (v) VALUES (1)", [])?;
        Ok(())
    })();
    // Always roll back — we don't care about the row, only that the
    // INSERT could be written to WAL without ENOSPC.
    let _ = conn.execute_batch("ROLLBACK;");
    match probe {
        Ok(()) => {
            #[cfg(not(test))]
            DISK_FULL_TRIPPED.store(false, Ordering::SeqCst);
            #[cfg(test)]
            DISK_FULL_TRIPPED.with(|flag| flag.set(false));
            Ok(())
        }
        Err(e) => {
            if is_disk_full_error(&e) {
                trip_disk_full();
            }
            Err(e)
        }
    }
}

#[cfg(test)]
mod tests;
