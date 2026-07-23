use crate::contract::RemoveTaskReminderArgs;
use crate::contract_validate::ContractValidate;
use crate::error::McpError;
use crate::json_row::query_one_as_json;
use crate::runtime::change_tracking::{
    enqueue_relation_sync_with_snapshot, execute_mcp_mutation_with_audit_finalizer,
};
use crate::system::handler_support::{reload_task_json, utc_now_iso};
use crate::tasks::lww::touch_task_lww;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, ENTITY_TASK_REMINDER, OP_DELETE};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::{params, Connection};
use serde_json::Value;

struct RemoveTaskReminderMutation {
    task_id: String,
    reminder_id: String,
    reminder_at: String,
    before: Value,
    now: String,
}

impl Mutation for RemoveTaskReminderMutation {
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
        let parent_version = hlc.next_version_string();
        touch_task_lww(conn, &self.task_id, &parent_version, &self.now)
            .map_err(mcp_error_to_store)?;

        conn.prepare_cached("DELETE FROM task_reminders WHERE id = ?1 AND task_id = ?2")?
            .execute(params![&self.reminder_id, &self.task_id])?;

        let title = self
            .before
            .get("title")
            .and_then(Value::as_str)
            .unwrap_or("task");
        let after = reload_task_json(conn, &self.task_id, "task after remove_task_reminder")
            .map_err(mcp_error_to_store)?;

        Ok(MutationOutput::new(
            after,
            format!("Removed reminder at {} for '{title}'", self.reminder_at),
        ))
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

pub(crate) fn remove_task_reminder(
    conn: &Connection,
    args: RemoveTaskReminderArgs,
) -> Result<String, McpError> {
    // Capture the canonical idempotency fingerprint BEFORE destructure
    // so a retry after the response leg dropped in flight returns the
    // cached response instead of re-stamping the parent task's
    // version and emitting another `set_reminders` changelog row.
    // Aligns with `AddTaskReminderArgs` / `add_task_reminder`'s
    // discipline.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    // #3607 — derive-driven shape validation replaces the prior
    // `validate_uuid_arg(task_id)` call. The same derive also covers
    // `reminder_id`, which flow unchecked.
    args.validate_shape()?;
    let RemoveTaskReminderArgs {
        task_id,
        reminder_id,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "remove_task_reminder",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let task_id = task_id.trim().to_string();

    let before = crate::system::handler_support::fetch_task_json(conn, &task_id)?;

    let reminder_snapshot = query_one_as_json(
        conn,
        "SELECT * FROM task_reminders WHERE id = ?1 AND task_id = ?2",
        params![&reminder_id, &task_id],
    )?
    .ok_or_else(|| {
        McpError::NotFound(format!(
            "reminder '{reminder_id}' not found for task '{task_id}'"
        ))
    })?;
    let reminder_at = reminder_snapshot
        .get("reminder_at")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    let now = utc_now_iso();

    let mutation = RemoveTaskReminderMutation {
        task_id: task_id.clone(),
        reminder_id: reminder_id.clone(),
        reminder_at,
        before,
        now,
    };
    let output = execute_mcp_mutation_with_audit_finalizer(
        conn,
        &mutation,
        "remove_task_reminder",
        task_id,
        McpError::from,
        move |conn, _execution| {
            enqueue_relation_sync_with_snapshot(
                conn,
                ENTITY_TASK_REMINDER,
                &reminder_id,
                OP_DELETE,
                Some(reminder_snapshot),
            )
        },
    )?;

    let response = serde_json::to_string(&output.after)?;
    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "remove_task_reminder",
        &request_repr,
        &response,
    )?;
    Ok(response)
}
