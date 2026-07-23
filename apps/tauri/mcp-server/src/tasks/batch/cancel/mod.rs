use crate::contract::{BatchCancelTasksInListArgs, TaskStatusValue};
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_mutation_with_finalizer;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_TASK;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use lorvex_workflow::task_batch_cancel::{
    self, BatchCancelInListInput, BatchCancelInListResult, BatchCancelStatus,
};
use rusqlite::Connection;
use serde_json::{json, Value};
use std::cell::RefCell;

mod effects;

struct BatchCancelTasksInListMutation {
    input: BatchCancelInListInput,
    result: RefCell<Option<BatchCancelInListResult>>,
}

impl BatchCancelTasksInListMutation {
    fn with_result<F>(&self, f: F) -> Result<(), McpError>
    where
        F: FnOnce(&BatchCancelInListResult) -> Result<(), McpError>,
    {
        let result = self.result.borrow();
        let result = result
            .as_ref()
            .expect("Mutation contract: batch_cancel_tasks_in_list result staged by apply");
        f(result)
    }

    fn payload(&self) -> Value {
        self.result
            .borrow()
            .as_ref()
            .expect("Mutation contract: batch_cancel_tasks_in_list result staged by apply")
            .payload
            .clone()
    }
}

impl Mutation for BatchCancelTasksInListMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "batch_cancel"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let result = task_batch_cancel::batch_cancel_tasks_in_list(conn, hlc, self.input.clone())?;
        let summary = result
            .summary
            .clone()
            .unwrap_or_else(|| format!("Cancelled 0 tasks in list {}", result.list_id));
        let output = MutationOutput::new(json!({ "after_states": result.after_tasks }), summary);
        self.result.replace(Some(result));
        Ok(output)
    }
}

pub(crate) fn batch_cancel_tasks_in_list(
    conn: &Connection,
    args: BatchCancelTasksInListArgs,
) -> Result<String, McpError> {
    // idempotency cache. Capture canonical
    // fingerprint before destructure.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let BatchCancelTasksInListArgs {
        list_id,
        statuses,
        cancel_series,
        // `dry_run` is consumed at the router layer (#2370) — the
        // mutation body itself is unaware of preview mode; the caller
        // decides whether the outer transaction commits or rolls back.
        dry_run: _,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "batch_cancel_tasks_in_list",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let typed_list_id = lorvex_domain::ListId::parse(&list_id).map_err(McpError::from)?;
    let input = BatchCancelInListInput {
        list_id: typed_list_id,
        statuses: statuses.filter(|values| !values.is_empty()).map(|values| {
            values
                .into_iter()
                .map(batch_cancel_status_from_contract)
                .collect::<Vec<_>>()
        }),
        cancel_series: cancel_series.unwrap_or(false),
    };
    let mutation = BatchCancelTasksInListMutation {
        input,
        result: RefCell::new(None),
    };
    execute_mcp_mutation_with_finalizer(conn, &mutation, McpError::from, |_execution| {
        mutation.with_result(|result| effects::flush_batch_cancel_effects(conn, result))
    })?;
    let response = serde_json::to_string(&mutation.payload())?;
    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "batch_cancel_tasks_in_list",
        &request_repr,
        &response,
    )?;
    Ok(response)
}

const fn batch_cancel_status_from_contract(status: TaskStatusValue) -> BatchCancelStatus {
    match status {
        TaskStatusValue::Open => BatchCancelStatus::Open,
        TaskStatusValue::Completed => BatchCancelStatus::Completed,
        TaskStatusValue::Cancelled => BatchCancelStatus::Cancelled,
        TaskStatusValue::Someday => BatchCancelStatus::Someday,
    }
}

#[cfg(test)]
mod tests;
