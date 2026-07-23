//! Atomic batch state transitions: complete / cancel / reopen.
//!
//! the singular `run_complete` / `run_cancel` /
//! `run_reopen` helpers were deleted along with the argv-length
//! dispatch in `main.rs`. Single-id calls now flow through the same
//! batch path so the JSON envelope shape is constant regardless of
//! input length.

use crate::cli::OutputFormat;
use crate::commands::mutate::tasks::lifecycle_effects::{
    cancel_task_in_tx, complete_task_in_tx, reopen_task_in_tx,
};

use super::run_task_batch_action;

pub(crate) fn run_complete_tasks(
    task_ids: &[String],
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    run_task_batch_action(
        task_ids,
        "task.complete",
        "completed",
        "Completed",
        format,
        |id, status, archived| {
            if archived.is_some() {
                return Err(format!("task '{id}' is in the Trash; restore first"));
            }
            match status {
                "completed" => Err(format!("task '{id}' is already completed")),
                "cancelled" => Err(format!(
                    "task '{id}' is cancelled and cannot be completed; reopen first"
                )),
                _ => Ok(()),
            }
        },
        // #3019-H3: use the inside-tx variant so the per-id call runs
        // inside the outer-tx + per-id-savepoint envelope, not its
        // own immediate transaction.
        complete_task_in_tx,
    )
}

pub(crate) fn run_cancel_tasks(
    task_ids: &[String],
    cancel_series: bool,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    run_task_batch_action(
        task_ids,
        "task.cancel",
        "cancelled",
        "Cancelled",
        format,
        |id, status, archived| {
            if archived.is_some() {
                return Err(format!("task '{id}' is in the Trash; restore first"));
            }
            match status {
                "cancelled" => Err(format!("task '{id}' is already cancelled")),
                "completed" => Err(format!(
                    "task '{id}' is completed and cannot be cancelled; reopen first"
                )),
                _ => Ok(()),
            }
        },
        |conn, task_id| cancel_task_in_tx(conn, task_id, cancel_series),
    )
}

pub(crate) fn run_reopen_tasks(
    task_ids: &[String],
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    run_task_batch_action(
        task_ids,
        "task.reopen",
        "reopened",
        "Reopened",
        format,
        |id, status, archived| {
            if archived.is_some() {
                return Err(format!("task '{id}' is in the Trash; restore first"));
            }
            if status == "open" {
                Err(format!("task '{id}' is already open"))
            } else {
                Ok(())
            }
        },
        reopen_task_in_tx,
    )
}
