use crate::contract::ReopenTaskArgs;
use crate::contract_validate::ContractValidate;
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_mutation_with_audit_finalizer;
use crate::system::handler_support::{
    fetch_task_json, reload_task_json, required_json_string_field, utc_now_iso,
};
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, STATUS_OPEN};
use lorvex_domain::TaskId;
use lorvex_store::{repositories::task::write, StoreError};
use lorvex_workflow::lifecycle::{
    effects as workflow_effects, LifecycleSyncPlan, ReopenLifecycleTransitionResult,
};
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::Value;
use std::cell::RefCell;

struct ReopenTaskMutation {
    task_id: TaskId,
    before: Value,
    before_status: String,
    now: String,
    summary: String,
    result: RefCell<Option<ReopenLifecycleTransitionResult>>,
}

impl ReopenTaskMutation {
    fn take_result(&self) -> ReopenLifecycleTransitionResult {
        self.result
            .borrow_mut()
            .take()
            .expect("Mutation contract: reopen_task result staged by apply")
    }
}

impl Mutation for ReopenTaskMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "reopen"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let before_status =
            write::parse_task_status_for_update(self.task_id.as_str(), &self.before_status)?;
        let result =
            workflow_effects::run_reopen(conn, &self.task_id, before_status, &self.now, hlc)?;

        let after = reload_task_json(conn, self.task_id.as_str(), "task after reopen (pre-stamp)")
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

pub(crate) fn reopen_task(conn: &Connection, args: ReopenTaskArgs) -> Result<String, McpError> {
    // capture the canonical request fingerprint
    // before destructure for the checksum-gated cache lookup. See
    // `batch_complete_tasks` for full rationale.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    args.validate_shape()?;
    let ReopenTaskArgs {
        id,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "reopen_task",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    // see `complete_task` — derive enforced UUID format; trim
    // defensively to match the prior `validate_uuid_arg` return shape.
    let id = id.trim().to_string();
    let before = fetch_task_json(conn, &id)?;
    let before_status =
        required_json_string_field(&before, "status", "reopen_task before-task")?.to_string();

    if before_status == STATUS_OPEN {
        return Err(McpError::Validation(format!("Task '{id}' is already open")));
    }

    let now = utc_now_iso();
    let title =
        required_json_string_field(&before, "title", "reopen_task before-task")?.to_string();
    let summary = format!("Reopened '{title}' (was {before_status})");
    let mutation = ReopenTaskMutation {
        task_id: TaskId::from_trusted(id.clone()),
        before,
        before_status,
        now,
        summary,
        result: RefCell::new(None),
    };
    execute_mcp_mutation_with_audit_finalizer(
        conn,
        &mutation,
        "reopen_task",
        id.clone(),
        McpError::from,
        |conn, _execution| {
            let transition = mutation.take_result();
            crate::tasks::lifecycle::effects::flush_sync_plan(
                conn,
                LifecycleSyncPlan::from_reopen(&transition),
                crate::tasks::lifecycle::effects::LifecycleSyncLogContext {
                    mcp_tool: "reopen_task",
                    spawned_successor_summary: None,
                    cancelled_successor_summary: Some(
                        "Cancelled recurring successor (task reopened)".to_string(),
                    ),
                    affected_dependent_reason: "task".to_string(),
                    successor_affected_reason: "cancelled successor".to_string(),
                    rewire_parent_task_id: None,
                    rewire_parent_description: "reopened recurring task",
                },
            )?;
            Ok(())
        },
    )?;

    // Note: reopen is a status reopen, not a logical undo. Dependency edges
    // deleted on cancel are NOT restored.

    // Re-fetch AFTER enqueue to get the post-stamp version.
    let after = reload_task_json(conn, &id, "task after reopen")?;

    let response = serde_json::to_string(&after)?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "reopen_task",
        &request_repr,
        &response,
    )?;

    Ok(response)
}
