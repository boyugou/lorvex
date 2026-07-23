use schemars::JsonSchema;

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct AddEventExceptionArgs {
    #[schemars(description = "Calendar event ID")]
    pub(crate) event_id: String,
    #[schemars(description = "Date to exclude from recurrence in YYYY-MM-DD format")]
    pub(crate) date: String,
    // #3029-M4: optional idempotency token. A retry without this
    // key writes a duplicate exception entry — silently destructive
    // against the recurrence series.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate exception writes; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
    // #3029-M4: dry_run preview affordance. Symmetric with
    // `permanent_delete_task` and `delete_calendar_event` —
    // adding an exception is destructive against a recurring
    // series and the assistant should be able to preview the
    // would-be exception list before committing.
    #[schemars(
        description = "If true, run the exception write in a rolled-back savepoint and return the would-be shape with `dry_run: true` (no commit). Default false."
    )]
    #[serde(default)]
    #[schemars(default)]
    pub(crate) dry_run: bool,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct RemoveEventExceptionArgs {
    #[schemars(description = "Calendar event ID")]
    pub(crate) event_id: String,
    #[schemars(description = "Date to restore to recurrence in YYYY-MM-DD format")]
    pub(crate) date: String,
    // #3029-M4: optional idempotency token. A retry of the remove
    // path against an already-removed exception writes a phantom
    // audit row.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate exception removals; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}
