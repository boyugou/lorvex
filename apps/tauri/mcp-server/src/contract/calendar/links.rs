use lorvex_mcp_derive::ContractValidate;
use schemars::JsonSchema;

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct LinkTaskToEventArgs {
    #[schemars(description = "Task id to link")]
    #[validate(uuid)]
    pub(crate) task_id: String,
    #[schemars(description = "Calendar event id to link")]
    #[validate(uuid)]
    pub(crate) event_id: String,
    // #3029-M4: optional idempotency token. The link upsert is
    // already LWW-gated, but a retry still bumps the HLC version
    // and writes a fresh audit row. Use the cache to suppress that
    // tail.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate links; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
    // #3033-H5: dry_run preview affordance. A relink against an
    // existing edge re-stamps the HLC and writes a fresh audit row;
    // the assistant should be able to preview the would-be edge
    // (including the relink-vs-fresh shape) before committing.
    #[schemars(
        description = "If true, run the link in a rolled-back savepoint and return the would-be edge payload tagged `dry_run: true` (no commit, no audit, no sync envelope). Default false."
    )]
    #[serde(default)]
    #[schemars(default)]
    pub(crate) dry_run: bool,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct BatchLinkTasksToEventArgs {
    #[schemars(description = "Task IDs to link")]
    pub(crate) task_ids: Vec<String>,
    #[schemars(description = "Calendar event id to link to")]
    pub(crate) event_id: String,
    // optional idempotency token. See
    // `BatchCompleteTasksArgs`.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate link batches; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

impl crate::contract_validate::ContractValidate for BatchLinkTasksToEventArgs {
    fn validate_shape(&self) -> Result<(), crate::error::McpError> {
        for task_id in &self.task_ids {
            crate::tasks::validation::validate_uuid_shape(task_id, "task_ids")?;
        }
        crate::tasks::validation::validate_uuid_shape(&self.event_id, "event_id")
    }
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema, ContractValidate)]
pub(crate) struct UnlinkTaskFromEventArgs {
    #[schemars(description = "Task id")]
    #[validate(uuid)]
    pub(crate) task_id: String,
    #[schemars(description = "Calendar event id")]
    #[validate(uuid)]
    pub(crate) event_id: String,
    // #3029-M4: optional idempotency token. Cf.
    // `LinkTaskToEventArgs`. A retry produces a phantom audit row
    // for an already-deleted edge.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate unlinks; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
    // #3033-H5: dry_run preview affordance. The unlink emits a
    // tombstone envelope that is replicated to peers; the assistant
    // should be able to preview the would-be `{deleted, links}`
    // payload before committing.
    #[schemars(
        description = "If true, run the unlink in a rolled-back savepoint and return the would-be `{deleted, links}` payload tagged `dry_run: true` (no commit). Default false."
    )]
    #[serde(default)]
    #[schemars(default)]
    pub(crate) dry_run: bool,
}

#[derive(Debug, serde::Deserialize, JsonSchema, ContractValidate)]
pub(crate) struct GetLinkedEventsForTaskArgs {
    #[schemars(description = "Task id")]
    #[validate(uuid)]
    pub(crate) task_id: String,
}

#[derive(Debug, serde::Deserialize, JsonSchema, ContractValidate)]
pub(crate) struct GetLinkedTasksForEventArgs {
    #[schemars(description = "Calendar event id")]
    #[validate(uuid)]
    pub(crate) event_id: String,
}
