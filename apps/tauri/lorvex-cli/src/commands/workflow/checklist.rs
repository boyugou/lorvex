//! Task checklist mutations — add / update / toggle / remove / reorder.
//! Each handler returns the updated parent task envelope so callers
//! can refresh local state without a follow-up read.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, ENTITY_TASK_CHECKLIST_ITEM};
use lorvex_runtime::resolve_db_path;
use lorvex_sync::outbox_enqueue::{enqueue_entity_upsert, enqueue_payload_delete};
use lorvex_workflow::task_checklist::{
    self, AddTaskChecklistItemInput, ChecklistSyncOperation, RemoveTaskChecklistItemInput,
    ReorderTaskChecklistItemsInput, TaskChecklistMutationResult, ToggleTaskChecklistItemInput,
    UpdateTaskChecklistItemInput,
};
use rusqlite::Connection;
use serde_json::json;

use crate::cli::OutputFormat;
use crate::commands::shared::{bare_outbox_ctx, log_cli_changelog_with_state, CliChangelogParams};
use crate::error::CliError;
use crate::hlc_guard::CliHlcStateHandle;
use crate::startup_maintenance::open_db_at_path;

use super::render_mutation_response;

fn run_checklist_workflow<F>(
    action: &'static str,
    format: OutputFormat,
    operation: F,
) -> Result<String, CliError>
where
    F: for<'a> FnOnce(
        &Connection,
        &HlcSession<'a>,
    ) -> Result<TaskChecklistMutationResult, lorvex_store::StoreError>,
{
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let result = lorvex_store::transaction::with_immediate_transaction(&conn, |conn| {
        let device_id = lorvex_runtime::get_or_create_device_id(conn)?;
        let mut hlc_guard = crate::hlc_guard::lock_shared(conn)?;
        let result = {
            let handle = CliHlcStateHandle::new(&mut hlc_guard);
            let session = HlcSession::new(&handle);
            operation(conn, &session)?
        };

        for change in &result.item_sync_changes {
            match change.operation {
                ChecklistSyncOperation::Upsert => enqueue_entity_upsert(
                    conn,
                    ENTITY_TASK_CHECKLIST_ITEM,
                    &change.item_id,
                    &mut hlc_guard,
                    &device_id,
                )?,
                ChecklistSyncOperation::Delete => {
                    let snapshot = change.snapshot.as_ref().ok_or_else(|| {
                        CliError::Internal(format!(
                            "task_checklist delete for '{}' did not carry a pre-delete snapshot",
                            change.item_id
                        ))
                    })?;
                    let version = hlc_guard.generate().to_string();
                    enqueue_payload_delete(
                        conn,
                        ENTITY_TASK_CHECKLIST_ITEM,
                        &change.item_id,
                        snapshot,
                        bare_outbox_ctx(&version, &device_id),
                    )?;
                }
            }
        }
        log_cli_changelog_with_state(
            conn,
            &mut hlc_guard,
            CliChangelogParams {
                operation: "set_checklist",
                entity_type: ENTITY_TASK,
                entity_id: &result.task_id,
                summary: &result.summary,
                before_json: Some(result.before_task.clone()),
                after_json: Some(result.after_task.clone()),
            },
        )?;
        lorvex_runtime::bump_local_change_seq(conn)?;
        Ok::<_, CliError>(result)
    })?;
    let raw = serde_json::to_string(&result.after_task)?;
    render_mutation_response(
        action,
        &db_path,
        raw,
        format,
        |payload| json!({ "task": payload }),
    )
}

pub(crate) fn run_checklist_add(
    task_id: &str,
    text: &str,
    position: Option<u32>,
    format: OutputFormat,
) -> Result<String, CliError> {
    let task_id = lorvex_domain::TaskId::parse(task_id)?;
    run_checklist_workflow("task.checklist_add", format, |conn, hlc| {
        task_checklist::add_task_checklist_item(
            conn,
            hlc,
            AddTaskChecklistItemInput {
                task_id,
                text: text.to_string(),
                position,
            },
        )
    })
}

pub(crate) fn run_checklist_update(
    item_id: &str,
    text: &str,
    format: OutputFormat,
) -> Result<String, CliError> {
    let item_id = lorvex_domain::ChecklistItemId::parse(item_id)?;
    run_checklist_workflow("task.checklist_update", format, |conn, hlc| {
        task_checklist::update_task_checklist_item(
            conn,
            hlc,
            UpdateTaskChecklistItemInput {
                item_id,
                text: text.to_string(),
            },
        )
    })
}

pub(crate) fn run_checklist_toggle(
    item_id: &str,
    completed: bool,
    format: OutputFormat,
) -> Result<String, CliError> {
    let item_id = lorvex_domain::ChecklistItemId::parse(item_id)?;
    run_checklist_workflow("task.checklist_toggle", format, |conn, hlc| {
        task_checklist::toggle_task_checklist_item(
            conn,
            hlc,
            ToggleTaskChecklistItemInput { item_id, completed },
        )
    })
}

pub(crate) fn run_checklist_remove(
    item_id: &str,
    format: OutputFormat,
) -> Result<String, CliError> {
    let item_id = lorvex_domain::ChecklistItemId::parse(item_id)?;
    run_checklist_workflow("task.checklist_remove", format, |conn, hlc| {
        task_checklist::remove_task_checklist_item(
            conn,
            hlc,
            RemoveTaskChecklistItemInput { item_id },
        )
    })
}

pub(crate) fn run_checklist_reorder(
    task_id: &str,
    item_ids: &[String],
    format: OutputFormat,
) -> Result<String, CliError> {
    let task_id = lorvex_domain::TaskId::parse(task_id)?;
    let item_ids = item_ids
        .iter()
        .map(lorvex_domain::ChecklistItemId::parse)
        .collect::<Result<Vec<_>, _>>()?;
    run_checklist_workflow("task.checklist_reorder", format, |conn, hlc| {
        task_checklist::reorder_task_checklist_items(
            conn,
            hlc,
            ReorderTaskChecklistItemsInput { task_id, item_ids },
        )
    })
}
