use crate::contract::{
    GetDueTaskRemindersArgs, GetUpcomingTaskRemindersArgs, DUE_REMINDERS_LIMIT_CAP,
    DUE_REMINDERS_LIMIT_DEFAULT, UPCOMING_REMINDERS_HOURS_CAP, UPCOMING_REMINDERS_HOURS_DEFAULT,
    UPCOMING_REMINDERS_LIMIT_CAP, UPCOMING_REMINDERS_LIMIT_DEFAULT,
};
use crate::error::McpError;
use crate::system::handler_support::{bounded_limit, next_offset_for_page};
use lorvex_store::repositories::task::reminders;
use rusqlite::Connection;
use serde_json::json;

pub(crate) fn get_due_task_reminders(
    conn: &Connection,
    args: &GetDueTaskRemindersArgs,
) -> Result<String, McpError> {
    let limit = bounded_limit(
        args.limit,
        DUE_REMINDERS_LIMIT_DEFAULT,
        DUE_REMINDERS_LIMIT_CAP,
    );
    let offset = args.offset;

    // Use the shared canonical sync timestamp shape for lex comparisons
    // against task_reminders.reminder_at.
    let now = lorvex_domain::sync_timestamp_now();

    // implement offset by widening the store fetch
    // (limit + offset) and slicing locally. The store layer keeps the
    // truncation-detection optimization intact for the offset-zero
    // poller path; deeper pagination pays a fetch overhead but still
    // doesn't run a separate COUNT.
    let widened_limit = limit.saturating_add(offset);
    let result = reminders::get_due_task_reminders(conn, &now, widened_limit)?;

    let mut rows = result.rows;
    let offset_usize = offset as usize;
    if rows.len() > offset_usize {
        rows.drain(0..offset_usize);
    } else {
        rows.clear();
    }
    let returned = rows.len() as i64;
    let consumed = i64::from(offset).saturating_add(returned);
    let truncated = result.total_matching < 0 || result.total_matching > consumed;
    let next_offset = next_offset_for_page(truncated, consumed, returned);
    // #2422: fence `task_title` on each reminder row.
    let mut reminders = serde_json::to_value(&rows)?;
    if let Some(arr) = reminders.as_array_mut() {
        for row in arr.iter_mut() {
            if let Some(obj) = row.as_object_mut() {
                crate::system::text_hygiene::fence_object_field(obj, "task_title");
            }
        }
    }
    let payload = json!({
        "limit": limit,
        "offset": offset,
        "total_matching": result.total_matching,
        "returned": returned,
        "truncated": truncated,
        "count": returned,
        "next_offset": next_offset,
        "reminders": reminders,
    });
    Ok(serde_json::to_string(&payload)?)
}

pub(crate) fn get_upcoming_task_reminders(
    conn: &Connection,
    args: &GetUpcomingTaskRemindersArgs,
) -> Result<String, McpError> {
    let hours = bounded_limit(
        args.hours,
        UPCOMING_REMINDERS_HOURS_DEFAULT,
        UPCOMING_REMINDERS_HOURS_CAP,
    );
    let limit = bounded_limit(
        args.limit,
        UPCOMING_REMINDERS_LIMIT_DEFAULT,
        UPCOMING_REMINDERS_LIMIT_CAP,
    );
    let offset = args.offset;

    let now = chrono::Utc::now();
    let horizon = now + chrono::Duration::hours(i64::from(hours));
    // Shared canonical sync timestamp shape; see `get_due_task_reminders`.
    let now_str = lorvex_domain::format_sync_timestamp(now);
    let horizon_str = lorvex_domain::format_sync_timestamp(horizon);

    // see `get_due_task_reminders` for the
    // widen-then-slice pagination pattern. The store layer fetches
    // `limit+offset+1` to keep truncation detection alive.
    let widened_limit = limit.saturating_add(offset);
    let result =
        reminders::get_upcoming_task_reminders_until(conn, &now_str, &horizon_str, widened_limit)?;

    let mut rows = result.rows;
    let offset_usize = offset as usize;
    if rows.len() > offset_usize {
        rows.drain(0..offset_usize);
    } else {
        rows.clear();
    }
    let returned = rows.len() as i64;
    let consumed = i64::from(offset).saturating_add(returned);
    let truncated = result.total_matching < 0 || result.total_matching > consumed;
    let next_offset = next_offset_for_page(truncated, consumed, returned);
    // #2422: fence `task_title` on each reminder row.
    let mut reminders = serde_json::to_value(&rows)?;
    if let Some(arr) = reminders.as_array_mut() {
        for row in arr.iter_mut() {
            if let Some(obj) = row.as_object_mut() {
                crate::system::text_hygiene::fence_object_field(obj, "task_title");
            }
        }
    }
    let payload = json!({
        "hours_window": hours,
        "limit": limit,
        "offset": offset,
        "total_matching": result.total_matching,
        "returned": returned,
        "truncated": truncated,
        "count": returned,
        "next_offset": next_offset,
        "reminders": reminders,
    });
    Ok(serde_json::to_string(&payload)?)
}
