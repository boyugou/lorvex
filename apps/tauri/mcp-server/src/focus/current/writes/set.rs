//! `set_current_focus` — overwrite the plan for `date` with the given
//! task ids. Rejects empty / over-limit / duplicate id lists, validates
//! every task id at the trust boundary, and chains through the standard
//! mutation executor (no custom audit finalizer — `SetCurrentFocusMutation`
//! emits the changelog itself).

use lorvex_workflow::current_focus::{SetCurrentFocusMutation, CURRENT_FOCUS_TASK_IDS_MAX};
use lorvex_workflow::timezone::anchored_timezone_name;
use rusqlite::Connection;

use crate::contract::{SetCurrentFocusArgs, MAX_BRIEFING_LENGTH};
use crate::contract_validate::{ContractValidate, ValidationCtx};
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_mutation;
use crate::system::handler_support::{resolve_optional_date, utc_now_iso};
use crate::tasks::validation::validate_optional_string_length;

use super::audit::load_enriched_focus;

pub(crate) fn set_current_focus(
    conn: &Connection,
    args: SetCurrentFocusArgs,
) -> Result<String, McpError> {
    // #3029-M4: idempotency cache. Cf. `batch_complete_tasks`.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "set_current_focus",
        args.idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }

    if args.task_ids.is_empty() || args.task_ids.len() > CURRENT_FOCUS_TASK_IDS_MAX {
        return Err(McpError::Validation(format!(
            "task_ids must contain between 1 and {CURRENT_FOCUS_TASK_IDS_MAX} items"
        )));
    }
    // reject duplicate task_ids explicitly. The
    // downstream `materialize_focus_items` writer dedupes silently,
    // which would have shrunk the user's intended plan from "five
    // tasks, two of them the same" to four rows without telling them.
    {
        let mut seen: std::collections::HashSet<&str> =
            std::collections::HashSet::with_capacity(args.task_ids.len());
        for id in &args.task_ids {
            if !seen.insert(id.as_str()) {
                return Err(McpError::Validation(format!(
                    "set_current_focus rejects duplicate task_id '{id}'; every id must appear at most once"
                )));
            }
        }
    }
    // validate every task_id at the trust boundary via the
    // `ContractValidate` derive. The `#[validate(exists_in =
    // "tasks_active")]` attribute on `SetCurrentFocusArgs.task_ids`
    // emits a `validate_task_ids_active` call that rejects both
    // phantom and soft-deleted (archived) IDs — every task read
    // path filters `archived_at IS NULL`, so an archived row in the
    // focus would render as an empty ghost just like a phantom UUID.
    args.validate(&ValidationCtx::new(conn))?;
    let SetCurrentFocusArgs {
        task_ids,
        briefing,
        date,
        idempotency_key,
    } = args;
    let briefing = briefing.map(|s| lorvex_domain::sanitize_user_text(&s));
    validate_optional_string_length(briefing.as_deref(), "briefing", MAX_BRIEFING_LENGTH)?;

    let date = resolve_optional_date(conn, date)?;
    let now = utc_now_iso();
    let timezone = anchored_timezone_name(conn)?;

    let before = load_enriched_focus(conn, &date)?;

    let operation = if before.is_some() { "update" } else { "create" };
    let mutation = SetCurrentFocusMutation {
        date: date.clone(),
        task_ids,
        briefing,
        timezone,
        now,
        before,
        operation,
    };
    let output = execute_mcp_mutation(conn, &mutation, "set_current_focus", date)?;

    let response = serde_json::to_string(&output.after)?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "set_current_focus",
        &request_repr,
        &response,
    )?;

    Ok(response)
}
