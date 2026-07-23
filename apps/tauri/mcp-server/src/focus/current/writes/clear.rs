//! `clear_current_focus` — wipe the plan for `date`. Reads the
//! pre-clear snapshot via `get_current_focus` so the response (and the
//! changelog audit emitted by `log_clear_current_focus_audit`) narrates
//! what was removed. Returns the canonical "no plan" shape (`current:
//! null`) on success — the same shape `get_current_focus` returns for
//! an empty day — so clients see one structural payload either way.

use lorvex_workflow::current_focus::ClearCurrentFocusMutation;
use rusqlite::Connection;

use crate::contract::ClearCurrentFocusArgs;
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_mutation_with_finalizer;
use crate::system::handler_support::resolve_optional_date;

use super::audit::log_clear_current_focus_audit;

pub(crate) fn clear_current_focus(
    conn: &Connection,
    args: ClearCurrentFocusArgs,
) -> Result<String, McpError> {
    let ClearCurrentFocusArgs { date } = args;
    let date = resolve_optional_date(conn, date)?;

    // CLAUDE.md rule 5 mandates rich return values. The
    // previous `{cleared: true, date}` shape forced the assistant to
    // either say "done" without specifics or re-call get_current_focus
    // to narrate what was cleared (#2177 writer-lock pressure). Read
    // the pre-clear snapshot and include it in the response.
    let before = crate::focus::current::get_current_focus(
        conn,
        crate::contract::GetCurrentFocusArgs {
            date: Some(date.clone()),
        },
    )?;
    let before_value: serde_json::Value =
        serde_json::from_str(&before).unwrap_or(serde_json::Value::Null);

    let mutation = ClearCurrentFocusMutation {
        date,
        before: before_value,
    };
    let output =
        execute_mcp_mutation_with_finalizer(conn, &mutation, McpError::from, |execution| {
            log_clear_current_focus_audit(conn, &execution)
        })?;

    Ok(serde_json::to_string(&output.after)?)
}
