use crate::contract::{BatchUpdateTaskPatch, BatchUpdateTasksArgs, TaskStatusValue};
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_batch_mutation_with_undo_audit_finalizer;
use crate::system::handler_support::fetch_tasks_json_batch;
use crate::system::vec_limits::validate_batch_ids;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_TASK;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use lorvex_workflow::task_batch_update::{
    BatchUpdateTaskPatchInput, BatchUpdateTasksInput, BatchUpdateTasksResult,
};
use rusqlite::Connection;
use serde_json::{json, Value};
use std::cell::RefCell;

mod effects;

struct BatchUpdateTasksMutation {
    input: BatchUpdateTasksInput,
    before_tasks: Vec<Value>,
    result: RefCell<Option<BatchUpdateTasksResult>>,
}

impl BatchUpdateTasksMutation {
    fn with_result_mut<F>(&self, f: F) -> Result<(), McpError>
    where
        F: FnOnce(&mut BatchUpdateTasksResult) -> Result<(), McpError>,
    {
        let mut result = self.result.borrow_mut();
        let result = result
            .as_mut()
            .expect("Mutation contract: batch_update_tasks result staged by apply");
        f(result)
    }

    fn payload(&self) -> Value {
        self.result
            .borrow()
            .as_ref()
            .expect("Mutation contract: batch_update_tasks result staged by apply")
            .payload
            .clone()
    }
}

impl Mutation for BatchUpdateTasksMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "batch_update"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(json!({ "before_states": self.before_tasks.clone() })))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let result =
            lorvex_workflow::task_batch_update::batch_update_tasks(conn, hlc, self.input.clone())?;
        let output = MutationOutput::new(
            json!({ "after_states": result.updated_tasks }),
            result.summary.clone(),
        );
        self.result.replace(Some(result));
        Ok(output)
    }
}

pub(crate) fn batch_update_tasks(
    conn: &Connection,
    args: BatchUpdateTasksArgs,
) -> Result<String, McpError> {
    let BatchUpdateTasksArgs {
        updates,
        // `dry_run` is consumed at the router layer (#2370).
        dry_run: _,
    } = args;
    let input = BatchUpdateTasksInput {
        updates: updates
            .into_iter()
            .map(workflow_batch_update_patch)
            .collect(),
    };
    let update_ids = input
        .updates
        .iter()
        .map(|update| update.id.clone())
        .collect::<Vec<_>>();
    validate_batch_ids(&update_ids, "batch_update_tasks")?;
    let before_tasks = fetch_tasks_json_batch(conn, &update_ids, "batch_update_tasks")?;
    if before_tasks.len() != update_ids.len() {
        return Err(McpError::NotFound(format!(
            "batch_update_tasks requested {} task(s) but only {} found",
            update_ids.len(),
            before_tasks.len()
        )));
    }

    let expires_at = crate::runtime::undo::compute_undo_expiry();
    let undo = crate::runtime::undo::McpUndoToken::batch_update(before_tasks.clone(), expires_at);
    let undo_token_json = undo.to_json_string()?;

    let mutation = BatchUpdateTasksMutation {
        input,
        before_tasks,
        result: RefCell::new(None),
    };
    execute_mcp_batch_mutation_with_undo_audit_finalizer(
        conn,
        &mutation,
        "batch_update_tasks",
        update_ids,
        undo_token_json.clone(),
        McpError::from,
        |conn, _execution| {
            mutation.with_result_mut(|result| {
                effects::flush_batch_update_effects(conn, result)?;
                if let Value::Object(payload) = &mut result.payload {
                    payload.insert("undo_token".to_string(), Value::String(undo_token_json));
                }
                Ok(())
            })
        },
    )?;

    Ok(serde_json::to_string(&mutation.payload())?)
}

fn workflow_batch_update_patch(update: BatchUpdateTaskPatch) -> BatchUpdateTaskPatchInput {
    BatchUpdateTaskPatchInput {
        id: update.id,
        // MCP's public surface keeps these as `Option<T>` because the
        // assistant contract does not expose a "clear to null"
        // affordance; the workflow's three-state shape is preserved by
        // mapping `Some/None → Set/Unset`.
        title: update
            .title
            .map(lorvex_domain::Patch::Set)
            .unwrap_or(lorvex_domain::Patch::Unset),
        body: update.body,
        raw_input: update
            .raw_input
            .map(lorvex_domain::Patch::Set)
            .unwrap_or(lorvex_domain::Patch::Unset),
        ai_notes: update.ai_notes,
        status: update
            .status
            .map(task_status_value_to_str)
            .map(str::to_string)
            .map(lorvex_domain::Patch::Set)
            .unwrap_or(lorvex_domain::Patch::Unset),
        list_id: update
            .list_id
            .map(lorvex_domain::Patch::Set)
            .unwrap_or(lorvex_domain::Patch::Unset),
        tags_set: update.tags_set,
        tags_add: update.tags_add,
        tags_remove: update.tags_remove,
        // MCP's batch surface keeps the public `Option<u8>` wire shape
        // because clearing priority via update is intentionally not
        // exposed to assistants; the workflow input takes a `Patch<u8>`
        // so the Tauri surface can post `priority: null` to clear.
        priority: update
            .priority
            .map(lorvex_domain::Patch::Set)
            .unwrap_or(lorvex_domain::Patch::Unset),
        due_date: update.due_date,
        due_time: update.due_time,
        estimated_minutes: update.estimated_minutes,
        recurrence: update.recurrence.map(|rule| rule.to_rule_json()),
        depends_on: update.depends_on,
        depends_on_add: update.depends_on_add,
        depends_on_remove: update.depends_on_remove,
        planned_date: update.planned_date,
    }
}

const fn task_status_value_to_str(status: TaskStatusValue) -> &'static str {
    match status {
        TaskStatusValue::Open => lorvex_domain::naming::STATUS_OPEN,
        TaskStatusValue::Completed => lorvex_domain::naming::STATUS_COMPLETED,
        TaskStatusValue::Cancelled => lorvex_domain::naming::STATUS_CANCELLED,
        TaskStatusValue::Someday => lorvex_domain::naming::STATUS_SOMEDAY,
    }
}

#[cfg(test)]
mod tests;
