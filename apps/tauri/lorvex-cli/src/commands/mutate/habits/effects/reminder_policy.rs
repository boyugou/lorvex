//! Habit reminder-policy CRUD: list, upsert, and delete.
//!
//! Reminder policies attach a per-day local time to a habit so the
//! agent can nudge the user. Each mutation enqueues a sync envelope
//! and a changelog row; `delete_habit_reminder_policy_with_conn`
//! rolls back the immediate-mode transaction when no row matched, so
//! a no-op delete does not bump the WAL frame counter and confuse
//! outbox-poll loops (#2905-M11).

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_HABIT_REMINDER_POLICY, OP_DELETE, OP_UPSERT};
use lorvex_runtime::{bump_local_change_seq, get_or_create_device_id};
use lorvex_store::StoreError;
use lorvex_sync::outbox_enqueue::{enqueue_entity_upsert, enqueue_payload_delete};
use lorvex_workflow::habit_reminder_ops;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::{json, Value};

use super::{habit_reminder_policy_delete_payload, HabitReminderPolicyDeleteResult};
use crate::commands::shared::{execute_cli_mutation_with_finalizer, log_cli_changelog_with_state};
use crate::hlc_guard::lock_shared;

struct UpsertCliHabitReminderPolicyMutation<'a> {
    policy_id: Option<&'a str>,
    habit_id: &'a str,
    reminder_time: &'a str,
    enabled: bool,
    before_json: Option<Value>,
    now: &'a str,
}

impl<'a> Mutation for UpsertCliHabitReminderPolicyMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_HABIT_REMINDER_POLICY
    }

    fn operation(&self) -> &'static str {
        OP_UPSERT
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(self.before_json.clone())
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version().to_string();
        let policy = habit_reminder_ops::upsert_habit_reminder_policy(
            conn,
            &habit_reminder_ops::UpsertHabitReminderPolicyParams {
                policy_id: self.policy_id,
                habit_id: self.habit_id,
                reminder_time: self.reminder_time,
                enabled: self.enabled,
                version: &version,
                now: self.now,
            },
        )?;
        Ok(MutationOutput::new(
            serde_json::to_value(&policy)?,
            format!(
                "Set reminder policy for habit '{}' at {}",
                policy.habit_name, policy.reminder_time
            ),
        ))
    }
}

struct DeleteCliHabitReminderPolicyMutation<'a> {
    policy_id: &'a str,
    before_json: Option<Value>,
    habit_name: String,
}

impl<'a> Mutation for DeleteCliHabitReminderPolicyMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_HABIT_REMINDER_POLICY
    }

    fn operation(&self) -> &'static str {
        OP_DELETE
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(self.before_json.clone())
    }

    fn apply(
        &self,
        conn: &Connection,
        _hlc: &HlcSession<'_>,
    ) -> Result<MutationOutput, StoreError> {
        let result = habit_reminder_ops::delete_habit_reminder_policy(conn, self.policy_id)?;
        Ok(MutationOutput::new(
            json!({
                "deleted": result.deleted,
                "id": self.policy_id,
                "before": self.before_json,
            }),
            format!("Deleted reminder policy for habit '{}'", self.habit_name),
        ))
    }
}

pub(crate) fn list_habit_reminder_policies_with_conn(
    conn: &Connection,
) -> Result<Vec<habit_reminder_ops::HabitReminderPolicyRow>, crate::error::CliError> {
    Ok(habit_reminder_ops::list_all_policies(conn)?)
}

pub(crate) fn upsert_habit_reminder_policy_with_conn(
    conn: &mut Connection,
    policy_id: Option<&lorvex_domain::HabitReminderPolicyId>,
    habit_id: &lorvex_domain::HabitId,
    reminder_time: &str,
    enabled: bool,
) -> Result<habit_reminder_ops::HabitReminderPolicyRow, crate::error::CliError> {
    let policy_id_str = policy_id.map(lorvex_domain::HabitReminderPolicyId::as_str);
    let habit_id_str = habit_id.as_str();
    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let before_json: Option<serde_json::Value> = match policy_id_str {
        Some(id) => habit_reminder_ops::load_policy_by_id(&tx, id)?
            .as_ref()
            .map(habit_reminder_policy_delete_payload),
        None => None,
    };
    let now = lorvex_domain::sync_timestamp_now();
    let mutation = UpsertCliHabitReminderPolicyMutation {
        policy_id: policy_id_str,
        habit_id: habit_id_str,
        reminder_time,
        enabled,
        before_json,
        now: &now,
    };
    let mut hlc_guard = lock_shared(&tx)?;
    let mut after_policy: Option<habit_reminder_ops::HabitReminderPolicyRow> = None;
    execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            let policy_id = execution
                .output
                .after
                .get("id")
                .and_then(Value::as_str)
                .expect("Mutation contract: habit reminder policy upsert must surface id")
                .to_string();
            enqueue_entity_upsert(
                &tx,
                ENTITY_HABIT_REMINDER_POLICY,
                &policy_id,
                hlc_state,
                &device_id,
            )?;
            let policy =
                habit_reminder_ops::load_policy_by_id(&tx, &policy_id)?.ok_or_else(|| {
                    crate::error::CliError::NotFound(format!(
                        "habit reminder policy '{policy_id}' not found after upsert"
                    ))
                })?;
            let typed_policy_id =
                lorvex_domain::HabitReminderPolicyId::from_trusted(policy.id.clone());
            let typed_habit_id = lorvex_domain::HabitId::from_trusted(policy.habit_id.clone());
            let after_json = lorvex_store::payload_loaders::habit_reminder_policy_payload(
                &typed_policy_id,
                &typed_habit_id,
                &policy.reminder_time,
                policy.enabled,
                &policy.version,
                &policy.created_at,
                &policy.updated_at,
            );
            log_cli_changelog_with_state(
                &tx,
                hlc_state,
                crate::commands::shared::CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: &policy_id,
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json: Some(after_json),
                },
            )?;
            bump_local_change_seq(&tx)?;
            after_policy = Some(policy);
            Ok(())
        },
    )?;
    drop(hlc_guard);
    tx.commit()?;
    Ok(after_policy.expect("habit reminder policy upsert finalizer should load post-state"))
}

pub(crate) fn delete_habit_reminder_policy_with_conn(
    conn: &mut Connection,
    policy_id: &lorvex_domain::HabitReminderPolicyId,
) -> Result<HabitReminderPolicyDeleteResult, crate::error::CliError> {
    let policy_id_str = policy_id.as_str();
    let device_id = get_or_create_device_id(conn)?;
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let before = habit_reminder_ops::load_policy_by_id(&tx, policy_id_str)?;
    let before_json = before.as_ref().map(habit_reminder_policy_delete_payload);
    let habit_name = before
        .as_ref()
        .map(|policy| policy.habit_name.clone())
        .unwrap_or_else(|| "habit".to_string());
    let mutation = DeleteCliHabitReminderPolicyMutation {
        policy_id: policy_id_str,
        before_json,
        habit_name,
    };
    let mut hlc_guard = lock_shared(&tx)?;
    let output = execute_cli_mutation_with_finalizer(
        &tx,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            let deleted = execution
                .output
                .after
                .get("deleted")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            if !deleted {
                return Ok(());
            }
            let snapshot = execution.before.clone().ok_or_else(|| {
                crate::error::CliError::Internal(format!(
                    "deleted habit reminder policy '{policy_id_str}' but failed to load before-state"
                ))
            })?;
            let version = hlc_state.generate().to_string();
            enqueue_payload_delete(
                &tx,
                ENTITY_HABIT_REMINDER_POLICY,
                policy_id_str,
                &snapshot,
                crate::commands::shared::bare_outbox_ctx(&version, &device_id),
            )?;
            log_cli_changelog_with_state(
                &tx,
                hlc_state,
                crate::commands::shared::CliChangelogParams {
                    operation: execution.operation,
                    entity_type: execution.entity_kind,
                    entity_id: policy_id_str,
                    summary: &execution.output.summary,
                    before_json: execution.before,
                    after_json: None,
                },
            )?;
            bump_local_change_seq(&tx)?;
            Ok(())
        },
    )?;
    let deleted = output
        .after
        .get("deleted")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    drop(hlc_guard);
    if !deleted {
        // Roll back the empty tx when no row matched `policy_id`. This
        // preserves the #2905-M11 no-op delete contract.
        tx.rollback()?;
        return Ok(HabitReminderPolicyDeleteResult {
            deleted: false,
            id: policy_id_str.to_string(),
            before,
        });
    }
    tx.commit()?;

    Ok(HabitReminderPolicyDeleteResult {
        deleted: true,
        id: policy_id_str.to_string(),
        before,
    })
}
