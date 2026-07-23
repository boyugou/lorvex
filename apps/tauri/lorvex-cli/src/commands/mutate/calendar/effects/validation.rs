//! Pure CLI-local validation + sanitization helpers that survive after
//! the calendar event create/update/delete write paths were routed
//! through [`lorvex_workflow::calendar_event`] (#4345 step b). The
//! workflow op owns title / text / URL / color / timezone / time /
//! date-range / recurrence normalization end-to-end; what stays here
//! is the surface area shared by the link, exception, and provider-link
//! helpers — title normalization for create/update entry validation,
//! the canonical event-type parser the CLI argument layer reuses, the
//! free-form CLI-id sanitizer (provider event keys), and the task-id
//! list de-duper.

/// Sanitize, trim, and refuse an empty CLI-supplied identifier. Used
/// by the provider-event link/unlink helpers — the calendar-event
/// surface accepts external task ids, provider kinds, and provider
/// event keys as opaque strings, but the provider event key in
/// particular is free-form text that lands in `task_provider_event_links`
///. Sanitize-then-trim mirrors every other CLI
/// trust boundary so bidi overrides, ZWSP, and control characters can
/// never reach the DB.
pub(super) fn normalize_nonempty_cli_id(
    value: &str,
    label: &str,
) -> Result<String, crate::error::CliError> {
    let sanitized = lorvex_domain::sanitize_user_text(value);
    let normalized = sanitized.trim();
    if normalized.is_empty() {
        return Err(crate::error::CliError::Validation(format!(
            "{label} must not be empty"
        )));
    }
    Ok(normalized.to_string())
}

pub(super) fn normalize_calendar_title(title: &str) -> Result<String, crate::error::CliError> {
    let sanitized = lorvex_domain::sanitize_user_text(title);
    let title = sanitized.trim();
    if title.is_empty() {
        return Err(crate::error::CliError::Validation(
            "calendar event title must not be empty".to_string(),
        ));
    }
    lorvex_domain::validation::validate_title(title)?;
    Ok(title.to_string())
}

pub(super) fn normalize_calendar_event_type(
    value: Option<&str>,
) -> Result<lorvex_domain::CanonicalCalendarEventType, crate::error::CliError> {
    match value.unwrap_or("event") {
        "event" => Ok(lorvex_domain::CanonicalCalendarEventType::Event),
        "birthday" => Ok(lorvex_domain::CanonicalCalendarEventType::Birthday),
        "anniversary" => Ok(lorvex_domain::CanonicalCalendarEventType::Anniversary),
        "memorial" => Ok(lorvex_domain::CanonicalCalendarEventType::Memorial),
        other => Err(crate::error::CliError::Validation(format!(
            "calendar event type must be one of: event, birthday, anniversary, memorial. Got: {other}"
        ))),
    }
}

pub(super) fn normalize_calendar_link_task_ids(
    task_ids: &[String],
) -> Result<Vec<String>, crate::error::CliError> {
    const MAX_LINK_TASKS: usize = 500;
    if task_ids.is_empty() {
        return Err(crate::error::CliError::Validation(
            "task_ids must contain at least one item".to_string(),
        ));
    }
    if task_ids.len() > MAX_LINK_TASKS {
        return Err(crate::error::CliError::Validation(format!(
            "calendar link supports at most {MAX_LINK_TASKS} task ids"
        )));
    }

    let mut normalized = Vec::with_capacity(task_ids.len());
    let mut seen = std::collections::HashSet::with_capacity(task_ids.len());
    for task_id in task_ids {
        let task_id = task_id.trim();
        if task_id.is_empty() {
            return Err(crate::error::CliError::Validation(
                "task id must not be empty".to_string(),
            ));
        }
        if seen.insert(task_id.to_string()) {
            normalized.push(task_id.to_string());
        }
    }
    Ok(normalized)
}
