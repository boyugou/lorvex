#[cfg(test)]
use super::*;

/// Runs the body-append mutation against a caller-supplied connection
/// and clock, without Spotlight/event-bus side effects.
#[cfg(test)]
pub(crate) fn append_to_task_body_with_conn(
    conn: &rusqlite::Connection,
    task_id: &lorvex_domain::TaskId,
    text: &str,
    now: &str,
) -> Result<Task, AppError> {
    // Unicode hygiene (#2427): scrub bidi overrides / zero-width / line
    // separators before trim + emptiness check, so text composed entirely
    // of invisible controls is rejected.
    let text = lorvex_domain::sanitize_user_text(text).trim().to_string();
    if text.is_empty() {
        return Err(AppError::Validation("text must not be empty".to_string()));
    }

    with_immediate_transaction(conn, |conn| {
        // stamp the version up front so the body
        // mutation alone carries valid LWW semantics, even before
        // the downstream `finalize_task_mutation` enqueues the
        // outbox row that re-stamps the version. The two stamps
        // are inside the same writer tx so peers see only the
        // post-commit state.
        let version = crate::hlc::generate_version_result()?;
        lorvex_workflow::lifecycle::append_to_task_body(conn, task_id, &text, &version, now)
            .map_err(AppError::from)?;

        finalize_task_mutation(conn, task_id.as_str())
    })
}
