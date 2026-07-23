use schemars::JsonSchema;

// typed status enum used at every status-bearing
// patch boundary (`UpdateTaskArgs.status`,
// `BatchUpdateTaskPatch.status`, `BatchCancelTasksInListArgs.statuses`).
// unused in this module. Wiring it through the args makes the JSON
// Schema document the allow-list and fails malformed retries at parse
// instead of inside `normalize_task_status`.
#[derive(Debug, Clone, Copy, serde::Deserialize, serde::Serialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub(crate) enum TaskStatusValue {
    Open,
    Completed,
    Cancelled,
    Someday,
}
