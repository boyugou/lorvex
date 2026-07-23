//! `upsert_habit_reminder_policy` — create or update a single
//! reminder slot for a habit. Idempotent through the canonical
//! request fingerprint cache. Validates HH:MM shape + habit existence
//! at the trust boundary before any write work, and threads the
//! pre-mutation row through `before_json` so the changelog records
//! the prior state on updates.

use lorvex_workflow::habit_reminder_ops;
use lorvex_workflow::habit_reminder_policy::UpsertHabitReminderPolicyMutation;
use rusqlite::Connection;
use serde_json::Value;

use crate::contract::UpsertHabitReminderPolicyArgs;
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_mutation_with_dynamic_audit_finalizer;
use crate::system::handler_support::utc_now_iso;

use super::validate::validate_habit_id_exists;

pub(crate) fn upsert_habit_reminder_policy(
    conn: &Connection,
    args: UpsertHabitReminderPolicyArgs,
) -> Result<String, McpError> {
    // idempotency cache. Capture the canonical
    // request fingerprint BEFORE any work so a retried upsert
    // (which fans out to ai_changelog + sync envelopes) short-
    // circuits to the cached response.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let idempotency_key = args.idempotency_key.clone();
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "upsert_habit_reminder_policy",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }

    // gate the HH:MM shape at the trust boundary.
    // scheduler later silently dropped reminders when it could not
    // parse them. Route through the canonical `validate_time_format`
    // shared with the calendar / task `due_time` paths.
    lorvex_domain::validation::validate_time_format(&args.reminder_time)?;

    // gate `habit_id` existence at the trust boundary
    // so a phantom habit reference fails with a clean Validation
    // error before any write work happens.
    validate_habit_id_exists(conn, &args.habit_id)?;

    // #2939-H3: capture the pre-mutation policy (if updating an
    // existing slot) so the changelog before_json reflects the
    // prior state. New-create paths leave it `None`.
    let before_json: Option<Value> = match args.id.as_deref() {
        Some(existing_id) if !existing_id.trim().is_empty() => {
            habit_reminder_ops::load_policy_by_id(conn, existing_id)?
                .map(serde_json::to_value)
                .transpose()?
        }
        _ => None,
    };

    let mutation = UpsertHabitReminderPolicyMutation {
        policy_id: args.id,
        habit_id: args.habit_id,
        reminder_time: args.reminder_time,
        enabled: args.enabled.unwrap_or(true),
        before_json,
        now: utc_now_iso(),
    };
    let output = execute_mcp_mutation_with_dynamic_audit_finalizer(
        conn,
        &mutation,
        "upsert_habit_reminder_policy",
        McpError::from,
        |execution| {
            execution
                .output
                .after
                .get("id")
                .and_then(Value::as_str)
                .unwrap_or(&mutation.habit_id)
                .to_string()
        },
        |_, _| Ok(()),
    )?;

    let response = serde_json::to_string(&output.after)?;
    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "upsert_habit_reminder_policy",
        &request_repr,
        &response,
    )?;
    Ok(response)
}
