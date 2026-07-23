use crate::error::McpError;
use crate::runtime::change_tracking::{
    execute_mcp_mutation_with_undo_tombstone_audit_finalizer, log_change, LogChangeParams,
};
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{
    EDGE_HABIT_COMPLETION, ENTITY_HABIT, ENTITY_HABIT_REMINDER_POLICY, OP_DELETE,
};
use lorvex_domain::HabitId;
use lorvex_store::StoreError;
use lorvex_sync::outbox_enqueue::{
    tombstone_completions_for_habit_delete, tombstone_reminder_policies_for_habit_delete,
};
use lorvex_workflow::mutation::{Mutation, MutationExecution, MutationOutput};
use lorvex_workflow::mutation_extras::{
    HABIT_DELETE_COMPLETION_TOMBSTONES, HABIT_DELETE_REMINDER_POLICY_TOMBSTONES,
};
use rusqlite::Connection;
use serde_json::{json, Value};
use std::collections::HashMap;

use super::super::load_habit_required;

struct DeleteHabitMutation {
    habit_id: HabitId,
    habit_name: String,
    pre_habit_json: Value,
    previous_response: Value,
    undo_token_json: String,
}

impl Mutation for DeleteHabitMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_HABIT
    }

    fn operation(&self) -> &'static str {
        OP_DELETE
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.pre_habit_json.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let child_tombstone_version = hlc.next_version_string();
        let completions =
            tombstone_completions_for_habit_delete(conn, &self.habit_id, &child_tombstone_version)
                .map_err(|error| {
                    StoreError::Invariant(format!(
                        "habit delete completion tombstone write failed: {error}"
                    ))
                })?;
        let reminder_policies = tombstone_reminder_policies_for_habit_delete(
            conn,
            &self.habit_id,
            &child_tombstone_version,
        )
        .map_err(|error| {
            StoreError::Invariant(format!(
                "habit delete reminder policy tombstone write failed: {error}"
            ))
        })?;

        let completions_destroyed = completions.len();
        let reminder_policies_destroyed = reminder_policies.len();

        let delete_version = hlc.next_version_string();
        lorvex_store::repositories::lww_delete::execute_lww_delete_by_id(
            conn,
            "habits",
            "id",
            ENTITY_HABIT,
            self.habit_id.as_str(),
            &delete_version,
        )?;

        let mut output = MutationOutput::new(
            json!({
                "deleted": true,
                "id": self.habit_id.as_str(),
                "name": self.habit_name,
                "undo_token": self.undo_token_json,
                "completions_destroyed": completions_destroyed,
                "reminder_policies_destroyed": reminder_policies_destroyed,
                "previous": self.previous_response,
            }),
            format!(
                "Deleted habit '{}' — destroyed {} completion record{} + {} reminder polic{}",
                self.habit_name,
                completions_destroyed,
                if completions_destroyed == 1 { "" } else { "s" },
                reminder_policies_destroyed,
                if reminder_policies_destroyed == 1 {
                    "y"
                } else {
                    "ies"
                },
            ),
        );
        output.set_extra(
            &HABIT_DELETE_COMPLETION_TOMBSTONES,
            Value::Array(
                completions
                    .iter()
                    .map(|completion| {
                        json!({
                            "entity_id": completion.entity_id(),
                            "completed_date": completion.completed_date,
                            "payload": completion.payload(),
                        })
                    })
                    .collect(),
            ),
        );
        output.set_extra(
            &HABIT_DELETE_REMINDER_POLICY_TOMBSTONES,
            Value::Array(
                reminder_policies
                    .iter()
                    .map(|policy| {
                        json!({
                            "id": policy.id.as_str(),
                            "payload": policy.payload(),
                        })
                    })
                    .collect(),
            ),
        );
        Ok(output)
    }
}

fn log_habit_delete_child_tombstones(
    conn: &Connection,
    execution: &MutationExecution,
) -> Result<(), McpError> {
    let habit_name = execution
        .output
        .after
        .get("name")
        .and_then(Value::as_str)
        .unwrap_or("habit");

    let completion_tombstones = execution
        .output
        .get_extra(&HABIT_DELETE_COMPLETION_TOMBSTONES)
        .and_then(Value::as_array)
        .ok_or_else(|| {
            McpError::Internal(
                "Mutation contract: habit delete completion tombstones extra is an array"
                    .to_string(),
            )
        })?;
    for completion in completion_tombstones {
        let entity_id = completion
            .get("entity_id")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                McpError::Internal(
                    "Mutation contract: habit delete completion tombstone has entity_id"
                        .to_string(),
                )
            })?;
        let completed_date = completion
            .get("completed_date")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                McpError::Internal(
                    "Mutation contract: habit delete completion tombstone has completed_date"
                        .to_string(),
                )
            })?;
        let snapshot = completion.get("payload").cloned().ok_or_else(|| {
            McpError::Internal(
                "Mutation contract: habit delete completion tombstone has payload".to_string(),
            )
        })?;
        let mut tombstones: HashMap<String, Value> = HashMap::with_capacity(1);
        tombstones.insert(entity_id.to_string(), snapshot.clone());
        log_change(
            conn,
            LogChangeParams::new(
                OP_DELETE,
                EDGE_HABIT_COMPLETION,
                "delete_habit",
                format!(
                    "Removed completion for habit '{habit_name}' on {completed_date} (cascade)"
                ),
            )
            .with_entity_id(entity_id.to_string())
            .with_before(snapshot),
            Some(&tombstones),
        )?;
    }

    let policy_tombstones = execution
        .output
        .get_extra(&HABIT_DELETE_REMINDER_POLICY_TOMBSTONES)
        .and_then(Value::as_array)
        .ok_or_else(|| {
            McpError::Internal(
                "Mutation contract: habit delete reminder policy tombstones extra is an array"
                    .to_string(),
            )
        })?;
    for policy in policy_tombstones {
        let policy_id = policy.get("id").and_then(Value::as_str).ok_or_else(|| {
            McpError::Internal(
                "Mutation contract: habit delete reminder policy tombstone has id".to_string(),
            )
        })?;
        let snapshot = policy.get("payload").cloned().ok_or_else(|| {
            McpError::Internal(
                "Mutation contract: habit delete reminder policy tombstone has payload".to_string(),
            )
        })?;
        let mut tombstones: HashMap<String, Value> = HashMap::with_capacity(1);
        tombstones.insert(policy_id.to_string(), snapshot.clone());
        log_change(
            conn,
            LogChangeParams::new(
                OP_DELETE,
                ENTITY_HABIT_REMINDER_POLICY,
                "delete_habit",
                format!("Removed reminder policy '{policy_id}' for habit '{habit_name}' (cascade)"),
            )
            .with_entity_id(policy_id.to_string())
            .with_before(snapshot),
            Some(&tombstones),
        )?;
    }
    Ok(())
}

pub(crate) fn delete_habit(conn: &Connection, habit_id: &HabitId) -> Result<String, McpError> {
    let habit = load_habit_required(conn, habit_id.as_str())?;

    // Snapshot the pre-delete habit row so a reverse write can
    // re-insert it from the token. Completions + reminder policies are
    // deliberately *not* captured in the undo — restoring them is out
    // of scope for the bounded undo window. The undo semantics stay
    // precise: "put the habit row back", not "unwind every cascaded
    // side effect".
    let pre_habit_json = lorvex_store::payload_loaders::load_habit_sync_payload(conn, habit_id)?
        .ok_or_else(|| McpError::NotFound(format!("habit not found: {habit_id}")))?;

    // Attach the undo token to the final (habit-level) changelog row,
    // not the per-child cascade rows (completions, reminder policies)
    // logged above. Offering an undo on a child row would restore the
    // parent but leave orphans — worse than the all-or-nothing
    // semantics the top-level token enforces.
    let expires_at = crate::runtime::undo::compute_undo_expiry();
    let undo = crate::runtime::undo::McpUndoToken::delete_entity(
        crate::runtime::undo::McpUndoKind::DeleteHabit,
        "delete_habit",
        habit_id.as_str().to_string(),
        pre_habit_json.clone(),
        expires_at,
    );
    let undo_token_json = undo.to_json_string()?;

    let previous_response = serde_json::to_value(&habit)?;
    let habit_name = habit.name;
    let mutation = DeleteHabitMutation {
        habit_id: habit_id.clone(),
        habit_name,
        pre_habit_json: pre_habit_json.clone(),
        previous_response,
        undo_token_json: undo_token_json.clone(),
    };
    let mut habit_tombstones: HashMap<String, Value> = HashMap::with_capacity(1);
    habit_tombstones.insert(habit_id.as_str().to_string(), pre_habit_json);
    let output = execute_mcp_mutation_with_undo_tombstone_audit_finalizer(
        conn,
        &mutation,
        "delete_habit",
        habit_id.as_str().to_string(),
        undo_token_json,
        habit_tombstones,
        McpError::from,
        log_habit_delete_child_tombstones,
    )?;

    // CLAUDE.md rule 5 — include the pre-delete habit
    // snapshot so the assistant can narrate what was removed
    // (frequency, target_count, streak history) and optionally guide
    // a re-create. Issue #2366 extends this with explicit counts of
    // completions + reminder policies that cascaded so the assistant
    // can surface the streak-history loss to the user.
    Ok(serde_json::to_string(&output.after)?)
}
