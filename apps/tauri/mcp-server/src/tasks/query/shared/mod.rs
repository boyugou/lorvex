use crate::error::McpError;
use crate::system::handler_support::next_offset_for_page;
use serde::Serialize;
use serde_json::{json, Value};

/// paginated variant. Echoes the request `offset` and
/// computes `next_offset` so callers can walk through page-2 and
/// beyond without losing access to the tail of the result set. The
/// trying to fetch the second page had no way to learn the right
/// offset to use, so anything beyond page 1 was silently inaccessible.
///
/// `next_offset` is `null` when the current page already exhausted
/// the matching rows (no further pages); otherwise it is
/// `offset + tasks.len()`.
pub(super) fn build_task_collection_payload_with_offset(
    limit: u32,
    offset: u32,
    total_matching: i64,
    tasks: Vec<Value>,
) -> Value {
    let returned = tasks.len() as i64;
    let consumed = i64::from(offset).saturating_add(returned);
    let next_offset = next_offset_for_page(total_matching > consumed, consumed, returned);
    json!({
        "limit": limit,
        "offset": offset,
        "count": tasks.len(),
        "returned": tasks.len(),
        "total_matching": total_matching,
        "truncated": total_matching > consumed,
        "next_offset": next_offset,
        "tasks": tasks,
    })
}

pub(super) fn serialize_payload(payload: &Value) -> Result<String, McpError> {
    Ok(serde_json::to_string(payload)?)
}

pub(crate) fn rows_to_values<T>(
    rows: impl IntoIterator<Item = T>,
    context: &str,
) -> Result<Vec<Value>, McpError>
where
    T: Serialize,
{
    rows.into_iter()
        .map(|row| {
            serde_json::to_value(row)
                .map_err(|error| McpError::Serialization(format!("{context}: {error}")))
        })
        .collect()
}

pub(super) fn insert_object_field(
    payload: &mut Value,
    key: &str,
    value: Value,
) -> Result<(), McpError> {
    let object = payload.as_object_mut().ok_or_else(|| {
        McpError::Internal("task collection payload must be a JSON object".to_string())
    })?;
    object.insert(key.to_string(), value);
    Ok(())
}

#[cfg(test)]
mod tests;
