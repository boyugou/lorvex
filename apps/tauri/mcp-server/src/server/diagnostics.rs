//! Persisted diagnostics for the MCP server runtime + startup paths.
//!
//! These helpers funnel into `lorvex_store::error_log::append_error_log_best_effort`
//! so every `mcp.runtime.*` and `mcp.startup.*` warning/info row hits
//! `error_logs` with a uniform shape. They are file-private free
//! functions (not methods) because they're called from both the
//! `LorvexMcpServer` impls (connection helpers) and the sibling
//! `startup` module's per-step closures, which run before the
//! `LorvexMcpServer` value exists.
//!
//! Re-exported as `super::record_runtime_warning` /
//! `super::record_diagnostic` from `server/mod.rs` so `server/startup.rs`
//! and `server/tests/mod.rs` can resolve them via `super::*` and
//! `super::record_*` without knowing this submodule exists.

use rusqlite::Connection;

pub(super) fn record_runtime_warning(
    conn: &Connection,
    source: &str,
    message: &str,
    details: &str,
) {
    record_diagnostic(conn, source, message, details, "warn");
}

pub(super) fn record_diagnostic(
    conn: &Connection,
    source: &str,
    message: &str,
    details: &str,
    level: &str,
) {
    lorvex_store::error_log::append_error_log_best_effort(
        conn,
        source,
        message,
        Some(details),
        Some(level),
    );
}
