use schemars::JsonSchema;

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct ProposeDailyScheduleArgs {
    #[schemars(description = "YYYY-MM-DD. Defaults to today.")]
    pub(crate) date: Option<String>,
}

#[derive(Debug, serde::Deserialize, JsonSchema)]
pub(crate) struct GetSavedFocusScheduleArgs {
    #[schemars(description = "YYYY-MM-DD. Defaults to today.")]
    pub(crate) date: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Deserialize, serde::Serialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub(crate) enum ScheduleBlockType {
    Task,
    Buffer,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct FocusScheduleBlockInput {
    /// buffer blocks intentionally have no
    /// task_id — they're break/transition slots between work
    /// blocks. The previous `task_id: String` shape forced
    /// callers to fabricate a placeholder ("buffer-1",
    /// "break-buffer", …) just to satisfy the type, and the
    /// downstream `materialize_blocks` helper already discards
    /// task_id whenever `block_type != "task"` (see
    /// `server_focus_schedule/shared.rs`). Make the absence
    /// explicit in the wire shape so the JSON Schema accurately
    /// reflects "task_id is required for task blocks, omitted
    /// for buffer blocks" and the assistant stops inventing
    /// throwaway ids.
    #[serde(default)]
    #[schemars(default)]
    pub(crate) task_id: Option<String>,
    pub(crate) start_time: String,
    pub(crate) end_time: String,
    pub(crate) block_type: ScheduleBlockType,
}

#[derive(Debug, serde::Deserialize, serde::Serialize, JsonSchema)]
pub(crate) struct SaveFocusScheduleArgs {
    #[schemars(description = "YYYY-MM-DD. Defaults to today.")]
    pub(crate) date: Option<String>,
    #[schemars(
        description = "Array of time blocks for the schedule (each with task_id, start_time HH:MM, end_time HH:MM, type task|buffer)"
    )]
    pub(crate) blocks: Vec<FocusScheduleBlockInput>,
    #[schemars(description = "AI explanation of the schedule reasoning")]
    pub(crate) rationale: Option<String>,
    // #3029-M4: optional idempotency token. The save path
    // delete-and-rewrites every block for the day, so a retry
    // bumps the HLC version + writes a fresh changelog entry
    // even when nothing changed.
    #[schemars(
        description = "Optional idempotency token. Reuse on retry to short-circuit duplicate schedule saves; the server returns the cached response for ~24h. Omit for non-retryable calls."
    )]
    #[serde(default)]
    pub(crate) idempotency_key: Option<String>,
}
