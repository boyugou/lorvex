use crate::contract::{BatchCreateTaskInput, BatchCreateTasksArgs};
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_batch_mutation_with_undo_audit_finalizer;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_TASK;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::{json, Value};
use std::cell::RefCell;

mod effects;

struct BatchCreateTasksMutation {
    input: lorvex_workflow::task_batch_create::BatchCreateTasksInput,
    result: RefCell<Option<lorvex_workflow::task_batch_create::BatchCreateTasksResult>>,
}

impl BatchCreateTasksMutation {
    fn with_result_mut<F>(&self, f: F) -> Result<(), McpError>
    where
        F: FnOnce(
            &mut lorvex_workflow::task_batch_create::BatchCreateTasksResult,
        ) -> Result<(), McpError>,
    {
        let mut result = self.result.borrow_mut();
        let result = result
            .as_mut()
            .expect("Mutation contract: batch_create_tasks result staged by apply");
        f(result)
    }

    fn payload(&self) -> Value {
        self.result
            .borrow()
            .as_ref()
            .expect("Mutation contract: batch_create_tasks result staged by apply")
            .payload
            .clone()
    }
}

impl Mutation for BatchCreateTasksMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "batch_create"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let result =
            lorvex_workflow::task_batch_create::batch_create_tasks(conn, hlc, self.input.clone())?;
        let output = MutationOutput::new(
            json!({ "after_states": result.created_tasks }),
            result.summary.clone(),
        );
        self.result.replace(Some(result));
        Ok(output)
    }
}

pub(crate) fn batch_create_tasks(
    conn: &Connection,
    args: BatchCreateTasksArgs,
) -> Result<String, McpError> {
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let BatchCreateTasksArgs {
        tasks,
        include_advice,
        idempotency_key,
        dry_run: _,
    } = args;
    if tasks.is_empty() {
        return Err(McpError::Validation(
            "tasks must contain at least one item".to_string(),
        ));
    }
    if tasks.len() > 500 {
        return Err(McpError::Validation(format!(
            "batch_create_tasks supports at most 500 items, got {}",
            tasks.len()
        )));
    }

    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "batch_create_tasks",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }

    let created_ids = (0..tasks.len())
        .map(|_| lorvex_domain::new_entity_id_string())
        .collect::<Vec<_>>();
    let input = lorvex_workflow::task_batch_create::BatchCreateTasksInput {
        ids: Some(created_ids.clone()),
        tasks: tasks
            .into_iter()
            .map(workflow_task_create_input)
            .collect::<Vec<_>>(),
        include_advice: include_advice.unwrap_or(false),
    };
    let expires_at = crate::runtime::undo::compute_undo_expiry();
    let undo = crate::runtime::undo::McpUndoToken::batch_create(created_ids.clone(), expires_at);
    let undo_token_json = undo.to_json_string()?;

    let mutation = BatchCreateTasksMutation {
        input,
        result: RefCell::new(None),
    };
    execute_mcp_batch_mutation_with_undo_audit_finalizer(
        conn,
        &mutation,
        "batch_create_tasks",
        created_ids,
        undo_token_json.clone(),
        McpError::from,
        |conn, _execution| {
            mutation.with_result_mut(|result| {
                effects::flush_batch_create_effects(conn, result)?;
                if let Value::Object(payload) = &mut result.payload {
                    payload.insert("undo_token".to_string(), Value::String(undo_token_json));
                }
                Ok(())
            })
        },
    )?;

    let response = serde_json::to_string(&mutation.payload())?;
    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "batch_create_tasks",
        &request_repr,
        &response,
    )?;
    Ok(response)
}

fn workflow_task_create_input(
    task: BatchCreateTaskInput,
) -> lorvex_workflow::task_create::TaskCreateInput {
    use lorvex_domain::Patch;
    fn lift<T>(value: Option<T>) -> Patch<T> {
        match value {
            None => Patch::Unset,
            Some(v) => Patch::Set(v),
        }
    }
    lorvex_workflow::task_create::TaskCreateInput {
        title: task.title,
        list_id: lift(task.list_id),
        priority: lift(task.priority),
        due_date: lift(task.due_date),
        due_time: lift(task.due_time),
        estimated_minutes: lift(task.estimated_minutes),
        tags: task.tags,
        body: lift(task.body),
        raw_input: lift(task.raw_input),
        ai_notes: lift(task.ai_notes),
        depends_on: task.depends_on,
        reminders: task.reminders,
        recurrence_json: lift(
            task.recurrence
                .as_ref()
                .map(crate::contract::RecurrenceRuleArgs::to_rule_json_string),
        ),
        planned_date: lift(task.planned_date),
        completed: task.completed,
        status: Patch::Unset,
    }
}

#[cfg(test)]
mod tests;
