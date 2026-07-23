//! Soft-delete (move to Trash), restore from Trash, and permanent
//! delete batch handlers.

use lorvex_runtime::resolve_db_path;
use serde::Serialize;
use serde_json::json;
use std::fmt::Write;

use crate::cli::OutputFormat;
use crate::commands::mutate::tasks::lifecycle_effects::{
    archive_task_in_tx, permanent_delete_task_in_tx, restore_task_from_trash_in_tx,
    PermanentDeleteTaskResult,
};
use crate::commands::shared::render_mutation_envelope;
use crate::startup_maintenance::open_db_at_path;

use super::{precheck_task_states_batch, run_task_batch_action};

pub(crate) fn run_trash_move_tasks(
    task_ids: &[String],
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    run_task_batch_action(
        task_ids,
        "task.trash_move",
        "moved to Trash",
        "Moved",
        format,
        |id, _status, archived| {
            if archived.is_some() {
                Err(format!("task '{id}' is already in the Trash"))
            } else {
                Ok(())
            }
        },
        |conn, task_id| {
            archive_task_in_tx(conn, task_id).map(|task| task.core().title().to_string())
        },
    )
}

pub(crate) fn run_trash_restore_tasks(
    task_ids: &[String],
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    run_task_batch_action(
        task_ids,
        "task.trash_restore",
        "restored from Trash",
        "Restored",
        format,
        |id, _status, archived| {
            if archived.is_none() {
                Err(format!("task '{id}' is not in the Trash"))
            } else {
                Ok(())
            }
        },
        |conn, task_id| {
            restore_task_from_trash_in_tx(conn, task_id).map(|task| task.core().title().to_string())
        },
    )
}

#[derive(Debug, Clone, Serialize)]
struct TrashDeleteBatchResult {
    task_id: String,
    title: Option<String>,
    archived_at: Option<String>,
    deleted: bool,
    dry_run: bool,
    error: Option<String>,
}

impl TrashDeleteBatchResult {
    fn success(result: PermanentDeleteTaskResult) -> Self {
        Self {
            task_id: result.task_id,
            title: result.title,
            archived_at: result.archived_at,
            deleted: result.deleted,
            dry_run: result.dry_run,
            error: None,
        }
    }

    fn failure(task_id: &str, dry_run: bool, error: &crate::error::CliError) -> Self {
        Self {
            task_id: task_id.to_string(),
            title: None,
            archived_at: None,
            deleted: false,
            dry_run,
            error: Some(error.to_string()),
        }
    }
}

pub(crate) fn run_trash_delete_tasks(
    task_ids: &[String],
    dry_run: bool,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    // Pre-flight every id BEFORE running any mutation. Trash-delete
    // requires the row to (a) exist and (b) be in Trash (i.e.
    // `archived_at IS NOT NULL`). Routes through the shared
    // `precheck_task_states_batch` so the SELECT is one IN-list
    // scan rather than N point-queries.
    let ineligible = precheck_task_states_batch(&conn, task_ids, |id, _status, archived| {
        if archived.is_none() {
            Err(format!(
                "task '{id}' is not in the Trash; move to Trash first"
            ))
        } else {
            Ok(())
        }
    })?;
    if !ineligible.is_empty() {
        return Err(crate::error::CliError::Validation(format!(
            "batch trash_delete rejects partial application: {} of {} task(s) are not eligible: [{}]. \
             Re-call with the eligible subset.",
            ineligible.len(),
            task_ids.len(),
            ineligible.join(", "),
        )));
    }

    // #3019-H3: same atomic envelope as `run_task_batch_action` —
    // one outer BEGIN IMMEDIATE, one savepoint per id. For
    // dry_run=true we still wrap each id in a savepoint and we
    // deliberately roll back the OUTER transaction at the end so
    // none of the sentinel reads (or any incidental enqueues that
    // dry-run-eligible callers might land) persist. For dry_run=false
    // a per-id failure rolls back only that savepoint and the loop
    // continues; the outer commit lands every successful per-id
    // savepoint atomically.
    let mut results = Vec::with_capacity(task_ids.len());
    let savepoint_prefix = if dry_run {
        "batch_task_trash_delete_dry_run".to_string()
    } else {
        "batch_task_trash_delete".to_string()
    };
    const DRY_RUN_ROLLBACK_SENTINEL: &str = "lorvex-cli internal: dry_run rollback sentinel";
    let outer = lorvex_store::transaction::with_immediate_transaction::<(), crate::error::CliError>(
        &conn,
        |conn| {
            for task_id in task_ids {
                let task_id_typed = lorvex_domain::TaskId::from_trusted(task_id.clone());
                let task_result = lorvex_store::transaction::with_savepoint::<
                    _,
                    crate::error::CliError,
                >(conn, &savepoint_prefix, |conn| {
                    permanent_delete_task_in_tx(conn, &task_id_typed, dry_run)
                });
                match task_result {
                    Ok(result) => results.push(TrashDeleteBatchResult::success(result)),
                    Err(error) => {
                        results.push(TrashDeleteBatchResult::failure(task_id, dry_run, &error));
                    }
                }
            }
            // dry_run abandons the outer tx so the
            // entire preview is rolled back as one unit — no commit
            // landed, no outbox row leaked. The success path commits.
            if dry_run {
                Err(crate::error::CliError::Internal(
                    DRY_RUN_ROLLBACK_SENTINEL.to_string(),
                ))
            } else {
                Ok(())
            }
        },
    );
    match outer {
        Ok(()) => {}
        Err(crate::error::CliError::Internal(ref message))
            if message == DRY_RUN_ROLLBACK_SENTINEL =>
        {
            // expected dry_run path — outer rollback already happened.
        }
        Err(error) => return Err(error),
    }
    let succeeded_count = results
        .iter()
        .filter(|result| result.error.is_none())
        .count();
    let deleted_count = results
        .iter()
        .filter(|result| result.error.is_none() && result.deleted)
        .count();
    let action_label = if dry_run {
        "dry-run delete forever"
    } else {
        "delete forever"
    };

    match format {
        OutputFormat::Text => {
            let mut output = format!(
                "Batch {action_label} Lorvex tasks\nDB: {}\nCount: {}\nSucceeded: {}\nDeleted: {}\n",
                db_path.display(),
                results.len(),
                succeeded_count,
                deleted_count,
            );
            for result in &results {
                if let Some(error) = &result.error {
                    let _ = writeln!(output, "- {}: error: {}", result.task_id, error);
                } else {
                    let _ = writeln!(
                        output,
                        "- {}: {} {}",
                        result.task_id,
                        if dry_run {
                            "would delete"
                        } else if result.deleted {
                            "deleted"
                        } else {
                            "noop"
                        },
                        result.title.as_deref().unwrap_or("(missing)")
                    );
                }
            }
            Ok(output)
        }
        // canonical batch envelope shape — same fields
        // as `run_task_batch_action`. `deleted_count` is kept as an
        // extra signal because trash delete distinguishes
        // "succeeded with row deleted" from "succeeded as a no-op
        // because the row was already gone" — that information
        // would be lost if collapsed into `success_count`.
        OutputFormat::Json => {
            let task_ids_array: Vec<&str> = results.iter().map(|r| r.task_id.as_str()).collect();
            let action = if dry_run {
                "task.trash_delete_dry_run"
            } else {
                "task.trash_delete"
            };
            render_mutation_envelope(
                action,
                &db_path,
                json!({
                    "count": task_ids.len(),
                    "success_count": succeeded_count,
                    "deleted_count": deleted_count,
                    "results": results,
                    "task_ids": task_ids_array,
                }),
            )
        }
    }
}
