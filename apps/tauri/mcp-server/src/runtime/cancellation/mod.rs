//! Cooperative cancellation plumbing for long-running MCP tools.
//!
//! Context (#2133): MCP tool handlers on the stdio transport are
//! dispatched sequentially on a single task. A slow multi-query handler
//! (`analyze_task_patterns`, `propose_daily_schedule`,
//! `get_weekly_review_brief`, `export_all_data`, `import_data`) holds
//! the writer `Mutex` for its entire run. Even if the client sends
//! `notifications/cancelled`, the handler plows through to completion
//! — so the user's "Stop" button does nothing and the assistant client
//! reports a phantom hang until the watchdog (#2385) trips.
//!
//! rmcp populates `RequestContext::ct` with a
//! `tokio_util::sync::CancellationToken` that flips to `cancelled`
//! when the client's cancellation notification arrives. The
//! `FromContextPart` impl on `CancellationToken` lets tool handlers
//! receive the token as a direct parameter via the `#[tool]` macro.
//!
//! This module exposes a tiny helper — [`check_cancelled`] — that each
//! long tool calls at its logical step boundaries (before each
//! expensive SQL query, between bucket computations, etc.). When
//! cancellation has fired the helper returns
//! [`McpError::CancelledByClient`]; the tool's `with_conn` / read
//! transaction wrapper then unwinds, the `MutexGuard` for the writer
//! drops, and any open `BEGIN IMMEDIATE` rolls back — so no partial
//! commits survive the aborted call.
//!
//! Short single-query tools deliberately skip this plumbing: the token
//! check is only useful if there are yield points between the start of
//! the handler and the point where work actually completes. Adding it
//! to `get_overview` would bloat the tool surface with zero benefit
//! because the single `SELECT` finishes before the token can realistically
//! flip.

use crate::error::McpError;
use tokio_util::sync::CancellationToken;

/// Return `CancelledByClient` if the caller's cancellation token has
/// fired. The caller is responsible for placing these checks between
/// logical steps — SQLite's own execution is not interruptible from
/// outside the connection thread without the `progress_handler` hook,
/// which is a separate follow-up (see #2133 PR plan).
#[inline]
pub(crate) fn check_cancelled(ct: &CancellationToken) -> Result<(), McpError> {
    if ct.is_cancelled() {
        Err(McpError::CancelledByClient)
    } else {
        Ok(())
    }
}

#[cfg(test)]
mod tests;
