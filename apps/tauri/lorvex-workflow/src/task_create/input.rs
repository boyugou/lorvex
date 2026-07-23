//! Input + result types for [`super::create_task`].
//!
//! Pure data shapes — no IO, no validation. The orchestrator in
//! [`super::orchestrator`] owns the create flow; preparation +
//! effects accumulation live in sibling modules.
//!
//! Every nullable scalar is [`Patch<T>`] so the canonical wire shape
//! matches [`crate::task_update::TaskUpdateInput`]. At create time
//! `Patch::Unset` and `Patch::Clear` are semantically equivalent
//! (both produce SQL NULL); the preparation gate accepts both and
//! collapses them into the single `Option<T>` the writer needs.
//! Surface adapters that only model `Option<T>` (MCP wire boundary,
//! CLI flags) project `Some(v) → Set(v)` and `None → Unset`. Tauri
//! IPC payloads accept `null → Clear` for symmetry with the update
//! path; the value never reaches SQL in a different shape than
//! `Unset` would. The collection-shaped fields (`tags`, `depends_on`,
//! `reminders`) stay `Option<Vec<String>>` here — the tag /
//! dependency patch shapes are tracked separately in.
//!
//! `title` and `id` stay as bare `String` because the create path
//! requires them: there is no row to fall back to.

use lorvex_domain::{Patch, TaskId};
use serde_json::Value;

#[derive(Debug, Clone, Default)]
pub struct TaskCreateInput {
    pub title: String,
    pub list_id: Patch<String>,
    pub priority: Patch<u8>,
    pub due_date: Patch<String>,
    pub due_time: Patch<String>,
    pub estimated_minutes: Patch<u32>,
    pub tags: Option<Vec<String>>,
    pub body: Patch<String>,
    pub raw_input: Patch<String>,
    pub ai_notes: Patch<String>,
    pub depends_on: Option<Vec<String>>,
    pub reminders: Option<Vec<String>>,
    pub recurrence_json: Patch<String>,
    pub planned_date: Patch<String>,
    pub completed: Option<bool>,
    /// Optional initial status. When `Patch::Unset` / `Patch::Clear`
    /// the task is created with `STATUS_OPEN`. The only other value
    /// accepted by `create_task` is `STATUS_SOMEDAY`; any other value
    /// is rejected with a typed validation error so the canonical
    /// create path remains the single source of truth for status
    /// seeding.
    pub status: Patch<String>,
}

impl TaskCreateInput {
    /// The canonical field set this input accepts. Used by the
    /// repo-governance contract test that pins MCP and Tauri/CLI to
    /// the same wire shape across create + update.
    pub const FIELDS: &'static [&'static str] = &[
        "title",
        "list_id",
        "priority",
        "due_date",
        "due_time",
        "estimated_minutes",
        "tags",
        "body",
        "raw_input",
        "ai_notes",
        "depends_on",
        "reminders",
        "recurrence_json",
        "planned_date",
        "completed",
        "status",
    ];
}

#[derive(Debug, Clone)]
pub struct CreateTaskInput {
    pub id: Option<String>,
    pub task: TaskCreateInput,
    pub include_advice: bool,
}

#[derive(Debug, Clone)]
pub struct CreateTaskSpawnedSuccessor {
    pub successor_id: TaskId,
    pub summary: String,
    pub after_task: Value,
}

#[derive(Debug, Clone)]
pub struct CreateTaskFocusRewireAudit {
    pub parent_task_id: TaskId,
    pub successor_id: TaskId,
    pub focus_schedule_dates: Vec<String>,
    pub current_focus_dates: Vec<String>,
}

#[derive(Debug)]
pub struct CreateTaskResult {
    pub task_id: TaskId,
    pub task: Value,
    pub next_occurrence: Value,
    pub newly_unblocked: Vec<Value>,
    pub advice: Vec<Value>,
    pub payload: Value,
    pub summary: String,
    pub sync_effects: super::effects::CreateTaskSyncEffects,
}
