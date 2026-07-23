//! `habits delete` — tombstone the habit row and cascade tombstones to
//! its completions + reminder policies, emitting a separate sync
//! delete + changelog row for each cascaded child so peers reconstruct
//! the same end state.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{
    EDGE_HABIT_COMPLETION, ENTITY_HABIT, ENTITY_HABIT_REMINDER_POLICY, OP_DELETE,
};
use lorvex_runtime::{bump_local_change_seq, get_or_create_device_id};
use lorvex_store::StoreError;
use lorvex_sync::outbox_enqueue::{
    enqueue_payload_delete, tombstone_completions_for_habit_delete,
    tombstone_reminder_policies_for_habit_delete,
};
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use lorvex_workflow::mutation_extras::{
    HABIT_DELETE_COMPLETION_TOMBSTONES, HABIT_DELETE_REMINDER_POLICY_TOMBSTONES,
};
use rusqlite::Connection;
use serde_json::{json, Value};

use super::super::{
    enqueue_habit_payload_delete_with_version, habit_payload, load_habit_row, HabitDeleteResult,
};
use crate::commands::shared::{execute_cli_mutation_with_finalizer, log_cli_changelog_with_state};
use crate::hlc_guard::lock_shared;

struct DeleteCliHabitMutation {
    id: lorvex_domain::HabitId,
    name: String,
    before_json: Value,
}

impl Mutation for DeleteCliHabitMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_HABIT
    }

    fn operation(&self) -> &'static str {
        OP_DELETE
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before_json.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let child_tombstone_version = hlc.next_version_string();
        let completions =
            tombstone_completions_for_habit_delete(conn, &self.id, &child_tombstone_version)
                .map_err(enqueue_error_to_store_error)?;
        let reminder_policies =
            tombstone_reminder_policies_for_habit_delete(conn, &self.id, &child_tombstone_version)
                .map_err(enqueue_error_to_store_error)?;

        let delete_version = hlc.next_version_string();
        lorvex_store::repositories::lww_delete::execute_lww_delete_by_id(
            conn,
            "habits",
            "id",
            ENTITY_HABIT,
            self.id.as_str(),
            &delete_version,
        )?;

        let completion_tombstones = completions
            .iter()
            .map(|completion| {
                json!({
                    "entity_id": completion.entity_id(),
                    "completed_date": completion.completed_date,
                    "payload": completion.payload(),
                })
            })
            .collect();
        let reminder_policy_tombstones = reminder_policies
            .iter()
            .map(|policy| {
                json!({
                    "id": policy.id.as_str(),
                    "payload": policy.payload(),
                })
            })
            .collect();

        let mut output = MutationOutput::new(
            json!({
                "id": self.id.as_str(),
                "name": self.name,
                "delete_version": delete_version,
                "completions_destroyed": completions.len(),
                "reminder_policies_destroyed": reminder_policies.len(),
            }),
            format!(
                "Deleted habit '{}' — destroyed {} completion record{} + {} reminder polic{}",
                self.name,
                completions.len(),
                if completions.len() == 1 { "" } else { "s" },
                reminder_policies.len(),
                if reminder_policies.len() == 1 {
                    "y"
                } else {
                    "ies"
                },
            ),
        );
        output.set_extra(
            &HABIT_DELETE_COMPLETION_TOMBSTONES,
            Value::Array(completion_tombstones),
        );
        output.set_extra(
            &HABIT_DELETE_REMINDER_POLICY_TOMBSTONES,
            Value::Array(reminder_policy_tombstones),
        );
        Ok(output)
    }
}

fn enqueue_error_to_store_error(error: lorvex_sync::outbox_enqueue::EnqueueError) -> StoreError {
    match error {
        lorvex_sync::outbox_enqueue::EnqueueError::Store(error) => error,
        lorvex_sync::outbox_enqueue::EnqueueError::Sqlite(error) => StoreError::from(error),
        other => StoreError::Invariant(other.to_string()),
    }
}

pub(crate) fn delete_habit_with_conn(
    conn: &mut Connection,
    habit_id: &lorvex_domain::HabitId,
) -> Result<HabitDeleteResult, crate::error::CliError> {
    let habit_id_str = habit_id.as_str();
    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let habit = load_habit_row(&tx, habit_id)?;
    let habit_payload = habit_payload(&tx, habit_id)?;
    let mutation = DeleteCliHabitMutation {
        id: habit_id.clone(),
        name: habit.name.clone(),
        before_json: habit_payload.clone(),
    };
    let mut hlc_guard = lock_shared(&tx)?;
    let output = execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            let completion_tombstones = execution
                .output
                .get_extra(&HABIT_DELETE_COMPLETION_TOMBSTONES)
                .and_then(Value::as_array)
                .expect("Mutation contract: habit delete must surface completion tombstones");
            for completion in completion_tombstones {
                let entity_id = completion
                    .get("entity_id")
                    .and_then(Value::as_str)
                    .expect("Mutation contract: completion tombstone must surface entity_id");
                let completed_date = completion
                    .get("completed_date")
                    .and_then(Value::as_str)
                    .expect("Mutation contract: completion tombstone must surface completed_date");
                let payload = completion
                    .get("payload")
                    .cloned()
                    .expect("Mutation contract: completion tombstone must surface payload");
                let version = hlc_state.generate().to_string();
                enqueue_payload_delete(
                    &tx,
                    EDGE_HABIT_COMPLETION,
                    entity_id,
                    &payload,
                    crate::commands::shared::bare_outbox_ctx(&version, &device_id),
                )?;
                log_cli_changelog_with_state(
                    &tx,
                    hlc_state,
                    crate::commands::shared::CliChangelogParams {
                        operation: OP_DELETE,
                        entity_type: EDGE_HABIT_COMPLETION,
                        entity_id,
                        summary: &format!(
                            "Removed completion for habit '{}' on {} (cascade)",
                            habit.name, completed_date
                        ),
                        before_json: Some(payload),
                        after_json: None,
                    },
                )?;
            }

            let reminder_policy_tombstones = execution
                .output
                .get_extra(&HABIT_DELETE_REMINDER_POLICY_TOMBSTONES)
                .and_then(Value::as_array)
                .expect("Mutation contract: habit delete must surface reminder policy tombstones");
            for policy in reminder_policy_tombstones {
                let policy_id = policy
                    .get("id")
                    .and_then(Value::as_str)
                    .expect("Mutation contract: reminder policy tombstone must surface id");
                let payload = policy
                    .get("payload")
                    .cloned()
                    .expect("Mutation contract: reminder policy tombstone must surface payload");
                let version = hlc_state.generate().to_string();
                enqueue_payload_delete(
                    &tx,
                    ENTITY_HABIT_REMINDER_POLICY,
                    policy_id,
                    &payload,
                    crate::commands::shared::bare_outbox_ctx(&version, &device_id),
                )?;
                log_cli_changelog_with_state(
                    &tx,
                    hlc_state,
                    crate::commands::shared::CliChangelogParams {
                        operation: OP_DELETE,
                        entity_type: ENTITY_HABIT_REMINDER_POLICY,
                        entity_id: policy_id,
                        summary: &format!(
                            "Removed reminder policy '{}' for habit '{}' (cascade)",
                            policy_id, habit.name
                        ),
                        before_json: Some(payload),
                        after_json: None,
                    },
                )?;
            }

            let delete_version = execution
                .output
                .after
                .get("delete_version")
                .and_then(Value::as_str)
                .expect("Mutation contract: habit delete must surface delete_version");
            enqueue_habit_payload_delete_with_version(
                &tx,
                &device_id,
                habit_id,
                &habit_payload,
                delete_version,
            )?;
            log_cli_changelog_with_state(
                &tx,
                hlc_state,
                crate::commands::shared::CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: habit_id_str,
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json: None,
                },
            )?;
            bump_local_change_seq(&tx)?;
            Ok(())
        },
    )?;
    let completions_destroyed = output
        .after
        .get("completions_destroyed")
        .and_then(Value::as_u64)
        .and_then(|value| usize::try_from(value).ok())
        .expect("Mutation contract: habit delete must surface completions_destroyed");
    let reminder_policies_destroyed = output
        .after
        .get("reminder_policies_destroyed")
        .and_then(Value::as_u64)
        .and_then(|value| usize::try_from(value).ok())
        .expect("Mutation contract: habit delete must surface reminder_policies_destroyed");
    drop(hlc_guard);
    tx.commit()?;

    Ok(HabitDeleteResult {
        id: habit.id.clone(),
        name: habit.name.clone(),
        completions_destroyed,
        reminder_policies_destroyed,
        previous: habit,
    })
}
