use super::{
    model::{hydrate_due_reminder_entries, reminder_from_query_row},
    *,
};

/// Returns due reminders (pending delivery, not dismissed/cancelled).
/// Delegates predicate to the shared `task_reminder_query` repo, then
/// enriches each result with the full Task object for the UI.
#[tauri::command]
pub fn get_due_reminders() -> Result<Vec<DueReminderEntry>, String> {
    let result = (|| -> AppResult<Vec<DueReminderEntry>> {
        let conn = get_read_conn()?;
        let now = sync_timestamp_now();

        let result =
            lorvex_store::repositories::task::reminders::get_due_task_reminders(&conn, &now, 50)?;
        hydrate_due_reminder_entries(&conn, result.rows)
    })();

    result.map_err(String::from)
}

/// Returns reminders due within the next `within_seconds` seconds (for adaptive polling).
/// Delegates predicate to the shared `task_reminder_query` repo.
#[tauri::command]
pub fn get_upcoming_reminders(
    within_seconds: Option<i64>,
) -> Result<Vec<DueReminderEntry>, String> {
    let result = (|| -> AppResult<Vec<DueReminderEntry>> {
        let conn = get_read_conn()?;
        let now = chrono::Utc::now();
        let seconds = clamp_limit(within_seconds, 120, 1, MAX_REMINDER_QUERY_WINDOW_SECONDS);
        let horizon = now + chrono::Duration::seconds(seconds);
        // Route through `format_sync_timestamp` so these comparison
        // strings match the millisecond-Z canonical form produced by
        // `sync_timestamp_now()` (see
        // `lorvex-domain/src/time/sync_timestamp.rs`). Using
        // `SecondsFormat::Micros` would mix 6-digit fractions into a
        // column otherwise written at 3-digit precision; the
        // resulting lex-comparisons would silently misorder rows at
        // the fractional-second boundary.
        let now_str = format_sync_timestamp(now);
        let horizon_str = format_sync_timestamp(horizon);

        let result =
            lorvex_store::repositories::task::reminders::get_upcoming_task_reminders_until(
                &conn,
                &now_str,
                &horizon_str,
                20,
            )?;
        hydrate_due_reminder_entries(&conn, result.rows)
    })();

    result.map_err(String::from)
}

/// Get all reminders for a specific task.
///
/// Routes through the shared `reminders::get_reminders_for_task`
/// repository helper so MCP and Tauri agree on the predicate. A bare
/// `task_reminders` SELECT with no `tasks` join would return
/// reminders attached to trashed (`archived_at IS NOT NULL`) tasks
/// and the task-detail view would render them, even though the
/// adjacent notification poller (through `get_due_task_reminders` /
/// `get_upcoming_task_reminders_until`) correctly suppresses them.
/// Centralizing the predicate in one helper keeps both surfaces
/// converged on the same trash semantics.
#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn get_task_reminders(task_id: String) -> Result<Vec<TaskReminder>, String> {
    let task_id = crate::commands::shared::validate_uuid_id(&task_id, "task_id")?;
    let result = (|| -> AppResult<Vec<TaskReminder>> {
        let conn = get_read_conn()?;
        get_task_reminders_for_validated_task_id(&conn, task_id)
    })();

    result.map_err(String::from)
}

#[cfg(test)]
pub(super) fn get_task_reminders_with_conn(
    conn: &rusqlite::Connection,
    task_id: &str,
) -> AppResult<Vec<TaskReminder>> {
    let task_id = crate::commands::shared::validate_uuid_id(task_id, "task_id")
        .map_err(AppError::Validation)?;
    get_task_reminders_for_validated_task_id(conn, task_id)
}

fn get_task_reminders_for_validated_task_id(
    conn: &rusqlite::Connection,
    task_id: String,
) -> AppResult<Vec<TaskReminder>> {
    let rows = lorvex_store::repositories::task::reminders::get_reminders_for_task(
        conn,
        &lorvex_domain::TaskId::from_trusted(task_id),
    )?;
    Ok(rows.into_iter().map(reminder_from_query_row).collect())
}
