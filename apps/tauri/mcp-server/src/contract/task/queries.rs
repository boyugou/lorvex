use super::super::{
    default_deferred_tasks_limit, default_dependency_graph_limit_edges,
    default_dependency_graph_limit_nodes, default_due_reminders_limit, default_list_tasks_limit,
    default_search_tasks_limit, default_status_all, default_status_open,
    default_tasks_by_tag_limit, default_todays_limit_per_bucket, default_upcoming_days,
    default_upcoming_limit, default_upcoming_reminders_hours, default_upcoming_reminders_limit,
};
use schemars::JsonSchema;

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetTaskArgs {
    #[schemars(description = "Task ID to retrieve")]
    pub(crate) id: String,
}

// `get_task` returns the full row via `SELECT *`, which
// carries task content. Consumers that treat
// `ai_notes` as trusted input MUST verify this column equals the local
// `sync_checkpoints.device_id` before acting on the note content —
// `ai_notes` is AI-only per CLAUDE.md rule #6, but the sync apply
// pipeline accepts task payloads from any peer, so notes pushed from a
// different (potentially malicious) device carry that device's id
// here. A NULL value means the origin is unknown (legacy row or peer
// on an older schema) and MUST also be treated as untrusted.

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub(crate) enum TaskStatusFilter {
    Open,
    Completed,
    Cancelled,
    Someday,
    All,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct ListTasksDueRangeArgs {
    #[schemars(description = "Inclusive start date (YYYY-MM-DD)")]
    pub(crate) from: Option<String>,
    #[schemars(description = "Inclusive end date (YYYY-MM-DD)")]
    pub(crate) to: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub(crate) enum ListTasksSortBy {
    PriorityDue,
    DueDate,
    PlannedDate,
    UpdatedAt,
    CreatedAt,
    Title,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Deserialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub(crate) enum SortDirection {
    Asc,
    Desc,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct ListTasksArgs {
    #[schemars(description = "Filter to tasks in this list")]
    pub(crate) list_id: Option<String>,
    #[serde(default = "default_status_open")]
    #[schemars(
        description = "Status filter. Default open. Use all to include every status.",
        default = "default_status_open"
    )]
    pub(crate) status: TaskStatusFilter,
    #[schemars(description = "Filter by priority: 1|2|3 (importance-first, not urgency-first)")]
    pub(crate) priority: Option<u8>,
    #[schemars(description = "Filter tasks within an inclusive due date range")]
    pub(crate) due_range: Option<ListTasksDueRangeArgs>,
    #[schemars(description = "Filter tasks within an inclusive planned date range")]
    pub(crate) planned_range: Option<ListTasksDueRangeArgs>,
    #[schemars(
        description = "Filter by completed_at date range (YYYY-MM-DD). Only meaningful when status includes 'completed'. Example: {\"from\":\"2026-04-01\",\"to\":\"2026-04-07\"}"
    )]
    pub(crate) completed_range: Option<ListTasksDueRangeArgs>,
    #[schemars(
        description = "Filter by created_at date range (YYYY-MM-DD). Example: {\"from\":\"2026-04-01\"}"
    )]
    pub(crate) created_range: Option<ListTasksDueRangeArgs>,
    #[schemars(
        description = "Filter by due-date presence. true = only tasks with due_date, false = only tasks without due_date."
    )]
    pub(crate) has_due_date: Option<bool>,
    #[schemars(
        description = "Filter by planned-date presence. true = only tasks with planned_date, false = only tasks without planned_date."
    )]
    pub(crate) has_planned_date: Option<bool>,
    #[schemars(description = "Tasks must have ALL of these tags")]
    pub(crate) tags: Option<Vec<String>>,
    #[schemars(description = "Case-insensitive substring match against title, body, and ai_notes")]
    pub(crate) text: Option<String>,
    #[schemars(
        description = "If true, only return tasks that have unmet dependencies (depends on other open tasks). Use for 'what's blocking me?'"
    )]
    pub(crate) blocked_only: Option<bool>,
    #[schemars(
        description = "If true, only return tasks that other open tasks depend on (appear in another task's depends_on). Use for 'what are my critical path tasks?'"
    )]
    pub(crate) blocking_others: Option<bool>,
    #[schemars(
        description = "Sort order. priority_due keeps the planning-first stable sort (priority, due_date, id)."
    )]
    pub(crate) sort_by: Option<ListTasksSortBy>,
    #[schemars(description = "Sort direction for sort_by. Default asc.")]
    pub(crate) sort_direction: Option<SortDirection>,
    #[serde(default = "default_list_tasks_limit")]
    #[schemars(
        description = "Maximum number of tasks to return. Default 100 (hard cap 500).",
        default = "default_list_tasks_limit",
        range(min = 1, max = 500)
    )]
    pub(crate) limit: u32,
    // zero-based row offset for stable pagination.
    // Pair with `limit` and the response's `next_offset` to walk
    // beyond page 1. Default 0 (start at the top of the result set).
    #[serde(default)]
    #[schemars(
        description = "Zero-based row offset for stable pagination. Default 0.",
        default,
        range(min = 0)
    )]
    pub(crate) offset: u32,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetTodaysTasksArgs {
    #[serde(default = "default_todays_limit_per_bucket")]
    #[schemars(
        description = "Maximum tasks returned per bucket. Default 100 (hard cap 500).",
        default = "default_todays_limit_per_bucket",
        range(min = 1, max = 500)
    )]
    pub(crate) limit_per_bucket: u32,
    // #3029-M3: paginate each bucket symmetrically so a heavy
    // planning session that exceeds the per-bucket cap can walk
    // past page 1. The offset applies to every bucket
    // (overdue / today / high-priority-undated) — peers should
    // increment in `limit_per_bucket` strides until each bucket's
    // `next_offset` is null.
    #[serde(default)]
    #[schemars(
        default,
        description = "Zero-based row offset applied symmetrically to every bucket. Default 0.",
        range(min = 0)
    )]
    pub(crate) offset: u32,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetUpcomingTasksArgs {
    #[serde(default = "default_upcoming_days")]
    #[schemars(
        description = "Number of days ahead to include. Default 7.",
        default = "default_upcoming_days",
        range(min = 1)
    )]
    pub(crate) days: u32,
    #[serde(default = "default_upcoming_limit")]
    #[schemars(
        description = "Maximum tasks to return across the full range. Default 200 (hard cap 1000).",
        default = "default_upcoming_limit",
        range(min = 1, max = 1000)
    )]
    pub(crate) limit: u32,
    // -M3: paginate the upcoming window.
    // hard-coded `offset: 0`, so workspaces with > 1000 upcoming
    // tasks across the requested span silently dropped the tail.
    #[serde(default)]
    #[schemars(
        default,
        description = "Zero-based row offset for stable pagination across the upcoming window. Default 0.",
        range(min = 0)
    )]
    pub(crate) offset: u32,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct SearchTasksArgs {
    #[schemars(
        description = "Search string matched against title, body, ai_notes, and tag names (#2574). Tag matches are weighted 3× vs body."
    )]
    pub(crate) query: String,
    #[serde(default = "default_status_all")]
    #[schemars(
        description = "Status filter. Default all statuses.",
        default = "default_status_all"
    )]
    pub(crate) status: TaskStatusFilter,
    #[serde(default = "default_search_tasks_limit")]
    #[schemars(
        description = "Maximum results to return. Default 50 (hard cap 500).",
        default = "default_search_tasks_limit",
        range(min = 1, max = 500)
    )]
    pub(crate) limit: u32,
    // pagination offset. See `ListTasksArgs::offset`.
    #[serde(default)]
    #[schemars(
        description = "Zero-based row offset for stable pagination. Default 0.",
        default,
        range(min = 0)
    )]
    pub(crate) offset: u32,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetDeferredTasksArgs {
    #[schemars(description = "Optional list filter")]
    pub(crate) list_id: Option<String>,
    #[serde(default = "default_deferred_tasks_limit")]
    #[schemars(
        description = "Maximum deferred tasks to return. Default 100 (hard cap 500).",
        default = "default_deferred_tasks_limit",
        range(min = 1, max = 500)
    )]
    pub(crate) limit: u32,
    // pagination offset. See `ListTasksArgs::offset`.
    #[serde(default)]
    #[schemars(
        description = "Zero-based row offset for stable pagination. Default 0.",
        default,
        range(min = 0)
    )]
    pub(crate) offset: u32,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct ListAllTagsArgs {
    // schemars must mirror serde's default so the
    // emitted JSON Schema marks the field optional.
    #[serde(default)]
    #[schemars(
        default,
        description = "Include tags only used by completed/cancelled tasks. Default: false"
    )]
    pub(crate) include_inactive: bool,
    #[serde(default)]
    #[schemars(
        default,
        description = "Maximum number of tags to return. Default: 100, cap: 1000",
        range(min = 1, max = 1000)
    )]
    pub(crate) limit: u32,
    // #3019-M1: pagination — `offset` lets callers walk past the
    // hard cap of 1000 tags. The response carries `next_offset` so a
    // client can paginate without re-deriving the offset arithmetic.
    #[serde(default)]
    #[schemars(
        default,
        description = "Zero-based row offset for stable pagination. Default 0.",
        range(min = 0)
    )]
    pub(crate) offset: u32,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetTasksByTagArgs {
    #[schemars(description = "Tag to filter by (case-insensitive)")]
    pub(crate) tag: String,
    #[serde(default = "default_status_open")]
    #[schemars(
        description = "Status filter. Default open.",
        default = "default_status_open"
    )]
    pub(crate) status: TaskStatusFilter,
    #[serde(default = "default_tasks_by_tag_limit")]
    #[schemars(
        description = "Maximum tasks to return. Default 100 (hard cap 500).",
        default = "default_tasks_by_tag_limit",
        range(min = 1, max = 500)
    )]
    pub(crate) limit: u32,
    // pagination offset. See `ListTasksArgs::offset`.
    #[serde(default)]
    #[schemars(
        description = "Zero-based row offset for stable pagination. Default 0.",
        default,
        range(min = 0)
    )]
    pub(crate) offset: u32,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct RenameTagArgs {
    #[schemars(description = "Current tag name to rename (case-insensitive match)")]
    pub(crate) old_name: String,
    #[schemars(description = "New tag name")]
    pub(crate) new_name: String,
    // #3033-M2: optional idempotency token. The rename touches every
    // task carrying the tag (per-task version bump + per-task sync
    // envelope) and writes one tag-entity audit row. A network retry
    // without this key writes a duplicate audit row and re-emits one
    // sync envelope per affected task — destructive against a large
    // tag fan-out. Use the cache to suppress that tail.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate tag renames; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetDueTaskRemindersArgs {
    #[serde(default = "default_due_reminders_limit")]
    #[schemars(
        description = "Maximum results to return. Default 50 (hard cap 200).",
        default = "default_due_reminders_limit",
        range(min = 1, max = 200)
    )]
    pub(crate) limit: u32,
    // pagination offset for the streaming due-reminder
    // poller. The store layer's truncation-detection optimization
    // returns at most `limit + 1` rows, so the MCP layer fetches
    // `limit + offset + 1` rows then slices the leading `offset` away.
    // For the rare case where pagination matters (deep backlog of due
    // reminders not yet dismissed), this lets the assistant walk past
    // the limit cap without losing rows.
    #[serde(default)]
    #[schemars(
        description = "Zero-based row offset for stable pagination. Default 0.",
        default,
        range(min = 0)
    )]
    pub(crate) offset: u32,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetUpcomingTaskRemindersArgs {
    #[serde(default = "default_upcoming_reminders_hours")]
    #[schemars(
        description = "Look-ahead window in hours. Default 24 (max 168 = 1 week).",
        default = "default_upcoming_reminders_hours",
        range(min = 1, max = 168)
    )]
    pub(crate) hours: u32,
    #[serde(default = "default_upcoming_reminders_limit")]
    #[schemars(
        description = "Maximum results to return. Default 50 (hard cap 200).",
        default = "default_upcoming_reminders_limit",
        range(min = 1, max = 200)
    )]
    pub(crate) limit: u32,
    // pagination offset. See
    // `GetDueTaskRemindersArgs::offset`.
    #[serde(default)]
    #[schemars(
        description = "Zero-based row offset for stable pagination. Default 0.",
        default,
        range(min = 0)
    )]
    pub(crate) offset: u32,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetDependencyGraphArgs {
    #[schemars(
        description = "Optional: root task ID to center the graph on (shows its direct neighbors). When combined with list_id, only edges where BOTH endpoints belong to the list are included."
    )]
    pub(crate) task_id: Option<String>,
    #[schemars(
        description = "Optional: list ID to scope the graph to. When combined with task_id, acts as an intersection filter — only edges where both endpoints are in this list are included."
    )]
    pub(crate) list_id: Option<String>,
    // schemars default mirrors serde's default.
    #[schemars(
        default,
        description = "Include completed/cancelled tasks. Default: false."
    )]
    #[serde(default)]
    pub(crate) include_inactive: bool,
    #[serde(default = "default_dependency_graph_limit_nodes")]
    #[schemars(
        description = "Maximum nodes in the graph. Default 100 (hard cap 500).",
        default = "default_dependency_graph_limit_nodes",
        range(min = 1, max = 500)
    )]
    pub(crate) limit_nodes: u32,
    #[serde(default = "default_dependency_graph_limit_edges")]
    #[schemars(
        description = "Maximum edges in the graph. Default 500 (hard cap 2000).",
        default = "default_dependency_graph_limit_edges",
        range(min = 1, max = 2000)
    )]
    pub(crate) limit_edges: u32,
}
