//! Cross-row guards for the batch task-update workflow.
//!
//! Validates the shape of the incoming `id` list — UUID shape, no
//! duplicates, within the batch cap — before any SQL runs. The
//! per-row dependency-cycle revalidation that runs against the final
//! edge state lives in [`crate::task_update::mutation::revalidate_dependency_cycles`];
//! this module only owns the pre-run id-list guards.

use lorvex_store::StoreError;

use crate::task_update::mutation::validate_task_id_shape;

use super::input::BATCH_UPDATE_TASKS_LIMIT;

pub(super) fn validate_batch_ids(ids: &[String], tool_name: &str) -> Result<(), StoreError> {
    if ids.is_empty() {
        return Err(StoreError::Validation(format!(
            "{tool_name} requires at least one ID"
        )));
    }
    if ids.len() > BATCH_UPDATE_TASKS_LIMIT {
        return Err(StoreError::Validation(format!(
            "{tool_name} supports at most {BATCH_UPDATE_TASKS_LIMIT} items, got {}",
            ids.len()
        )));
    }
    let mut seen = std::collections::HashSet::new();
    for id in ids {
        validate_task_id_shape(id, "id")?;
        if !seen.insert(id.as_str()) {
            return Err(StoreError::Validation(format!(
                "{tool_name} contains duplicate id '{id}'"
            )));
        }
    }
    Ok(())
}
