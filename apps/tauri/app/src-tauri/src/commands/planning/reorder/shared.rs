use super::*;

pub(super) fn normalize_requested_task_ids(task_ids: Vec<String>) -> Vec<String> {
    let mut normalized_requested: Vec<String> = Vec::new();
    let mut seen_requested: HashSet<String> = HashSet::new();
    for raw_id in task_ids {
        if raw_id.is_empty() {
            continue;
        }
        if seen_requested.insert(raw_id.clone()) {
            normalized_requested.push(raw_id);
        }
    }
    normalized_requested
}

pub(super) fn validate_same_open_task_ids(
    current_ids: &[String],
    requested_ids: &[String],
    error_message: &str,
) -> Result<(), AppError> {
    // Return a typed validation error so the IPC envelope's `kind`
    // tag stays accurate. A bare `String` would launder through the
    // catch-all `From<String>` impl into `AppError::Internal` and the
    // renderer would surface an opaque "internal error" toast instead
    // of the actionable validation message.
    let current_set: HashSet<String> = current_ids.iter().cloned().collect();
    let requested_set: HashSet<String> = requested_ids.iter().cloned().collect();
    if requested_ids.len() != current_ids.len() || current_set != requested_set {
        return Err(AppError::Validation(error_message.to_string()));
    }
    Ok(())
}
