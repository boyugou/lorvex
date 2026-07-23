//! Task-related clap argument structs: search, list, capture, update,
//! complete/cancel/defer, and the dependency graph query.

use clap::Args;

use super::super::parsers::{
    parse_cli_date_arg, parse_dependency_id, parse_estimated_minutes, parse_list_id,
    parse_positive_i64, parse_positive_u32, parse_priority, parse_sort_direction, parse_tag,
    parse_task_id, parse_task_priority, parse_task_sort_by, parse_task_status_filter,
    parse_task_status_value, parse_time,
};

#[derive(Args, Debug)]
pub(in crate::cli) struct SearchArgs {
    /// One or more words to search for (joined with spaces).
    #[arg(required = true, num_args = 1..)]
    pub(in crate::cli) query: Vec<String>,
    #[arg(short = 'l', long = "limit", default_value_t = 20, value_parser = parse_positive_u32)]
    pub(in crate::cli) limit: u32,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct MoveArgs {
    /// Destination list id.
    #[arg(value_parser = parse_list_id)]
    pub(in crate::cli) list_id: String,
    /// One or more task ids to move.
    #[arg(
        required = true,
        num_args = 1..,
        value_parser = parse_task_id
    )]
    pub(in crate::cli) task_ids: Vec<String>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct ShowArgs {
    #[arg(value_parser = parse_task_id)]
    pub(in crate::cli) task_id: String,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct UpcomingArgs {
    #[arg(short = 'd', long = "days", default_value_t = 7, value_parser = parse_positive_u32)]
    pub(in crate::cli) days: u32,
    #[arg(short = 'l', long = "limit", default_value_t = 20, value_parser = parse_positive_u32)]
    pub(in crate::cli) limit: u32,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct DeferredArgs {
    /// Optional list id to filter by.
    #[arg(long = "list", value_parser = parse_list_id)]
    pub(in crate::cli) list_id: Option<String>,
    #[arg(short = 'l', long = "limit", default_value_t = 100, value_parser = parse_positive_u32)]
    pub(in crate::cli) limit: u32,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct CaptureArgs {
    /// One or more words for the task title (joined with spaces).
    #[arg(required = true, num_args = 1..)]
    pub(in crate::cli) title: Vec<String>,
    /// Target list id (defaults to inbox).
    #[arg(long = "list", value_parser = parse_list_id)]
    pub(in crate::cli) list: Option<String>,
    /// Importance priority: 1 is highest, 3 is lowest.
    #[arg(long = "priority", value_parser = parse_priority)]
    pub(in crate::cli) priority: Option<i64>,
    /// Deadline date in YYYY-MM-DD format.
    #[arg(long = "due-date", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) due_date: Option<String>,
    /// Intended work date in YYYY-MM-DD format.
    #[arg(long = "planned-date", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) planned_date: Option<String>,
    /// Rough duration estimate in minutes, 0..=1440.
    #[arg(long = "estimated-minutes", value_parser = parse_estimated_minutes)]
    pub(in crate::cli) estimated_minutes: Option<i64>,
    /// Tag to attach to the task. Repeat for multiple tags.
    #[arg(long = "tag", value_parser = parse_tag)]
    pub(in crate::cli) tags: Vec<String>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct TaskUpdateArgs {
    #[arg(value_parser = parse_task_id)]
    pub(in crate::cli) task_id: String,
    #[arg(long = "title")]
    pub(in crate::cli) title: Option<String>,
    #[arg(long = "body", conflicts_with = "clear_body")]
    pub(in crate::cli) body: Option<String>,
    #[arg(long = "clear-body")]
    pub(in crate::cli) clear_body: bool,
    #[arg(long = "ai-notes", conflicts_with = "clear_ai_notes")]
    pub(in crate::cli) ai_notes: Option<String>,
    #[arg(long = "clear-ai-notes")]
    pub(in crate::cli) clear_ai_notes: bool,
    // bring CLI parity with MCP `update_task`. The MCP
    // contract patches `status` and `raw_input` directly; the CLI
    // forced operators to either edit SQL or fall back to a
    // separate `complete`/`cancel`/`reopen` command for status, and
    // had no surface at all for `raw_input`.
    #[arg(long = "status", value_parser = parse_task_status_value)]
    pub(in crate::cli) status: Option<String>,
    #[arg(long = "raw-input")]
    pub(in crate::cli) raw_input: Option<String>,
    #[arg(long = "list", value_parser = parse_list_id)]
    pub(in crate::cli) list: Option<String>,
    #[arg(long = "priority", value_parser = parse_priority, conflicts_with = "clear_priority")]
    pub(in crate::cli) priority: Option<i64>,
    #[arg(long = "clear-priority")]
    pub(in crate::cli) clear_priority: bool,
    #[arg(long = "due-date", value_parser = parse_cli_date_arg, conflicts_with = "clear_due_date")]
    pub(in crate::cli) due_date: Option<String>,
    #[arg(long = "clear-due-date")]
    pub(in crate::cli) clear_due_date: bool,
    #[arg(long = "due-time", value_parser = parse_time, conflicts_with = "clear_due_time")]
    pub(in crate::cli) due_time: Option<String>,
    #[arg(long = "clear-due-time")]
    pub(in crate::cli) clear_due_time: bool,
    #[arg(long = "planned-date", value_parser = parse_cli_date_arg, conflicts_with = "clear_planned_date")]
    pub(in crate::cli) planned_date: Option<String>,
    #[arg(long = "clear-planned-date")]
    pub(in crate::cli) clear_planned_date: bool,
    #[arg(
        long = "estimated-minutes",
        value_parser = parse_estimated_minutes,
        conflicts_with = "clear_estimated_minutes"
    )]
    pub(in crate::cli) estimated_minutes: Option<i64>,
    #[arg(long = "clear-estimated-minutes")]
    pub(in crate::cli) clear_estimated_minutes: bool,
    #[arg(
        long = "tag-set",
        value_parser = parse_tag,
        conflicts_with_all = ["clear_tags", "tag_add", "tag_remove"]
    )]
    pub(in crate::cli) tag_set: Vec<String>,
    #[arg(long = "clear-tags", conflicts_with_all = ["tag_set", "tag_add", "tag_remove"])]
    pub(in crate::cli) clear_tags: bool,
    #[arg(long = "tag-add", value_parser = parse_tag)]
    pub(in crate::cli) tag_add: Vec<String>,
    #[arg(long = "tag-remove", value_parser = parse_tag)]
    pub(in crate::cli) tag_remove: Vec<String>,
    #[arg(
        long = "depends-on-set",
        value_parser = parse_dependency_id,
        conflicts_with_all = ["clear_depends_on", "depends_on_add", "depends_on_remove"]
    )]
    pub(in crate::cli) depends_on_set: Vec<String>,
    #[arg(
        long = "clear-depends-on",
        conflicts_with_all = ["depends_on_set", "depends_on_add", "depends_on_remove"]
    )]
    pub(in crate::cli) clear_depends_on: bool,
    #[arg(long = "depends-on-add", value_parser = parse_dependency_id)]
    pub(in crate::cli) depends_on_add: Vec<String>,
    #[arg(long = "depends-on-remove", value_parser = parse_dependency_id)]
    pub(in crate::cli) depends_on_remove: Vec<String>,
    /// Structured recurrence rule as a JSON object (mirrors the
    /// MCP `update_task` `recurrence` patch). Example:
    /// `{"freq":"weekly","interval":2,"byday":["MO"]}`.
    #[arg(long = "recurrence", conflicts_with = "clear_recurrence")]
    pub(in crate::cli) recurrence: Option<String>,
    /// Drop the task's recurrence rule, leaving the row non-recurring.
    #[arg(long = "clear-recurrence")]
    pub(in crate::cli) clear_recurrence: bool,
    /// Optional idempotency token. Reuse on retry to short-circuit
    /// duplicate updates; the cache returns the prior response without
    /// re-applying additive `--tag-add` / `--depends-on-add` patches.
    #[arg(long = "idempotency-key")]
    pub(in crate::cli) idempotency_key: Option<String>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct TaskIdsArgs {
    #[arg(
        required = true,
        num_args = 1..,
        value_parser = parse_task_id
    )]
    pub(in crate::cli) task_ids: Vec<String>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct CancelArgs {
    #[arg(
        required = true,
        num_args = 1..,
        value_parser = parse_task_id
    )]
    pub(in crate::cli) task_ids: Vec<String>,
    /// Cancel the entire recurring series, not just this occurrence.
    #[arg(long = "series")]
    pub(in crate::cli) series: bool,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct DeferArgs {
    #[arg(
        required = true,
        num_args = 1..,
        value_parser = parse_task_id
    )]
    pub(in crate::cli) task_ids: Vec<String>,
    /// Days to defer by.
    #[arg(short = 'd', long = "days", value_parser = parse_positive_i64)]
    pub(in crate::cli) days: Option<i64>,
    /// Free-form defer reason.
    #[arg(long = "reason")]
    pub(in crate::cli) reason: Option<String>,
    /// Structured defer reason key (e.g. `needs_info`, `waiting_on_someone`).
    #[arg(long = "structured-reason")]
    pub(in crate::cli) structured_reason: Option<String>,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct TasksArgs {
    /// Optional list id filter.
    #[arg(long = "list", value_parser = parse_list_id)]
    pub(in crate::cli) list_id: Option<String>,
    /// Status filter. Defaults to open.
    #[arg(long = "status", default_value = "open", value_parser = parse_task_status_filter)]
    pub(in crate::cli) status: String,
    /// Priority filter: 1, 2, or 3.
    #[arg(long = "priority", value_parser = parse_task_priority)]
    pub(in crate::cli) priority: Option<u8>,
    #[arg(long = "due-from", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) due_from: Option<String>,
    #[arg(long = "due-to", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) due_to: Option<String>,
    #[arg(long = "planned-from", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) planned_from: Option<String>,
    #[arg(long = "planned-to", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) planned_to: Option<String>,
    #[arg(long = "completed-from", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) completed_from: Option<String>,
    #[arg(long = "completed-to", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) completed_to: Option<String>,
    #[arg(long = "created-from", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) created_from: Option<String>,
    #[arg(long = "created-to", value_parser = parse_cli_date_arg)]
    pub(in crate::cli) created_to: Option<String>,
    #[arg(long = "has-due-date", conflicts_with = "no_due_date")]
    pub(in crate::cli) has_due_date: bool,
    #[arg(long = "no-due-date")]
    pub(in crate::cli) no_due_date: bool,
    #[arg(long = "has-planned-date", conflicts_with = "no_planned_date")]
    pub(in crate::cli) has_planned_date: bool,
    #[arg(long = "no-planned-date")]
    pub(in crate::cli) no_planned_date: bool,
    /// Require every repeated tag.
    #[arg(long = "tag", value_parser = parse_tag)]
    pub(in crate::cli) tags: Vec<String>,
    /// Case-insensitive substring match against title/body/AI notes.
    #[arg(long = "text")]
    pub(in crate::cli) text: Option<String>,
    #[arg(long = "blocked-only")]
    pub(in crate::cli) blocked_only: bool,
    #[arg(long = "blocking-others")]
    pub(in crate::cli) blocking_others: bool,
    #[arg(long = "sort-by", default_value = "priority_due", value_parser = parse_task_sort_by)]
    pub(in crate::cli) sort_by: String,
    #[arg(long = "sort-direction", default_value = "asc", value_parser = parse_sort_direction)]
    pub(in crate::cli) sort_direction: String,
    #[arg(short = 'l', long = "limit", default_value_t = 100, value_parser = parse_positive_u32)]
    pub(in crate::cli) limit: u32,
}

#[derive(Args, Debug)]
pub(in crate::cli) struct DependencyGraphArgs {
    /// Optional task id to center the graph on.
    #[arg(long = "task-id", value_parser = parse_task_id)]
    pub(in crate::cli) task_id: Option<String>,
    /// Optional list id scope.
    #[arg(long = "list", value_parser = parse_list_id)]
    pub(in crate::cli) list_id: Option<String>,
    /// Include completed and cancelled tasks.
    #[arg(long = "include-inactive")]
    pub(in crate::cli) include_inactive: bool,
    /// Maximum nodes to return.
    #[arg(long = "limit-nodes", default_value_t = 100, value_parser = parse_positive_u32)]
    pub(in crate::cli) limit_nodes: u32,
    /// Maximum edges to return.
    #[arg(long = "limit-edges", default_value_t = 500, value_parser = parse_positive_u32)]
    pub(in crate::cli) limit_edges: u32,
}
