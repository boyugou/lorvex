//! Async blocking-pool wrappers for the connection helpers (#2177).
//!
//! rmcp's tool dispatcher `tokio::spawn`s every incoming call, so a
//! synchronous `with_conn` runs `rusqlite` I/O directly on a tokio
//! worker. Under concurrent fan-out (session-context bundles, parallel
//! reads on the round-robin read pool, batch tool calls) a long
//! handler — FTS5 aggregation, weekly review, export — can starve the
//! runtime, stalling the watchdog and every other in-flight future on
//! that worker.
//!
//! The async wrappers below route through `tokio::task::spawn_blocking`
//! so rusqlite lives on the blocking thread pool (default 512 threads)
//! while the reactor stays responsive. They're additive: the
//! synchronous helpers in `connections.rs` stay intact for fast
//! handlers where the context-switch overhead would exceed the
//! benefit. A `JoinError` from the blocking pool (panic / runtime
//! shutdown) surfaces as `McpError::Internal` so the structured error
//! boundary stays uniform.

use rusqlite::Connection;

use super::LorvexMcpServer;
use crate::runtime::tool_timeout::current_watchdog_token;

impl LorvexMcpServer {
    /// Async variant of `with_conn` that dispatches the blocking
    /// rusqlite closure onto the tokio blocking pool.
    pub(crate) async fn with_conn_async<F, T>(&self, f: F) -> Result<T, String>
    where
        F: FnOnce(&Connection) -> Result<T, String> + Send + 'static,
        T: Send + 'static,
    {
        let this = self.clone();
        let in_flight_guard = self.in_flight.enter();
        // #3302: snapshot the watchdog token *before* spawn_blocking
        // so the blocking thread can check it right before COMMIT and
        // route to ROLLBACK on a timeout. Reading task-local from
        // inside `spawn_blocking` would return `None` because
        // task-local context does not propagate across the blocking
        // boundary.
        let cancel = current_watchdog_token();
        match tokio::task::spawn_blocking(move || {
            let _guard = in_flight_guard;
            this.with_conn_cancellable(cancel, f)
        })
        .await
        {
            Ok(result) => result,
            Err(join_err) => Err(String::from(crate::error::McpError::Internal(format!(
                "blocking task join failed: {join_err}"
            )))),
        }
    }

    /// Async variant of `with_conn_typed`.
    pub(crate) async fn with_conn_typed_async<F, T>(&self, f: F) -> Result<T, String>
    where
        F: FnOnce(&Connection) -> Result<T, crate::error::McpError> + Send + 'static,
        T: Send + 'static,
    {
        self.with_conn_async(|conn| f(conn).map_err(String::from))
            .await
    }

    /// Async variant of `with_writer_no_savepoint`.
    pub(crate) async fn with_writer_no_savepoint_async<F, T>(&self, f: F) -> Result<T, String>
    where
        F: FnOnce(&Connection) -> Result<T, String> + Send + 'static,
        T: Send + 'static,
    {
        let this = self.clone();
        let in_flight_guard = self.in_flight.enter();
        // #3302: same watchdog-snapshot rationale as `with_conn_async`.
        // The closure here owns its own transaction frame, so we can
        // only short-circuit BEFORE entering it; closures that need
        // mid-tx cancellation should consult
        // `current_watchdog_token()` directly.
        let cancel = current_watchdog_token();
        match tokio::task::spawn_blocking(move || {
            let _guard = in_flight_guard;
            this.with_writer_no_savepoint_cancellable(cancel, f)
        })
        .await
        {
            Ok(result) => result,
            Err(join_err) => Err(String::from(crate::error::McpError::Internal(format!(
                "blocking task join failed: {join_err}"
            )))),
        }
    }

    /// Async variant of `with_read_conn`.
    pub(crate) async fn with_read_conn_async<F, T>(&self, f: F) -> Result<T, String>
    where
        F: FnOnce(&Connection) -> Result<T, String> + Send + 'static,
        T: Send + 'static,
    {
        let this = self.clone();
        let in_flight_guard = self.in_flight.enter();
        match tokio::task::spawn_blocking(move || {
            let _guard = in_flight_guard;
            this.with_read_conn(f)
        })
        .await
        {
            Ok(result) => result,
            Err(join_err) => Err(String::from(crate::error::McpError::Internal(format!(
                "blocking task join failed: {join_err}"
            )))),
        }
    }

    /// Async variant of `with_read_conn_typed`.
    pub(crate) async fn with_read_conn_typed_async<F, T>(&self, f: F) -> Result<T, String>
    where
        F: FnOnce(&Connection) -> Result<T, crate::error::McpError> + Send + 'static,
        T: Send + 'static,
    {
        self.with_read_conn_async(|conn| f(conn).map_err(String::from))
            .await
    }
}
