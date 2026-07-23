use super::*;

#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct DueReminderEntry {
    pub task: Task,
    pub reminder: TaskReminder,
}

pub(super) fn reminder_from_query_row(
    row: lorvex_store::repositories::task::reminders::ReminderRow,
) -> TaskReminder {
    // #3286: ReminderRow's timestamp fields are typed `SyncTimestamp`;
    // the wire model `TaskReminder` still carries `String` for now (the
    // typed migration of the Tauri-shaped models is a follow-up batch),
    // so render through `.as_string()` to preserve byte-identical
    // canonical RFC 3339 millisecond `Z` form.
    TaskReminder {
        id: row.id,
        task_id: row.task_id,
        reminder_at: row.reminder_at.as_string(),
        dismissed_at: row.dismissed_at.map(|ts| ts.as_string()),
        cancelled_at: row.cancelled_at.map(|ts| ts.as_string()),
        created_at: row.created_at.as_string(),
        delivery_state: Some(row.delivery_state),
    }
}

pub(super) fn hydrate_due_reminder_entries(
    conn: &rusqlite::Connection,
    rows: Vec<lorvex_store::repositories::task::reminders::ReminderRow>,
) -> AppResult<Vec<DueReminderEntry>> {
    if rows.is_empty() {
        return Ok(Vec::new());
    }

    let task_ids: Vec<String> = rows.iter().map(|row| row.task_id.clone()).collect();
    let tasks_by_id = fetch_tasks_by_ids(conn, &task_ids)?;

    let mut entries = Vec::with_capacity(rows.len());
    for row in rows {
        let task = tasks_by_id
            .get(&row.task_id)
            .cloned()
            .ok_or_else(|| AppError::NotFound(format!("Task not found: {}", row.task_id)))?;
        entries.push(DueReminderEntry {
            task,
            reminder: reminder_from_query_row(row),
        });
    }
    Ok(entries)
}
