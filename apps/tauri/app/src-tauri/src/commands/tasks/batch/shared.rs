//! Shared scaffolding for the per-operation `batch_*` task commands.
//!
//! Holds the IPC-boundary id validator shared by batch lifecycle commands.

use crate::error::AppError;

/// Maximum number of task ids accepted by any `batch_*` command. Caps the
/// worst-case memory + writer-mutex hold time — each id triggers a
/// `fetch_task_by_id` round-trip and at least one outbox enqueue, all
/// inside a single `with_immediate_transaction` closure.
pub(crate) const MAX_BATCH_TASK_IDS: usize = 500;

/// Shape-check and de-duplicate every task UUID at the IPC boundary
/// before opening the writer transaction. Mirrors the pattern audit
/// #2948-M1 / #2970-H3 already established for sibling task-id IPC
/// handlers (`validate_current_focus_task_ids`). The previous body
/// only checked the array length — a malformed id flowed straight
/// into `fetch_tasks_by_ids` and only surfaced as an opaque
/// sync-apply mismatch on a peer device.
///
/// Returns the canonical (trimmed), first-seen ids on success so callers can
/// drop the original `Vec<String>` and use the validated copy
/// throughout the writer body. Duplicate ids are not meaningful in a batch
/// lifecycle request; preserving them can mint duplicate audit/undo rows for
/// one real mutation.
pub(crate) fn validate_batch_task_ids(task_ids: &[String]) -> Result<Vec<String>, AppError> {
    if task_ids.is_empty() {
        return Err(AppError::Validation(
            "task_ids must contain at least one item".to_string(),
        ));
    }
    if task_ids.len() > MAX_BATCH_TASK_IDS {
        return Err(AppError::Validation(format!(
            "task_ids exceeds maximum of {} items (got {})",
            MAX_BATCH_TASK_IDS,
            task_ids.len()
        )));
    }
    let mut seen = std::collections::HashSet::new();
    let mut validated = Vec::with_capacity(task_ids.len());
    for raw in task_ids {
        let id = crate::commands::shared::validate_uuid_id(raw, "task_id")
            .map_err(AppError::Validation)?;
        if seen.insert(id.clone()) {
            validated.push(id);
        }
    }
    Ok(validated)
}
