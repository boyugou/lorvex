use crate::contract::BatchMoveTasksArgs;
use crate::error::McpError;
use crate::runtime::change_tracking::execute_mcp_batch_mutation_with_audit_finalizer;
use crate::system::handler_support::{
    fetch_tasks_json_batch, plural_s, required_json_string_field, resolve_list_name, utc_now_iso,
};
use crate::system::vec_limits::validate_batch_ids;
use crate::tasks::lww::execute_task_lww_update;
use crate::tasks::validation::validate_list_exists;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, STATUS_CANCELLED};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::{params, Connection};
use serde_json::{json, Value};

struct BatchMoveTasksMutation {
    task_ids: Vec<String>,
    list_id: String,
    before_tasks: Vec<Value>,
    now: String,
    summary: String,
}

impl Mutation for BatchMoveTasksMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "batch_update"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(Value::Array(self.before_tasks.clone())))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        for task_id in &self.task_ids {
            let version = hlc.next_version_string();
            execute_task_lww_update(
                conn,
                "UPDATE tasks
                 SET list_id = ?1, version = ?2, updated_at = ?3
                 WHERE id = ?4 AND ?2 > version
                 RETURNING 1",
                params![
                    self.list_id.as_str(),
                    version.as_str(),
                    self.now.as_str(),
                    task_id.as_str()
                ],
                task_id,
            )
            .map_err(mcp_error_to_store)?;
        }

        let updated_tasks = fetch_tasks_json_batch(conn, &self.task_ids, "task after move")
            .map_err(mcp_error_to_store)?;
        Ok(MutationOutput::new(
            Value::Array(updated_tasks),
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

pub(crate) fn batch_move_tasks(
    conn: &Connection,
    args: BatchMoveTasksArgs,
) -> Result<String, McpError> {
    // see `batch_complete_tasks` — capture the
    // canonical request fingerprint before destructure for the
    // checksum-gated cache lookup.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let BatchMoveTasksArgs {
        task_ids,
        list_id,
        idempotency_key,
    } = args;
    // see batch_complete_tasks for rationale.
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "batch_move_tasks",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    validate_batch_ids(&task_ids, "batch_move_tasks")?;
    // validate the target list exists at the trust
    // boundary instead of relying on the FK constraint. The FK
    // surfaces a generic "FOREIGN KEY constraint failed" string;
    // `validate_list_exists` produces the canonical
    // "list 'X' does not exist" error that matches every other
    // batch tool's diagnostic. Mirrors `batch_cancel_tasks_in_list`.
    validate_list_exists(conn, Some(&list_id))?;

    // the pre-move snapshot is captured for
    // the changelog `before_json` slot. Without this, the diff
    // renderer has no visibility into which list each task moved
    // away from.
    let before_tasks = fetch_tasks_json_batch(conn, &task_ids, "batch_move_tasks")?;
    if before_tasks.len() != task_ids.len() {
        return Err(McpError::NotFound(format!(
            "batch_move_tasks requested {} task(s) but only {} found",
            task_ids.len(),
            before_tasks.len()
        )));
    }

    let mut moved_task_ids = Vec::new();
    let mut moved_before_tasks = Vec::new();
    let mut skipped = Vec::new();
    for task in &before_tasks {
        let task_id = required_json_string_field(task, "id", "batch_move_tasks before-task")?;
        let status = required_json_string_field(task, "status", "batch_move_tasks before-task")?;
        let current_list_id =
            required_json_string_field(task, "list_id", "batch_move_tasks before-task")?;
        if status == STATUS_CANCELLED || current_list_id == list_id {
            skipped.push(task_id.to_string());
        } else {
            moved_task_ids.push(task_id.to_string());
            moved_before_tasks.push(task.clone());
        }
    }

    let updated_tasks = if moved_task_ids.is_empty() {
        Vec::new()
    } else {
        let now = utc_now_iso();
        let target_list = resolve_list_name(conn, &list_id)?.unwrap_or_else(|| list_id.clone());
        let summary = format!(
            "Moved {} task{} to {}",
            moved_task_ids.len(),
            plural_s(moved_task_ids.len()),
            target_list
        );
        let mutation = BatchMoveTasksMutation {
            task_ids: moved_task_ids.clone(),
            list_id: list_id.clone(),
            before_tasks: moved_before_tasks,
            now,
            summary,
        };
        let output = execute_mcp_batch_mutation_with_audit_finalizer(
            conn,
            &mutation,
            "batch_move_tasks",
            moved_task_ids,
            McpError::from,
            |_, _| Ok(()),
        )?;
        output
            .after
            .as_array()
            .expect("Mutation contract: batch_move_tasks after is task array")
            .clone()
    };

    let response = serde_json::to_string(&json!({
        "moved_count": updated_tasks.len(),
        "list_id": list_id,
        "tasks": updated_tasks,
        "skipped": skipped,
    }))?;

    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "batch_move_tasks",
        &request_repr,
        &response,
    )?;

    Ok(response)
}
