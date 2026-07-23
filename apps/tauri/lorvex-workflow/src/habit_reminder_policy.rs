//! [`Mutation`] descriptors for habit reminder policy upsert + delete.
//!
//! The low-level SQL ops live in [`crate::habit_reminder_ops`]; this
//! module wraps them as `Mutation` descriptors so every surface (MCP,
//! Tauri, CLI, sync apply) drives the same executor pipeline rather
//! than re-implementing the `version` / `updated_at` stamping and
//! changelog projection independently.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_HABIT_REMINDER_POLICY, OP_DELETE, OP_UPSERT};
use lorvex_store::StoreError;
use rusqlite::Connection;
use serde_json::Value;

use crate::habit_reminder_ops;
use crate::mutation::{Mutation, MutationOutput};

/// Upsert a habit reminder policy.
///
/// `policy_id == None` creates a new slot; `Some(id)` updates an
/// existing slot (the `apply` enforces cross-habit + duplicate-time
/// rejection via [`habit_reminder_ops::upsert_habit_reminder_policy`]).
///
/// `before_json` is the caller-captured pre-mutation snapshot used by
/// the changelog audit on update paths; create paths leave it `None`.
pub struct UpsertHabitReminderPolicyMutation {
    pub policy_id: Option<String>,
    pub habit_id: String,
    pub reminder_time: String,
    pub enabled: bool,
    pub before_json: Option<Value>,
    pub now: String,
}

impl Mutation for UpsertHabitReminderPolicyMutation {
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
        let version = hlc.next_version_string();
        let policy = habit_reminder_ops::upsert_habit_reminder_policy(
            conn,
            &habit_reminder_ops::UpsertHabitReminderPolicyParams {
                policy_id: self.policy_id.as_deref(),
                habit_id: &self.habit_id,
                reminder_time: &self.reminder_time,
                enabled: self.enabled,
                version: &version,
                now: &self.now,
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

/// Delete a habit reminder policy by id.
///
/// `before` is the caller-captured pre-delete snapshot threaded into
/// both the changelog `before_json` and the outbox tombstone payload.
/// `habit_name` populates the human summary string and is sourced from
/// the same pre-delete snapshot.
pub struct DeleteHabitReminderPolicyMutation {
    pub id: String,
    pub before: Option<Value>,
    pub habit_name: String,
}

impl Mutation for DeleteHabitReminderPolicyMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_HABIT_REMINDER_POLICY
    }

    fn operation(&self) -> &'static str {
        OP_DELETE
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(self.before.clone())
    }

    fn apply(
        &self,
        conn: &Connection,
        _hlc: &HlcSession<'_>,
    ) -> Result<MutationOutput, StoreError> {
        let result = habit_reminder_ops::delete_habit_reminder_policy(conn, &self.id)?;
        Ok(MutationOutput::new(
            serde_json::json!({
                "deleted": result.deleted,
                "id": self.id,
                "before": self.before,
            }),
            format!("Deleted reminder policy for habit '{}'", self.habit_name),
        ))
    }
}
