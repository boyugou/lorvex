//! Uniquely-named SAVEPOINT helpers.
//!
//! Savepoint names follow the pattern `lvx_sp_{prefix}_{counter}`. The
//! [`SAVEPOINT_COUNTER`] guarantees per-process uniqueness so siblings nested
//! inside one outer savepoint never alias. [`assert_safe_savepoint_prefix`]
//! enforces a defensive contract on the caller-supplied prefix component.
//!
//! Three flavors:
//! - [`with_savepoint`] commits on `Ok`, rolls back on `Err`.
//! - [`with_savepoint_mapped`] is the same shape but threads a custom error
//!   mapper for callers whose error types do not implement
//!   `From<rusqlite::Error>`.
//! - [`with_savepoint_then_rollback`] is the dry-run wrapper that ALWAYS
//!   rolls back, regardless of closure outcome, while still propagating the
//!   closure's `Ok` value through.
//!
//! All three roll the savepoint back BEFORE resuming a panic unwind so a
//! panicking closure cannot leave a dangling savepoint frame on the
//! connection.

use crate::busy_retry::{with_busy_retry, DEFAULT_RETRY_BUDGET};
use rusqlite::Connection;
use std::panic::{catch_unwind, resume_unwind, AssertUnwindSafe};
use std::sync::atomic::{AtomicU64, Ordering};

/// Process-global counter that names uniquely-scoped SAVEPOINTs.
///
/// `Ordering::Relaxed` is load-bearing here and safe
/// because the counter's single invariant is "no two concurrent
/// `fetch_add` calls return the same value." That is guaranteed by
/// atomicity alone — which every ordering mode provides — so no
/// cross-thread happens-before edge is needed. We do NOT rely on
/// "savepoint 100 started before savepoint 101 completed" or any
/// other ordering relation; savepoint names are merely distinct
/// token strings used once each on a connection the writer mutex
/// serializes access to.
///
/// If a future change needs to reason about the counter's value in
/// a cross-thread ordering context (e.g., observing the current
/// monotonic sequence number from another thread and acting on
/// it), that call site must either acquire the writer mutex OR use
/// `Ordering::AcqRel` / `SeqCst` at the read — the declaration
/// here should stay `Relaxed` so the performance cost of ordering
/// is paid only where actually required.
static SAVEPOINT_COUNTER: AtomicU64 = AtomicU64::new(0);

/// Maximum allowed savepoint-prefix length after sanitization. SQLite
/// identifier-length limit (`SQLITE_MAX_LENGTH`) is generous, but the
/// realistic upper bound for a useful savepoint name is far smaller —
/// 63 chars matches PostgreSQL's identifier limit and keeps the
/// generated `lvx_sp_<prefix>_<counter>` format under any reasonable
/// log-line truncation.
pub(super) const MAX_SAVEPOINT_PREFIX_LEN: usize = 63;

/// Validate that `prefix` is safe to embed inside a SAVEPOINT SQL
/// identifier, returning the sanitized form on success.
///
/// The helper enforces two contracts on the eventual savepoint name:
///
/// 1. **Non-empty after sanitization.** Strips every character that
///    is not ASCII alphanumeric or `_`. If nothing remains, an error
///    is returned. Without this guard, an all-non-alphanumeric
///    prefix (`"@@@"`, `"---"`, `"   "`) would collapse silently to
///    the empty string and every such caller would share the
///    savepoint namespace `"lvx_sp__{counter}"` — a real but
///    invisible collision SQLite happily tolerates.
/// 2. **At most [`MAX_SAVEPOINT_PREFIX_LEN`] (= 63) chars after
///    sanitization.** This matches PostgreSQL's identifier limit and
///    keeps the generated `lvx_sp_<prefix>_<counter>` name well under
///    every reasonable log-line truncation budget.
///
/// The `assert_*` name marks this as a defensive contract check that
/// returns a `Result` rather than panicking — so each caller can
/// decide whether to surface the error to the user or treat it as an
/// internal invariant violation.
///
/// # Examples
///
/// ```ignore
/// // (Helper is private to the crate; the snippet illustrates the
/// //  contract callers like `with_savepoint` enforce on their inputs.)
/// // Empty / all-non-alphanumeric prefixes are rejected.
/// assert!(assert_safe_savepoint_prefix("").is_err());
/// assert!(assert_safe_savepoint_prefix("---").is_err());
/// // Over-long prefixes (> 63 chars after sanitization) are rejected.
/// assert!(assert_safe_savepoint_prefix(&"a".repeat(64)).is_err());
/// // Mixed-case alphanumerics + `_` survive untouched.
/// assert_eq!(
///     assert_safe_savepoint_prefix("foo_Bar123").unwrap(),
///     "foo_Bar123",
/// );
/// // Non-identifier chars (incl. Unicode) are stripped before checks.
/// assert_eq!(assert_safe_savepoint_prefix("a/b\\c").unwrap(), "abc");
/// ```
///
/// The `assert_*` prefix and the doctest above make the contract
/// explicit at every call site — a `sanitize_*` name would imply the
/// function quietly fixes up its input, masking the fact that an
/// empty result silently aliases every non-alphanumeric caller into
/// the same savepoint namespace.
pub(super) fn assert_safe_savepoint_prefix(prefix: &str) -> Result<String, String> {
    let sanitized: String = prefix
        .chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '_')
        .collect();
    if sanitized.is_empty() {
        return Err(format!(
            "savepoint prefix '{prefix}' contains no valid identifier characters \
             (allowed: ASCII alphanumeric + underscore)"
        ));
    }
    if sanitized.len() > MAX_SAVEPOINT_PREFIX_LEN {
        return Err(format!(
            "savepoint prefix '{sanitized}' exceeds {MAX_SAVEPOINT_PREFIX_LEN}-char limit"
        ));
    }
    Ok(sanitized)
}

/// Execute `f` inside a uniquely-named `SAVEPOINT`.
///
/// Name pattern: `lvx_sp_{prefix}_{counter}`.
/// On success: `RELEASE SAVEPOINT`. On error: `ROLLBACK TO` + `RELEASE`.
/// On panic: `ROLLBACK TO` + `RELEASE` runs BEFORE the unwind resumes,
/// mirroring [`with_immediate_transaction`]'s panic-safety contract. Without
/// this, a panic inside `f` would leave the savepoint dangling on the
/// connection, and the next write would fail with "no such savepoint" even
/// after the outer `Mutex` recovered from poison.
///
/// [`with_immediate_transaction`]: super::with_immediate_transaction
pub fn with_savepoint<T, E>(
    conn: &Connection,
    prefix: &str,
    f: impl FnOnce(&Connection) -> Result<T, E>,
) -> Result<T, E>
where
    E: From<rusqlite::Error> + From<String> + std::fmt::Display,
{
    let id = SAVEPOINT_COUNTER.fetch_add(1, Ordering::Relaxed);
    let safe_prefix = assert_safe_savepoint_prefix(prefix).map_err(E::from)?;
    let name = format!("lvx_sp_{safe_prefix}_{id}");

    // Savepoints nest inside an already-open transaction, so the
    // write lock is already held by the outer BEGIN IMMEDIATE. In
    // theory the `SAVEPOINT` statement itself cannot return BUSY —
    // but route through `with_busy_retry` anyway for symmetry with
    // `with_immediate_transaction`, so any future path that opens
    // savepoints on a reader connection still inherits the retry.
    //
    // route the rusqlite::Error through `E::from`
    // (the `From<rusqlite::Error>` impl this function bounds on)
    // rather than `to_string()` round-tripping through
    // `From<String>`. Typed conversions classify SQLITE_FULL into
    // `StoreError::DiskFull` etc.; a string round-trip would lose
    // the classification. The mapped variant below cannot share this
    // path because its caller may not implement `From<rusqlite::Error>`,
    // which is the entire reason the two functions exist.
    with_busy_retry(DEFAULT_RETRY_BUDGET, || {
        conn.execute_batch(&format!("SAVEPOINT \"{name}\""))
    })
    .map_err(E::from)?;

    let closure_result = catch_unwind(AssertUnwindSafe(|| f(conn)));

    match closure_result {
        Ok(Ok(val)) => {
            conn.execute_batch(&format!("RELEASE SAVEPOINT \"{name}\""))
                .map_err(E::from)?;
            Ok(val)
        }
        Ok(Err(err)) => finish_failed_savepoint(&name, conn, err, E::from),
        Err(panic_payload) => {
            // Clean up the savepoint BEFORE resuming the unwind so the
            // underlying connection doesn't retain a dangling savepoint.
            // Errors from the cleanup are intentionally swallowed — the
            // panic takes precedence and must propagate faithfully.
            let _ = conn.execute_batch(&format!("ROLLBACK TO SAVEPOINT \"{name}\""));
            let _ = conn.execute_batch(&format!("RELEASE SAVEPOINT \"{name}\""));
            resume_unwind(panic_payload);
        }
    }
}

/// Like [`with_savepoint`] but accepts an error mapper instead of requiring `From`.
/// Useful when the error type is not `From<rusqlite::Error>`. Panic-safety:
/// panics roll back the savepoint before the unwind resumes — without this, a
/// panic inside `f` would leave the savepoint dangling on the connection, and
/// the next write would fail with "no such savepoint" even after the outer
/// `Mutex` recovered from poison.
pub fn with_savepoint_mapped<T, E>(
    conn: &Connection,
    prefix: &str,
    map_err: impl Fn(String) -> E,
    f: impl FnOnce(&Connection) -> Result<T, E>,
) -> Result<T, E>
where
    E: std::fmt::Display,
{
    let id = SAVEPOINT_COUNTER.fetch_add(1, Ordering::Relaxed);
    let safe_prefix = assert_safe_savepoint_prefix(prefix).map_err(&map_err)?;
    let name = format!("lvx_sp_{safe_prefix}_{id}");

    // Savepoints nest inside an already-open transaction, so the
    // write lock is already held by the outer BEGIN IMMEDIATE. In
    // theory the `SAVEPOINT` statement itself cannot return BUSY —
    // but route through `with_busy_retry` anyway for symmetry with
    // `with_immediate_transaction`, so any future path that opens
    // savepoints on a reader connection still inherits the retry.
    with_busy_retry(DEFAULT_RETRY_BUDGET, || {
        conn.execute_batch(&format!("SAVEPOINT \"{name}\""))
    })
    .map_err(|error| map_err(error.to_string()))?;

    let closure_result = catch_unwind(AssertUnwindSafe(|| f(conn)));

    match closure_result {
        Ok(Ok(val)) => {
            conn.execute_batch(&format!("RELEASE SAVEPOINT \"{name}\""))
                .map_err(|error| map_err(error.to_string()))?;
            Ok(val)
        }
        Ok(Err(err)) => finish_failed_savepoint(&name, conn, err, map_err),
        Err(panic_payload) => {
            // Clean up the savepoint BEFORE resuming the unwind so the
            // underlying connection doesn't retain a dangling savepoint.
            // Errors from the cleanup are intentionally swallowed — the
            // panic takes precedence and must propagate faithfully.
            let _ = conn.execute_batch(&format!("ROLLBACK TO SAVEPOINT \"{name}\""));
            let _ = conn.execute_batch(&format!("RELEASE SAVEPOINT \"{name}\""));
            resume_unwind(panic_payload);
        }
    }
}

fn finish_failed_savepoint<T, E>(
    name: &str,
    conn: &Connection,
    err: E,
    map_message: impl Fn(String) -> E,
) -> Result<T, E>
where
    E: std::fmt::Display,
{
    let rollback_result = conn.execute_batch(&format!("ROLLBACK TO SAVEPOINT \"{name}\""));
    let release_result = conn.execute_batch(&format!("RELEASE SAVEPOINT \"{name}\""));

    match (rollback_result, release_result) {
        (Ok(()), Ok(())) => Err(err),
        (Err(rollback_error), Ok(())) => Err(map_message(format!(
            "{err}; rollback failed: {rollback_error}"
        ))),
        (Ok(()), Err(release_error)) => Err(map_message(format!(
            "{err}; release failed: {release_error}"
        ))),
        (Err(rollback_error), Err(release_error)) => Err(map_message(format!(
            "{err}; rollback failed: {rollback_error}; release failed: {release_error}"
        ))),
    }
}

/// Execute `body` inside a uniquely-named `SAVEPOINT` and ALWAYS roll
/// back, regardless of whether the closure returns `Ok` or `Err`.
///
/// The dry-run pattern wants the savepoint to wrap a closure whose
/// SQL writes must be discarded but whose return value (typically a
/// JSON preview built from the in-savepoint state) must flow back to
/// the caller. The standard [`with_savepoint`] / [`with_savepoint_mapped`]
/// pair commit on `Ok` and roll back on `Err`, which is the wrong shape
/// here.
///
/// Panic-safety: a panic inside `f` rolls the savepoint back BEFORE the
/// unwind resumes, mirroring [`with_savepoint`]. Without this, a panic
/// would leave the savepoint dangling on the connection and the next
/// write would fail with "no such savepoint".
///
/// **Side-effect contract.** The savepoint covers SQL writes only. Any
/// non-SQLite state (process-wide statics, connection-bound thread
/// locals, allocator state) survives the rollback; callers that
/// invoke this helper for dry-run-style previews must keep their
/// closure mutations either inside SQLite or monotonic-only outside it.
pub fn with_savepoint_then_rollback<T, E>(
    conn: &Connection,
    prefix: &str,
    f: impl FnOnce(&Connection) -> Result<T, E>,
) -> Result<T, E>
where
    E: From<rusqlite::Error> + From<String> + std::fmt::Display,
{
    let id = SAVEPOINT_COUNTER.fetch_add(1, Ordering::Relaxed);
    let safe_prefix = assert_safe_savepoint_prefix(prefix).map_err(E::from)?;
    let name = format!("lvx_sp_{safe_prefix}_{id}");

    with_busy_retry(DEFAULT_RETRY_BUDGET, || {
        conn.execute_batch(&format!("SAVEPOINT \"{name}\""))
    })
    .map_err(E::from)?;

    let closure_result = catch_unwind(AssertUnwindSafe(|| f(conn)));

    // Whether the closure succeeded or failed, the savepoint MUST be
    // rolled back (dry-run never commits). On panic, rollback BEFORE
    // resuming the unwind so the connection isn't left dangling.
    match closure_result {
        Ok(result) => {
            // Best-effort rollback. If the caller's closure returned
            // `Ok`, surface a rollback error as a typed failure so the
            // dry-run never silently slips a commit through. If the
            // closure already returned `Err`, the original error wins;
            // rollback / release errors are appended as a `;` -joined
            // diagnostic suffix so the operator can correlate
            // dangling-frame symptoms with the original failure
            // (sibling `with_savepoint`'s `finish_failed_savepoint`
            // already appends `; rollback failed: …; release failed: …`).
            let rollback = conn.execute_batch(&format!("ROLLBACK TO SAVEPOINT \"{name}\""));
            let release = conn.execute_batch(&format!("RELEASE SAVEPOINT \"{name}\""));
            match (result, rollback, release) {
                (Ok(value), Ok(()), Ok(())) => Ok(value),
                (Ok(_), Err(rb), _) => Err(E::from(format!(
                    "with_savepoint_then_rollback rollback failed: {rb}"
                ))),
                (Ok(_), Ok(()), Err(rl)) => Err(E::from(format!(
                    // Rollback succeeded but RELEASE failed. Surface
                    // the failure rather than swallowing it and
                    // returning the closure's value: `ROLLBACK TO
                    // SAVEPOINT` does not pop the savepoint from
                    // SQLite's stack — only RELEASE does. A leaked
                    // savepoint corrupts the stack for the next
                    // nested savepoint on this connection, which can
                    // surface much later as a confusing "no such
                    // savepoint" or wrong-frame ROLLBACK at a
                    // completely unrelated call site.
                    "with_savepoint_then_rollback release failed: {rl}"
                ))),
                (Err(err), Ok(()), Ok(())) => Err(err),
                (Err(err), Err(rb), Ok(())) => {
                    Err(E::from(format!("{err}; rollback failed: {rb}")))
                }
                (Err(err), Ok(()), Err(rl)) => Err(E::from(format!("{err}; release failed: {rl}"))),
                (Err(err), Err(rb), Err(rl)) => Err(E::from(format!(
                    "{err}; rollback failed: {rb}; release failed: {rl}"
                ))),
            }
        }
        Err(panic_payload) => {
            let _ = conn.execute_batch(&format!("ROLLBACK TO SAVEPOINT \"{name}\""));
            let _ = conn.execute_batch(&format!("RELEASE SAVEPOINT \"{name}\""));
            resume_unwind(panic_payload);
        }
    }
}
