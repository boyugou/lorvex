//! CLI handler for `task.batch_update`. The patch shape is owned by
//! [`task_batch_update::BatchUpdateTasksInput`] (which derives serde
//! `Deserialize` from a `TaskUpdateInput` patch shim), so the CLI only
//! plumbs the array and stamps the audit/sync trail.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_TASK;
use lorvex_runtime::resolve_db_path;
use lorvex_workflow::task_batch_update::{self, BatchUpdateTasksInput, BatchUpdateTasksResult};
use rusqlite::Connection;
use serde_json::{json, Value};

use crate::cli::OutputFormat;
use crate::commands::shared::{log_cli_changelog_many_with_state, CliMultiChangelogParams};
use crate::error::CliError;
use crate::hlc_guard::CliHlcStateHandle;
use crate::startup_maintenance::open_db_at_path;

use super::super::render_mutation_response;
use super::dry_run::stamp_dry_run_flag;
use super::shared_flush::enqueue_task_lifecycle_effects;

pub(crate) fn run_batch_update(
    updates_json: &str,
    dry_run: bool,
    format: OutputFormat,
) -> Result<String, CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let updates: Value = serde_json::from_str(updates_json)
        .map_err(|e| CliError::Validation(format!("--updates-json must be a JSON array: {e}")))?;
    if !updates.is_array() {
        return Err(CliError::Validation(
            "--updates-json must be a JSON array".to_string(),
        ));
    }
    let input: BatchUpdateTasksInput = serde_json::from_value(json!({ "updates": updates }))
        .map_err(|e| CliError::Validation(format!("--updates-json entries are invalid: {e}")))?;
    let mut result = if dry_run {
        run_batch_update_preview(&conn, input)?
    } else {
        run_batch_update_workflow(&conn, input)?
    };
    if dry_run {
        stamp_dry_run_flag(&mut result.payload);
    }
    let raw = serde_json::to_string(&result.payload)?;
    render_mutation_response(
        "task.batch_update",
        &db_path,
        raw,
        format,
        |payload| json!({ "result": payload, "dry_run": dry_run }),
    )
}

fn run_batch_update_preview(
    conn: &Connection,
    input: BatchUpdateTasksInput,
) -> Result<BatchUpdateTasksResult, CliError> {
    lorvex_store::transaction::with_immediate_transaction(conn, |conn| {
        let mut hlc_guard = crate::hlc_guard::lock_shared(conn)?;
        let handle = CliHlcStateHandle::new(&mut hlc_guard);
        let session = HlcSession::new(&handle);
        let result =
            lorvex_store::with_savepoint_then_rollback(conn, "cli_batch_update_dry_run", |conn| {
                task_batch_update::batch_update_tasks(conn, &session, input)
            })?;
        Ok::<_, CliError>(result)
    })
}

fn run_batch_update_workflow(
    conn: &Connection,
    input: BatchUpdateTasksInput,
) -> Result<BatchUpdateTasksResult, CliError> {
    lorvex_store::transaction::with_immediate_transaction(conn, |conn| {
        let device_id = lorvex_runtime::get_or_create_device_id(conn)?;
        let mut hlc_guard = crate::hlc_guard::lock_shared(conn)?;
        let result = {
            let handle = CliHlcStateHandle::new(&mut hlc_guard);
            let session = HlcSession::new(&handle);
            task_batch_update::batch_update_tasks(conn, &session, input)?
        };
        enqueue_task_lifecycle_effects(conn, &device_id, &mut hlc_guard, &result.sync_effects)?;
        log_cli_changelog_many_with_state(
            conn,
            &mut hlc_guard,
            CliMultiChangelogParams {
                operation: "batch_update",
                entity_type: ENTITY_TASK,
                entity_ids: &result.updated_ids,
                summary: &result.summary,
                before_json: Some(json!({ "before_states": result.before_tasks })),
                after_json: Some(json!({ "after_states": result.updated_tasks })),
            },
        )?;
        lorvex_runtime::bump_local_change_seq(conn)?;
        Ok::<_, CliError>(result)
    })
}
