use crate::contract::{
    AddTaskChecklistItemArgs, RemoveTaskChecklistItemArgs, ReorderTaskChecklistItemsArgs,
    ToggleTaskChecklistItemArgs, UpdateTaskChecklistItemArgs,
};
use crate::contract_validate::ContractValidate;
use crate::error::McpError;
use crate::runtime::change_tracking::{
    enqueue_relation_sync_with_snapshot, execute_mcp_mutation_with_audit_finalizer,
};
use crate::tasks::validation::validate_uuid_arg;
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, ENTITY_TASK_CHECKLIST_ITEM};
use lorvex_domain::{ChecklistItemId, TaskId};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationExecution, MutationOutput};
use lorvex_workflow::mutation_extras::TASK_CHECKLIST_ITEM_SYNC_CHANGES;
use lorvex_workflow::task_checklist::{
    self, AddTaskChecklistItemInput, RemoveTaskChecklistItemInput, ReorderTaskChecklistItemsInput,
    TaskChecklistMutationResult, ToggleTaskChecklistItemInput, UpdateTaskChecklistItemInput,
};
use rusqlite::{params, Connection};
use serde_json::{json, Value};

enum TaskChecklistMutation {
    Add(AddTaskChecklistItemInput),
    Update {
        task_id: TaskId,
        input: UpdateTaskChecklistItemInput,
    },
    Toggle {
        task_id: TaskId,
        input: ToggleTaskChecklistItemInput,
    },
    Remove {
        task_id: TaskId,
        input: RemoveTaskChecklistItemInput,
    },
    Reorder(ReorderTaskChecklistItemsInput),
}

impl TaskChecklistMutation {
    const fn task_id(&self) -> &TaskId {
        match self {
            Self::Add(input) => &input.task_id,
            Self::Reorder(input) => &input.task_id,
            Self::Update { task_id, .. }
            | Self::Toggle { task_id, .. }
            | Self::Remove { task_id, .. } => task_id,
        }
    }
}

impl Mutation for TaskChecklistMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "set_checklist"
    }

    fn pre_snapshot(&self, conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(
            lorvex_workflow::task_response::load_enriched_task_json(conn, self.task_id())?,
        ))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let result = match self {
            Self::Add(input) => task_checklist::add_task_checklist_item(conn, hlc, input.clone())?,
            Self::Update { input, .. } => {
                task_checklist::update_task_checklist_item(conn, hlc, input.clone())?
            }
            Self::Toggle { input, .. } => {
                task_checklist::toggle_task_checklist_item(conn, hlc, input.clone())?
            }
            Self::Remove { input, .. } => {
                task_checklist::remove_task_checklist_item(conn, hlc, input.clone())?
            }
            Self::Reorder(input) => {
                task_checklist::reorder_task_checklist_items(conn, hlc, input.clone())?
            }
        };
        Ok(output_from_checklist_result(result))
    }
}

fn output_from_checklist_result(result: TaskChecklistMutationResult) -> MutationOutput {
    let item_sync_changes = result
        .item_sync_changes
        .into_iter()
        .map(|change| {
            json!({
                "item_id": change.item_id,
                "operation": change.operation.as_str(),
                "snapshot": change.snapshot,
            })
        })
        .collect();
    let mut output = MutationOutput::new(result.after_task, result.summary);
    output.set_extra(
        &TASK_CHECKLIST_ITEM_SYNC_CHANGES,
        Value::Array(item_sync_changes),
    );
    output
}

fn enqueue_checklist_item_syncs(
    conn: &Connection,
    execution: &MutationExecution,
) -> Result<(), McpError> {
    let changes = execution
        .output
        .get_extra(&TASK_CHECKLIST_ITEM_SYNC_CHANGES)
        .and_then(Value::as_array)
        .expect("Mutation contract: task checklist sync changes stamped by apply");

    for change in changes {
        let item_id = change
            .get("item_id")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                McpError::Internal(
                    "task checklist sync change missing string `item_id`".to_string(),
                )
            })?;
        let operation = change
            .get("operation")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                McpError::Internal(
                    "task checklist sync change missing string `operation`".to_string(),
                )
            })?;
        let snapshot = change
            .get("snapshot")
            .cloned()
            .filter(|value| !value.is_null());
        enqueue_relation_sync_with_snapshot(
            conn,
            ENTITY_TASK_CHECKLIST_ITEM,
            item_id,
            operation,
            snapshot,
        )?;
    }
    Ok(())
}

fn load_task_id_for_checklist_item(
    conn: &Connection,
    item_id: &ChecklistItemId,
) -> Result<TaskId, McpError> {
    conn.prepare_cached("SELECT task_id FROM task_checklist_items WHERE id = ?1")?
        .query_row(params![item_id], |row| {
            let task_id: String = row.get(0)?;
            Ok(TaskId::from_trusted(task_id))
        })
        .map_err(|error| match error {
            rusqlite::Error::QueryReturnedNoRows => StoreError::NotFound {
                entity: "checklist item",
                id: item_id.to_string(),
            }
            .into(),
            other => McpError::from(other),
        })
}

fn execute_checklist_mutation(
    conn: &Connection,
    mcp_tool: &'static str,
    mutation: TaskChecklistMutation,
    idempotency_key: Option<&str>,
    request_repr: &str,
) -> Result<String, McpError> {
    let output = execute_mcp_mutation_with_audit_finalizer(
        conn,
        &mutation,
        mcp_tool,
        mutation.task_id().to_string(),
        McpError::from,
        enqueue_checklist_item_syncs,
    )?;
    let response = serde_json::to_string(&output.after)?;
    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key,
        mcp_tool,
        request_repr,
        &response,
    )?;
    Ok(response)
}

pub(crate) fn add_task_checklist_item(
    conn: &Connection,
    args: AddTaskChecklistItemArgs,
) -> Result<String, McpError> {
    // capture the canonical request fingerprint
    // before destructure for the checksum-gated cache lookup. See
    // `batch_complete_tasks` for full rationale.
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    let AddTaskChecklistItemArgs {
        id: task_id,
        text,
        position,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "add_task_checklist_item",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let task_id = TaskId::from_trusted(validate_uuid_arg(&task_id, "id")?);
    let mutation = TaskChecklistMutation::Add(AddTaskChecklistItemInput {
        task_id,
        text,
        position,
    });
    execute_checklist_mutation(
        conn,
        "add_task_checklist_item",
        mutation,
        idempotency_key.as_deref(),
        &request_repr,
    )
}

pub(crate) fn update_task_checklist_item(
    conn: &Connection,
    args: UpdateTaskChecklistItemArgs,
) -> Result<String, McpError> {
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    args.validate_shape()?;
    let UpdateTaskChecklistItemArgs {
        item_id,
        text,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "update_task_checklist_item",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let item_id = ChecklistItemId::from_trusted(item_id);
    let task_id = load_task_id_for_checklist_item(conn, &item_id)?;
    let mutation = TaskChecklistMutation::Update {
        task_id,
        input: UpdateTaskChecklistItemInput { item_id, text },
    };
    execute_checklist_mutation(
        conn,
        "update_task_checklist_item",
        mutation,
        idempotency_key.as_deref(),
        &request_repr,
    )
}

pub(crate) fn toggle_task_checklist_item(
    conn: &Connection,
    args: ToggleTaskChecklistItemArgs,
) -> Result<String, McpError> {
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    args.validate_shape()?;
    let ToggleTaskChecklistItemArgs {
        item_id,
        completed,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "toggle_task_checklist_item",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let item_id = ChecklistItemId::from_trusted(item_id);
    let task_id = load_task_id_for_checklist_item(conn, &item_id)?;
    let mutation = TaskChecklistMutation::Toggle {
        task_id,
        input: ToggleTaskChecklistItemInput { item_id, completed },
    };
    execute_checklist_mutation(
        conn,
        "toggle_task_checklist_item",
        mutation,
        idempotency_key.as_deref(),
        &request_repr,
    )
}

pub(crate) fn remove_task_checklist_item(
    conn: &Connection,
    args: RemoveTaskChecklistItemArgs,
) -> Result<String, McpError> {
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    args.validate_shape()?;
    let RemoveTaskChecklistItemArgs {
        item_id,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "remove_task_checklist_item",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let item_id = ChecklistItemId::from_trusted(item_id);
    let task_id = load_task_id_for_checklist_item(conn, &item_id)?;
    let mutation = TaskChecklistMutation::Remove {
        task_id,
        input: RemoveTaskChecklistItemInput { item_id },
    };
    execute_checklist_mutation(
        conn,
        "remove_task_checklist_item",
        mutation,
        idempotency_key.as_deref(),
        &request_repr,
    )
}

pub(crate) fn reorder_task_checklist_items(
    conn: &Connection,
    args: ReorderTaskChecklistItemsArgs,
) -> Result<String, McpError> {
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    args.validate_shape()?;
    let ReorderTaskChecklistItemsArgs {
        id: task_id,
        item_ids,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "reorder_task_checklist_items",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }
    let task_id = TaskId::from_trusted(validate_uuid_arg(&task_id, "id")?);
    let item_ids = item_ids
        .into_iter()
        .map(ChecklistItemId::from_trusted)
        .collect();
    let mutation =
        TaskChecklistMutation::Reorder(ReorderTaskChecklistItemsInput { task_id, item_ids });
    execute_checklist_mutation(
        conn,
        "reorder_task_checklist_items",
        mutation,
        idempotency_key.as_deref(),
        &request_repr,
    )
}
