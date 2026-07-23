use std::cell::RefCell;

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, STATUS_CANCELLED, STATUS_COMPLETED};
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use lorvex_workflow::task_deferral;
use rusqlite::Connection;
use serde_json::Value;

use crate::commands::fetch_task_row_unenriched;
use crate::commands::shared::effects::execute_ipc_mutation_with_finalizer;

use super::super::*;
use super::shared::validate_batch_task_ids;

#[derive(Debug, serde::Serialize)]
pub struct BatchDeferResult {
    pub deferred_count: usize,
    pub deferred: Vec<Task>,
    pub skipped: Vec<String>,
}

#[tauri::command]
pub fn batch_defer_tasks(
    task_ids: Vec<String>,
    until_date: String,
    structured_reason: Option<String>,
) -> Result<BatchDeferResult, String> {
    batch_defer_tasks_inner(task_ids, until_date, structured_reason).map_err(String::from)
}

fn batch_defer_tasks_inner(
    task_ids: Vec<String>,
    until_date: String,
    structured_reason: Option<String>,
) -> Result<BatchDeferResult, AppError> {
    let conn = get_conn()?;
    let result = batch_defer_tasks_with_conn(&conn, task_ids, until_date, structured_reason)?;

    // event_bus emit is handled by the per-row executor.

    // Post-commit Spotlight dispatch: reindex deferred tasks.
    if !result.deferred.is_empty() {
        let deferred_ids: Vec<String> = result.deferred.iter().map(|t| t.id.clone()).collect();
        crate::platform::spotlight::apply_actions(
            &conn,
            &[crate::platform::spotlight::SpotlightAction::ReindexTaskIds(
                deferred_ids,
            )],
        );
    }
    Ok(result)
}

/// `Mutation` descriptor for one task's deferral inside a
/// `batch_defer_tasks` loop. `apply` runs the canonical
/// `task_deferral::defer_task` against the per-mutation `HlcSession`
/// and stashes the resulting `shifted_reminder_ids` so the surface
/// finalizer can enqueue the reminder upserts.
struct BatchDeferTaskMutation<'a> {
    task_id: &'a lorvex_domain::TaskId,
    now: &'a str,
    normalized_until_date: &'a str,
    structured_reason: Option<&'a str>,
    shifted_reminder_ids: RefCell<Vec<String>>,
}

impl<'a> Mutation for BatchDeferTaskMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "defer"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let version = hlc.next_version_string();
        let patch = task_deferral::TaskDeferralPatch {
            planned_date: Some(self.normalized_until_date),
            ai_notes: None,
            last_defer_reason: self.structured_reason,
        };
        let result =
            task_deferral::defer_task(conn, self.task_id, &patch, &version, self.now, || {
                Ok::<String, StoreError>(hlc.next_version_string())
            })?;
        if !result.updated {
            return Err(StoreError::StaleVersion {
                entity: ENTITY_TASK,
                id: self.task_id.to_string(),
            });
        }
        *self.shifted_reminder_ids.borrow_mut() = result.shifted_reminder_ids;
        let summary = format!(
            "Batch-deferred task '{}' until {}",
            self.task_id.as_str(),
            self.normalized_until_date
        );
        let after = serde_json::json!({ "id": self.task_id.as_str() });
        Ok(MutationOutput::new(after, summary))
    }
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
/// Transactional body of `batch_defer_tasks` against a caller-supplied
/// connection, returning the rich `BatchDeferResult`.
pub(crate) fn batch_defer_tasks_with_conn(
    conn: &rusqlite::Connection,
    task_ids: Vec<String>,
    until_date: String,
    structured_reason: Option<String>,
) -> Result<BatchDeferResult, AppError> {
    let task_ids = validate_batch_task_ids(&task_ids)?;

    // Validate structured defer reason if provided.
    if let Some(ref r) = structured_reason {
        if !lorvex_domain::naming::is_valid_defer_reason(r) {
            return Err(AppError::Validation(format!(
                "Invalid defer reason '{}'. Valid values: {}",
                r,
                lorvex_domain::naming::ALL_DEFER_REASONS.join(", ")
            )));
        }
    }

    with_immediate_transaction(conn, |conn| {
        let now = sync_timestamp_now();
        let normalized_until_date = normalize_date_input_for_conn(conn, &until_date)?;
        if lorvex_domain::validation::validate_date_format(&normalized_until_date).is_err() {
            return Err(AppError::Validation(
                "until_date must be a valid YYYY-MM-DD date".to_string(),
            ));
        }

        let mut deferred_ids = Vec::new();
        let mut skipped = Vec::new();

        // Pre-fetch status for all tasks in one batch.
        let pre_map = fetch_tasks_by_ids(conn, &task_ids)?;

        for id in &task_ids {
            let Some(task) = pre_map.get(id) else {
                skipped.push(id.clone());
                continue;
            };
            if task.status == STATUS_COMPLETED || task.status == STATUS_CANCELLED {
                skipped.push(id.clone());
                continue;
            }

            let task_id_typed = lorvex_domain::TaskId::from_trusted(id.clone());
            let mutation = BatchDeferTaskMutation {
                task_id: &task_id_typed,
                now: &now,
                normalized_until_date: &normalized_until_date,
                structured_reason: structured_reason.as_deref(),
                shifted_reminder_ids: RefCell::new(Vec::new()),
            };

            execute_ipc_mutation_with_finalizer(conn, &mutation, |conn, _execution| {
                let shifted = mutation.shifted_reminder_ids.borrow();
                for reminder_id in shifted.iter() {
                    enqueue_task_reminder_upsert(conn, reminder_id)?;
                }
                // Unenriched — `enqueue_task_upsert` strips derived
                // child fields anyway.
                let updated = fetch_task_row_unenriched(conn, id)?;
                enqueue_task_upsert(conn, &updated)?;
                Ok(())
            })?;

            deferred_ids.push(id.clone());
        }

        // Batch re-fetch for post-stamp versions.
        let deferred = fetch_ordered_tasks_by_ids(conn, &deferred_ids, "batch defer")?;

        Ok(BatchDeferResult {
            deferred_count: deferred.len(),
            deferred,
            skipped,
        })
    })
}
