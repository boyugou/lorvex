//! Wire-shape input types for the batch task-update workflow.
//!
//! `BatchUpdateTaskPatchInput` is an alias for the per-row patch the
//! single-item `update_task` surface also consumes — keeping the
//! canonical definition in [`crate::task_update::TaskUpdateInput`]
//! means MCP, Tauri, CLI, and the batch surface share one wire shape
//! and any new field flows through both call sites automatically.

use crate::task_update::TaskUpdateInput;

/// Single-row patch input. Type alias preserves the canonical batch
/// name while keeping the wire definition in
/// [`TaskUpdateInput`].
pub type BatchUpdateTaskPatchInput = TaskUpdateInput;

/// Cap on the number of rows accepted in one batch — both as an
/// input-validation guard and as the cycle-revalidation cost ceiling.
pub const BATCH_UPDATE_TASKS_LIMIT: usize = 500;

#[derive(Debug, Clone, serde::Deserialize)]
#[serde(deny_unknown_fields)]
pub struct BatchUpdateTasksInput {
    pub updates: Vec<BatchUpdateTaskPatchInput>,
}
