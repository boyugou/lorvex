//! Array count caps for defense-in-depth validation.
use crate::error::McpError;
use std::collections::HashSet;

/// Maximum number of reminders per task.
///
/// re-exported from `lorvex_domain::validation` so the
/// CLI / MCP / Tauri write surfaces share one source of truth rather
/// than three same-valued declarations under three different names
/// that drifted on every cap bump.
pub(crate) use lorvex_domain::validation::MAX_REMINDERS_PER_TASK;
/// Maximum number of blocks in a focus schedule.
pub(crate) const MAX_SCHEDULE_BLOCKS: usize = 100;
/// Maximum number of IDs in a single batch operation.
const MAX_BATCH_IDS: usize = 500;

/// Validate that a required Vec does not exceed `max_count` entries.
fn validate_required_vec_count<T>(
    items: &[T],
    field_name: &str,
    max_count: usize,
) -> Result<(), McpError> {
    if items.len() > max_count {
        return Err(McpError::Validation(format!(
            "{field_name} exceeds maximum count ({} items, limit {max_count})",
            items.len()
        )));
    }
    Ok(())
}

/// Validate reminders count (for set_task_reminders).
pub(crate) fn validate_reminders_count(reminders: &[String]) -> Result<(), McpError> {
    validate_required_vec_count(reminders, "reminders", MAX_REMINDERS_PER_TASK)
}

/// Validate that a batch ID list is non-empty, within the max batch
/// size, and free of duplicate ids.
///
/// `[t1, t1, t1]` passed cleanly and the downstream `WHERE id IN (?, ?,
/// ?)` predicate silently deduplicated the targets. Callers that
/// retried failed completions by re-sending the same id list saw
/// confusing `NotFound` diagnostics ("requested 3, found 1") because
/// the validator never told them the duplicates were the real problem.
/// Reject duplicates explicitly so the failure mode is loud.
pub(crate) fn validate_batch_ids(ids: &[String], tool_name: &str) -> Result<(), McpError> {
    if ids.is_empty() {
        return Err(McpError::Validation(format!(
            "{tool_name} requires at least one ID"
        )));
    }
    if ids.len() > MAX_BATCH_IDS {
        return Err(McpError::Validation(format!(
            "{tool_name} supports at most {MAX_BATCH_IDS} items, got {}",
            ids.len()
        )));
    }
    let mut seen: HashSet<&str> = HashSet::with_capacity(ids.len());
    for id in ids {
        if !seen.insert(id.as_str()) {
            return Err(McpError::Validation(format!(
                "{tool_name} rejects duplicate id '{id}'; every id must appear at most once"
            )));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests;
