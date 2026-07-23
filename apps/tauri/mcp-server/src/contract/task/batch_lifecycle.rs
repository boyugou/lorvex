use schemars::JsonSchema;

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct BatchCompleteTasksArgs {
    pub(crate) task_ids: Vec<String>,
    // optional idempotency token mirroring `create_task` /
    // `batch_create_tasks`. Without it, a transport flake during the
    // response leg of a successful retry caused the assistant to retry
    // the call and silently double-process the completion (recurrence
    // successors spawned twice, completion sound played twice).
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate completions; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct BatchCancelTasksArgs {
    #[schemars(description = "Task IDs to cancel")]
    pub(crate) task_ids: Vec<String>,
    #[schemars(description = "Optional cancellation reason")]
    pub(crate) reason: Option<String>,
    // explicit semantics for the mixed-batch case.
    // `cancel_series` is a *per-task* directive applied uniformly to
    // every id in `task_ids`. Behavior table:
    //
    // | task type      | cancel_series=true       | cancel_series=false        |
    // |----------------|--------------------------|----------------------------|
    // | non-recurring  | cancelled (no successor) | cancelled (no successor)   |
    // | recurring      | series stopped, rule
    //                    cleared on the cancelled
    //                    instance, no successor   | this occurrence cancelled,
    //                                               next occurrence spawned   |
    //
    // The flag is a no-op for non-recurring tasks — there is no
    // "series" to stop. A regression test in `cancel_by_ids.rs`
    // (`batch_cancel_mixed_recurring_and_non_recurring_respects_cancel_series`)
    // pins the invariant.
    #[schemars(
        description = "Per-task directive applied uniformly to every id. If true and a task is recurring, stop the entire series (clear recurrence rule, do not spawn the next occurrence). For non-recurring tasks the flag is a no-op (cancellation behavior is identical regardless of the flag). Default false: cancel this occurrence and spawn the next for recurring tasks; cancel only for non-recurring tasks."
    )]
    pub(crate) cancel_series: Option<bool>,
    #[schemars(
        description = "Issue #2370: if true, return the would-be cancellation shape (cancelled ids, already-done ids, any spawned successors) with `dry_run: true`, and roll back. Default false."
    )]
    // see `BatchCreateTasksArgs::dry_run`.
    #[serde(default)]
    #[schemars(default)]
    pub(crate) dry_run: bool,
    // optional idempotency token. See
    // `BatchCompleteTasksArgs`.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate batch cancellations; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct BatchReopenTasksArgs {
    #[schemars(description = "Task IDs to reopen")]
    pub(crate) task_ids: Vec<String>,
    // optional idempotency token. See
    // `BatchCompleteTasksArgs`.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate reopens; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct BatchDeferTasksArgs {
    #[schemars(description = "Task IDs to defer")]
    pub(crate) task_ids: Vec<String>,
    #[schemars(
        description = "Absolute planned date target in YYYY-MM-DD. Canonical deferral semantics are absolute, not relative."
    )]
    pub(crate) until_date: String,
    #[schemars(description = "Why the tasks are being deferred (appended to ai_notes)")]
    pub(crate) reason: Option<String>,
    #[schemars(
        description = "Structured defer reason: not_today, blocked, low_energy, needs_breakdown, needs_info. Stored in last_defer_reason column."
    )]
    pub(crate) structured_reason: Option<String>,
    // optional idempotency token. See
    // `BatchCompleteTasksArgs`.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate defers; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}
