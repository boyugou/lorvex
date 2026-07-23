use crate::contract::BatchReopenTasksArgs;
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_batch_mutation_with_audit_finalizer;
use crate::system::handler_support::{
    fetch_tasks_json_batch, plural_s, required_json_string_field, utc_now_iso,
};
use crate::system::vec_limits::validate_batch_ids;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, STATUS_OPEN};
use lorvex_domain::TaskId;
use lorvex_store::{repositories::task::write, StoreError};
use lorvex_workflow::lifecycle::{
    effects as workflow_effects, LifecycleSyncPlan, ReopenLifecycleTransitionResult,
};
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::{json, Value};
use std::cell::RefCell;

struct BatchReopenTaskInput {
    id: String,
    before_status: String,
}

struct BatchReopenTasksMutation {
    tasks: Vec<BatchReopenTaskInput>,
    before_tasks: Vec<Value>,
    now: String,
    summary: String,
    transitions: RefCell<Vec<ReopenLifecycleTransitionResult>>,
}

impl BatchReopenTasksMutation {
    fn take_transitions(&self) -> Vec<ReopenLifecycleTransitionResult> {
        self.transitions.replace(Vec::new())
    }
}

impl Mutation for BatchReopenTasksMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "batch_reopen"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(json!({ "before_states": self.before_tasks })))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let mut transitions = Vec::with_capacity(self.tasks.len());
        for task in &self.tasks {
            let task_id = TaskId::from_trusted(task.id.clone());
            let before_status =
                write::parse_task_status_for_update(task_id.as_str(), &task.before_status)?;
            let transition =
                workflow_effects::run_reopen(conn, &task_id, before_status, &self.now, hlc)?;
            transitions.push(transition);
        }

        let reopened_ids: Vec<String> = self.tasks.iter().map(|task| task.id.clone()).collect();
        let reopened_tasks = fetch_tasks_json_batch(conn, &reopened_ids, "task after reopen")
            .map_err(mcp_error_to_store)?;
        self.transitions.replace(transitions);
        Ok(MutationOutput::new(
            json!({ "after_states": reopened_tasks }),
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

pub(crate) fn batch_reopen_tasks(
    conn: &Connection,
    args: BatchReopenTasksArgs,
) -> Result<String, McpError> {
    // capture the canonical request fingerprint
    // before destructure for the checksum-gated cache lookup.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let BatchReopenTasksArgs {
        task_ids: ids,
        idempotency_key,
    } = args;
    // see batch_complete_tasks for rationale.
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "batch_reopen_tasks",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    validate_batch_ids(&ids, "batch_reopen_tasks")?;

    let before_tasks = fetch_tasks_json_batch(conn, &ids, "batch_reopen_tasks")?;
    if before_tasks.len() != ids.len() {
        return Err(McpError::NotFound(format!(
            "batch_reopen_tasks requested {} task(s) but only {} found",
            ids.len(),
            before_tasks.len()
        )));
    }

    // reject the whole batch instead of silently
    // skipping already-open tasks. Matches the atomicity discipline
    // of batch_complete_tasks and the broader CLAUDE.md rule.
    let mut already_open: Vec<String> = Vec::with_capacity(ids.len());
    let mut to_reopen: Vec<(String, &Value)> = Vec::with_capacity(ids.len());
    for (id, task) in ids.iter().zip(before_tasks.iter()) {
        let status = required_json_string_field(task, "status", "batch_reopen_tasks before-task")?;
        if status == STATUS_OPEN {
            already_open.push(id.clone());
        } else {
            to_reopen.push((id.clone(), task));
        }
    }

    if !already_open.is_empty() {
        return Err(McpError::Validation(format!(
            "batch_reopen_tasks rejects partial application: {} of {} task(s) are already open and cannot be reopened: [{}]. \
             Re-call with the non-open subset.",
            already_open.len(),
            ids.len(),
            already_open.join(", ")
        )));
    }

    let reopened_ids: Vec<String> = to_reopen.iter().map(|(id, _)| id.clone()).collect();
    let titles = to_reopen
        .iter()
        .map(|(_, task)| {
            required_json_string_field(task, "title", "batch_reopen_tasks before-task")
                .map(|title| format!("'{title}'"))
        })
        .collect::<Result<Vec<_>, _>>()?
        .join(", ");
    let summary = format!(
        "Reopened {} task{}: {}",
        reopened_ids.len(),
        plural_s(reopened_ids.len()),
        titles,
    );

    let tasks = to_reopen
        .iter()
        .map(|(id, task)| {
            Ok(BatchReopenTaskInput {
                id: id.clone(),
                before_status: required_json_string_field(
                    task,
                    "status",
                    "batch_reopen_tasks before-task",
                )?
                .to_string(),
            })
        })
        .collect::<Result<Vec<_>, McpError>>()?;
    let before_states_array: Vec<Value> =
        to_reopen.iter().map(|(_, task)| (*task).clone()).collect();
    let mutation = BatchReopenTasksMutation {
        tasks,
        before_tasks: before_states_array,
        now: utc_now_iso(),
        summary,
        transitions: RefCell::new(Vec::new()),
    };
    let output = execute_mcp_batch_mutation_with_audit_finalizer(
        conn,
        &mutation,
        "batch_reopen_tasks",
        reopened_ids,
        McpError::from,
        |conn, _execution| {
            for transition in mutation.take_transitions() {
                crate::tasks::lifecycle::effects::flush_sync_plan(
                    conn,
                    LifecycleSyncPlan::from_reopen(&transition),
                    crate::tasks::lifecycle::effects::LifecycleSyncLogContext {
                        mcp_tool: "batch_reopen_tasks",
                        spawned_successor_summary: None,
                        cancelled_successor_summary: Some(
                            "Cancelled recurring successor (batch reopen)".to_string(),
                        ),
                        affected_dependent_reason: "task".to_string(),
                        successor_affected_reason: "cancelled successor".to_string(),
                        rewire_parent_task_id: None,
                        rewire_parent_description: "reopened recurring task",
                    },
                )?;
            }
            Ok(())
        },
    )?;
    let reopened_tasks = output
        .after
        .get("after_states")
        .and_then(Value::as_array)
        .expect("Mutation contract: batch_reopen_tasks after_states stamped by apply")
        .clone();

    // Note: reopen is a status reopen, not a logical undo. Dependency edges
    // that were deleted on cancel are NOT restored. The user must re-add them
    // if needed. This is consistent across MCP and Tauri.

    let response = serde_json::to_string(&json!({
        "reopened_count": reopened_tasks.len(),
        "reopened": reopened_tasks,
        "already_open": already_open,
    }))?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "batch_reopen_tasks",
        &request_repr,
        &response,
    )?;

    Ok(response)
}
