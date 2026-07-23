//! CLI handler for `task.batch_create`. Accepts a JSON array of task
//! shapes via `--tasks-json`, deserializes them through the
//! [`TaskCreateInputWire`] shim (so the wire format owns its own serde
//! contract instead of open-coding `take_required_string` /
//! `take_optional_*` JSON pickers), and runs the batch through
//! [`task_batch_create::batch_create_tasks`] under the CLI's
//! transaction + audit envelope.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_TASK;
use lorvex_runtime::resolve_db_path;
use lorvex_workflow::task_batch_create::{self, BatchCreateTasksInput, BatchCreateTasksResult};
use lorvex_workflow::task_create::{TaskCreateInput, TaskCreateInputWire};
use rusqlite::Connection;
use serde_json::json;

use crate::cli::OutputFormat;
use crate::commands::shared::{log_cli_changelog_many_with_state, CliMultiChangelogParams};
use crate::error::CliError;
use crate::hlc_guard::CliHlcStateHandle;
use crate::startup_maintenance::open_db_at_path;

use super::super::render_mutation_response;
use super::dry_run::stamp_dry_run_flag;
use super::shared_flush::enqueue_task_lifecycle_effects;

pub(crate) fn run_batch_create(
    tasks_json: &str,
    include_advice: bool,
    _idempotency_key: Option<&str>,
    dry_run: bool,
    format: OutputFormat,
) -> Result<String, CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let wires: Vec<TaskCreateInputWire> = serde_json::from_str(tasks_json)
        .map_err(|e| CliError::Validation(format!("--tasks-json must be a JSON array: {e}")))?;
    let tasks: Vec<TaskCreateInput> = wires
        .into_iter()
        .map(TaskCreateInputWire::into_workflow_input)
        .collect::<Result<Vec<_>, _>>()
        .map_err(CliError::Validation)?;
    let input = BatchCreateTasksInput {
        ids: None,
        tasks,
        include_advice,
    };
    let mut result = if dry_run {
        run_batch_create_preview(&conn, input)?
    } else {
        run_batch_create_workflow(&conn, input)?
    };
    if dry_run {
        stamp_dry_run_flag(&mut result.payload);
    }
    let raw = serde_json::to_string(&result.payload)?;
    render_mutation_response(
        "task.batch_create",
        &db_path,
        raw,
        format,
        |payload| json!({ "result": payload, "dry_run": dry_run }),
    )
}

fn run_batch_create_preview(
    conn: &Connection,
    input: BatchCreateTasksInput,
) -> Result<BatchCreateTasksResult, CliError> {
    lorvex_store::transaction::with_immediate_transaction(conn, |conn| {
        let mut hlc_guard = crate::hlc_guard::lock_shared(conn)?;
        let handle = CliHlcStateHandle::new(&mut hlc_guard);
        let session = HlcSession::new(&handle);
        let result =
            lorvex_store::with_savepoint_then_rollback(conn, "cli_batch_create_dry_run", |conn| {
                task_batch_create::batch_create_tasks(conn, &session, input)
            })?;
        Ok::<_, CliError>(result)
    })
}

fn run_batch_create_workflow(
    conn: &Connection,
    input: BatchCreateTasksInput,
) -> Result<BatchCreateTasksResult, CliError> {
    lorvex_store::transaction::with_immediate_transaction(conn, |conn| {
        let device_id = lorvex_runtime::get_or_create_device_id(conn)?;
        let mut hlc_guard = crate::hlc_guard::lock_shared(conn)?;
        let result = {
            let handle = CliHlcStateHandle::new(&mut hlc_guard);
            let session = HlcSession::new(&handle);
            task_batch_create::batch_create_tasks(conn, &session, input)?
        };
        enqueue_task_lifecycle_effects(conn, &device_id, &mut hlc_guard, &result.sync_effects)?;
        log_cli_changelog_many_with_state(
            conn,
            &mut hlc_guard,
            CliMultiChangelogParams {
                operation: "batch_create",
                entity_type: ENTITY_TASK,
                entity_ids: &result.created_ids,
                summary: &result.summary,
                before_json: None,
                after_json: Some(json!({ "after_states": result.created_tasks })),
            },
        )?;
        lorvex_runtime::bump_local_change_seq(conn)?;
        Ok::<_, CliError>(result)
    })
}
