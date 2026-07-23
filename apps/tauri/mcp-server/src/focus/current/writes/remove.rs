//! `remove_from_current_focus` — drop a single task id from the plan.
//! Fails with NotFound when no plan exists for `date`, with Validation
//! when the task id is not in the plan. The mutation marks
//! `plan_cleared = true` when the removal empties the plan; the audit
//! finalizer (`log_remove_from_current_focus_audit`) switches the
//! changelog op between DELETE and UPDATE on that signal.

use lorvex_workflow::current_focus::RemoveFromCurrentFocusMutation;
use rusqlite::Connection;

use crate::contract::RemoveFromCurrentFocusArgs;
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_mutation_with_finalizer;
use crate::system::handler_support::{resolve_optional_date, utc_now_iso};

use super::audit::{load_enriched_focus, log_remove_from_current_focus_audit};

pub(crate) fn remove_from_current_focus(
    conn: &Connection,
    args: RemoveFromCurrentFocusArgs,
) -> Result<String, McpError> {
    let RemoveFromCurrentFocusArgs { task_id, date } = args;
    let date = resolve_optional_date(conn, date)?;
    let now = utc_now_iso();

    let before = load_enriched_focus(conn, &date)?;

    let before =
        before.ok_or_else(|| McpError::NotFound(format!("no current focus exists for {date}")))?;

    let mut task_ids = lorvex_store::current_focus_items::query_focus_task_ids(conn, &date)?;
    let original_len = task_ids.len();
    task_ids.retain(|id| id != &task_id);

    if task_ids.len() == original_len {
        return Err(McpError::Validation(format!(
            "task {task_id} is not in the current focus for {date}"
        )));
    }

    let mutation = RemoveFromCurrentFocusMutation {
        date,
        task_id,
        remaining_task_ids: task_ids,
        now,
        before,
    };
    let output =
        execute_mcp_mutation_with_finalizer(conn, &mutation, McpError::from, |execution| {
            log_remove_from_current_focus_audit(conn, &execution)
        })?;

    Ok(serde_json::to_string(&output.after)?)
}
