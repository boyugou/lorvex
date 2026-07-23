//! CLI handler for `task.batch_cancel_in_list`. Cancels every task in
//! a list whose status matches `--status` (or all open statuses when
//! `--status` is omitted), optionally including future recurrence
//! successors via `--cancel-series`.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_TASK;
use lorvex_runtime::resolve_db_path;
use lorvex_workflow::task_batch_cancel::{
    self, flush_batch_cancel_with_backend, BatchCancelInListInput, BatchCancelInListResult,
    BatchCancelStatus,
};
use rusqlite::Connection;
use serde_json::json;

use crate::cli::OutputFormat;
use crate::commands::shared::{log_cli_changelog_many_with_state, CliMultiChangelogParams};
use crate::error::CliError;
use crate::hlc_guard::CliHlcStateHandle;
use crate::startup_maintenance::open_db_at_path;

use super::super::render_mutation_response;
use super::dry_run::stamp_dry_run_flag;
mod flush;
use flush::CliBatchCancelFlush;

pub(crate) fn run_batch_cancel_in_list(
    list_id: &str,
    statuses: &[String],
    cancel_series: Option<bool>,
    dry_run: bool,
    format: OutputFormat,
) -> Result<String, CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let typed_list_id = lorvex_domain::ListId::parse(list_id)?;
    let input = BatchCancelInListInput {
        list_id: typed_list_id,
        statuses: parse_batch_cancel_statuses(statuses)?,
        cancel_series: cancel_series.unwrap_or(false),
    };
    let mut result = if dry_run {
        run_batch_cancel_in_list_preview(&conn, input)?
    } else {
        run_batch_cancel_in_list_workflow(&conn, input)?
    };
    if dry_run {
        stamp_dry_run_flag(&mut result.payload);
    }
    let raw = serde_json::to_string(&result.payload)?;
    render_mutation_response(
        "task.batch_cancel_in_list",
        &db_path,
        raw,
        format,
        |payload| json!({ "result": payload, "dry_run": dry_run }),
    )
}

fn parse_batch_cancel_statuses(
    statuses: &[String],
) -> Result<Option<Vec<BatchCancelStatus>>, CliError> {
    if statuses.is_empty() {
        return Ok(None);
    }
    let parsed = statuses
        .iter()
        .map(|status| BatchCancelStatus::parse(status))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(Some(parsed))
}

fn run_batch_cancel_in_list_preview(
    conn: &Connection,
    input: BatchCancelInListInput,
) -> Result<BatchCancelInListResult, CliError> {
    lorvex_store::transaction::with_immediate_transaction(conn, |conn| {
        let mut hlc_guard = crate::hlc_guard::lock_shared(conn)?;
        let handle = CliHlcStateHandle::new(&mut hlc_guard);
        let session = HlcSession::new(&handle);
        let result = lorvex_store::with_savepoint_then_rollback(
            conn,
            "cli_batch_cancel_in_list_dry_run",
            |conn| task_batch_cancel::batch_cancel_tasks_in_list(conn, &session, input),
        )?;
        Ok::<_, CliError>(result)
    })
}

fn run_batch_cancel_in_list_workflow(
    conn: &Connection,
    input: BatchCancelInListInput,
) -> Result<BatchCancelInListResult, CliError> {
    lorvex_store::transaction::with_immediate_transaction(conn, |conn| {
        let device_id = lorvex_runtime::get_or_create_device_id(conn)?;
        let mut hlc_guard = crate::hlc_guard::lock_shared(conn)?;
        let result = {
            let handle = CliHlcStateHandle::new(&mut hlc_guard);
            let session = HlcSession::new(&handle);
            task_batch_cancel::batch_cancel_tasks_in_list(conn, &session, input)?
        };
        flush_cli_batch_cancel_effects(conn, &device_id, &mut hlc_guard, &result.sync_effects)?;
        if let Some(summary) = &result.summary {
            let entity_id_strings: Vec<String> = result
                .task_ids
                .iter()
                .map(|id| id.as_str().to_string())
                .collect();
            log_cli_changelog_many_with_state(
                conn,
                &mut hlc_guard,
                CliMultiChangelogParams {
                    operation: "batch_cancel",
                    entity_type: ENTITY_TASK,
                    entity_ids: &entity_id_strings,
                    summary,
                    before_json: Some(json!({ "before_states": result.before_tasks })),
                    after_json: Some(json!({ "after_states": result.after_tasks })),
                },
            )?;
            lorvex_runtime::bump_local_change_seq(conn)?;
        }
        Ok::<_, CliError>(result)
    })
}

fn flush_cli_batch_cancel_effects(
    conn: &Connection,
    device_id: &str,
    hlc_state: &mut lorvex_domain::hlc_state::HlcState,
    effects: &lorvex_workflow::task_batch_cancel::BatchCancelSyncEffects,
) -> Result<(), CliError> {
    let backend = CliBatchCancelFlush::new(device_id, hlc_state);
    flush_batch_cancel_with_backend(conn, effects, &backend)
}
