use lorvex_domain::naming::DeferReason;
use lorvex_domain::TaskLateness;
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Task {
    pub id: String,
    pub title: String,
    pub body: Option<String>,
    pub raw_input: Option<String>,
    pub ai_notes: Option<String>,
    pub status: String,
    pub list_id: String,
    pub tags: Option<Vec<String>>,
    pub checklist_items: Option<Vec<TaskChecklistItem>>,
    pub priority: Option<i64>,
    pub due_date: Option<String>,
    pub due_time: Option<String>,
    pub estimated_minutes: Option<i64>,
    pub recurrence: Option<String>,
    pub recurrence_exceptions: Option<String>,
    pub depends_on: Option<Vec<String>>,
    pub spawned_from: Option<String>,
    pub recurrence_group_id: Option<String>,
    pub canonical_occurrence_date: Option<String>,
    /// Opaque key identifying a specific occurrence of a recurring task —
    /// `"{recurrence_group_id}:{canonical_occurrence_date}"`. When two devices
    /// spawn a successor for the same occurrence offline, the sync merge in
    /// `lorvex_sync::apply::aggregate::merge_duplicate_recurrence_instances`
    /// deduplicates them via this field. Must be present on `Task` so that
    /// `enqueue_task_upsert` → `serde_json::to_value(task)` emits it in the
    /// outbox envelope; otherwise remote peers never see the dedup key and
    /// the merge becomes dead on the Tauri write path.
    pub recurrence_instance_key: Option<String>,
    pub version: String,
    pub created_at: String,
    pub updated_at: String,
    pub completed_at: Option<String>,
    pub last_deferred_at: Option<String>,
    /// typed `DeferReason` mirrors the TS
    /// `DeferReason | null` declaration in `shared/src/types.ts`, so
    /// unrecognised reason values fail to deserialize at the IPC
    /// boundary instead of silently flowing through as opaque strings
    /// on Rust and a typed enum on TypeScript.
    pub last_defer_reason: Option<DeferReason>,
    /// typed `TaskLateness` mirrors the TS `lateness_state?:
    /// TaskLateness | null` declaration in `shared/src/types.ts`, so
    /// unrecognised state values fail to deserialize at the IPC
    /// boundary instead of silently flowing through as opaque strings
    /// on Rust and a typed enum on TypeScript. The `skip_serializing_if`
    /// keeps the field absent (rather than emitting `null`) on tasks
    /// that have no lateness state, matching the TS optionality.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub lateness_state: Option<TaskLateness>,
    pub planned_date: Option<String>,
    pub defer_count: i64,
    /// soft-delete timestamp. `Some` means the task is in the
    /// Trash and must be hidden from every user-facing view; `None` means
    /// active. Propagated through the sync envelope so peers converge on
    /// archive state the same way they do for status/priority.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub archived_at: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct TaskChecklistItem {
    pub id: String,
    pub task_id: String,
    pub position: i64,
    pub text: String,
    pub completed_at: Option<String>,
    pub version: String,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct TaskReminder {
    pub id: String,
    pub task_id: String,
    pub reminder_at: String,
    pub dismissed_at: Option<String>,
    pub cancelled_at: Option<String>,
    pub created_at: String,
    /// Device-local delivery state from `task_reminder_delivery_state` table.
    /// Only populated when querying due/upcoming reminders. `None` means unknown/pending.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub delivery_state: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct TaskList {
    pub id: String,
    pub name: String,
    pub color: Option<String>,
    pub icon: Option<String>,
    pub description: Option<String>,
    pub ai_notes: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ListWithCount {
    #[serde(flatten)]
    pub list: TaskList,
    pub open_count: i64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct DeleteListResult {
    pub deleted_list_id: String,
    /// Opaque snapshot-undo token (#3420). Round-tripped through the
    /// frontend's "Undo" toast; pass back to `undo_delete_entity` to
    /// restore the list within the TTL window. Token shape and TTL
    /// match the calendar-event undo flow (#3392).
    pub undo_token: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CurrentFocusWithTasks {
    pub date: String,
    pub task_ids: Vec<String>,
    pub briefing: Option<String>,
    pub timezone: Option<String>,
    pub tasks: Vec<Task>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CurrentFocusSummary {
    pub task_count: usize,
    pub briefing: Option<String>,
    pub timezone: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ScheduleBlock {
    pub task_id: Option<String>,
    pub start_time: String,
    pub end_time: String,
    pub block_type: String,
    pub event_id: Option<String>,
    pub title: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct FocusScheduleWithTasks {
    pub date: String,
    pub blocks: Vec<ScheduleBlock>,
    pub rationale: Option<String>,
    pub timezone: Option<String>,
    pub created_at: String,
    pub tasks: Vec<Task>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Stats {
    pub open_count: i64,
    pub overdue_count: i64,
    pub today_pool_count: i64,
    pub attention_count: i64,
    pub upcoming_week_count: i64,
    pub completed_today: i64,
    pub completed_this_week: i64,
    pub completed_last_week: i64,
    pub someday_count: i64,
    pub completion_streak: i64,
    pub streak_active_today: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Overview {
    pub stats: Stats,
    pub lists: Vec<ListWithCount>,
    pub current_focus: Option<CurrentFocusSummary>,
    pub top_by_priority: Vec<Task>,
    pub recently_completed: Vec<Task>,
}
