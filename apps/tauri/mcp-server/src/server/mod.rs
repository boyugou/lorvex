//! `LorvexMcpServer` — the rmcp `ServerHandler` implementation.
//!
//! This module is a thin hub: the struct definition + read-pool
//! constant live here, and per-concern siblings own the bulk of the
//! impl surface so each file stays focused on a single axis.
//!
//! | sibling                     | concern                                   |
//! |-----------------------------|-------------------------------------------|
//! | `startup`                   | per-step constructor maintenance helpers  |
//! | `construction`              | `LorvexMcpServer::new` + small accessors  |
//! | `connections`               | sync `with_*` connection helpers          |
//! | `connections_async`         | async wrappers (`*_async`) for the above  |
//! | `dry_run`                   | `dispatch_dry_run` (preview-vs-commit)    |
//! | `diagnostics`               | `record_runtime_warning` + `_diagnostic`  |
//! | `handler`                   | `impl ServerHandler` (rmcp transport)     |
//! | `tests`                     | `#[cfg(test)]` integration tests          |
//!
//! The aggregated `tool_router` is built in `construction::new` from
//! the individual `*_tool_router()` factories owned by the domain router
//! modules, for example `tasks/router.rs` and `workflow/router/`.

use std::sync::Arc;
use std::time::Duration;

use lorvex_store::ConnectionPool;
use rmcp::handler::server::router::tool::ToolRouter;

use crate::shutdown::InFlightTracker;

mod connections;
mod connections_async;
mod construction;
mod diagnostics;
mod dry_run;
mod handler;
mod startup;
pub(crate) mod tool_macros;

// Re-export the diagnostic free functions so siblings (`startup.rs`)
// and `tests/mod.rs` (which does `use super::*`) can resolve them via
// `super::record_*` without depending on the `diagnostics` submodule
// path. They were file-private free functions in the pre-split
// `server.rs`; preserving the resolved path keeps every existing
// `super::record_diagnostic` call site valid.
use diagnostics::{record_diagnostic, record_runtime_warning};

// The test tree (`tests/mod.rs::pub(super) use super::*`) inherits
// our scope, so any identifier the test files reference unqualified
// must be in scope HERE. Anchored `#[cfg(test)]` re-exports keep the
// pre-split bare names (`to_error_message`, `today_ymd_local_for_test`)
// resolving the same way they did when `server.rs` was a single file.
#[cfg(test)]
#[allow(unused_imports)]
use crate::system::handler_support::to_error_message;
#[cfg(test)]
#[allow(unused_imports)]
use crate::time::today_ymd_local_for_test;

/// renamed from `READ_POOL_SIZE` (which collided
/// with the same identifier in `app/src-tauri/src/db/connection.rs`,
/// where it had a different value of 4) to make the per-surface
/// rationale searchable. The MCP server caps reader cardinality at
/// the assistant's tool-call fan-out (no concurrent SELECTs beyond
/// the in-flight + queued tool); the desktop app pools four because
/// the renderer can fan out across multiple panel queries.
///
/// #3053 M13: bumped from 2 → 3 because future MCP fan-outs that
/// run `get_changelog` + `get_overview` + `list_tasks` in
/// parallel were hitting the pool-mutex boundary at exactly the
/// in-flight cardinality, serializing the third reader behind the
/// first. Three slots covers the fan-out without leaving idle
/// connections holding fds; the desktop app's four-slot pool is the
/// next-step ceiling and is sized for renderer parallelism that the
/// MCP server never sees.
const MCP_READ_POOL_SIZE: usize = 3;

#[derive(Debug, Clone)]
pub struct LorvexMcpServer {
    pool: Arc<ConnectionPool>,
    tool_router: ToolRouter<Self>,
    /// Per-tool watchdog timeout (#2385). Resolved once at
    /// construction from `LORVEX_MCP_TOOL_TIMEOUT_SECS`, so env
    /// changes require a server restart — which is fine, the stdio
    /// MCP server is a short-lived child of the assistant anyway.
    tool_timeout: Duration,
    in_flight: InFlightTracker,
}

#[cfg(test)]
mod tests;
