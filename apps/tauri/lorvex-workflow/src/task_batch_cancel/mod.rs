use std::collections::HashSet;

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{STATUS_CANCELLED, STATUS_COMPLETED, STATUS_OPEN, STATUS_SOMEDAY};
use lorvex_domain::{ListId, TaskId};
use lorvex_store::StoreError;
use rusqlite::{params_from_iter, types::Value as SqlValue, Connection};
use serde_json::{json, Value};

use crate::lifecycle::{self, CopiedTagEdge, DeletedDependencyEdge, StatusSideEffectSyncPlan};
use crate::task_response::load_enriched_task_json;

mod flush;

pub use flush::{
    flush_batch_cancel_with_backend, BatchCancelBackendError, BatchCancelFlushBackend,
};
// Re-export the cross-effect base trait through this module so
// per-surface backends can `use lorvex_workflow::task_batch_cancel::MutationFlushBackend`
// alongside the BatchCancel-specific subtrait. The trait itself
// lives in `task_update::flush` (it is intentionally cross-effect:
// every per-effect bundle layers on top of the same base).
pub use crate::task_update::MutationFlushBackend;

const MAX_IN_LIST_CANCEL: usize = 500;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BatchCancelStatus {
    Open,
    Completed,
    Cancelled,
    Someday,
}

impl BatchCancelStatus {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Open => STATUS_OPEN,
            Self::Completed => STATUS_COMPLETED,
            Self::Cancelled => STATUS_CANCELLED,
            Self::Someday => STATUS_SOMEDAY,
        }
    }

    pub fn parse(raw: &str) -> Result<Self, StoreError> {
        match raw.trim().to_ascii_lowercase().as_str() {
            STATUS_OPEN => Ok(Self::Open),
            STATUS_COMPLETED => Ok(Self::Completed),
            STATUS_CANCELLED => Ok(Self::Cancelled),
            STATUS_SOMEDAY => Ok(Self::Someday),
            _ => Err(StoreError::Validation(format!(
                "status must be one of {STATUS_OPEN}, {STATUS_COMPLETED}, {STATUS_CANCELLED}, {STATUS_SOMEDAY}"
            ))),
        }
    }
}

#[derive(Debug, Clone)]
pub struct BatchCancelInListInput {
    pub list_id: ListId,
    pub statuses: Option<Vec<BatchCancelStatus>>,
    pub cancel_series: bool,
}

#[derive(Debug, Clone)]
pub struct SpawnedSuccessorLog {
    pub successor_id: TaskId,
    pub summary: String,
    pub after_task: Value,
}

#[derive(Debug, Default)]
pub struct BatchCancelSyncEffects {
    pub task_upsert_ids: Vec<String>,
    pub cancelled_reminder_ids: Vec<String>,
    pub deleted_dependency_edges: Vec<DeletedDependencyEdge>,
    pub affected_dependent_ids: Vec<String>,
    pub spawned_successors: Vec<SpawnedSuccessorLog>,
    pub spawned_successor_tag_edges: Vec<CopiedTagEdge>,
    pub spawned_successor_checklist_item_ids: Vec<String>,
    pub spawned_successor_reminder_ids: Vec<String>,
    pub rewired_focus_schedule_dates: Vec<String>,
    pub rewired_current_focus_dates: Vec<String>,
}

#[derive(Debug)]
pub struct BatchCancelInListResult {
    pub list_id: ListId,
    pub task_ids: Vec<TaskId>,
    pub before_tasks: Vec<Value>,
    pub after_tasks: Vec<Value>,
    pub payload: Value,
    pub summary: Option<String>,
    pub sync_effects: BatchCancelSyncEffects,
}

fn load_enriched_tasks_existing(
    conn: &Connection,
    ids: &[TaskId],
) -> Result<Vec<Value>, StoreError> {
    let mut tasks = Vec::with_capacity(ids.len());
    for task_id in ids {
        if let Ok(task) = load_enriched_task_json(conn, task_id) {
            tasks.push(task);
        }
    }
    Ok(tasks)
}

fn list_name(conn: &Connection, list_id: &ListId) -> Result<String, StoreError> {
    match conn.query_row(
        "SELECT name FROM lists WHERE id = ?1",
        [list_id.as_str()],
        |row| row.get::<_, String>(0),
    ) {
        Ok(name) => Ok(name),
        Err(rusqlite::Error::QueryReturnedNoRows) => Ok(list_id.as_str().to_string()),
        Err(error) => Err(StoreError::from(error)),
    }
}

const fn plural_s(count: usize) -> &'static str {
    if count == 1 {
        ""
    } else {
        "s"
    }
}

fn candidate_tasks(
    conn: &Connection,
    list_id: &ListId,
    status_labels: &[String],
) -> Result<Vec<Value>, StoreError> {
    let placeholders = lorvex_domain::sql_csv_placeholders(status_labels.len());
    let mut params = vec![SqlValue::Text(list_id.as_str().to_string())];
    for status in status_labels {
        params.push(SqlValue::Text(status.clone()));
    }
    let sql = format!(
        "SELECT id FROM tasks
         WHERE list_id = ? AND archived_at IS NULL AND status IN ({placeholders})
         ORDER BY created_at ASC, id ASC"
    );
    let mut stmt = conn.prepare_cached(&sql)?;
    let ids: Vec<TaskId> = stmt
        .query_map(params_from_iter(params.iter()), |row| {
            row.get::<_, String>(0)
        })?
        .map(|row| row.map(TaskId::from_trusted))
        .collect::<Result<Vec<_>, _>>()?;
    load_enriched_tasks_existing(conn, &ids)
}

fn task_id_from_json(task: &Value) -> Result<TaskId, StoreError> {
    task.get("id")
        .and_then(Value::as_str)
        .map(|s| TaskId::from_trusted(s.to_string()))
        .ok_or_else(|| StoreError::Invariant("batch cancel task row missing id".to_string()))
}

fn task_title(task: &Value) -> String {
    task.get("title")
        .and_then(Value::as_str)
        .unwrap_or("unknown")
        .to_string()
}

fn append_unique(target: &mut Vec<String>, seen: &mut HashSet<String>, values: &[String]) {
    for value in values {
        if seen.insert(value.clone()) {
            target.push(value.clone());
        }
    }
}

pub fn batch_cancel_tasks_in_list(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    input: BatchCancelInListInput,
) -> Result<BatchCancelInListResult, StoreError> {
    let BatchCancelInListInput {
        list_id,
        statuses,
        cancel_series,
    } = input;
    lorvex_store::validate_task_list_exists(conn, &list_id)?;

    let target_statuses =
        statuses.unwrap_or_else(|| vec![BatchCancelStatus::Open, BatchCancelStatus::Someday]);
    let target_status_labels: Vec<String> = target_statuses
        .iter()
        .map(|status| status.as_str().to_string())
        .collect();
    let before_tasks = candidate_tasks(conn, &list_id, &target_status_labels)?;

    if before_tasks.is_empty() {
        let payload = json!({
            "cancelled_count": 0,
            "cancelled": [],
            "next_occurrences": [],
            "list_id": list_id,
            "statuses": target_status_labels,
        });
        return Ok(BatchCancelInListResult {
            list_id,
            task_ids: Vec::new(),
            before_tasks,
            after_tasks: Vec::new(),
            payload,
            summary: None,
            sync_effects: BatchCancelSyncEffects::default(),
        });
    }

    if before_tasks.len() > MAX_IN_LIST_CANCEL {
        return Err(StoreError::Validation(format!(
            "batch_cancel_tasks_in_list supports at most {MAX_IN_LIST_CANCEL} matching tasks per call; \
             list '{}' has {} matching tasks. Narrow the `statuses` filter or call \
             batch_cancel_tasks with explicit ids in chunks.",
            list_id.as_str(),
            before_tasks.len()
        )));
    }

    let ids: Vec<TaskId> = before_tasks
        .iter()
        .map(task_id_from_json)
        .collect::<Result<Vec<_>, _>>()?;
    let ids_set: HashSet<&str> = ids.iter().map(TaskId::as_str).collect();
    let now = lorvex_domain::sync_timestamp_now();
    let mut sync_effects = BatchCancelSyncEffects {
        task_upsert_ids: ids.iter().map(|id| id.as_str().to_string()).collect(),
        ..BatchCancelSyncEffects::default()
    };
    let mut affected_seen = HashSet::new();
    let mut next_occurrences = Vec::new();

    for task_id in &ids {
        let before_title = before_tasks
            .iter()
            .find(|task| task.get("id").and_then(Value::as_str) == Some(task_id.as_str()))
            .map(task_title)
            .unwrap_or_else(|| "unknown".to_string());
        let result = lifecycle::effects::run_cancel(conn, task_id, &now, cancel_series, hlc)?;

        sync_effects
            .cancelled_reminder_ids
            .extend(result.cancelled_reminder_ids);
        sync_effects
            .deleted_dependency_edges
            .extend(result.deleted_dependency_edges);
        let external_affected: Vec<String> = result
            .affected_dependent_ids
            .iter()
            .filter(|dep_id| !ids_set.contains(dep_id.as_str()))
            .cloned()
            .collect();
        append_unique(
            &mut sync_effects.affected_dependent_ids,
            &mut affected_seen,
            &external_affected,
        );

        if let Some(successor_id) = result.spawned_successor_id {
            let typed_successor_id = TaskId::from_trusted(successor_id);
            let successor_task = load_enriched_task_json(conn, &typed_successor_id)?;
            let summary =
                format!("Spawned recurrence successor of '{before_title}' (skip-cancel in list)");
            sync_effects.spawned_successors.push(SpawnedSuccessorLog {
                successor_id: typed_successor_id,
                summary,
                after_task: successor_task.clone(),
            });
            next_occurrences.push(successor_task);
        }
        sync_effects
            .spawned_successor_tag_edges
            .extend(result.spawned_successor_tag_edges);
        sync_effects
            .spawned_successor_checklist_item_ids
            .extend(result.spawned_successor_checklist_item_ids);
        sync_effects
            .spawned_successor_reminder_ids
            .extend(result.spawned_successor_reminder_ids);
        sync_effects
            .rewired_focus_schedule_dates
            .extend(result.rewired_focus_schedule_dates);
        sync_effects
            .rewired_current_focus_dates
            .extend(result.rewired_current_focus_dates);
    }

    let after_tasks = load_enriched_tasks_existing(conn, &ids)?;
    let name = list_name(conn, &list_id)?;
    let summary = format!(
        "Cancelled {} task{} in {}",
        ids.len(),
        plural_s(ids.len()),
        name
    );
    let payload = json!({
        "cancelled_count": ids.len(),
        "cancelled": after_tasks,
        "next_occurrences": next_occurrences,
        "list_id": list_id,
        "statuses": target_status_labels,
    });

    Ok(BatchCancelInListResult {
        list_id,
        task_ids: ids,
        before_tasks,
        after_tasks,
        payload,
        summary: Some(summary),
        sync_effects,
    })
}

pub fn status_labels(statuses: &[BatchCancelStatus]) -> Vec<String> {
    statuses
        .iter()
        .map(|status| status.as_str().to_string())
        .collect()
}

pub fn status_side_effect_plan<'a>(
    effects: &'a BatchCancelSyncEffects,
) -> StatusSideEffectSyncPlan<'a> {
    StatusSideEffectSyncPlan {
        cancelled_reminder_ids: &effects.cancelled_reminder_ids,
        affected_dependent_ids: &effects.affected_dependent_ids,
        deleted_dependency_edges: &effects.deleted_dependency_edges,
    }
}
