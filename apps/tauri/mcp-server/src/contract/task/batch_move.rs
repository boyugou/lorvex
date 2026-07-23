use schemars::JsonSchema;

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct BatchMoveTasksArgs {
    pub(crate) task_ids: Vec<String>,
    pub(crate) list_id: String,
    // optional idempotency token. See
    // `BatchCompleteTasksArgs`.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate moves; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}
