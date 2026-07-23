use crate::contract::AddTaskReminderArgs;
use crate::contract_validate::ContractValidate;
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_mutation_with_audit_finalizer;
use crate::system::handler_support::{canonicalize_reminder_timestamp, new_uuid, utc_now_iso};
use crate::system::vec_limits::MAX_REMINDERS_PER_TASK;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, ENTITY_TASK_REMINDER, OP_UPSERT};
use lorvex_domain::TaskId;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::{params, Connection};
use serde_json::Value;

struct AddTaskReminderMutation {
    task_id: String,
    reminder_id: String,
    reminder_at: String,
    now: String,
    before: Value,
}

impl Mutation for AddTaskReminderMutation {
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
        // Cancelled/dismissed history must not permanently consume a task's
        // reminder budget.
        let existing_count: i64 = conn
            .prepare_cached(
                "SELECT COUNT(*) FROM task_reminders
                 WHERE task_id = ?1 AND dismissed_at IS NULL AND cancelled_at IS NULL",
            )?
            .query_row(params![&self.task_id], |row| row.get(0))?;
        if existing_count >= MAX_REMINDERS_PER_TASK as i64 {
            return Err(StoreError::Validation(format!(
                "task already has {existing_count} active reminders (limit {MAX_REMINDERS_PER_TASK}). \
                 Use set_task_reminders to replace existing reminders."
            )));
        }

        let version = hlc.next_version_string();
        let (original_local_time, original_tz) =
            lorvex_workflow::reminder_anchor::resolve_task_reminder_local_anchor(
                conn,
                &self.reminder_at,
            )?;
        conn.prepare_cached(
            "INSERT INTO task_reminders \
               (id, task_id, reminder_at, original_local_time, original_tz, version, created_at) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
        )?
        .execute(params![
            &self.reminder_id,
            &self.task_id,
            &self.reminder_at,
            original_local_time,
            original_tz,
            version,
            &self.now
        ])?;

        let after = lorvex_workflow::task_response::load_enriched_task_json(
            conn,
            &TaskId::from_trusted(self.task_id.clone()),
        )?;
        let title = lorvex_workflow::task_response::task_title(&self.before);
        Ok(MutationOutput::new(
            after,
            format!("Added reminder for '{title}' at {}", self.reminder_at),
        ))
    }
}

pub(crate) fn add_task_reminder(
    conn: &Connection,
    args: AddTaskReminderArgs,
) -> Result<String, McpError> {
    // capture the canonical request fingerprint
    // before destructure for the checksum-gated cache lookup. See
    // `batch_complete_tasks` for full rationale.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    // #3607 — derive-driven shape validation replaces the prior
    // `validate_uuid_arg(id)` call.
    args.validate_shape()?;
    let AddTaskReminderArgs {
        id: task_id,
        reminder_at,
        idempotency_key,
    } = args;

    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "add_task_reminder",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let task_id = task_id.trim().to_string();

    // Verify task exists and capture before-state for the audit row.
    let before = crate::system::handler_support::fetch_task_json(conn, &task_id)?;
    let reminder_at = canonicalize_reminder_timestamp(&reminder_at)?;
    let now = utc_now_iso();
    let rid = new_uuid();

    let mutation = AddTaskReminderMutation {
        task_id: task_id.clone(),
        reminder_id: rid.clone(),
        reminder_at,
        now,
        before,
    };
    let output = execute_mcp_mutation_with_audit_finalizer(
        conn,
        &mutation,
        "add_task_reminder",
        task_id,
        McpError::from,
        move |conn, _execution| {
            crate::runtime::change_tracking::enqueue_relation_sync(
                conn,
                ENTITY_TASK_REMINDER,
                &rid,
                OP_UPSERT,
            )
        },
    )?;

    let response = serde_json::to_string(&output.after)?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "add_task_reminder",
        &request_repr,
        &response,
    )?;

    Ok(response)
}
