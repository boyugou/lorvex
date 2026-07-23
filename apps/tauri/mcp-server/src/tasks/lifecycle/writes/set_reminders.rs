use crate::contract::SetTaskRemindersArgs;
use crate::contract_validate::ContractValidate;
use crate::error::McpError;
use crate::json_row::query_all_as_json;
use crate::runtime::change_tracking::{
    enqueue_relation_sync, enqueue_relation_sync_with_snapshot,
    execute_mcp_mutation_with_audit_finalizer,
};
use crate::system::handler_support::{
    canonicalize_reminder_timestamp, new_uuid, reload_task_json, resolve_reminder_local_anchor,
    utc_now_iso,
};
use crate::system::vec_limits::validate_reminders_count;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, ENTITY_TASK_REMINDER, OP_DELETE, OP_UPSERT};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::{params, Connection};
use serde_json::Value;

struct SetTaskRemindersMutation {
    task_id: String,
    reminders: Vec<String>,
    new_reminder_ids: Vec<String>,
    before: Value,
    now: String,
}

impl Mutation for SetTaskRemindersMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "set_reminders"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        conn.prepare_cached(
            "DELETE FROM task_reminders \
             WHERE task_id = ?1 AND dismissed_at IS NULL AND cancelled_at IS NULL",
        )?
        .execute(params![&self.task_id])?;

        if !self.reminders.is_empty() {
            let mut stmt = conn.prepare_cached(
                "INSERT INTO task_reminders \
                   (id, task_id, reminder_at, original_local_time, original_tz, version, created_at) \
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            )?;
            for (rid, ts) in self.new_reminder_ids.iter().zip(&self.reminders) {
                let version = hlc.next_version_string();
                let (original_local_time, original_tz) =
                    resolve_reminder_local_anchor(conn, ts).map_err(mcp_error_to_store)?;
                stmt.execute(params![
                    rid,
                    &self.task_id,
                    ts,
                    original_local_time,
                    original_tz,
                    version,
                    &self.now
                ])?;
            }
        }

        let title = self
            .before
            .get("title")
            .and_then(Value::as_str)
            .unwrap_or("task");
        let summary = if self.reminders.is_empty() {
            format!("Cleared all reminders for '{title}'")
        } else {
            format!(
                "Set {} reminder{} for '{title}'",
                self.reminders.len(),
                if self.reminders.len() == 1 { "" } else { "s" }
            )
        };

        let after = reload_task_json(conn, &self.task_id, "task after set_reminders")
            .map_err(mcp_error_to_store)?;
        Ok(MutationOutput::new(after, summary))
    }
}

fn mcp_error_to_store(error: McpError) -> StoreError {
    match error {
        McpError::Store(store_error) => *store_error,
        McpError::Sql(sql_error) => StoreError::from(*sql_error),
        McpError::Validation(message) | McpError::UserMessage(message) => {
            StoreError::Validation(message)
        }
        McpError::NotFound(message) => StoreError::NotFound {
            entity: ENTITY_TASK,
            id: message,
        },
        McpError::Serialization(message) => StoreError::Serialization(message),
        other => StoreError::Invariant(other.to_string()),
    }
}

pub(crate) fn set_task_reminders(
    conn: &Connection,
    args: SetTaskRemindersArgs,
) -> Result<String, McpError> {
    // capture the canonical request fingerprint
    // before destructure for the checksum-gated cache lookup. See
    // `batch_complete_tasks` for full rationale.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    // #3607 — derive-driven shape validation replaces the prior
    // `validate_uuid_arg(id)` call.
    args.validate_shape()?;
    let SetTaskRemindersArgs {
        id: task_id,
        reminders,
        idempotency_key,
    } = args;

    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "set_task_reminders",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let task_id = task_id.trim().to_string();
    validate_reminders_count(&reminders)?;

    let before = crate::system::handler_support::fetch_task_json(conn, &task_id)?;
    let now = utc_now_iso();

    let old_reminders: Vec<Value> = query_all_as_json(
        conn,
        "SELECT * FROM task_reminders \
         WHERE task_id = ?1 AND dismissed_at IS NULL AND cancelled_at IS NULL",
        params![&task_id],
    )?;

    let reminders: Vec<String> = reminders
        .iter()
        .map(|ts| canonicalize_reminder_timestamp(ts))
        .collect::<Result<_, _>>()?;
    let new_reminder_ids: Vec<String> = reminders.iter().map(|_| new_uuid()).collect();

    let mutation = SetTaskRemindersMutation {
        task_id: task_id.clone(),
        reminders,
        new_reminder_ids: new_reminder_ids.clone(),
        before,
        now,
    };
    let output = execute_mcp_mutation_with_audit_finalizer(
        conn,
        &mutation,
        "set_task_reminders",
        task_id,
        McpError::from,
        move |conn, _execution| {
            for old in &old_reminders {
                let old_id = old
                    .get("id")
                    .and_then(Value::as_str)
                    .ok_or_else(|| {
                        McpError::Internal(
                            "task_reminder snapshot missing string `id` column".to_string(),
                        )
                    })?
                    .to_string();
                enqueue_relation_sync_with_snapshot(
                    conn,
                    ENTITY_TASK_REMINDER,
                    &old_id,
                    OP_DELETE,
                    Some(old.clone()),
                )?;
            }
            for new_id in &new_reminder_ids {
                enqueue_relation_sync(conn, ENTITY_TASK_REMINDER, new_id, OP_UPSERT)?;
            }
            Ok(())
        },
    )?;

    let response = serde_json::to_string(&output.after)?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "set_task_reminders",
        &request_repr,
        &response,
    )?;

    Ok(response)
}
