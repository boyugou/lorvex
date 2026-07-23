use lorvex_mcp_derive::ContractValidate;
use schemars::JsonSchema;

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetCurrentFocusArgs {
    #[schemars(description = "YYYY-MM-DD. Defaults to today.")]
    pub(crate) date: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct SetCurrentFocusArgs {
    #[schemars(
        description = "Ordered list of task IDs for today's focus. First = highest priority."
    )]
    #[validate(exists_in = "tasks_active")]
    pub(crate) task_ids: Vec<String>,
    #[schemars(description = "Assistant contextual note for the day.")]
    pub(crate) briefing: Option<String>,
    #[schemars(description = "YYYY-MM-DD. Defaults to today.")]
    pub(crate) date: Option<String>,
    // #3029-M4: optional idempotency token. Without it a retry
    // re-runs the full materialize_focus_items rewrite (delete-all
    // + insert-N) and writes a fresh changelog row even though the
    // user-visible state is unchanged.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate focus rewrites; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct AddToCurrentFocusArgs {
    #[schemars(description = "Task IDs to append to the current focus. Duplicates are skipped.")]
    #[validate(exists_in = "tasks_active")]
    pub(crate) task_ids: Vec<String>,
    #[schemars(description = "Update briefing text. If omitted, existing briefing is preserved.")]
    pub(crate) briefing: Option<String>,
    #[schemars(description = "YYYY-MM-DD. Defaults to today.")]
    pub(crate) date: Option<String>,
    // #3029-M4: optional idempotency token. Cf.
    // `SetCurrentFocusArgs`.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate focus appends; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct ClearCurrentFocusArgs {
    #[schemars(description = "YYYY-MM-DD. Defaults to today.")]
    pub(crate) date: Option<String>,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct RemoveFromCurrentFocusArgs {
    #[schemars(description = "Task ID to remove from the current focus.")]
    pub(crate) task_id: String,
    #[schemars(description = "YYYY-MM-DD. Defaults to today.")]
    pub(crate) date: Option<String>,
}
