//! Task mutation handlers, grouped by lifecycle / handler-family.
//!
//! Submodules:
//! - [`capture`] — single-task creation (`run_capture`).
//! - [`update`] — partial-field edits (`run_update_task`).
//! - [`lifecycle`] — atomic batch state transitions (`run_complete_tasks`,
//!   `run_cancel_tasks`, `run_reopen_tasks`).
//! - [`trash`] — soft-delete + restore + permanent delete batches.
//! - [`defer`] — date-shifting batch with structured-reason validation.
//! - [`move_list`] — multi-task list assignment.
//!
//! The shared atomic-batch driver (`run_task_batch_action`) and the
//! one-IN-list precheck (`precheck_task_states_batch`) live in this
//! file because every batch verb in the submodules consumes them.

use crate::cli::OutputFormat;
use crate::commands::shared::render_mutation_envelope;
use crate::startup_maintenance::open_db_at_path;
use lorvex_domain::TaskId;
use lorvex_runtime::resolve_db_path;
use serde::Serialize;
use serde_json::json;
use std::fmt::Write;

mod body_writes;
pub(crate) mod body_writes_effects;
#[cfg(test)]
mod body_writes_effects_tests;
mod capture;
pub(crate) mod capture_effects;
#[cfg(test)]
mod capture_effects_tests;
mod defer;
pub(crate) mod dependencies;
mod lifecycle;
pub(crate) mod lifecycle_effects;
mod move_list;
mod trash;
mod update;

pub(crate) use body_writes::{
    run_task_add_ai_notes, run_task_add_recurrence_exception, run_task_append_body,
    run_task_remove_recurrence_exception,
};
pub(crate) use capture::run_capture;
pub(crate) use defer::run_defer_tasks;
pub(crate) use lifecycle::{run_cancel_tasks, run_complete_tasks, run_reopen_tasks};
pub(crate) use move_list::run_move_tasks;
pub(crate) use trash::{run_trash_delete_tasks, run_trash_move_tasks, run_trash_restore_tasks};
pub(crate) use update::run_update_task;

#[cfg(test)]
mod tests;

#[derive(Debug, Clone, Serialize)]
pub(super) struct TaskBatchActionResult {
    task_id: String,
    title: Option<String>,
    error: Option<String>,
}

/// pre-flight eligibility gate mirroring
/// `mcp-server/src/tasks/batch/complete.rs::batch_complete_tasks`
/// (#2928-H7). Each batch verb supplies a `precheck` closure that
/// returns the per-id error string if the task is in a state that
/// makes the action invalid (already-terminal, missing row, or any
/// other verb-specific block). All ineligible ids are surfaced in
/// one error message and NO mutation runs.
/// per-task with try/match-on-error, pushing successes and failures
/// into the same envelope; that left the caller unable to
/// distinguish racing-peer "already completed" from user-error
/// "wrong id" because both showed up as a partial-result row.
pub(super) fn run_task_batch_action<E, F>(
    task_ids: &[String],
    action: &str,
    past_tense: &str,
    count_label: &str,
    format: OutputFormat,
    eligibility: E,
    mut apply: F,
) -> Result<String, crate::error::CliError>
where
    E: Fn(&str, &str, Option<&str>) -> Result<(), String>,
    F: FnMut(&rusqlite::Connection, &TaskId) -> Result<String, crate::error::CliError>,
{
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    // Pre-flight: one IN-list SELECT loads every task's
    // (status, archived_at) and the eligibility closure runs in
    // memory per id.
    // per id, paying one round trip per task; an N-task batch
    // therefore burned N point-queries before any mutation could
    // start. Missing rows surface as `task '{id}' not found`;
    // every id-specific ineligibility is collected so the caller
    // sees every problem in a single error message
    //.
    let ineligible = precheck_task_states_batch(&conn, task_ids, &eligibility)?;
    if !ineligible.is_empty() {
        return Err(crate::error::CliError::Validation(format!(
            "batch {action} rejects partial application: {} of {} task(s) are not eligible: [{}]. \
             Re-call with the eligible subset.",
            ineligible.len(),
            task_ids.len(),
            ineligible.join(", "),
        )));
    }

    // #3019-H3: run every per-id mutation inside ONE outer
    // BEGIN IMMEDIATE transaction, with each per-id call wrapped in
    // its own SAVEPOINT (`batch_<task_id>`-like prefix sanitized by
    // `with_savepoint`). A per-id failure rolls back only that
    // savepoint and the loop continues; the outer transaction commits
    // every successful per-id savepoint atomically when the loop
    // returns.
    // `BEGIN IMMEDIATE` and committed immediately, so a mid-batch
    // failure left the prior ids permanently committed and the
    // remaining ids untouched — the comment in the file (#2939-M1)
    // already promised atomicity that the implementation never
    // delivered.
    let mut results = Vec::with_capacity(task_ids.len());
    let savepoint_prefix = format!("batch_{}", action.replace('.', "_"));
    lorvex_store::transaction::with_immediate_transaction::<_, crate::error::CliError>(
        &conn,
        |conn| {
            for task_id in task_ids {
                let task_id_typed = TaskId::from_trusted(task_id.clone());
                match lorvex_store::transaction::with_savepoint::<_, crate::error::CliError>(
                    conn,
                    &savepoint_prefix,
                    |conn| apply(conn, &task_id_typed),
                ) {
                    Ok(title) => results.push(TaskBatchActionResult {
                        task_id: task_id.clone(),
                        title: Some(title),
                        error: None,
                    }),
                    Err(error) => results.push(TaskBatchActionResult {
                        task_id: task_id.clone(),
                        title: None,
                        error: Some(error.to_string()),
                    }),
                }
            }
            Ok(())
        },
    )?;

    let success_count = results
        .iter()
        .filter(|result| result.error.is_none())
        .count();

    match format {
        OutputFormat::Text => {
            let mut output = format!(
                "Batch {past_tense} Lorvex tasks\nDB: {}\nCount: {}\n{count_label}: {}\n",
                db_path.display(),
                results.len(),
                success_count,
            );
            for result in &results {
                if let Some(title) = &result.title {
                    let _ = writeln!(output, "- {}: {past_tense} {}", result.task_id, title);
                } else {
                    let _ = writeln!(
                        output,
                        "- {}: error: {}",
                        result.task_id,
                        result.error.as_deref().unwrap_or("unknown error"),
                    );
                }
            }
            Ok(output)
        }
        // canonical batch envelope shape is
        // `{action, db_path, count, success_count, results, task_ids}`.
        // The previous shape used per-verb count fields
        // (`completed_count`, `cancelled_count`, ...) so JSON
        // consumers had to hard-code each verb to find the success
        // count; `task_ids` is also a top-level convenience array of
        // every input id (in `results` order) so a consumer can
        // `jq '.task_ids[]'` without traversing per-row objects.
        OutputFormat::Json => {
            let task_ids_array: Vec<&str> = results.iter().map(|r| r.task_id.as_str()).collect();
            render_mutation_envelope(
                action,
                &db_path,
                json!({
                    "count": task_ids.len(),
                    "success_count": success_count,
                    "results": results,
                    "task_ids": task_ids_array,
                }),
            )
        }
    }
}

/// Load `(status, archived_at)` for every id in `task_ids` in a
/// single `IN (…)` scan, then run `eligibility` against each row.
///
/// Returns the formatted per-id ineligibility messages — empty
/// vector means every id is eligible. Missing rows surface as
/// `task '{id}' not found` (/ 3 contract).
/// Each eligibility closure receives `(task_id, status, archived_at)`
/// so the verb-specific message can render the full
/// `"task '{id}' is …"` form matching CLI's lifecycle helpers
/// (`archive_task_with_conn` / `restore_task_from_trash_with_conn`)
/// and the Tauri / MCP surfaces. SQL errors propagate as typed
/// `CliError::Sql` (exit 74) instead of being silently masked.
pub(super) fn precheck_task_states_batch(
    conn: &rusqlite::Connection,
    task_ids: &[String],
    eligibility: impl Fn(&str, &str, Option<&str>) -> Result<(), String>,
) -> Result<Vec<String>, crate::error::CliError> {
    let mut ineligible: Vec<String> = Vec::new();
    if task_ids.is_empty() {
        return Ok(ineligible);
    }

    let placeholders = lorvex_domain::sql_csv_placeholders(task_ids.len());
    let sql = format!("SELECT id, status, archived_at FROM tasks WHERE id IN ({placeholders})");
    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt.query_map(rusqlite::params_from_iter(task_ids.iter()), |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, Option<String>>(2)?,
        ))
    })?;
    let mut by_id: std::collections::HashMap<String, (String, Option<String>)> =
        std::collections::HashMap::with_capacity(task_ids.len());
    for row in rows {
        let (id, status, archived_at) = row?;
        by_id.insert(id, (status, archived_at));
    }

    // Iterate `task_ids` (not the SELECT result) so missing ids
    // surface and the order of the diagnostic matches the order
    // the caller passed.
    for task_id in task_ids {
        match by_id.get(task_id) {
            None => ineligible.push(format!("task '{task_id}' not found")),
            Some((status, archived_at)) => {
                if let Err(reason) = eligibility(task_id, status, archived_at.as_deref()) {
                    ineligible.push(format!("{task_id}: {reason}"));
                }
            }
        }
    }
    Ok(ineligible)
}
