//! Read-aggregation / workflow / introspection arms — the MCP
//! orchestration helpers (`get_overview`, `get_session_context`,
//! `get_guide`, `get_recent_logs`, `analyze_task_patterns`,
//! `reorganize_list`, `get_habit_completions`).

use super::OutputFormat;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum WorkflowCommand {
    /// MCP `get_overview` / `get_overview_compact` mirror.
    Overview { compact: bool, format: OutputFormat },
    /// MCP `get_session_context` mirror.
    SessionContext { format: OutputFormat },
    /// MCP `get_guide` mirror.
    Guide {
        topic: Option<&'static str>,
        format: OutputFormat,
    },
    /// MCP `get_recent_logs` mirror — full merged view.
    RecentLogs {
        limit: Option<u32>,
        since: Option<String>,
        levels: Vec<String>,
        sources: Vec<String>,
        include_details: bool,
        redact: bool,
        format: OutputFormat,
    },
    /// MCP `analyze_task_patterns` mirror.
    Analyze {
        window_days: Option<u32>,
        top_n: Option<u32>,
        format: OutputFormat,
    },
    /// MCP `reorganize_list` mirror.
    Reorganize {
        list_id: String,
        strategy: &'static str,
        task_ids: Vec<String>,
        dry_run: bool,
        format: OutputFormat,
    },
    /// MCP `get_habit_completions` mirror.
    HabitCompletions {
        habit_id: String,
        days: Option<u32>,
        format: OutputFormat,
    },
}
