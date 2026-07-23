use crate::contract::{CancelTaskArgs, MAX_SHORT_TEXT_LENGTH};
use crate::contract_validate::ContractValidate;
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_mutation_with_audit_finalizer;
use crate::system::handler_support::{
    fetch_existing_tasks_json, fetch_task_json, reload_task_json, required_json_string_field,
    utc_now_iso,
};
use crate::tasks::validation::sanitize_optional_user_text;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, STATUS_CANCELLED, STATUS_COMPLETED};
use lorvex_domain::TaskId;
use lorvex_store::StoreError;
use lorvex_workflow::lifecycle::{
    effects as workflow_effects, CancelLifecycleTransitionResult, LifecycleSyncPlan,
};
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::{params, Connection};
use serde_json::{json, Value};
use std::cell::RefCell;

struct CancelTaskMutation {
    task_id: TaskId,
    before: Value,
    before_ai_notes: String,
    new_ai_notes: String,
    now: String,
    cancel_series: bool,
    summary: String,
    result: RefCell<Option<CancelLifecycleTransitionResult>>,
}

impl CancelTaskMutation {
    fn take_result(&self) -> CancelLifecycleTransitionResult {
        self.result
            .borrow_mut()
            .take()
            .expect("Mutation contract: cancel_task result staged by apply")
    }
}

impl Mutation for CancelTaskMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "cancel"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let result =
            workflow_effects::run_cancel(conn, &self.task_id, &self.now, self.cancel_series, hlc)?;
        if !result.updated {
            return Err(StoreError::Validation(format!(
                "Task '{}' could not be cancelled",
                self.task_id
            )));
        }

        // MCP-specific: annotate ai_notes with cancellation reason.
        if self.new_ai_notes != self.before_ai_notes {
            conn.prepare_cached(
                "UPDATE tasks
                 SET ai_notes = ?1
                 WHERE id = ?2",
            )?
            .execute(params![&self.new_ai_notes, self.task_id.as_str()])?;
        }

        let after = reload_task_json(conn, self.task_id.as_str(), "task after cancel (pre-stamp)")
            .map_err(mcp_error_to_store)?;
        self.result.replace(Some(result));
        Ok(MutationOutput::new(after, self.summary.clone()))
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

pub(crate) fn cancel_task(conn: &Connection, args: CancelTaskArgs) -> Result<String, McpError> {
    // capture the canonical request fingerprint
    // before destructure for the checksum-gated cache lookup. See
    // `batch_complete_tasks` for full rationale.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    // #3607 — derive-driven shape validation replaces the prior
    // `validate_uuid_arg(id)` + `validate_optional_string_length(reason,
    // MAX_SHORT_TEXT_LENGTH)` calls.
    args.validate_shape()?;
    let CancelTaskArgs {
        id,
        reason,
        cancel_series,
        idempotency_key,
        // dry_run is consumed by the router-level
        // `dispatch_dry_run` wrapper before this body runs (preview
        // mode opens a savepoint, runs the real mutation, then rolls
        // back). The body itself is unaware of preview semantics —
        // it must execute identically in real and preview modes so
        // the rolled-back response matches what a real call would
        // have returned.
        dry_run: _,
    } = args;
    let reason = sanitize_optional_user_text(reason, "reason", MAX_SHORT_TEXT_LENGTH)?;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "cancel_task",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let id = id.trim().to_string();
    let before = fetch_task_json(conn, &id)?;

    let before_status = required_json_string_field(&before, "status", "cancel_task before-task")?;
    if before_status == STATUS_CANCELLED {
        return Err(McpError::Validation(format!(
            "Task '{id}' is already cancelled"
        )));
    }
    if before_status == STATUS_COMPLETED {
        return Err(McpError::Validation(format!(
            "Cannot cancel a completed task ('{id}'). Use reopen_task(id) to reopen it first."
        )));
    }

    let now = utc_now_iso();
    let before_ai_notes = before
        .get("ai_notes")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    let new_ai_notes = if let Some(reason_text) = reason.as_ref() {
        if before_ai_notes.trim().is_empty() {
            format!("Cancelled: {reason_text}")
        } else {
            format!("{before_ai_notes}\n\nCancelled: {reason_text}")
        }
    } else if before_ai_notes.trim().is_empty() {
        String::new()
    } else {
        before_ai_notes.clone()
    };

    let title =
        required_json_string_field(&before, "title", "cancel_task before-task")?.to_string();
    let reason_part = reason
        .as_ref()
        .map(|reason_text| format!(" - reason: {reason_text}"))
        .unwrap_or_default();
    let series_part = if cancel_series.unwrap_or(false) {
        " (series stopped)"
    } else {
        ""
    };
    let summary = format!("Cancelled task '{title}'{reason_part}{series_part}");

    let id_typed = TaskId::from_trusted(id.clone());
    let mutation = CancelTaskMutation {
        task_id: id_typed,
        before,
        before_ai_notes,
        new_ai_notes,
        now,
        cancel_series: cancel_series.unwrap_or(false),
        summary,
        result: RefCell::new(None),
    };
    let mut dep_affected = Vec::new();
    let mut next_occurrence = Value::Null;
    execute_mcp_mutation_with_audit_finalizer(
        conn,
        &mutation,
        "cancel_task",
        id.clone(),
        McpError::from,
        |conn, _execution| {
            let result = mutation.take_result();
            dep_affected = result.affected_dependent_ids.clone();
            next_occurrence = crate::tasks::lifecycle::effects::flush_sync_plan(
                conn,
                LifecycleSyncPlan::from_cancel(&result),
                crate::tasks::lifecycle::effects::LifecycleSyncLogContext {
                    mcp_tool: "cancel_task",
                    spawned_successor_summary: Some(format!(
                        "Spawned recurrence successor of '{title}' (skip-cancel)"
                    )),
                    cancelled_successor_summary: None,
                    affected_dependent_reason: title,
                    successor_affected_reason: "cancelled successor".to_string(),
                    rewire_parent_task_id: Some(id.clone()),
                    rewire_parent_description: "cancelled recurring task",
                },
            )?
            .unwrap_or(Value::Null);
            Ok(())
        },
    )?;

    // Re-fetch AFTER enqueue to get the post-stamp version.
    let after = reload_task_json(conn, &id, "task after cancel")?;

    let dep_unblocked = fetch_existing_tasks_json(conn, &dep_affected)?;

    let response = serde_json::to_string(&json!({
        "cancelled": after,
        "next_occurrence": next_occurrence,
        "dependency_updates": dep_unblocked,
    }))?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "cancel_task",
        &request_repr,
        &response,
    )?;

    Ok(response)
}
