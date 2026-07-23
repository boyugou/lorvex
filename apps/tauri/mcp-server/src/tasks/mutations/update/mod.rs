//! MCP `update_task` adapter — routes the single-row update through
//! the canonical `lorvex_workflow::task_update::update_task` so the SQL
//! writes, lifecycle transitions, recurrence + due_date co-application,
//! edge diffing, and per-row sync-effect accumulation share one
//! implementation with the batch surface and the CLI.

use crate::contract::UpdateTaskArgs;
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_mutation_with_audit_finalizer;
use crate::system::handler_support::{fetch_task_json, reload_task_json};
use crate::tasks::support::task_status_value_to_str;
use crate::tasks::update_sync::flush_task_update_effects;
use crate::tasks::validation::validate_uuid_arg;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_TASK;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use lorvex_workflow::task_update::{TaskUpdateInput, UpdatedTaskOutcome};
use rusqlite::Connection;
use serde_json::Value;
use std::cell::RefCell;

struct UpdateTaskMutation {
    input: TaskUpdateInput,
    before: Value,
    result: RefCell<Option<UpdatedTaskOutcome>>,
}

impl UpdateTaskMutation {
    fn with_result<R>(&self, f: impl FnOnce(&UpdatedTaskOutcome) -> R) -> R {
        let borrowed = self.result.borrow();
        let outcome = borrowed
            .as_ref()
            .expect("Mutation contract: update_task outcome staged by apply");
        f(outcome)
    }
}

impl Mutation for UpdateTaskMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "update"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let outcome = lorvex_workflow::task_update::update_task(conn, hlc, self.input.clone())?;
        // The workflow already loads the enriched after-task and a
        // summary that names the title; the MCP audit row carries
        // them straight through.
        let after = outcome.updated_task.clone();
        let summary = outcome.summary.clone();
        self.result.replace(Some(outcome));
        Ok(MutationOutput::new(after, summary))
    }
}

pub(crate) fn update_task(conn: &Connection, args: UpdateTaskArgs) -> Result<String, McpError> {
    // see `batch_complete_tasks` for full rationale of the canonical
    // request fingerprint + idempotency cache. `update_task` is
    // additive on `tags_add` / `depends_on` patches — a retry without
    // the cache short-circuit re-runs the side-effect appliers and
    // writes a duplicate audit row.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let mut args = args;
    let task_id = validate_uuid_arg(&args.id, "id")?;
    args.id.clone_from(&task_id);
    let idempotency_key = args.idempotency_key.clone();
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "update_task",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let before = fetch_task_json(conn, &task_id)?;
    let input = workflow_task_update_input(args, task_id.clone());

    let mutation = UpdateTaskMutation {
        input,
        before,
        result: RefCell::new(None),
    };
    let executor_handled = vec![task_id.clone()];
    execute_mcp_mutation_with_audit_finalizer(
        conn,
        &mutation,
        "update_task",
        task_id.clone(),
        McpError::from,
        |conn, _execution| {
            mutation.with_result(|outcome| {
                flush_task_update_effects(
                    conn,
                    &outcome.sync_effects,
                    &executor_handled,
                    "update_task",
                )
            })
        },
    )?;

    let final_task = reload_task_json(conn, &task_id, "task final post-stamp")?;
    let response = serde_json::to_string(&final_task)?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "update_task",
        &request_repr,
        &response,
    )?;

    Ok(response)
}

fn workflow_task_update_input(args: UpdateTaskArgs, task_id: String) -> TaskUpdateInput {
    let UpdateTaskArgs {
        id: _,
        title,
        body,
        raw_input,
        ai_notes,
        status,
        list_id,
        tags_set,
        tags_add,
        tags_remove,
        priority,
        due_date,
        due_time,
        estimated_minutes,
        recurrence,
        depends_on,
        depends_on_add,
        depends_on_remove,
        planned_date,
        idempotency_key: _,
    } = args;
    TaskUpdateInput {
        id: task_id,
        // MCP's public surface keeps these as `Option<T>` because the
        // assistant contract doesn't expose a "clear to null" affordance
        // for them (title/status/list_id are NOT NULL columns;
        // raw_input is technically nullable but the public schema does
        // not offer a clear gesture). Map `Some(v) → Set(v)` and
        // `None → Unset` so the workflow's three-state shape is preserved.
        title: title
            .map(lorvex_domain::Patch::Set)
            .unwrap_or(lorvex_domain::Patch::Unset),
        body,
        raw_input: raw_input
            .map(lorvex_domain::Patch::Set)
            .unwrap_or(lorvex_domain::Patch::Unset),
        ai_notes,
        status: status
            .map(task_status_value_to_str)
            .map(str::to_string)
            .map(lorvex_domain::Patch::Set)
            .unwrap_or(lorvex_domain::Patch::Unset),
        list_id: list_id
            .map(lorvex_domain::Patch::Set)
            .unwrap_or(lorvex_domain::Patch::Unset),
        tags_set,
        tags_add,
        tags_remove,
        // MCP exposes `priority: Option<u8>` because the public assistant
        // contract does not allow clearing priority via update_task. The
        // workflow input keeps the three-state shape because the Tauri
        // surface does allow clearing (renderer posts `priority: null`);
        // map MCP's `Some/None` onto `Set/Unset` so the no-clear surface
        // semantics are preserved.
        priority: priority
            .map(lorvex_domain::Patch::Set)
            .unwrap_or(lorvex_domain::Patch::Unset),
        due_date,
        due_time,
        estimated_minutes,
        recurrence: recurrence.map(|rule| rule.to_rule_json()),
        depends_on,
        depends_on_add,
        depends_on_remove,
        planned_date,
    }
}
