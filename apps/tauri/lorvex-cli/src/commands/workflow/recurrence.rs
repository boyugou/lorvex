//! Set-recurrence wrapper. The dedicated input struct keeps the CLI
//! flag fan-out (FREQ + INTERVAL/BYDAY/BYMONTHDAY/UNTIL/COUNT) out of
//! the dispatch handler signature.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::ENTITY_TASK;
use lorvex_runtime::resolve_db_path;
use lorvex_sync::outbox_enqueue::enqueue_entity_upsert;
use lorvex_workflow::task_recurrence::{
    self, SetTaskRecurrenceInput, TaskRecurrenceMutationResult, TaskRecurrenceRuleInput,
};
use rusqlite::Connection;
use serde_json::json;

use crate::cli::OutputFormat;
use crate::commands::shared::{log_cli_changelog_with_state, CliChangelogParams};
use crate::error::CliError;
use crate::hlc_guard::CliHlcStateHandle;
use crate::startup_maintenance::open_db_at_path;

use super::render_mutation_response;

pub(crate) struct SetRecurrenceInputs<'a> {
    pub(crate) task_id: &'a str,
    pub(crate) freq: &'a str,
    pub(crate) interval: Option<u32>,
    pub(crate) byday: &'a [String],
    pub(crate) bymonthday: &'a [i64],
    pub(crate) until: Option<&'a str>,
    pub(crate) count: Option<u32>,
}

pub(crate) fn run_set_recurrence(
    inputs: &SetRecurrenceInputs<'_>,
    format: OutputFormat,
) -> Result<String, CliError> {
    let task_id = lorvex_domain::TaskId::parse(inputs.task_id)?;
    let result = run_set_recurrence_workflow(|conn, hlc| {
        task_recurrence::set_task_recurrence(
            conn,
            hlc,
            SetTaskRecurrenceInput {
                task_id,
                rule: TaskRecurrenceRuleInput {
                    freq: inputs.freq.to_string(),
                    interval: inputs.interval,
                    byday: (!inputs.byday.is_empty()).then(|| inputs.byday.to_vec()),
                    bymonth: None,
                    // `--bymonthday` accepts a comma-separated list with
                    // negatives (e.g. `1,15,-1`), matching the `[i64]` wire
                    // model. An empty list means the flag was omitted.
                    bymonthday: (!inputs.bymonthday.is_empty()).then(|| inputs.bymonthday.to_vec()),
                    bysetpos: None,
                    wkst: None,
                    until: inputs.until.map(str::to_string),
                    count: inputs.count,
                },
            },
        )
    })?;
    let db_path = resolve_db_path();
    let raw = serde_json::to_string(&result.after_task)?;
    render_mutation_response(
        "task.set_recurrence",
        &db_path,
        raw,
        format,
        |payload| json!({ "task": payload }),
    )
}

fn run_set_recurrence_workflow<F>(operation: F) -> Result<TaskRecurrenceMutationResult, CliError>
where
    F: for<'a> FnOnce(
        &Connection,
        &HlcSession<'a>,
    ) -> Result<TaskRecurrenceMutationResult, lorvex_store::StoreError>,
{
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    lorvex_store::transaction::with_immediate_transaction(&conn, |conn| {
        let device_id = lorvex_runtime::get_or_create_device_id(conn)?;
        let mut hlc_guard = crate::hlc_guard::lock_shared(conn)?;
        let result = {
            let handle = CliHlcStateHandle::new(&mut hlc_guard);
            let session = HlcSession::new(&handle);
            operation(conn, &session)?
        };
        enqueue_entity_upsert(
            conn,
            ENTITY_TASK,
            &result.task_id,
            &mut hlc_guard,
            &device_id,
        )?;
        log_cli_changelog_with_state(
            conn,
            &mut hlc_guard,
            CliChangelogParams {
                operation: "update",
                entity_type: ENTITY_TASK,
                entity_id: &result.task_id,
                summary: &result.summary,
                before_json: Some(result.before_task.clone()),
                after_json: Some(result.after_task.clone()),
            },
        )?;
        lorvex_runtime::bump_local_change_seq(conn)?;
        Ok::<_, CliError>(result)
    })
}
