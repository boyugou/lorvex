//! Per-tool watchdog timeout for the MCP stdio server.
//!
//! Context (#2385): the rmcp stdio transport dispatches tool calls
//! sequentially on a single task. A tool handler that blocks
//! indefinitely — a slow query, a deadlocked writer mutex, a network
//! stall — also blocks every subsequent MCP request, so the assistant
//! client times out and the user sees a hung session. Equally bad,
//! the handler still holds any resources (writer mutex, pool guards)
//! it acquired, so cancelling the client-side RPC can't free them.
//!
//! The watchdog here is a soft timeout wrapping each tool handler's
//! future. On expiry it returns an `ErrorData::internal_error` naming
//! the tool and elapsed seconds, so the stdio transport is free to
//! serve the next request. This does NOT cancel the underlying
//! handler future — that's tracked separately in #2133
//! (cooperative cancellation + SQLite progress handlers). The handler
//! may therefore continue to completion in the background; any work
//! it has committed stays committed, matching the behaviour of a
//! crashed or disconnected client.
//!
//! The timeout is configurable via the `LORVEX_MCP_TOOL_TIMEOUT_SECS`
//! environment variable, primarily for debugging (a developer
//! stepping through a slow handler in a debugger wants a much larger
//! window than 30s). Parse failure, zero, or absence fall back to
//! [`DEFAULT_MCP_TOOL_TIMEOUT_SECS`].

use std::future::Future;
use std::time::Duration;

use rmcp::{model::CallToolResult, ErrorData};
use tokio_util::sync::CancellationToken;

tokio::task_local! {
    /// Watchdog cancellation token for the currently-executing tool
    /// handler future. `run_with_timeout` enters this scope before
    /// awaiting the handler so deeper layers (notably the async
    /// connection helpers in `server::connections_async`) can clone it
    /// into their `spawn_blocking` closure and abort to ROLLBACK
    /// instead of COMMITting a transaction the client has already
    /// stopped waiting for. See #3302 for the duplicate-write race
    /// this prevents.
    pub(crate) static WATCHDOG_TOKEN: CancellationToken;
}

/// Best-effort access to the in-scope watchdog token. Returns `None`
/// when called outside `run_with_timeout` (e.g., from tests or from a
/// path that bypasses the rmcp dispatch wrapper). Helpers that observe
/// `None` should fall back to running uncancellably — the worst-case
/// regression.
pub(crate) fn current_watchdog_token() -> Option<CancellationToken> {
    WATCHDOG_TOKEN.try_with(CancellationToken::clone).ok()
}

/// Default soft timeout applied to every MCP tool handler.
pub const DEFAULT_MCP_TOOL_TIMEOUT_SECS: u64 = 30;

/// Environment variable that overrides [`DEFAULT_MCP_TOOL_TIMEOUT_SECS`].
const MCP_TOOL_TIMEOUT_ENV: &str = "LORVEX_MCP_TOOL_TIMEOUT_SECS";

/// Resolve the per-tool watchdog timeout from `LORVEX_MCP_TOOL_TIMEOUT_SECS`.
///
/// Thin wrapper around [`parse_tool_timeout`] that reads the env var
/// once at server-start time. The split lets tests exercise every
/// parsing branch without `unsafe { std::env::set_var(..) }` — env
/// mutation is racey under `cargo test`'s default parallelism (Rust
/// 2024 made the setter `unsafe` for exactly that reason). See
/// H1.
pub fn resolve_tool_timeout() -> Duration {
    parse_tool_timeout(std::env::var(MCP_TOOL_TIMEOUT_ENV).ok().as_deref())
}

/// Parse a watchdog-timeout value out of an optional raw env-var string.
///
/// Branch table:
///   * `None` (var unset) → default
///   * `Some("")` / whitespace-only → default
///   * `Some("0")` → default + warning
///   * `Some(<u64>)` → that many seconds
///   * `Some(<garbage>)` (parse failure) → default + warning
///
/// Warnings go through structured tracing so operators running the
/// MCP server from a launchd / systemd job get parseable diagnostics
/// instead of silently getting the default.
pub fn parse_tool_timeout(raw: Option<&str>) -> Duration {
    let Some(raw) = raw else {
        return Duration::from_secs(DEFAULT_MCP_TOOL_TIMEOUT_SECS);
    };
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Duration::from_secs(DEFAULT_MCP_TOOL_TIMEOUT_SECS);
    }
    match trimmed.parse::<u64>() {
        Ok(0) => {
            tracing::warn!(
                env_var = MCP_TOOL_TIMEOUT_ENV,
                default_secs = DEFAULT_MCP_TOOL_TIMEOUT_SECS,
                "MCP tool timeout override was zero; using default"
            );
            Duration::from_secs(DEFAULT_MCP_TOOL_TIMEOUT_SECS)
        }
        Ok(secs) => Duration::from_secs(secs),
        Err(err) => {
            tracing::warn!(
                env_var = MCP_TOOL_TIMEOUT_ENV,
                raw = %lorvex_domain::diagnostics::redact_diagnostic_text(raw),
                error = %err,
                default_secs = DEFAULT_MCP_TOOL_TIMEOUT_SECS,
                "MCP tool timeout override was invalid; using default"
            );
            Duration::from_secs(DEFAULT_MCP_TOOL_TIMEOUT_SECS)
        }
    }
}

/// Wrap `handler` in a soft timeout. On expiry, return an
/// `ErrorData::internal_error` naming the tool and elapsed seconds.
///
/// The handler future is dropped on timeout, but the rusqlite work it
/// kicked off via `tokio::task::spawn_blocking` cannot be cancelled by
/// dropping the future — the blocking thread runs to its own
/// completion.
/// `COMMIT;` after the watchdog had already returned the error, which
/// meant a client retry under the same `idempotency_key` (the cached
/// row not yet visible) re-executed the write and produced duplicate
/// audit/outbox/tag rows.
///
/// To close that race we publish a [`CancellationToken`] in the
/// `WATCHDOG_TOKEN` task-local for the duration of the handler future,
/// and signal `cancel()` on it before we return the timeout error. The
/// async connection helpers in `server::connections_async` clone this
/// token into their spawn_blocking closure; the synchronous
/// `with_conn_cancellable` helper checks it after the user closure
/// succeeds and routes a cancelled run to ROLLBACK instead of COMMIT.
/// A retry then sees no committed state from the prior attempt — same
/// outcome as a crashed handler — and the second invocation is the
/// only one that lands.
pub async fn run_with_timeout<F>(
    tool_name: &str,
    timeout: Duration,
    handler: F,
) -> Result<CallToolResult, ErrorData>
where
    F: Future<Output = Result<CallToolResult, ErrorData>>,
{
    let token = CancellationToken::new();
    let scoped = WATCHDOG_TOKEN.scope(token.clone(), handler);
    tokio::time::timeout(timeout, scoped).await.unwrap_or_else(|_| {
        // Cancel BEFORE returning so any in-flight blocking task that
        // observes the token at its pre-COMMIT checkpoint will roll
        // back. Cancellation is racy by nature — a thread already past
        // the checkpoint will commit anyway — but the window where a
        // client retry can land between cancel + COMMIT is now bounded
        // by the SQLite COMMIT latency rather than the entire handler
        // duration.
        token.cancel();
        let elapsed = timeout.as_secs();
        let message = format!(
            "tool {tool_name:?} exceeded watchdog timeout of {elapsed}s; partial work may have been committed"
        );
        tracing::warn!(
            tool_name,
            elapsed_secs = elapsed,
            "MCP tool watchdog timeout elapsed"
        );
        Err(ErrorData::internal_error(message, None))
    })
}

#[cfg(test)]
mod tests;
