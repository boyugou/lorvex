#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub(crate) struct TaskListItem {
    pub(crate) id: String,
    pub(crate) title: String,
    pub(crate) when: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize, PartialEq, Eq)]
pub(crate) struct TaskSummary {
    pub(crate) id: String,
    pub(crate) title: String,
    pub(crate) status: String,
    pub(crate) due_date: Option<lorvex_domain::Date>,
    pub(crate) planned_date: Option<lorvex_domain::Date>,
    pub(crate) priority: Option<i64>,
    pub(crate) list_id: String,
}

#[derive(Debug, Clone, serde::Serialize, PartialEq, Eq)]
pub(crate) struct TaskListSnapshot {
    pub(crate) limit: u32,
    pub(crate) returned: usize,
    pub(crate) total_matching: i64,
    pub(crate) truncated: bool,
    pub(crate) tasks: Vec<TaskSummary>,
}

#[derive(Debug, Clone, serde::Serialize, PartialEq, Eq)]
pub(crate) struct DependencyGraphSnapshot {
    pub(crate) limit_nodes: u32,
    pub(crate) limit_edges: u32,
    pub(crate) node_count: usize,
    pub(crate) edge_count: usize,
    pub(crate) nodes: Vec<DependencyGraphNode>,
    pub(crate) edges: Vec<DependencyGraphEdge>,
    pub(crate) roots: Vec<String>,
    pub(crate) blocked: Vec<String>,
    pub(crate) leaf_blockers: Vec<String>,
    pub(crate) truncated: bool,
}

#[derive(Debug, Clone, serde::Serialize, PartialEq, Eq)]
pub(crate) struct DependencyGraphNode {
    pub(crate) id: String,
    pub(crate) title: String,
    pub(crate) status: String,
    pub(crate) priority: Option<i64>,
    pub(crate) due_date: Option<lorvex_domain::Date>,
    pub(crate) planned_date: Option<lorvex_domain::Date>,
    pub(crate) list_id: String,
}

#[derive(Debug, Clone, serde::Serialize, PartialEq, Eq)]
pub(crate) struct DependencyGraphEdge {
    pub(crate) from: String,
    pub(crate) to: String,
}

#[derive(Debug, Clone, serde::Serialize, PartialEq, Eq)]
pub(crate) struct ListSummary {
    pub(crate) id: String,
    pub(crate) name: String,
    pub(crate) open_count: i64,
    pub(crate) total_count: i64,
    pub(crate) color: Option<String>,
    pub(crate) icon: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize, PartialEq, Eq)]
pub(crate) struct ListHealthSnapshot {
    pub(crate) date: String,
    pub(crate) summary: ListHealthSummary,
    pub(crate) lists: Vec<ListHealthRow>,
    pub(crate) limits: ListHealthLimits,
}

#[derive(Debug, Clone, serde::Serialize, PartialEq, Eq)]
pub(crate) struct ListHealthSummary {
    pub(crate) total_lists: i64,
    pub(crate) returned_lists: usize,
    pub(crate) limit: u32,
    pub(crate) truncated: bool,
}

#[derive(Debug, Clone, serde::Serialize, PartialEq, Eq)]
pub(crate) struct ListHealthLimits {
    pub(crate) lists: u32,
    pub(crate) name_max_chars: usize,
}

#[derive(Debug, Clone, serde::Serialize, PartialEq, Eq)]
pub(crate) struct ListHealthRow {
    pub(crate) id: String,
    pub(crate) name: String,
    pub(crate) color: Option<String>,
    pub(crate) icon: Option<String>,
    pub(crate) open_count: i64,
    pub(crate) overdue_open_count: i64,
    pub(crate) due_today_open_count: i64,
}

#[derive(Debug, Clone, serde::Serialize, PartialEq, Eq)]
pub(crate) struct DeferredTasksSnapshot {
    pub(crate) limit: u32,
    pub(crate) returned: usize,
    pub(crate) total_matching: i64,
    pub(crate) truncated: bool,
    pub(crate) list_id: Option<String>,
    pub(crate) tasks: Vec<DeferredTaskSummary>,
}

#[derive(Debug, Clone, serde::Serialize, PartialEq, Eq)]
pub(crate) struct DeferredTaskSummary {
    pub(crate) id: String,
    pub(crate) title: String,
    pub(crate) status: String,
    pub(crate) list_id: String,
    pub(crate) due_date: Option<lorvex_domain::Date>,
    pub(crate) planned_date: Option<lorvex_domain::Date>,
    pub(crate) priority: Option<i64>,
    pub(crate) defer_count: i64,
    pub(crate) last_deferred_at: Option<String>,
    pub(crate) last_defer_reason: Option<String>,
    pub(crate) updated_at: String,
}

#[derive(Debug, Clone, serde::Serialize, PartialEq, Eq)]
pub(crate) struct TaskReminderSnapshot {
    pub(crate) hours_window: Option<u32>,
    pub(crate) limit: u32,
    pub(crate) returned: usize,
    pub(crate) total_matching: i64,
    pub(crate) truncated: bool,
    pub(crate) reminders: Vec<TaskReminderSummary>,
}

#[derive(Debug, Clone, serde::Serialize, PartialEq, Eq)]
pub(crate) struct TaskReminderSummary {
    pub(crate) id: String,
    pub(crate) task_id: String,
    pub(crate) reminder_at: lorvex_domain::SyncTimestamp,
    pub(crate) dismissed_at: Option<lorvex_domain::SyncTimestamp>,
    pub(crate) cancelled_at: Option<lorvex_domain::SyncTimestamp>,
    pub(crate) created_at: lorvex_domain::SyncTimestamp,
    pub(crate) delivery_state: String,
    pub(crate) task_title: String,
    pub(crate) task_status: String,
    pub(crate) task_due_date: Option<lorvex_domain::Date>,
    pub(crate) task_priority: Option<i64>,
}

#[derive(Debug, Clone, serde::Serialize, PartialEq, Eq)]
pub(crate) struct TaskReminderRow {
    pub(crate) id: String,
    pub(crate) task_id: String,
    pub(crate) reminder_at: String,
    pub(crate) dismissed_at: Option<String>,
    pub(crate) cancelled_at: Option<String>,
    pub(crate) created_at: String,
    pub(crate) original_local_time: Option<String>,
    pub(crate) original_tz: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize)]
pub(crate) struct TaskReminderMutationResult {
    pub(crate) task: lorvex_store::repositories::task::read::TaskRow,
    pub(crate) reminders: Vec<TaskReminderRow>,
}

#[derive(Debug, Clone, serde::Serialize, PartialEq)]
pub(crate) struct PendingOutboxEntry {
    pub(crate) id: i64,
    pub(crate) entity_type: lorvex_domain::naming::EntityKind,
    pub(crate) entity_id: String,
    pub(crate) operation: String,
    pub(crate) payload: serde_json::Value,
    pub(crate) created_at: String,
    pub(crate) device_id: String,
    pub(crate) synced_at: Option<String>,
    pub(crate) retry_count: i64,
    pub(crate) last_retry_at: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize, PartialEq, Eq)]
pub(crate) struct CurrentFocusView {
    pub(crate) date: String,
    pub(crate) briefing: Option<String>,
    pub(crate) timezone: Option<String>,
    pub(crate) created_at: String,
    pub(crate) updated_at: String,
    pub(crate) task_ids: Vec<String>,
    pub(crate) tasks: Vec<TaskSummary>,
}

#[derive(Debug, Clone, serde::Serialize, PartialEq, Eq)]
pub(crate) struct FocusScheduleView {
    pub(crate) date: String,
    pub(crate) rationale: Option<String>,
    pub(crate) timezone: Option<String>,
    pub(crate) version: String,
    pub(crate) created_at: String,
    pub(crate) updated_at: String,
    pub(crate) blocks: Vec<FocusScheduleBlockView>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub(crate) task_ids_applied: Option<Vec<String>>,
}

#[derive(Debug, Clone, serde::Serialize, PartialEq, Eq)]
pub(crate) struct FocusScheduleBlockView {
    pub(crate) block_type: String,
    pub(crate) start_time: String,
    pub(crate) end_time: String,
    pub(crate) task_id: Option<String>,
    pub(crate) event_id: Option<String>,
    pub(crate) title: Option<String>,
}

pub(crate) type DailyReviewView = lorvex_store::daily_review_ops::DailyReviewRow;

pub(crate) type WeeklyReviewSnapshot = lorvex_workflow::weekly_review::WeeklyReviewSnapshot;

/// Mirror of MCP `get_weekly_review_brief`. The brief differs from the
/// snapshot in that each section reports a `total_matching` count plus a
/// `truncated` flag, so the assistant can decide whether to drill in
/// further. The flat field layout matches the MCP JSON keys verbatim.
pub(crate) type WeeklyReviewBrief = lorvex_workflow::weekly_review::WeeklyReviewBrief;

#[derive(Debug, PartialEq, Eq, serde::Serialize)]
pub(crate) struct DashboardSnapshot {
    pub(crate) db_path: std::path::PathBuf,
    pub(crate) today: String,
    pub(crate) device_id: String,
    pub(crate) open_tasks: i64,
    pub(crate) overdue_tasks: i64,
    pub(crate) current_focus: Option<String>,
    pub(crate) next_task: Option<String>,
    pub(crate) next_task_id: Option<String>,
    pub(crate) due_today: Vec<TaskListItem>,
    pub(crate) upcoming: Vec<TaskListItem>,
    pub(crate) recently_completed: Vec<TaskListItem>,
}

#[derive(Debug, Clone, serde::Serialize, PartialEq, Eq)]
pub(crate) struct HabitSummary {
    pub(crate) id: String,
    pub(crate) name: String,
    pub(crate) icon: Option<String>,
    pub(crate) frequency_type: String,
    pub(crate) target_count: i64,
    pub(crate) completions_today: i64,
}

#[derive(Debug, Clone, serde::Serialize, PartialEq, Eq)]
pub(crate) struct TagSummary {
    pub(crate) id: String,
    pub(crate) display_name: String,
    pub(crate) color: Option<String>,
    pub(crate) task_count: i64,
}

#[derive(Debug, Clone)]
pub(crate) struct McpTargetStatus {
    pub(crate) present: bool,
    pub(crate) points_to_current_cli: Option<bool>,
    /// What kind of binary is configured as the MCP host for this target.
    pub(crate) host_kind: Option<String>,
}

#[derive(Debug, serde::Serialize)]
pub(crate) struct DoctorReport {
    pub(crate) db_path: String,
    pub(crate) db_source: String,
    pub(crate) platform_default_db_path: String,
    pub(crate) device_id: String,
    pub(crate) local_change_seq: i64,
    pub(crate) db_exists_before_open: bool,
    pub(crate) journal_mode: String,
    pub(crate) foreign_keys_enabled: bool,
    pub(crate) mcp_host: bool,
    pub(crate) filesystem_bridge_owner: String,
    pub(crate) claude_desktop_config_present: bool,
    pub(crate) claude_code_config_present: bool,
    pub(crate) codex_config_present: bool,
    pub(crate) claude_desktop_points_to_current_cli: Option<bool>,
    pub(crate) claude_code_points_to_current_cli: Option<bool>,
    pub(crate) codex_points_to_current_cli: Option<bool>,
    pub(crate) mcp_host_authority: Option<String>,
    pub(crate) warnings: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub(crate) info: Vec<String>,
}
