//! Task queries, structured writes, lifecycle transitions, checklist
//! mutations, and recurrence-exception arms. The "big" domain — every
//! variant here works on `tasks` rows or their per-task children
//! (checklist items, recurrence exceptions, batch task writes).

use super::OutputFormat;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum TasksCommand {
    List {
        list_id: Option<String>,
        status: String,
        priority: Option<u8>,
        due_from: Option<String>,
        due_to: Option<String>,
        planned_from: Option<String>,
        planned_to: Option<String>,
        completed_from: Option<String>,
        completed_to: Option<String>,
        created_from: Option<String>,
        created_to: Option<String>,
        has_due_date: Option<bool>,
        has_planned_date: Option<bool>,
        tags: Vec<String>,
        text: Option<String>,
        blocked_only: bool,
        blocking_others: bool,
        sort_by: String,
        sort_direction: String,
        limit: u32,
        format: OutputFormat,
    },
    DependencyGraph {
        task_id: Option<String>,
        list_id: Option<String>,
        include_inactive: bool,
        limit_nodes: u32,
        limit_edges: u32,
        format: OutputFormat,
    },
    Search {
        query: String,
        limit: u32,
        format: OutputFormat,
    },
    Move {
        list_id: String,
        task_ids: Vec<String>,
        format: OutputFormat,
    },
    Show {
        task_id: String,
        format: OutputFormat,
    },
    Today {
        limit: u32,
        format: OutputFormat,
    },
    Overdue {
        limit: u32,
        format: OutputFormat,
    },
    Upcoming {
        days: u32,
        limit: u32,
        format: OutputFormat,
    },
    Deferred {
        list_id: Option<String>,
        limit: u32,
        format: OutputFormat,
    },
    Capture {
        title: String,
        list: Option<String>,
        priority: Option<i64>,
        due_date: Option<String>,
        planned_date: Option<String>,
        estimated_minutes: Option<i64>,
        tags: Vec<String>,
        format: OutputFormat,
    },
    Update {
        task_id: String,
        title: Option<String>,
        body: lorvex_domain::Patch<String>,
        ai_notes: lorvex_domain::Patch<String>,
        // status / raw_input parity with MCP.
        status: Option<String>,
        raw_input: Option<String>,
        list_id: Option<String>,
        priority: lorvex_domain::Patch<i64>,
        due_date: lorvex_domain::Patch<String>,
        due_time: lorvex_domain::Patch<String>,
        planned_date: lorvex_domain::Patch<String>,
        estimated_minutes: lorvex_domain::Patch<i64>,
        tags_set: Option<Vec<String>>,
        tags_add: Option<Vec<String>>,
        tags_remove: Option<Vec<String>>,
        depends_on_set: Option<Vec<String>>,
        depends_on_add: Option<Vec<String>>,
        depends_on_remove: Option<Vec<String>>,
        recurrence: lorvex_domain::Patch<String>,
        idempotency_key: Option<String>,
        format: OutputFormat,
    },
    /// append text to a task's body (MCP `append_to_task_body`).
    AppendBody {
        task_id: String,
        text: String,
        format: OutputFormat,
    },
    /// append AI notes with a date prefix.
    AddAiNotes {
        task_id: String,
        notes: String,
        format: OutputFormat,
    },
    /// add a recurrence exception (MCP `add_task_recurrence_exception`).
    AddRecurrenceException {
        task_id: String,
        date: String,
        format: OutputFormat,
    },
    /// remove a recurrence exception (MCP `remove_task_recurrence_exception`).
    RemoveRecurrenceException {
        task_id: String,
        date: String,
        format: OutputFormat,
    },
    Complete {
        task_ids: Vec<String>,
        format: OutputFormat,
    },
    Reopen {
        task_ids: Vec<String>,
        format: OutputFormat,
    },
    Cancel {
        task_ids: Vec<String>,
        cancel_series: Option<bool>,
        format: OutputFormat,
    },
    Defer {
        task_ids: Vec<String>,
        days: Option<i64>,
        reason: Option<String>,
        structured_reason: Option<String>,
        format: OutputFormat,
    },

    // ── task checklist mutations ───────────────────────
    /// MCP `add_task_checklist_item` mirror.
    ChecklistAdd {
        task_id: String,
        text: String,
        position: Option<u32>,
        format: OutputFormat,
    },
    /// MCP `update_task_checklist_item` mirror.
    ChecklistUpdate {
        item_id: String,
        text: String,
        format: OutputFormat,
    },
    /// MCP `toggle_task_checklist_item` mirror.
    ChecklistToggle {
        item_id: String,
        completed: bool,
        format: OutputFormat,
    },
    /// MCP `remove_task_checklist_item` mirror.
    ChecklistRemove {
        item_id: String,
        format: OutputFormat,
    },
    /// MCP `reorder_task_checklist_items` mirror.
    ChecklistReorder {
        task_id: String,
        item_ids: Vec<String>,
        format: OutputFormat,
    },

    // ── task structured writes ─────────────────────────
    /// MCP `create_task` mirror — distinct from `capture` / `Capture`
    /// (which is the brief lightweight form).
    Create {
        title: String,
        list_id: Option<String>,
        priority: Option<u8>,
        due_date: Option<String>,
        due_time: Option<String>,
        planned_date: Option<String>,
        estimated_minutes: Option<u32>,
        tags: Vec<String>,
        body: Option<String>,
        ai_notes: Option<String>,
        depends_on: Vec<String>,
        reminders: Vec<String>,
        recurrence: Option<String>,
        completed: bool,
        idempotency_key: Option<String>,
        format: OutputFormat,
    },
    /// MCP `set_recurrence` mirror.
    SetRecurrence {
        task_id: String,
        freq: &'static str,
        interval: Option<u32>,
        byday: Vec<String>,
        bymonthday: Vec<i64>,
        until: Option<String>,
        count: Option<u32>,
        format: OutputFormat,
    },
    /// MCP `permanent_delete_task` mirror — distinct verb from
    /// `trash delete` (which routes through the same workflow helper but a
    /// different return shape).
    PermanentDelete {
        task_id: String,
        dry_run: bool,
        format: OutputFormat,
    },
    /// MCP `batch_create_tasks` mirror.
    BatchCreate {
        tasks_json: String,
        include_advice: bool,
        idempotency_key: Option<String>,
        dry_run: bool,
        format: OutputFormat,
    },
    /// MCP `batch_update_tasks` mirror.
    BatchUpdate {
        updates_json: String,
        dry_run: bool,
        format: OutputFormat,
    },
    /// MCP `batch_cancel_tasks_in_list` mirror.
    BatchCancelInList {
        list_id: String,
        statuses: Vec<String>,
        cancel_series: Option<bool>,
        dry_run: bool,
        format: OutputFormat,
    },
}
