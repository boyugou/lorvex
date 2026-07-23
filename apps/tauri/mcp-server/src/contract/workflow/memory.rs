use schemars::JsonSchema;

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct ReadMemoryArgs {
    #[schemars(description = "Specific memory section key, or omit for all")]
    pub(crate) key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct WriteMemoryArgs {
    #[schemars(description = "Memory section key")]
    pub(crate) key: String,
    #[schemars(description = "Memory content")]
    pub(crate) content: String,
    // #3029-H2: optional idempotency token. `write_memory`
    // creates an immutable `memory_revision` row on every call; a
    // retried write without this key produces a duplicate revision
    // entry that pollutes `get_memory_history`.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate memory writes (which would otherwise create duplicate revision rows); the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct DeleteMemoryArgs {
    #[schemars(description = "Memory section key to delete")]
    pub(crate) key: String,
    // parity with the other irreversible writes
    // (`delete_list`, `permanent_delete_task`, `delete_habit`,
    // `batch_create_tasks`). When `dry_run=true`, the handler returns
    // the would-be deletion shape with `dry_run: true` *without*
    // touching the row, so the assistant can preview the audit-trail
    // impact (revision history loss, content size) before destroying
    // the memory section.
    #[schemars(
        description = "Issue #2370 / #3006-M21: if true, return the would-be deletion shape with `dry_run: true` and roll back without persisting changes. Default false."
    )]
    #[serde(default)]
    #[schemars(default)]
    pub(crate) dry_run: bool,
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to replay the original memory delete response and avoid duplicate delete audit/sync rows; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetMemoryHistoryArgs {
    #[schemars(description = "Memory section key to get revision history for")]
    pub(crate) key: String,
    #[schemars(description = "Max revisions to return (default 20, max 100)")]
    pub(crate) limit: Option<u32>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct RestoreMemoryRevisionArgs {
    #[schemars(description = "ID of the revision to restore from")]
    pub(crate) revision_id: String,
    // #3029-H2: optional idempotency token. A retried restore
    // without this key creates a second new revision row for the
    // same logical "go back to revision X" intent.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate restores (which would otherwise create a second new revision row); the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}
