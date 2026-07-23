use super::super::{DUE_DATE_FIELD_DESCRIPTION, TASK_PRIORITY_FIELD_DESCRIPTION};
use super::RecurrenceRuleArgs;
use schemars::JsonSchema;

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
#[serde(deny_unknown_fields)]
pub(crate) struct CreateTaskArgs {
    #[schemars(description = "Task title")]
    pub(crate) title: String,
    #[schemars(description = "List ID")]
    pub(crate) list_id: Option<String>,
    // surface the 1|2|3 allow-list directly in the
    // emitted JSON Schema via `range(min=1,max=3)` so strict assistant
    // clients reject 0/4-255 at the schema validation step instead of
    // riding the value into the deeper `validate_priority` gate.
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
    // typed RRULE-aligned shape.
    // `Option<String>` carrying a hand-parsed JSON blob; the typed
    // form gates freq + range + cardinality at the JSON Schema
    // boundary so malformed retries never reach the canonical
    // normalizer.
    #[schemars(
        description = "Optional structured recurrence rule. RRULE-aligned: FREQ + optional INTERVAL/BYDAY/BYMONTH/BYMONTHDAY/BYSETPOS/WKST/UNTIL/COUNT. INTERVAL defaults to 1. BYDAY array only for WEEKLY/MONTHLY/YEARLY. BYMONTHDAY -31..=-1 / 1..=31 only for MONTHLY/YEARLY. COUNT and UNTIL mutually exclusive."
    )]
    pub(crate) recurrence: Option<RecurrenceRuleArgs>,
    #[schemars(
        description = "Date (YYYY-MM-DD) when the task is planned to be worked on. Separate from due_date (deadline)."
    )]
    pub(crate) planned_date: Option<String>,
    #[schemars(
        description = "If true, immediately mark the task as completed after creation (sets status='completed', completed_at=now, spawns recurrence, unblocks dependents). Use for historical logging or past activity capture."
    )]
    pub(crate) completed: Option<bool>,
    #[schemars(
        description = "If true, return bounded deterministic intake advisories alongside the created task."
    )]
    pub(crate) include_advice: Option<bool>,
    #[schemars(
        description = "Optional idempotency token. Clients that retry this tool after a transient failure should reuse the same key; the server short-circuits duplicates by returning the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}
