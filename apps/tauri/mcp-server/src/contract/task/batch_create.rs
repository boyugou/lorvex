use super::super::{DUE_DATE_FIELD_DESCRIPTION, TASK_PRIORITY_FIELD_DESCRIPTION};
use super::RecurrenceRuleArgs;
use schemars::JsonSchema;

// see sibling args — Serialize required for the
// idempotency-cache checksum.
#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub(crate) struct BatchCreateTaskInput {
    #[schemars(description = "Task title")]
    pub(crate) title: String,
    #[schemars(description = "List ID")]
    pub(crate) list_id: Option<String>,
    // see `CreateTaskArgs.priority` — every priority
    // schema slot now declares `range(min=1,max=3)` so strict clients
    // reject out-of-band values at parse.
    #[schemars(description = TASK_PRIORITY_FIELD_DESCRIPTION, range(min = 1, max = 3))]
    pub(crate) priority: Option<u8>,
    #[schemars(description = DUE_DATE_FIELD_DESCRIPTION)]
    pub(crate) due_date: Option<String>,
    #[schemars(description = "Due time in HH:MM")]
    pub(crate) due_time: Option<String>,
    #[schemars(description = "Estimated duration in minutes")]
    pub(crate) estimated_minutes: Option<u32>,
    #[schemars(description = "Task tags")]
    pub(crate) tags: Option<Vec<String>>,
    #[schemars(description = "Task body")]
    pub(crate) body: Option<String>,
    #[schemars(description = "Original user input")]
    pub(crate) raw_input: Option<String>,
    #[schemars(description = "AI notes")]
    pub(crate) ai_notes: Option<String>,
    #[schemars(description = "Task IDs this task depends on")]
    pub(crate) depends_on: Option<Vec<String>>,
    #[schemars(description = "Array of ISO reminder timestamps.")]
    pub(crate) reminders: Option<Vec<String>>,
    // typed RRULE-aligned shape; see
    // `CreateTaskArgs.recurrence`.
    #[schemars(
        description = "Optional structured recurrence rule. RRULE-aligned: FREQ + optional INTERVAL/BYDAY/BYMONTH/BYMONTHDAY/BYSETPOS/WKST/UNTIL/COUNT. INTERVAL defaults to 1. COUNT and UNTIL mutually exclusive."
    )]
    pub(crate) recurrence: Option<RecurrenceRuleArgs>,
    #[schemars(
        description = "Date (YYYY-MM-DD) when the task is planned to be worked on. Separate from due_date (deadline)."
    )]
    pub(crate) planned_date: Option<String>,
    #[schemars(description = "If true, immediately mark the task as completed after creation.")]
    pub(crate) completed: Option<bool>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct BatchCreateTasksArgs {
    pub(crate) tasks: Vec<BatchCreateTaskInput>,
    #[schemars(
        description = "If true, return bounded deterministic intake advisories for each created task."
    )]
    pub(crate) include_advice: Option<bool>,
    #[schemars(
        description = "Optional idempotency token. Clients that retry this tool after a transient failure should reuse the same key; the server short-circuits duplicates by returning the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
    #[schemars(
        description = "Issue #2370: if true, prepare the batch insert, return the would-be created tasks (including freshly-minted IDs and any advisory output) with `dry_run: true`, then roll back. Does not consume the idempotency key. Default false."
    )]
    // schemars must mirror serde's default so the
    // emitted JSON Schema marks `dry_run` optional. Without
    // `#[schemars(default)]` the schema marks it required and
    // strict assistant clients reject calls that omit it.
    #[serde(default)]
    #[schemars(default)]
    pub(crate) dry_run: bool,
}
