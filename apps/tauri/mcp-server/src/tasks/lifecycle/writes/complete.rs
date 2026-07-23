use crate::contract::CompleteTaskArgs;
use crate::contract_validate::ContractValidate;
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_mutation_with_audit_finalizer;
use crate::system::handler_support::{
    fetch_existing_tasks_json, fetch_task_json, reload_task_json, required_json_string_field,
    utc_now_iso,
};
use crate::tasks::dependencies::find_tasks_depending_on;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, STATUS_COMPLETED};
use lorvex_domain::TaskId;
use lorvex_store::StoreError;
use lorvex_workflow::lifecycle::{
    effects as workflow_effects, CompletionLifecycleTransitionResult, LifecycleSyncPlan,
};
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::{json, Value};
use std::cell::RefCell;

struct CompleteTaskMutation {
    task_id: TaskId,
    before: Value,
    title: String,
    now: String,
    result: RefCell<Option<CompletionLifecycleTransitionResult>>,
}

impl CompleteTaskMutation {
    fn take_result(&self) -> CompletionLifecycleTransitionResult {
        self.result
            .borrow_mut()
            .take()
            .expect("Mutation contract: complete_task result staged by apply")
    }
}

impl Mutation for CompleteTaskMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "complete"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let result = workflow_effects::run_completion(conn, &self.task_id, &self.now, hlc)?;
        if !result.updated {
            return Err(StoreError::Validation(format!(
                "Task '{}' could not be completed",
                self.task_id
            )));
        }

        let after = reload_task_json(
            conn,
            self.task_id.as_str(),
            "task after completion (pre-stamp)",
        )
        .map_err(mcp_error_to_store)?;
        self.result.replace(Some(result));
        Ok(MutationOutput::new(
            after,
            format!("Marked '{}' as completed", self.title),
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

pub(crate) fn complete_task(conn: &Connection, args: CompleteTaskArgs) -> Result<String, McpError> {
    // capture the canonical request fingerprint
    // before destructure for the checksum-gated cache lookup. See
    // `batch_complete_tasks` for full rationale.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    args.validate_shape()?;
    let CompleteTaskArgs {
        id,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "complete_task",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    // `validate_shape()` already enforced UUID format
    // via the derive (#3373). Trim defensively to match the prior
    // `validate_uuid_arg` return shape, since downstream SQL binds the
    // to ride into `WHERE id = ?` lookups.
    let id = id.trim().to_string();
    let before = fetch_task_json(conn, &id)?;

    if required_json_string_field(&before, "status", "complete_task before-task")?
        == STATUS_COMPLETED
    {
        return Err(McpError::Validation(format!(
            "Task '{id}' is already completed"
        )));
    }

    let now = utc_now_iso();
    let id_typed = TaskId::from_trusted(id.clone());

    // Find direct dependents for the response.
    let dependents = find_tasks_depending_on(conn, &id_typed)?;

    let title =
        required_json_string_field(&before, "title", "complete_task before-task")?.to_string();
    let mutation = CompleteTaskMutation {
        task_id: id_typed,
        before,
        title,
        now,
        result: RefCell::new(None),
    };
    let mut next_occurrence = Value::Null;
    execute_mcp_mutation_with_audit_finalizer(
        conn,
        &mutation,
        "complete_task",
        id.clone(),
        McpError::from,
        |conn, _execution| {
            let result = mutation.take_result();
            next_occurrence = crate::tasks::lifecycle::effects::flush_sync_plan(
                conn,
                LifecycleSyncPlan::from_completion(&result),
                crate::tasks::lifecycle::effects::LifecycleSyncLogContext {
                    mcp_tool: "complete_task",
                    spawned_successor_summary: Some(format!(
                        "Spawned recurrence successor of '{}'",
                        mutation.title
                    )),
                    cancelled_successor_summary: None,
                    affected_dependent_reason: mutation.title.clone(),
                    successor_affected_reason: "cancelled successor".to_string(),
                    rewire_parent_task_id: Some(id.clone()),
                    rewire_parent_description: "completed recurring task",
                },
            )?
            .unwrap_or(Value::Null);
            Ok(())
        },
    )?;

    // Re-fetch AFTER enqueue to get the post-stamp version.
    let completed = reload_task_json(conn, &id, "task after completion")?;
    let newly_unblocked = fetch_existing_tasks_json(conn, &dependents)?;

    let response = serde_json::to_string(&json!({
        "completed": completed,
        "next_occurrence": next_occurrence,
        "newly_unblocked": newly_unblocked,
    }))?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "complete_task",
        &request_repr,
        &response,
    )?;

    Ok(response)
}
