use crate::contract::GetCurrentFocusArgs;
use crate::error::McpError;
use crate::json_row::query_one_as_json;
use crate::system::handler_support::{fetch_existing_active_tasks_json, resolve_optional_date};
use rusqlite::Connection;
use serde_json::Value;

use super::model::{enrich_current_focus_row, query_focus_task_ids};

pub(crate) fn get_current_focus(
    conn: &Connection,
    args: GetCurrentFocusArgs,
) -> Result<String, McpError> {
    let GetCurrentFocusArgs { date } = args;
    let date = resolve_optional_date(conn, date)?;
    let plan = query_one_as_json(
        conn,
        "SELECT * FROM current_focus WHERE date = ?",
        [date.clone()],
    )?;

    let Some(plan) = plan else {
        return Ok("null".to_string());
    };

    let mut payload = enrich_current_focus_row(conn, plan)?;
    let task_ids = query_focus_task_ids(conn, &date)?;

    // Batch-fetch all tasks in a single query (eliminates N+1).
    //
    // route through `fetch_existing_active_tasks_json`
    // so a task that was added to focus and then archived no longer
    // surfaces in `tasks[]`. The archive can happen between the
    // pre-write `validate_task_ids_active` gate (#2888 / #2971-H1) and
    // the next read — e.g. user trashes the task in the UI, which is a
    // legitimate write that the focus surface must reflect. The link
    // table row is left in place so the pin re-emerges automatically
    // if the task is restored.
    let tasks = fetch_existing_active_tasks_json(conn, &task_ids)?;

    if let Value::Object(ref mut obj) = payload {
        obj.insert("tasks".to_string(), Value::Array(tasks));
    }
    Ok(serde_json::to_string(&payload)?)
}
