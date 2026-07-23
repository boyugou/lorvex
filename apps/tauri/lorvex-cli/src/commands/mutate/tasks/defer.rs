use lorvex_runtime::resolve_db_path;

use crate::cli::OutputFormat;
use crate::commands::mutate::tasks::lifecycle_effects::defer_task_in_tx;
use crate::startup_maintenance::open_db_at_path;

use super::run_task_batch_action;

pub(crate) fn run_defer_tasks(
    task_ids: &[String],
    days: Option<i64>,
    reason: Option<&str>,
    structured_reason: Option<&str>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    // pre-validate + sanitize + resolve the planned date ONCE for the
    // whole batch BEFORE the outer tx opens. The same sanitized inputs
    // and the resolved planned-date string are then passed into every
    // per-id `defer_task_in_tx` call inside the savepoint loop, so all
    // ids land on the same target date even if the wall clock crossed
    // midnight mid-batch.
    if let Some(value) = structured_reason {
        if !lorvex_domain::naming::is_valid_defer_reason(value) {
            return Err(crate::error::CliError::Validation(format!(
                "invalid structured defer reason '{value}'"
            )));
        }
    }
    if let Some(value) = days {
        if value < 1 {
            return Err(crate::error::CliError::Validation(
                "defer days must be >= 1".to_string(),
            ));
        }
    }
    let reason_sanitized = reason.map(lorvex_domain::sanitize_user_text);
    if let Some(value) = reason_sanitized.as_deref() {
        lorvex_domain::validation::validate_body(value)?;
    }

    let db_path = resolve_db_path();
    let probe_conn = open_db_at_path(&db_path)?;
    let planned_date = days
        .map(|offset| {
            crate::commands::shared::effects::date_plus_days_ymd_for_conn(&probe_conn, offset)
        })
        .transpose()?;
    drop(probe_conn);

    run_task_batch_action(
        task_ids,
        "task.defer",
        "deferred",
        "Deferred",
        format,
        |id, status, archived| {
            if archived.is_some() {
                return Err(format!("task '{id}' is in the Trash; restore first"));
            }
            if matches!(status, "completed" | "cancelled") {
                Err(format!("task '{id}' is {status} and cannot be deferred"))
            } else {
                Ok(())
            }
        },
        move |conn, task_id| {
            defer_task_in_tx(
                conn,
                task_id,
                days,
                reason_sanitized.as_deref(),
                structured_reason,
                planned_date.as_deref(),
            )
        },
    )
}
