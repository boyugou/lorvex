use crate::contract::BatchCompleteTasksArgs;
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_batch_mutation_with_audit_finalizer;
use crate::system::handler_support::required_json_string_field;
use crate::system::handler_support::{fetch_tasks_json_batch, plural_s, utc_now_iso};
use crate::system::vec_limits::validate_batch_ids;
use crate::tasks::lifecycle::effects::LifecycleSyncLogContext;
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

struct BatchCompleteTasksMutation {
    task_ids: Vec<String>,
    before_tasks: Vec<Value>,
    now: String,
    summary: String,
    transitions: RefCell<Vec<(String, CompletionLifecycleTransitionResult)>>,
}

impl BatchCompleteTasksMutation {
    fn take_transitions(&self) -> Vec<(String, CompletionLifecycleTransitionResult)> {
        self.transitions.replace(Vec::new())
    }
}

impl Mutation for BatchCompleteTasksMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "batch_complete"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(json!({ "before_states": self.before_tasks })))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let mut transitions = Vec::with_capacity(self.task_ids.len());
        for id in &self.task_ids {
            let task_id = TaskId::from_trusted(id.clone());
            let result = workflow_effects::run_completion(conn, &task_id, &self.now, hlc)?;
            transitions.push((id.clone(), result));
        }

        let completed_tasks = fetch_tasks_json_batch(conn, &self.task_ids, "task after completion")
            .map_err(mcp_error_to_store)?;
        self.transitions.replace(transitions);
        Ok(MutationOutput::new(
            json!({ "after_states": completed_tasks }),
            self.summary.clone(),
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

pub(crate) fn batch_complete_tasks(
    conn: &Connection,
    args: BatchCompleteTasksArgs,
) -> Result<String, McpError> {
    // capture the canonical request fingerprint
    // before destructure so the idempotency lookup can detect token
    // collisions with semantically different payloads.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let BatchCompleteTasksArgs {
        task_ids: ids,
        idempotency_key,
    } = args;
    // gate retries via the shared idempotency cache so
    // a transport flake on the response leg doesn't double-complete
    // every task in the batch (recurrence successors twice, completion
    // sound twice, etc.).
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "batch_complete_tasks",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    validate_batch_ids(&ids, "batch_complete_tasks")?;

    let before_tasks = fetch_tasks_json_batch(conn, &ids, "batch_complete_tasks")?;
    if before_tasks.len() != ids.len() {
        return Err(McpError::NotFound(format!(
            "batch_complete_tasks requested {} task(s) but only {} found",
            ids.len(),
            before_tasks.len()
        )));
    }
    let mut before_states_array = Vec::with_capacity(ids.len());
    for (id, task) in ids.iter().zip(before_tasks.iter()) {
        if required_json_string_field(task, "status", "batch_complete_tasks before-task")?
            == STATUS_COMPLETED
        {
            return Err(McpError::Validation(format!(
                "Task '{id}' is already completed"
            )));
        }
        before_states_array.push(task.clone());
    }

    let titles = ids
        .iter()
        .zip(before_states_array.iter())
        .map(|(_id, task)| -> Result<String, McpError> {
            Ok(
                required_json_string_field(task, "title", "batch_complete_tasks before-task")
                    .map(|title| format!("'{title}'"))?,
            )
        })
        .collect::<Result<Vec<_>, McpError>>()?
        .join(", ");
    let summary = format!(
        "Marked {} task{} as completed: {}",
        ids.len(),
        plural_s(ids.len()),
        titles
    );

    let mutation = BatchCompleteTasksMutation {
        task_ids: ids.clone(),
        before_tasks: before_states_array,
        now: utc_now_iso(),
        summary,
        transitions: RefCell::new(Vec::new()),
    };
    let mut next_occurrences: Vec<Value> = Vec::new();
    let output = execute_mcp_batch_mutation_with_audit_finalizer(
        conn,
        &mutation,
        "batch_complete_tasks",
        ids,
        McpError::from,
        |conn, _execution| {
            for (id, result) in mutation.take_transitions() {
                if let Some(successor_json) = crate::tasks::lifecycle::effects::flush_sync_plan(
                    conn,
                    LifecycleSyncPlan::from_completion(&result),
                    LifecycleSyncLogContext {
                        mcp_tool: "batch_complete_tasks",
                        spawned_successor_summary: Some(
                            "Spawned recurrence successor from batch completion".to_string(),
                        ),
                        cancelled_successor_summary: None,
                        affected_dependent_reason: "completed task".to_string(),
                        successor_affected_reason: "cancelled successor".to_string(),
                        rewire_parent_task_id: Some(id),
                        rewire_parent_description: "completed recurring task",
                    },
                )? {
                    next_occurrences.push(successor_json);
                }
            }
            Ok(())
        },
    )?;
    let completed_tasks = output
        .after
        .get("after_states")
        .and_then(Value::as_array)
        .expect("Mutation contract: batch_complete_tasks after_states stamped by apply")
        .clone();

    let response = serde_json::to_string(&json!({
        "completed_count": completed_tasks.len(),
        "tasks": completed_tasks,
        "next_occurrences": next_occurrences,
    }))?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "batch_complete_tasks",
        &request_repr,
        &response,
    )?;

    Ok(response)
}
