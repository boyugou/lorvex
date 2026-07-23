//! `get_habit_reminder_policies` — read-only list of every habit
//! reminder policy currently configured. Delegates to the workflow
//! layer which already returns the canonical JSON shape.

use rusqlite::Connection;

use crate::contract::GetHabitReminderPoliciesArgs;
use crate::error::McpError;
use lorvex_workflow::habit_reminder_ops;

pub(crate) fn get_habit_reminder_policies(
    conn: &Connection,
    _args: GetHabitReminderPoliciesArgs,
) -> Result<String, McpError> {
    let policies = habit_reminder_ops::list_all_policies(conn)?;
    Ok(serde_json::to_string(&policies)?)
}
