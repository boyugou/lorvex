//! Read-path workflow tools — overview, session_context, guide,
//! recent_logs, analyze_task_patterns, and habit_completions.
//!
//! These helpers do not pass through `render_mutation_envelope`; they
//! emit the same envelope-less JSON shape that an MCP client receives,
//! with `db_path` + `action` prepended for downstream `jq` consumers.

use lorvex_mcp_server::public_api;
use lorvex_runtime::resolve_db_path;
use serde_json::{json, Value};

use crate::cli::OutputFormat;
use crate::error::CliError;
use crate::startup_maintenance::open_db_at_path;

use super::{map_public_api_error, render_query_response};

pub(crate) fn run_overview(compact: bool, format: OutputFormat) -> Result<String, CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let raw = if compact {
        public_api::get_overview_compact(&conn).map_err(map_public_api_error)?
    } else {
        public_api::get_overview(&conn).map_err(map_public_api_error)?
    };
    let action = if compact {
        "workflow.overview_compact"
    } else {
        "workflow.overview"
    };
    render_query_response(action, &db_path, raw, format)
}

pub(crate) fn run_session_context(format: OutputFormat) -> Result<String, CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let raw = public_api::get_session_context(&conn).map_err(map_public_api_error)?;
    render_query_response("workflow.session_context", &db_path, raw, format)
}

pub(crate) fn run_guide(
    topic: Option<&'static str>,
    format: OutputFormat,
) -> Result<String, CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let args = topic.map_or_else(|| json!({}), |t| json!({ "topic": t }));
    let raw = public_api::get_guide(&conn, args).map_err(map_public_api_error)?;
    render_query_response("workflow.guide", &db_path, raw, format)
}

pub(crate) fn run_recent_logs(
    limit: Option<u32>,
    since: Option<&str>,
    levels: &[String],
    sources: &[String],
    include_details: bool,
    redact: bool,
    format: OutputFormat,
) -> Result<String, CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let mut args = serde_json::Map::new();
    if let Some(value) = limit {
        args.insert("limit".to_string(), json!(value));
    }
    if let Some(value) = since {
        args.insert("since".to_string(), json!(value));
    }
    if !levels.is_empty() {
        args.insert("levels".to_string(), json!(levels));
    }
    // The MCP contract uses snake_case for the source enum
    // (`error_log`, `ai_changelog`, `sync_outbox`); pass through
    // verbatim so a typo surfaces as a clean public_api parse error.
    if !sources.is_empty() {
        args.insert("sources".to_string(), json!(sources));
    }
    args.insert("include_details".to_string(), json!(include_details));
    args.insert("redact".to_string(), json!(redact));
    let raw =
        public_api::get_recent_logs(&conn, Value::Object(args)).map_err(map_public_api_error)?;
    render_query_response("workflow.recent_logs", &db_path, raw, format)
}

pub(crate) fn run_analyze(
    window_days: Option<u32>,
    top_n: Option<u32>,
    format: OutputFormat,
) -> Result<String, CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let mut args = serde_json::Map::new();
    if let Some(value) = window_days {
        args.insert("window_days".to_string(), json!(value));
    }
    if let Some(value) = top_n {
        args.insert("top_n".to_string(), json!(value));
    }
    let raw = public_api::analyze_task_patterns(&conn, Value::Object(args))
        .map_err(map_public_api_error)?;
    render_query_response("workflow.analyze_task_patterns", &db_path, raw, format)
}

pub(crate) fn run_habit_completions(
    habit_id: &str,
    days: Option<u32>,
    format: OutputFormat,
) -> Result<String, CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let mut args = serde_json::Map::new();
    args.insert("id".to_string(), json!(habit_id));
    if let Some(value) = days {
        args.insert("days".to_string(), json!(value));
    }
    let raw = public_api::get_habit_completions(&conn, Value::Object(args))
        .map_err(map_public_api_error)?;
    render_query_response("workflow.habit_completions", &db_path, raw, format)
}
