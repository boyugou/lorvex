//! Shared widget structs reused across multiple subcommand groups
//! (`LimitArgs`, `PathArgs`, `TuiArgs`, `McpCmd`,
//! `TaskFreeTextArgs`, `RecurrenceExceptionCmd`, `RecurrenceExceptionArgs`,
//! `ErrorLogsArgs`, `SetupCompleteArgs`).

use clap::{Args, Subcommand};

use super::super::command::McpInstallTarget;
use super::super::parsers::{parse_positive_u32, parse_task_id};

// --- shared flag groups ---------------------------------------------------

#[derive(Args, Debug)]
pub(in crate::cli) struct LimitArgs {
    /// Maximum number of rows to return.
    #[arg(short = 'l', long = "limit", default_value_t = 20, value_parser = parse_positive_u32)]
    pub(in crate::cli) limit: u32,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct PathArgs {
    /// Zip archive path.
    pub(in crate::cli) path: String,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct TuiArgs {
    /// Live-updating dashboard (redraws on every DB mutation).
    #[arg(long = "watch")]
    pub(in crate::cli) watch: bool,
}

#[derive(Subcommand, Debug)]
pub(in crate::cli) enum McpCmd {
    /// Start the stdio MCP server (blocking).
    Serve,
    /// Install MCP config for one or more clients.
    Install {
        /// Which client(s) to install for.
        #[arg(long = "for", value_enum)]
        target: McpInstallTarget,
    },
}

// --- task body / ai_notes / recurrence-exception args -------

/// Shared shape for `append-body` and `add-ai-notes`: a task id plus
/// one or more words that get joined with spaces, mirroring the
/// `Capture` / `Search` ergonomics so the CLI doesn't force users to
/// quote their note.
#[derive(Args, Debug)]
pub(in crate::cli) struct TaskFreeTextArgs {
    /// Target task id.
    #[arg(value_parser = parse_task_id)]
    pub(in crate::cli) task_id: String,
    /// One or more words for the appended text (joined with spaces).
    #[arg(required = true, num_args = 1..)]
    pub(in crate::cli) text: Vec<String>,
}

#[derive(Subcommand, Debug)]
pub(in crate::cli) enum RecurrenceExceptionCmd {
    /// Add a recurrence exception date to a recurring task.
    Add(RecurrenceExceptionArgs),
    /// Remove a recurrence exception date from a recurring task.
    Remove(RecurrenceExceptionArgs),
}

#[derive(Args, Debug)]
pub(in crate::cli) struct RecurrenceExceptionArgs {
    /// Target task id.
    #[arg(value_parser = parse_task_id)]
    pub(in crate::cli) task_id: String,
    /// Exception date in YYYY-MM-DD form (must be an actual occurrence
    /// of the task's recurrence rule).
    #[arg(value_parser = super::super::parsers::parse_cli_date_arg)]
    pub(in crate::cli) date: String,
}

// --- error-logs / setup-status / setup-complete --

#[derive(Args, Debug)]
pub(in crate::cli) struct ErrorLogsArgs {
    /// Optional source filter (e.g. `sync`, `mcp`, `cli`).
    #[arg(long = "source")]
    pub(in crate::cli) source: Option<String>,
    #[arg(short = 'l', long = "limit", default_value_t = 25, value_parser = parse_positive_u32)]
    pub(in crate::cli) limit: u32,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct SetupCompleteArgs {
    /// One or more words for the completion summary (joined with spaces).
    #[arg(required = true, num_args = 1..)]
    pub(in crate::cli) summary: Vec<String>,
}
