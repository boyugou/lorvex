//! Public API for read-only MCP server tool calls exposed to in-process
//! callers, chiefly `lorvex-cli`.
//!
//! Workflow writes be exposed here as JSON shims so the CLI could call
//! MCP handlers in-process. Those write paths now call typed `lorvex-workflow`
//! owners directly and keep boundary-specific audit/outbox projection in their
//! own crates. This module intentionally stays read/query-only.

use crate::contract::{
    AnalyzeTaskPatternsArgs, GetGuideArgs, GetHabitCompletionsArgs, GetRecentLogsArgs,
};
use crate::habits;
use crate::system::guidance;
use crate::system::logs;
use crate::system::overview;
use crate::system::session_context;
use rusqlite::Connection;
use serde_json::Value;
use tokio_util::sync::CancellationToken;

/// Convert any internal error into the `String` shape used at the rmcp
/// boundary. Callers (the CLI) wrap this back into `CliError::Internal`
/// or similar; the boundary keeps mcp-server's typed error tree private.
fn err_string(e: impl std::fmt::Display) -> String {
    e.to_string()
}

/// Deserialize typed contract args from a `serde_json::Value`.
fn parse_args<T: serde::de::DeserializeOwned>(args: Value) -> Result<T, String> {
    serde_json::from_value(args).map_err(|e| format!("invalid args: {e}"))
}

/// MCP `get_overview` — full dashboard snapshot.
pub fn get_overview(conn: &Connection) -> Result<String, String> {
    overview::get_overview(conn).map_err(err_string)
}

/// MCP `get_overview_compact` — compact dashboard snapshot.
pub fn get_overview_compact(conn: &Connection) -> Result<String, String> {
    overview::get_overview_compact(conn).map_err(err_string)
}

/// MCP `get_session_context` — bounded all-in-one session snapshot.
pub fn get_session_context(conn: &Connection) -> Result<String, String> {
    session_context::get_session_context(conn).map_err(err_string)
}

/// MCP `get_guide` — contextual guidance for the current state.
pub fn get_guide(conn: &Connection, args: Value) -> Result<String, String> {
    let args: GetGuideArgs = parse_args(args)?;
    guidance::get_guide(conn, &args).map_err(err_string)
}

/// MCP `get_recent_logs` — merged error_log + ai_changelog + sync_outbox view.
pub fn get_recent_logs(conn: &Connection, args: Value) -> Result<String, String> {
    let args: GetRecentLogsArgs = parse_args(args)?;
    logs::get_recent_logs(conn, args).map_err(err_string)
}

/// MCP `analyze_task_patterns` — bounded analytics over the trailing window.
/// Cancellation token defaults to a fresh, never-cancelled token when called
/// from the CLI; the MCP path threads its real one.
pub fn analyze_task_patterns(conn: &Connection, args: Value) -> Result<String, String> {
    let args: AnalyzeTaskPatternsArgs = parse_args(args)?;
    let ct = CancellationToken::new();
    guidance::analyze_task_patterns(conn, &args, &ct).map_err(err_string)
}

/// MCP `get_habit_completions` — per-day completion timeline for a habit.
pub fn get_habit_completions(conn: &Connection, args: Value) -> Result<String, String> {
    let args: GetHabitCompletionsArgs = parse_args(args)?;
    let habit_id = lorvex_domain::HabitId::from_trusted(args.id);
    habits::get_habit_completions(conn, &habit_id, args.days).map_err(err_string)
}
