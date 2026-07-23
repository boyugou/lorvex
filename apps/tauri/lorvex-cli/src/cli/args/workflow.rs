//! clap arg structs for the workflow / read-aggregation
//! tools — `overview`, `overview-compact`, `session-context`, `guide`,
//! `recent-logs`, `analyze`, and the per-list `reorganize` mutation.

use clap::{Args, Subcommand, ValueEnum};

use super::super::parsers::{
    parse_bymonthday, parse_habit_id, parse_list_id, parse_positive_u32, parse_task_id,
};

#[derive(Args, Debug)]
pub(in crate::cli) struct OverviewArgs {
    /// Emit the compact form (smaller payload, fewer fields). Mirrors
    /// MCP `get_overview_compact`.
    #[arg(long = "compact")]
    pub(in crate::cli) compact: bool,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct SessionContextArgs {}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub(in crate::cli) enum GuideTopicArg {
    Overview,
    #[value(name = "getting_started")]
    GettingStarted,
    #[value(name = "task_management")]
    TaskManagement,
    #[value(name = "current_focus")]
    CurrentFocus,
    Lists,
    #[value(name = "focus_mode")]
    FocusMode,
    #[value(name = "weekly_review")]
    WeeklyReview,
    Preferences,
    #[value(name = "data_and_export")]
    DataAndExport,
}

impl GuideTopicArg {
    /// Convert to the snake_case form the MCP contract serializes.
    pub(in crate::cli) const fn as_serde_value(self) -> &'static str {
        match self {
            Self::Overview => "overview",
            Self::GettingStarted => "getting_started",
            Self::TaskManagement => "task_management",
            Self::CurrentFocus => "current_focus",
            Self::Lists => "lists",
            Self::FocusMode => "focus_mode",
            Self::WeeklyReview => "weekly_review",
            Self::Preferences => "preferences",
            Self::DataAndExport => "data_and_export",
        }
    }
}

#[derive(Args, Debug)]
pub(in crate::cli) struct GuideArgs {
    /// Optional explicit topic; omit to auto-detect from app state.
    #[arg(long = "topic", value_enum)]
    pub(in crate::cli) topic: Option<GuideTopicArg>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct RecentLogsArgs {
    /// Maximum entries to return after merge/sort (default 100, max 500).
    #[arg(short = 'l', long = "limit", value_parser = parse_positive_u32)]
    pub(in crate::cli) limit: Option<u32>,
    /// ISO timestamp — include entries strictly newer than this.
    #[arg(long = "since")]
    pub(in crate::cli) since: Option<String>,
    /// Repeatable `--level` filter (debug/info/warn/error).
    #[arg(long = "level")]
    pub(in crate::cli) levels: Vec<String>,
    /// Repeatable `--source` filter (error_log/ai_changelog/sync_outbox).
    #[arg(long = "source")]
    pub(in crate::cli) sources: Vec<String>,
    /// Include sanitized details payload for `error_log` entries.
    #[arg(long = "include-details")]
    pub(in crate::cli) include_details: bool,
    /// Disable the default secret-redaction policy. NOT recommended.
    #[arg(long = "no-redact")]
    pub(in crate::cli) no_redact: bool,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct AnalyzeArgs {
    /// Analysis window in days (default 14, max 90).
    #[arg(long = "window-days", value_parser = parse_positive_u32)]
    pub(in crate::cli) window_days: Option<u32>,
    /// Max samples to surface per insight (default 5, max 20).
    #[arg(long = "top-n", value_parser = parse_positive_u32)]
    pub(in crate::cli) top_n: Option<u32>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub(in crate::cli) enum ReorganizeStrategyArg {
    Manual,
    Deadline,
    Priority,
}

impl ReorganizeStrategyArg {
    pub(in crate::cli) const fn as_serde_value(self) -> &'static str {
        match self {
            Self::Manual => "manual",
            Self::Deadline => "deadline",
            Self::Priority => "priority",
        }
    }
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ReorganizeArgs {
    /// List id to reorganize.
    #[arg(value_parser = parse_list_id)]
    pub(in crate::cli) list_id: String,
    /// Strategy.
    #[arg(long = "strategy", value_enum)]
    pub(in crate::cli) strategy: ReorganizeStrategyArg,
    /// Manual ordering: pass every open task id in the desired order.
    /// Required when --strategy=manual.
    #[arg(long = "task-id", value_parser = parse_task_id)]
    pub(in crate::cli) task_ids: Vec<String>,
    /// If set, run validation and return the would-be ordering without
    /// writing to ai_changelog.
    #[arg(long = "dry-run")]
    pub(in crate::cli) dry_run: bool,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct HabitCompletionsArgs {
    /// Habit id.
    #[arg(value_parser = parse_habit_id)]
    pub(in crate::cli) habit_id: String,
    /// Window in days (default 30, max 365).
    #[arg(short = 'd', long = "days", value_parser = parse_positive_u32)]
    pub(in crate::cli) days: Option<u32>,
}

// ── Task-create / set-recurrence / batch / permanent-delete ───────────

#[derive(Subcommand, Debug)]
pub(in crate::cli) enum TaskWriteCmd {
    /// Create a task with the full structured shape (mirrors MCP
    /// `create_task`). Distinct from `capture` — accepts ai_notes,
    /// recurrence, depends_on, reminders at create time.
    Create(TaskCreateArgs),
    /// Set or replace a task's recurrence rule (mirrors MCP
    /// `set_recurrence`).
    SetRecurrence(SetRecurrenceArgs),
    /// Permanently delete a trashed task (mirrors MCP
    /// `permanent_delete_task`). Distinct from `trash delete` — this
    /// verb is the canonical agent-facing form.
    PermanentDelete(PermanentDeleteArgs),
    /// Batch-create tasks from a JSON array (mirrors MCP
    /// `batch_create_tasks`).
    BatchCreate(BatchCreateArgs),
    /// Batch-update tasks from a JSON array of patches (mirrors MCP
    /// `batch_update_tasks`).
    BatchUpdate(BatchUpdateArgs),
    /// Cancel every open task in a list in one transaction (mirrors
    /// MCP `batch_cancel_tasks_in_list`).
    BatchCancelInList(BatchCancelInListArgs),
}

#[derive(Args, Debug)]
pub(in crate::cli) struct TaskCreateArgs {
    /// Task title (joined with spaces).
    #[arg(required = true, num_args = 1..)]
    pub(in crate::cli) title: Vec<String>,
    /// Target list id.
    #[arg(long = "list", value_parser = parse_list_id)]
    pub(in crate::cli) list_id: Option<String>,
    /// Importance priority (1=highest, 3=lowest).
    #[arg(long = "priority")]
    pub(in crate::cli) priority: Option<u8>,
    /// Deadline date (YYYY-MM-DD).
    #[arg(long = "due-date")]
    pub(in crate::cli) due_date: Option<String>,
    /// Due time (HH:MM).
    #[arg(long = "due-time")]
    pub(in crate::cli) due_time: Option<String>,
    /// Intended work date (YYYY-MM-DD).
    #[arg(long = "planned-date")]
    pub(in crate::cli) planned_date: Option<String>,
    /// Rough duration estimate in minutes.
    #[arg(long = "estimated-minutes")]
    pub(in crate::cli) estimated_minutes: Option<u32>,
    /// Repeatable tag.
    #[arg(long = "tag")]
    pub(in crate::cli) tags: Vec<String>,
    /// Task body text.
    #[arg(long = "body")]
    pub(in crate::cli) body: Option<String>,
    /// AI notes (visually distinct from body).
    #[arg(long = "ai-notes")]
    pub(in crate::cli) ai_notes: Option<String>,
    /// Repeatable `--depends-on TASK_ID` to seed dependencies.
    #[arg(long = "depends-on", value_parser = parse_task_id)]
    pub(in crate::cli) depends_on: Vec<String>,
    /// Repeatable RFC 3339 reminder timestamp.
    #[arg(long = "reminder")]
    pub(in crate::cli) reminders: Vec<String>,
    /// Optional structured recurrence rule as a JSON object:
    /// `{"freq":"weekly","interval":2,"byday":["MO"]}`. Structured
    /// shape only; stringly-typed RRULE blobs (`{"FREQ":...}`) are
    /// rejected so the flag matches `set_recurrence`'s typed contract.
    #[arg(long = "recurrence")]
    pub(in crate::cli) recurrence: Option<String>,
    /// Mark the new task as completed immediately.
    #[arg(long = "completed")]
    pub(in crate::cli) completed: bool,
    /// Idempotency token; reuse on retry to dedupe.
    #[arg(long = "idempotency-key")]
    pub(in crate::cli) idempotency_key: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
pub(in crate::cli) enum RecurrenceFreqArg {
    Daily,
    Weekly,
    Monthly,
    Yearly,
}

impl RecurrenceFreqArg {
    pub(in crate::cli) const fn as_serde_value(self) -> &'static str {
        match self {
            Self::Daily => "daily",
            Self::Weekly => "weekly",
            Self::Monthly => "monthly",
            Self::Yearly => "yearly",
        }
    }
}

#[derive(Args, Debug)]
pub(in crate::cli) struct SetRecurrenceArgs {
    /// Task id.
    #[arg(value_parser = parse_task_id)]
    pub(in crate::cli) task_id: String,
    /// Frequency.
    #[arg(long = "freq", value_enum)]
    pub(in crate::cli) freq: RecurrenceFreqArg,
    /// Repeat interval (default 1).
    #[arg(long = "interval", value_parser = parse_positive_u32)]
    pub(in crate::cli) interval: Option<u32>,
    /// Repeatable BYDAY code (SU/MO/TU/WE/TH/FR/SA), weekly only.
    #[arg(long = "byday")]
    pub(in crate::cli) byday: Vec<String>,
    /// Day(s)-of-month (monthly/yearly only). Comma-separated; negative
    /// values count from the end of the month (e.g. `--bymonthday=1,15,-1`).
    #[arg(long = "bymonthday", value_delimiter = ',', value_parser = parse_bymonthday)]
    pub(in crate::cli) bymonthday: Vec<i64>,
    /// UNTIL date (YYYY-MM-DD); mutually exclusive with --count.
    #[arg(long = "until")]
    pub(in crate::cli) until: Option<String>,
    /// COUNT cap; mutually exclusive with --until.
    #[arg(long = "count", value_parser = parse_positive_u32)]
    pub(in crate::cli) count: Option<u32>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct PermanentDeleteArgs {
    /// Task id.
    #[arg(value_parser = parse_task_id)]
    pub(in crate::cli) task_id: String,
    /// Run the cascade plan and return the would-be shape; no writes.
    #[arg(long = "dry-run")]
    pub(in crate::cli) dry_run: bool,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct BatchCreateArgs {
    /// JSON array of task-create inputs (matches MCP
    /// `batch_create_tasks` schema).
    #[arg(long = "tasks-json")]
    pub(in crate::cli) tasks_json: String,
    /// Return advisories alongside each created task.
    #[arg(long = "include-advice")]
    pub(in crate::cli) include_advice: bool,
    /// Idempotency token; reuse on retry to dedupe.
    #[arg(long = "idempotency-key")]
    pub(in crate::cli) idempotency_key: Option<String>,
    /// Run the batch insert in a rolled-back savepoint.
    #[arg(long = "dry-run")]
    pub(in crate::cli) dry_run: bool,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct BatchUpdateArgs {
    /// JSON array of update patches (matches MCP
    /// `batch_update_tasks.updates`).
    #[arg(long = "updates-json")]
    pub(in crate::cli) updates_json: String,
    /// Apply patches in a rolled-back savepoint and return preview.
    #[arg(long = "dry-run")]
    pub(in crate::cli) dry_run: bool,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct BatchCancelInListArgs {
    /// List id whose tasks will be cancelled.
    #[arg(value_parser = parse_list_id)]
    pub(in crate::cli) list_id: String,
    /// Repeatable status filter (defaults to `open` only). Valid:
    /// open, completed, cancelled, someday.
    #[arg(long = "status")]
    pub(in crate::cli) statuses: Vec<String>,
    /// Cancel the entire recurring series for any recurring tasks.
    #[arg(long = "series")]
    pub(in crate::cli) cancel_series: bool,
    /// Run the cancel plan and return the preview; no writes.
    #[arg(long = "dry-run")]
    pub(in crate::cli) dry_run: bool,
}
