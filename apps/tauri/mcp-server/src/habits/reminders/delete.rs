//! `delete_habit_reminder_policy` — tombstone-emitting deletion of a
//! single reminder slot. Idempotent through the canonical request
//! fingerprint cache. Captures the pre-delete snapshot so the
//! changelog `before_json` and the outbox tombstone payload describe
//! what was removed.

use std::collections::HashMap;

use lorvex_workflow::habit_reminder_ops;
use lorvex_workflow::habit_reminder_policy::DeleteHabitReminderPolicyMutation;
use rusqlite::Connection;
use serde_json::Value;

use crate::contract::DeleteHabitReminderPolicyArgs;
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_mutation_with_tombstone_audit_finalizer;

pub(crate) fn delete_habit_reminder_policy(
    conn: &Connection,
    args: DeleteHabitReminderPolicyArgs,
) -> Result<String, McpError> {
    // idempotency cache. Capture canonical fingerprint
    // before destructure so a retried delete short-circuits to the
    // cached response (a re-run would emit duplicate tombstone +
    // changelog audit rows).
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    // dry_run is consumed by the router-level
    // `dispatch_dry_run` wrapper; the body runs identically in
    // real and preview modes.
    let DeleteHabitReminderPolicyArgs {
        id,
        dry_run: _,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "delete_habit_reminder_policy",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    // Fetch before-state for changelog / sync payload
    let before_policy = habit_reminder_ops::load_policy_by_id(conn, &id)?;
    let before = before_policy
        .as_ref()
        .map(serde_json::to_value)
        .transpose()?;
    let habit_name = before
        .as_ref()
        .and_then(|v| v.get("habit_name"))
        .and_then(|v| v.as_str())
        .unwrap_or("habit")
        .to_string();
    // Thread the captured pre-delete policy snapshot through both the
    // changelog `before_json` and the outbox tombstone payload.
    let mut tombstones: HashMap<String, Value> = HashMap::with_capacity(1);
    if let Some(before_value) = before.clone() {
        tombstones.insert(id.clone(), before_value);
    }
    let mutation = DeleteHabitReminderPolicyMutation {
        id: id.clone(),
        before,
        habit_name,
    };
    let output = execute_mcp_mutation_with_tombstone_audit_finalizer(
        conn,
        &mutation,
        "delete_habit_reminder_policy",
        id,
        tombstones,
        McpError::from,
        |_, _| Ok(()),
    )?;

    let response = serde_json::to_string(&output.after)?;
    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "delete_habit_reminder_policy",
        &request_repr,
        &response,
    )?;
    Ok(response)
}
