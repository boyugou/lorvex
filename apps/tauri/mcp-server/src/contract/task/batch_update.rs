use super::super::{
    DUE_DATE_PATCH_FIELD_DESCRIPTION, TASK_PRIORITY_FIELD_DESCRIPTION,
    TASK_STATUS_FIELD_DESCRIPTION,
};
use super::{RecurrenceRuleArgs, TaskStatusValue};
use lorvex_domain::Patch;
use schemars::JsonSchema;

#[derive(Debug, serde::Deserialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub(crate) struct BatchUpdateTaskPatch {
    #[schemars(description = "Task ID to update")]
    pub(crate) id: String,
    #[schemars(description = "New task title")]
    pub(crate) title: Option<String>,
    #[schemars(description = "Task body. Use null to clear.")]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub(crate) body: Patch<String>,
    #[schemars(description = "Original user input")]
    pub(crate) raw_input: Option<String>,
    #[schemars(description = "AI notes. Use null to clear.")]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub(crate) ai_notes: Patch<String>,
    // see `UpdateTaskArgs.status` — typed enum at the
    // parse boundary instead of stringly-typed.
    #[schemars(description = TASK_STATUS_FIELD_DESCRIPTION)]
    pub(crate) status: Option<TaskStatusValue>,
    #[schemars(description = "List ID to move the task to")]
    pub(crate) list_id: Option<String>,
    #[schemars(description = "Replace the full tag set. Pass [] to clear all tags.")]
    pub(crate) tags_set: Option<Vec<String>>,
    #[schemars(description = "Append tags without replacing the existing set.")]
    pub(crate) tags_add: Option<Vec<String>>,
    #[schemars(description = "Remove tags without replacing the remaining set.")]
    pub(crate) tags_remove: Option<Vec<String>>,
    // see `CreateTaskArgs.priority` — every priority
    // schema slot now declares `range(min=1,max=3)` so strict clients
    // reject out-of-band values at parse.
    #[schemars(description = TASK_PRIORITY_FIELD_DESCRIPTION, range(min = 1, max = 3))]
    pub(crate) priority: Option<u8>,
    #[schemars(description = DUE_DATE_PATCH_FIELD_DESCRIPTION)]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub(crate) due_date: Patch<String>,
    #[schemars(description = "Due time in HH:MM. Use null to clear.")]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub(crate) due_time: Patch<String>,
    #[schemars(description = "Estimated duration in minutes. Use null to clear.")]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub(crate) estimated_minutes: Patch<u32>,
    // typed RRULE-aligned shape; see
    // `UpdateTaskArgs.recurrence`. Tri-state semantics preserved.
    #[schemars(
        description = "Optional structured recurrence rule patch. RRULE-aligned: FREQ + optional INTERVAL/BYDAY/BYMONTH/BYMONTHDAY/BYSETPOS/WKST/UNTIL/COUNT. Use null to clear."
    )]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub(crate) recurrence: Patch<RecurrenceRuleArgs>,
    #[schemars(
        description = "Replaces dependency list. Task IDs this task depends on. Mutually exclusive with depends_on_add / depends_on_remove."
    )]
    pub(crate) depends_on: Option<Vec<String>>,
    #[schemars(description = "Append dependency edges without replacing the existing set.")]
    pub(crate) depends_on_add: Option<Vec<String>>,
    #[schemars(description = "Remove dependency edges without replacing the remaining set.")]
    pub(crate) depends_on_remove: Option<Vec<String>>,
    #[schemars(
        description = "Date (YYYY-MM-DD) when the task is planned to be worked on. Separate from due_date (deadline). Use null to clear."
    )]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub(crate) planned_date: Patch<String>,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
// `deny_unknown_fields` makes the JSON-side surface
// reject any caller-supplied flag the server doesn't know about
// (instead of silently dropping it on the floor). The destructure in
// `batch::update::batch_update_tasks` already exhausts the
// fields below, so adding a new bool here without wiring it into the
// destructure is a compile error too — the Rust side is exhaustive
// and the wire side is deny-unknown, closing both halves of the
// "future flag added but never read" failure mode.
#[serde(deny_unknown_fields)]
pub(crate) struct BatchUpdateTasksArgs {
    pub(crate) updates: Vec<BatchUpdateTaskPatch>,
    #[schemars(
        description = "Issue #2370: if true, apply every patch in a rolled-back savepoint, validate dependency cycles, return the would-be updated rows with `dry_run: true`, and roll back. Default false."
    )]
    // see `BatchCreateTasksArgs::dry_run`.
    #[serde(default)]
    #[schemars(default)]
    pub(crate) dry_run: bool,
}
