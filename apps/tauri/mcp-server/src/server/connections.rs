//! Synchronous pool-connection helpers on `LorvexMcpServer`.
//!
//! `with_writer_no_savepoint` / `with_conn` / `with_conn_typed` /
//! `with_read_conn` / `with_read_conn_typed` form the closed set of
//! sync entry points that handlers use to acquire a `rusqlite::Connection`.
//! Async variants (`*_async`) live in `server/connections_async.rs`
//! and dispatch through `tokio::task::spawn_blocking` so the rmcp
//! reactor isn't starved by long-running rusqlite work.
//!
//! `with_conn` is the primary write path: it wraps the closure in a
//! `BEGIN IMMEDIATE` transaction (with busy-retry) plus a named
//! savepoint (`mcp_tool`) and routes any failure through
//! `record_runtime_warning` so the diagnostic surface always carries
//! a breadcrumb. The lengthy doc comments inline below predate this
//! split and are preserved verbatim — they justify each piece of the
//! transaction frame against the original SQLITE_BUSY / poisoned-mutex
//! incident reports.

use std::cell::RefCell;

use rusqlite::Connection;
use tokio_util::sync::CancellationToken;

use super::{record_runtime_warning, LorvexMcpServer};
use crate::system::handler_support::to_error_message;

/// Sentinel error message returned by [`LorvexMcpServer::with_conn_cancellable`]
/// when the watchdog token fired between the closure completing and
/// the COMMIT being issued. Callers (the async wrapper layer) match on
/// this to log the watchdog rollback distinctly from a closure-thrown
/// error, but the handler future itself has already been dropped by
/// the time this value would surface — so the string is purely a
/// breadcrumb in the diagnostic trail, not a wire-format value.
const WATCHDOG_CANCELLED_SENTINEL: &str =
    "Error: tool was cancelled by watchdog timeout; transaction rolled back.";

impl LorvexMcpServer {
    /// Get the writer connection WITHOUT a savepoint wrapper.
    /// Use when the closure manages its own transaction (e.g., import_from_zip).
    ///
    /// Production callers go through `with_writer_no_savepoint_async`,
    /// which itself calls the cancellable variant. This sync wrapper
    /// remains for tests in the `server::tests` tree that need raw
    /// writer access without a transaction frame.
    #[cfg_attr(not(test), allow(dead_code))]
    pub(crate) fn with_writer_no_savepoint<T>(
        &self,
        f: impl FnOnce(&Connection) -> Result<T, String>,
    ) -> Result<T, String> {
        self.with_writer_no_savepoint_cancellable(None, f)
    }

    /// Cancellation-aware variant of [`with_writer_no_savepoint`].
    ///
    /// The closure manages its own transaction (e.g. `import_from_zip`),
    /// so the only thing we can do at this layer is short-circuit
    /// BEFORE handing control to the closure when the watchdog has
    /// already fired. Closures that want a finer cancellation grain
    /// must thread the token in via their own argument list — which
    /// they can fetch from
    /// `crate::runtime::tool_timeout::current_watchdog_token()`. See
    /// #3302.
    pub(crate) fn with_writer_no_savepoint_cancellable<T>(
        &self,
        cancel: Option<CancellationToken>,
        f: impl FnOnce(&Connection) -> Result<T, String>,
    ) -> Result<T, String> {
        if let Some(token) = cancel.as_ref() {
            if token.is_cancelled() {
                return Err(WATCHDOG_CANCELLED_SENTINEL.to_string());
            }
        }
        let guard = self.pool.writer_result().map_err(|e| {
            // poisoned writer: the previous holder
            // panicked. Without a breadcrumb the diagnostic surface had
            // no record of WHY the writer mutex died. Log to tracing
            // before returning the user-facing string. (We can't reach
            // a connection to call `record_runtime_warning` because
            // that's exactly what just failed; tracing is the only
            // reachable sink here.)
            tracing::error!(
                target = "mcp.runtime.writer_pool_poisoned",
                error = %e,
                "writer connection pool returned a poisoned guard; the previous holder panicked",
            );
            "Error: an internal error occurred. Please try again or report a bug.".to_string()
        })?;
        f(&guard)
    }

    pub(crate) fn with_conn<T>(
        &self,
        f: impl FnOnce(&Connection) -> Result<T, String>,
    ) -> Result<T, String> {
        self.with_conn_cancellable(None, f)
    }

    /// Cancellation-aware variant of [`with_conn`]. The async wrapper
    /// layer (`server::connections_async`) clones the watchdog
    /// `CancellationToken` published by `run_with_timeout` and passes
    /// it down through this helper. After the user closure completes
    /// successfully we re-check the token; if cancellation fired we
    /// route to ROLLBACK instead of COMMIT, so a watchdog-killed
    /// handler does not silently land its in-flight transaction once
    /// the client has already retried under the same idempotency key.
    /// See #3302 for the duplicate-write race this closes.
    pub(crate) fn with_conn_cancellable<T>(
        &self,
        cancel: Option<CancellationToken>,
        f: impl FnOnce(&Connection) -> Result<T, String>,
    ) -> Result<T, String> {
        let guard = self.pool.writer_result().map_err(|e| {
            // see `with_writer_no_savepoint` — same
            // poisoned-writer breadcrumb so the diagnostic isn't
            // silently swallowed.
            tracing::error!(
                target = "mcp.runtime.writer_pool_poisoned",
                error = %e,
                "writer connection pool returned a poisoned guard; the previous holder panicked",
            );
            "Error: an internal error occurred. Please try again or report a bug.".to_string()
        })?;
        // wrapped only in `with_savepoint_mapped`,
        // which created a SAVEPOINT on a connection with no outer
        // BEGIN IMMEDIATE — SQLite promoted it into a deferred
        // transaction that only acquired the write lock at the first
        // write statement. If any future second-writer path
        // (background compactor, CLI driven while MCP is in-flight)
        // contends with the MCP write mid-sequence, SQLITE_BUSY
        // could surface after partial rows committed to the savepoint
        // frame. Wrap in an explicit BEGIN IMMEDIATE so the lock is
        // acquired up-front and contention surfaces on entry.
        //
        // The helper `with_immediate_transaction` requires
        // `E: From<rusqlite::Error>`, which `String` doesn't
        // implement, so inline the same BEGIN/COMMIT/ROLLBACK pattern
        // with String-based error mapping.
        //
        // route the BEGIN IMMEDIATE through
        // `with_busy_retry` so cross-process contention (app + MCP
        // sibling racing for the writer lock) is retried with jitter
        // instead of surfacing as an opaque `SQLITE_BUSY` to the tool
        // caller. `with_busy_retry` classifies `DatabaseBusy` /
        // `DatabaseLocked` as retryable and surfaces every other
        // rusqlite error immediately — so the existing error mapping
        // behavior is preserved.
        if let Err(e) = lorvex_store::with_busy_retry(lorvex_store::DEFAULT_RETRY_BUDGET, || {
            guard.execute_batch("BEGIN IMMEDIATE;")
        }) {
            record_runtime_warning(
                &guard,
                "mcp.runtime.transaction_begin_failed",
                "MCP tool transaction BEGIN IMMEDIATE failed",
                &e.to_string(),
            );
            return Err(to_error_message(e.to_string()));
        }
        let savepoint_error_detail = RefCell::new(None);
        let inner = lorvex_store::with_savepoint_mapped(
            &guard,
            "mcp_tool",
            |message| {
                *savepoint_error_detail.borrow_mut() = Some(message.clone());
                to_error_message(message)
            },
            f,
        );
        match inner {
            Ok(value) => {
                // #3302: if the per-tool watchdog fired while the
                // user closure was still on the blocking thread, the
                // tokio future driving this task has already been
                // dropped and the client has already received an
                // `internal_error("watchdog timeout")`. Issuing
                // COMMIT here would make those writes visible after
                // the client retried, producing duplicate audit /
                // outbox / tag rows. Roll back instead and surface a
                // sentinel so the async wrapper layer logs the
                // distinction.
                if let Some(token) = cancel.as_ref() {
                    if token.is_cancelled() {
                        let rollback_error = guard.execute_batch("ROLLBACK;").err();
                        record_runtime_warning(
                            &guard,
                            "mcp.runtime.watchdog_cancelled_rollback",
                            "MCP tool watchdog fired before COMMIT; transaction rolled back",
                            "watchdog cancellation token observed before COMMIT",
                        );
                        if let Some(rb) = rollback_error {
                            record_runtime_warning(
                                &guard,
                                "mcp.runtime.transaction_rollback_failed",
                                "MCP tool transaction ROLLBACK failed after watchdog cancellation",
                                &rb.to_string(),
                            );
                        }
                        return Err(WATCHDOG_CANCELLED_SENTINEL.to_string());
                    }
                }
                if let Err(e) = guard.execute_batch("COMMIT;") {
                    let commit_error = e.to_string();
                    let rollback_error = guard.execute_batch("ROLLBACK;").err();
                    record_runtime_warning(
                        &guard,
                        "mcp.runtime.transaction_commit_failed",
                        "MCP tool transaction COMMIT failed",
                        &commit_error,
                    );
                    if let Some(rb) = rollback_error {
                        record_runtime_warning(
                            &guard,
                            "mcp.runtime.transaction_rollback_failed",
                            "MCP tool transaction ROLLBACK failed after COMMIT failure",
                            &rb.to_string(),
                        );
                    }
                    return Err(to_error_message(format!("commit failed: {e}")));
                }
                Ok(value)
            }
            Err(err) => {
                let rollback_error = guard.execute_batch("ROLLBACK;").err();
                if let Some(detail) = savepoint_error_detail.into_inner() {
                    record_runtime_warning(
                        &guard,
                        "mcp.runtime.transaction_savepoint_failed",
                        "MCP tool savepoint failed",
                        &detail,
                    );
                }
                if let Some(rb) = rollback_error {
                    record_runtime_warning(
                        &guard,
                        "mcp.runtime.transaction_rollback_failed",
                        "MCP tool transaction ROLLBACK failed after error",
                        &rb.to_string(),
                    );
                }
                Err(err)
            }
        }
    }

    /// Like `with_conn` but accepts closures returning `McpError`.
    pub(crate) fn with_conn_typed<T>(
        &self,
        f: impl FnOnce(&Connection) -> Result<T, crate::error::McpError>,
    ) -> Result<T, String> {
        self.with_conn(|conn| f(conn).map_err(String::from))
    }

    /// Execute a read-only query on a pooled read connection (round-robin).
    ///
    /// Read connections are opened with `SQLITE_OPEN_READ_ONLY` and do not
    /// use savepoints. WAL mode allows these reads to proceed concurrently
    /// with writes on the main writer connection.
    pub(crate) fn with_read_conn<T>(
        &self,
        f: impl FnOnce(&Connection) -> Result<T, String>,
    ) -> Result<T, String> {
        let arc = self.pool.read();
        let guard = arc.lock().map_err(|e| {
            // poisoned reader: same rationale as the
            // writer paths above. The reader Mutex sits in front of
            // every read connection in the pool; if it poisons we
            // need a breadcrumb so a recurring offender (a reader
            // that paniced mid-row-mapper) can be diagnosed instead
            // of vanishing into the generic user-facing string.
            tracing::error!(
                target = "mcp.runtime.reader_pool_poisoned",
                error = %e,
                "reader connection pool mutex was poisoned; the previous holder panicked",
            );
            "Error: an internal error occurred. Please try again or report a bug.".to_string()
        })?;
        f(&guard)
    }

    /// Like `with_read_conn` but accepts closures returning `McpError`.
    pub(crate) fn with_read_conn_typed<T>(
        &self,
        f: impl FnOnce(&Connection) -> Result<T, crate::error::McpError>,
    ) -> Result<T, String> {
        self.with_read_conn(|conn| f(conn).map_err(String::from))
    }
}
