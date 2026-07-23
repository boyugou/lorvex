//! Shared helpers for task batch cancellation surfaces.

use serde_json::Value;

/// Filter `before_tasks` to a parallel vector aligned with `ids` for
/// the `before_states` audit field used by every cancel/defer batch
/// path.
pub(super) fn filter_before_states(before_tasks: &[Value], ids: &[String]) -> Vec<Value> {
    ids.iter()
        .filter_map(|tid| {
            before_tasks
                .iter()
                .find(|task| task.get("id").and_then(Value::as_str) == Some(tid))
                .cloned()
        })
        .collect()
}
