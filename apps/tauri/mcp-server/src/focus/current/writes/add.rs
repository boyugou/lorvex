//! `add_to_current_focus` — additive variant. Merges the supplied
//! task ids onto the existing plan (skipping ids already present and
//! reporting them in `skipped_duplicates`), enforcing the same
//! `CURRENT_FOCUS_TASK_IDS_MAX` ceiling as `set_current_focus`.

use lorvex_workflow::current_focus::{AddToCurrentFocusMutation, CURRENT_FOCUS_TASK_IDS_MAX};
use lorvex_workflow::timezone::anchored_timezone_name;
use rusqlite::Connection;

use crate::contract::{AddToCurrentFocusArgs, MAX_BRIEFING_LENGTH};
use crate::contract_validate::{ContractValidate, ValidationCtx};
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_mutation;
use crate::system::handler_support::{resolve_optional_date, utc_now_iso};
use crate::tasks::validation::validate_optional_string_length;

use super::audit::load_enriched_focus;

pub(crate) fn add_to_current_focus(
    conn: &Connection,
    args: AddToCurrentFocusArgs,
) -> Result<String, McpError> {
    // #3029-M4: idempotency cache. Cf. `set_current_focus`.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "add_to_current_focus",
        args.idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }

    if args.task_ids.is_empty() {
        return Err(McpError::Validation(
            "task_ids must contain at least one item".to_string(),
        ));
    }
    // validate every task_id at the trust boundary via the
    // `ContractValidate` derive before merging into the focus list.
    // The `#[validate(exists_in = "tasks_active")]` attribute on
    // `AddToCurrentFocusArgs.task_ids` rejects both phantom and
    // soft-deleted task IDs so an archived task can't ride in via
    // the additive path.
    args.validate(&ValidationCtx::new(conn))?;
    let AddToCurrentFocusArgs {
        task_ids: new_ids,
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

    // also reject duplicates *within* the supplied
    // `new_ids` payload. Duplicates against the existing focus list
    // are tracked separately and reported in the response so the
    // caller can see what was a no-op.
    {
        let mut seen: std::collections::HashSet<&str> =
            std::collections::HashSet::with_capacity(new_ids.len());
        for id in &new_ids {
            if !seen.insert(id.as_str()) {
                return Err(McpError::Validation(format!(
                    "add_to_current_focus rejects duplicate task_id '{id}' in the request payload; every id must appear at most once"
                )));
            }
        }
    }

    // Read existing task_ids and append new ones (skip duplicates).
    // `skipped_duplicates` records which ids were already in the
    // current focus so the response narrates the no-op semantics.
    let mut merged_ids: Vec<String> = if before.is_some() {
        lorvex_store::current_focus_items::query_focus_task_ids(conn, &date)?
    } else {
        Vec::new()
    };
    let before_count = merged_ids.len();
    // Hash-based dedupe:
    // against `merged_ids` per new id, which is O(N·M) for N existing
    // tasks and M new ones. Bounded by `CURRENT_FOCUS_TASK_IDS_MAX` so
    // the worst case is small, but the matching `set_current_focus`
    // path already uses a `HashSet` for the same dedupe shape — this
    // brings the two writers in line.
    let mut existing: std::collections::HashSet<&str> =
        merged_ids.iter().map(String::as_str).collect();
    let mut skipped_duplicates: Vec<String> = Vec::new();
    let mut to_append: Vec<String> = Vec::new();
    for id in &new_ids {
        if existing.contains(id.as_str()) {
            skipped_duplicates.push(id.clone());
        } else {
            existing.insert(id.as_str());
            to_append.push(id.clone());
        }
    }
    drop(existing);
    merged_ids.extend(to_append);

    if merged_ids.len() > CURRENT_FOCUS_TASK_IDS_MAX {
        return Err(McpError::Validation(format!(
            "current focus would exceed {CURRENT_FOCUS_TASK_IDS_MAX} tasks after adding {} new items (current: {before_count})",
            new_ids.len()
        )));
    }

    let added_count = merged_ids.len() - before_count;
    let mutation = AddToCurrentFocusMutation {
        date: date.clone(),
        merged_ids,
        briefing,
        timezone,
        now,
        before,
        added_count,
    };
    let output = execute_mcp_mutation(conn, &mutation, "add_to_current_focus", date)?;

    // surface ids that were already present so the
    // caller can distinguish "added 3, two were already there" from
    // "added 5".
    let mut payload = output.after;
    if let Some(obj) = payload.as_object_mut() {
        obj.insert(
            "skipped_duplicates".to_string(),
            serde_json::Value::Array(
                skipped_duplicates
                    .into_iter()
                    .map(serde_json::Value::String)
                    .collect(),
            ),
        );
    }
    let response = serde_json::to_string(&payload)?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "add_to_current_focus",
        &request_repr,
        &response,
    )?;

    Ok(response)
}
