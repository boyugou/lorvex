//! Audit-summary builder for the batch task-update workflow.
//!
//! Produces the one-line `"Updated N task(s): 'title1', 'title2', …"`
//! string the changelog UI groups by. Validates that every updated
//! task carries the `title` field the rich-return contract requires —
//! a missing field would indicate the per-row apply silently produced
//! an incomplete row, which the audit funnel must surface rather than
//! mask with a blank string.

use lorvex_store::StoreError;
use serde_json::Value;

pub(super) fn build_batch_update_summary(updated_tasks: &[Value]) -> Result<String, StoreError> {
    let titles = updated_tasks
        .iter()
        .map(|task| {
            let title = task.get("title").and_then(Value::as_str).ok_or_else(|| {
                StoreError::Invariant(
                    "batch_update_tasks updated-task: missing string field `title`".to_string(),
                )
            })?;
            Ok(format!("'{title}'"))
        })
        .collect::<Result<Vec<_>, StoreError>>()?
        .join(", ");
    Ok(format!(
        "Updated {} task{}: {}",
        updated_tasks.len(),
        if updated_tasks.len() == 1 { "" } else { "s" },
        titles
    ))
}
