use crate::contract::CreateTaskArgs;
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_mutation_with_audit_finalizer;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_TASK;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::Value;
use std::cell::RefCell;

mod effects;

struct CreateTaskMutation {
    input: lorvex_workflow::task_create::CreateTaskInput,
    result: RefCell<Option<lorvex_workflow::task_create::CreateTaskResult>>,
}

impl CreateTaskMutation {
    fn with_result_mut<F>(&self, f: F) -> Result<(), McpError>
    where
        F: FnOnce(&mut lorvex_workflow::task_create::CreateTaskResult) -> Result<(), McpError>,
    {
        let mut result = self.result.borrow_mut();
        let result = result
            .as_mut()
            .expect("Mutation contract: create_task result staged by apply");
        f(result)
    }

    fn payload(&self) -> Value {
        self.result
            .borrow()
            .as_ref()
            .expect("Mutation contract: create_task result staged by apply")
            .payload
            .clone()
    }
}

impl Mutation for CreateTaskMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "create"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let result = lorvex_workflow::task_create::create_task(conn, hlc, self.input.clone())?;
        let output = MutationOutput::new(result.task.clone(), result.summary.clone());
        self.result.replace(Some(result));
        Ok(output)
    }
}

pub(crate) fn create_task(conn: &Connection, args: CreateTaskArgs) -> Result<String, McpError> {
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "create_task",
        args.idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }

    let idempotency_key = args.idempotency_key.clone();
    let include_advice = args.include_advice.unwrap_or(false);
    let task_id = lorvex_domain::new_entity_id_string();
    let input = lorvex_workflow::task_create::CreateTaskInput {
        id: Some(task_id.clone()),
        task: workflow_task_create_input(args),
        include_advice,
    };
    let mutation = CreateTaskMutation {
        input,
        result: RefCell::new(None),
    };
    execute_mcp_mutation_with_audit_finalizer(
        conn,
        &mutation,
        "create_task",
        task_id,
        McpError::from,
        |conn, _execution| {
            mutation.with_result_mut(|result| {
                effects::flush_create_effects(conn, result)?;
                Ok(())
            })
        },
    )?;

    let response = serde_json::to_string(&mutation.payload())?;
    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "create_task",
        &request_repr,
        &response,
    )?;

    Ok(response)
}

fn workflow_task_create_input(
    args: CreateTaskArgs,
) -> lorvex_workflow::task_create::TaskCreateInput {
    use lorvex_domain::Patch;
    fn lift<T>(value: Option<T>) -> Patch<T> {
        match value {
            None => Patch::Unset,
            Some(v) => Patch::Set(v),
        }
    }
    lorvex_workflow::task_create::TaskCreateInput {
        title: args.title,
        list_id: lift(args.list_id),
        priority: lift(args.priority),
        due_date: lift(args.due_date),
        due_time: lift(args.due_time),
        estimated_minutes: lift(args.estimated_minutes),
        tags: args.tags,
        body: lift(args.body),
        raw_input: lift(args.raw_input),
        ai_notes: lift(args.ai_notes),
        depends_on: args.depends_on,
        reminders: args.reminders,
        recurrence_json: lift(
            args.recurrence
                .as_ref()
                .map(crate::contract::RecurrenceRuleArgs::to_rule_json_string),
        ),
        planned_date: lift(args.planned_date),
        completed: args.completed,
        status: Patch::Unset,
    }
}

#[cfg(test)]
mod tests;
