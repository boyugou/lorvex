use super::super::{
    DUE_DATE_PATCH_FIELD_DESCRIPTION, TASK_PRIORITY_FIELD_DESCRIPTION,
    TASK_STATUS_FIELD_DESCRIPTION,
};
use super::{RecurrenceRuleArgs, TaskStatusValue};
use lorvex_domain::Patch;
use schemars::JsonSchema;

#[derive(Debug, Clone, serde::Deserialize, serde::Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub(crate) struct UpdateTaskArgs {
    #[schemars(description = "Task ID to update")]
    pub(crate) id: String,
    #[schemars(description = "New task title")]
    pub(crate) title: Option<String>,
    #[schemars(description = "Task body. Use null to clear.")]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub(crate) body: Patch<String>,
    #[schemars(
        description = "Original user input text (distinct from body — preserves unprocessed phrasing)"
    )]
    pub(crate) raw_input: Option<String>,
    #[schemars(
        description = "Assistant context. Use null to clear; prefer set_task_ai_notes for dedicated assistant-context writes."
    )]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub(crate) ai_notes: Patch<String>,
    // status now uses the typed `TaskStatusValue`
    // enum instead of a stringly-typed `Option<String>`.
    // enum existed but was unused; deserialization happily accepted
    // any string and the deeper `normalize_task_status` gate was the
    // only thing rejecting "Open"/"OPEN"/"opened". With the typed
    // enum, serde rejects bad values at the parse boundary so the
    // schema documents the allow-list `open|completed|cancelled|someday`.
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
    // see `CreateTaskArgs.recurrence` — typed structured form.
    // `Patch<RecurrenceRuleArgs>` carries the tri-state semantics:
    // `Unset` = not in patch, `Clear` = explicit null, `Set(rule)` = set.
    #[schemars(
        description = "Optional structured recurrence rule patch. RRULE-aligned: FREQ + optional INTERVAL/BYDAY/BYMONTH/BYMONTHDAY/BYSETPOS/WKST/UNTIL/COUNT. Use null to clear."
    )]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub(crate) recurrence: Patch<RecurrenceRuleArgs>,
    #[schemars(
        description = "Replaces dependency list. Task IDs this task depends on (blocked by). Mutually exclusive with depends_on_add / depends_on_remove."
    )]
    pub(crate) depends_on: Option<Vec<String>>,
    #[schemars(
        description = "Append dependency edges without replacing the existing set. Task IDs this task depends on (blocked by)."
    )]
    pub(crate) depends_on_add: Option<Vec<String>>,
    #[schemars(description = "Remove dependency edges without replacing the remaining set.")]
    pub(crate) depends_on_remove: Option<Vec<String>>,
    #[schemars(
        description = "Date (YYYY-MM-DD) when the task is planned to be worked on. Separate from due_date (deadline). Use null to clear."
    )]
    #[serde(default, skip_serializing_if = "Patch::is_unset")]
    pub(crate) planned_date: Patch<String>,
    // #3029-H2: optional idempotency token. `update_task` is
    // additive on the `tags_add` / `depends_on` patches — a retry
    // without this key re-runs `apply_tag_side_effects` /
    // `apply_dependency_side_effects` on a row whose state already
    // reflects the prior call. The current side-effect appliers are
    // set-shaped, so the duplicate write is mostly cosmetic at the
    // SQL layer, but the audit trail still records two distinct
    // changelog rows for one logical edit. Mirror the H4 pattern so
    // the cache short-circuits the retry.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate updates; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}
