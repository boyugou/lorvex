use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{EDGE_TASK_DEPENDENCY, EDGE_TASK_TAG, ENTITY_TAG};
use lorvex_domain::TaskId;
use lorvex_store::StoreError;
use rusqlite::Connection;
use serde_json::{json, Value};

use crate::lifecycle::{self, CopiedTagEdge, DeletedDependencyEdge, StatusSideEffectSyncPlan};
use crate::task_create::{self, TaskCreateInput};
use crate::task_response::load_enriched_tasks_json;

const BATCH_CREATE_TASKS_LIMIT: usize = 500;

#[derive(Debug, Clone)]
pub struct BatchCreateTasksInput {
    pub ids: Option<Vec<String>>,
    pub tasks: Vec<TaskCreateInput>,
    pub include_advice: bool,
}

#[derive(Debug, Clone)]
pub struct SpawnedSuccessorLog {
    pub successor_id: TaskId,
    pub summary: String,
    pub after_task: Value,
}

#[derive(Debug, Clone)]
pub struct FocusRewireAudit {
    pub parent_task_id: TaskId,
    pub successor_id: TaskId,
    pub focus_schedule_dates: Vec<String>,
    pub current_focus_dates: Vec<String>,
}

#[derive(Debug, Default)]
pub struct BatchCreateSyncEffects {
    pub task_upsert_ids: Vec<String>,
    pub reminder_upsert_ids: Vec<String>,
    pub cancelled_reminder_ids: Vec<String>,
    pub dependency_edge_upsert_ids: Vec<String>,
    pub tag_upsert_ids: Vec<String>,
    pub task_tag_edge_upsert_ids: Vec<String>,
    pub affected_dependent_ids: Vec<String>,
    pub deleted_dependency_edges: Vec<DeletedDependencyEdge>,
    pub spawned_successors: Vec<SpawnedSuccessorLog>,
    pub spawned_successor_tag_edges: Vec<CopiedTagEdge>,
    pub spawned_successor_checklist_item_ids: Vec<String>,
    pub spawned_successor_reminder_ids: Vec<String>,
    pub focus_rewire_audits: Vec<FocusRewireAudit>,
    pub rewired_focus_schedule_dates: Vec<String>,
    pub rewired_current_focus_dates: Vec<String>,
}

#[derive(Debug)]
pub struct BatchCreateTasksResult {
    pub created_ids: Vec<String>,
    pub created_tasks: Vec<Value>,
    pub payload: Value,
    pub summary: String,
    pub sync_effects: BatchCreateSyncEffects,
}

pub fn batch_create_tasks(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    input: BatchCreateTasksInput,
) -> Result<BatchCreateTasksResult, StoreError> {
    let BatchCreateTasksInput {
        ids,
        tasks,
        include_advice,
    } = input;
    if tasks.is_empty() {
        return Err(StoreError::Validation(
            "tasks must contain at least one item".to_string(),
        ));
    }
    if tasks.len() > BATCH_CREATE_TASKS_LIMIT {
        return Err(StoreError::Validation(format!(
            "batch_create_tasks supports at most {BATCH_CREATE_TASKS_LIMIT} items, got {}",
            tasks.len()
        )));
    }
    let ids = match ids {
        Some(ids) if ids.len() == tasks.len() => ids,
        Some(ids) => {
            return Err(StoreError::Validation(format!(
                "batch_create_tasks expected {} pre-generated ids, got {}",
                tasks.len(),
                ids.len()
            )));
        }
        None => (0..tasks.len())
            .map(|_| lorvex_domain::new_entity_id_string())
            .collect(),
    };
    let mut seen_ids = std::collections::HashSet::with_capacity(ids.len());
    for id in &ids {
        if !seen_ids.insert(id.as_str()) {
            return Err(StoreError::Validation(format!(
                "batch_create_tasks pre-generated ids must be unique; duplicate id '{id}'"
            )));
        }
    }

    let now = lorvex_domain::sync_timestamp_now();
    let mut created_ids = Vec::with_capacity(tasks.len());
    let mut prepared_tasks = Vec::with_capacity(tasks.len());
    let mut complete_ids = Vec::new();
    let mut sync_effects = BatchCreateSyncEffects::default();

    for (task, id) in tasks.into_iter().zip(ids) {
        let should_complete = task.completed.unwrap_or(false);
        let reminders = task.reminders.clone();
        let prepared = task_create::prepare_task_insert(conn, hlc, id.clone(), now.clone(), task)?;
        prepared.execute_insert(conn)?;
        let tag_effects = task_create::insert_task_tags(
            conn,
            hlc,
            &TaskId::from_trusted(id.clone()),
            &prepared.tags,
        )?;
        sync_effects
            .tag_upsert_ids
            .extend(tag_effects.tag_upsert_ids);
        sync_effects
            .task_tag_edge_upsert_ids
            .extend(tag_effects.task_tag_edge_upsert_ids);
        let reminder_ids = task_create::insert_task_reminders(conn, hlc, &id, reminders)?;
        sync_effects.reminder_upsert_ids.extend(reminder_ids);
        if should_complete {
            complete_ids.push(id.clone());
        }
        sync_effects.task_upsert_ids.push(id.clone());
        created_ids.push(id);
        prepared_tasks.push(prepared);
    }

    for (idx, prepared) in prepared_tasks.iter().enumerate() {
        let task_id = TaskId::from_trusted(created_ids[idx].clone());
        let edge_ids =
            task_create::insert_dependency_edges(conn, hlc, &task_id, &prepared.depends_on)?;
        sync_effects.dependency_edge_upsert_ids.extend(edge_ids);
    }

    let mut next_occurrences = Vec::new();
    for created_id in &complete_ids {
        let task_id = TaskId::from_trusted(created_id.clone());
        let completion = lifecycle::effects::run_completion(conn, &task_id, &now, hlc)?;
        sync_effects
            .cancelled_reminder_ids
            .extend(completion.cancelled_reminder_ids);
        if let Some(successor_id) = completion.spawned_successor_id {
            let typed_successor_id = TaskId::from_trusted(successor_id);
            sync_effects.focus_rewire_audits.push(FocusRewireAudit {
                parent_task_id: TaskId::from_trusted(created_id.clone()),
                successor_id: typed_successor_id.clone(),
                focus_schedule_dates: completion.rewired_focus_schedule_dates.clone(),
                current_focus_dates: completion.rewired_current_focus_dates.clone(),
            });
            let successor =
                crate::task_response::load_enriched_task_json(conn, &typed_successor_id)?;
            sync_effects.spawned_successors.push(SpawnedSuccessorLog {
                successor_id: typed_successor_id,
                summary: "Spawned recurrence successor from pre-completed batch create".to_string(),
                after_task: successor.clone(),
            });
            next_occurrences.push(successor);
        }
        sync_effects
            .spawned_successor_tag_edges
            .extend(completion.spawned_successor_tag_edges);
        sync_effects
            .spawned_successor_checklist_item_ids
            .extend(completion.spawned_successor_checklist_item_ids);
        sync_effects
            .spawned_successor_reminder_ids
            .extend(completion.spawned_successor_reminder_ids);
        sync_effects
            .rewired_focus_schedule_dates
            .extend(completion.rewired_focus_schedule_dates);
        sync_effects
            .rewired_current_focus_dates
            .extend(completion.rewired_current_focus_dates);
    }

    let created_tasks = load_enriched_tasks_json(conn, &created_ids)?;
    let advice = build_advice_envelopes(conn, &created_tasks, include_advice)?;
    let titles = prepared_tasks
        .iter()
        .map(|task| format!("'{}'", task.title))
        .collect::<Vec<_>>()
        .join(", ");
    let summary = format!(
        "Created {} task{}: {}",
        created_ids.len(),
        plural_s(created_ids.len()),
        titles
    );
    let payload = json!({
        "created_count": created_tasks.len(),
        "tasks": created_tasks,
        "next_occurrences": next_occurrences,
        "advice": advice,
        "undo_token": Value::Null,
    });

    Ok(BatchCreateTasksResult {
        created_ids,
        created_tasks,
        payload,
        summary,
        sync_effects,
    })
}

pub fn status_side_effect_plan<'a>(
    effects: &'a BatchCreateSyncEffects,
) -> StatusSideEffectSyncPlan<'a> {
    StatusSideEffectSyncPlan {
        cancelled_reminder_ids: &effects.cancelled_reminder_ids,
        affected_dependent_ids: &effects.affected_dependent_ids,
        deleted_dependency_edges: &effects.deleted_dependency_edges,
    }
}

pub const fn dependency_edge_entity_type() -> &'static str {
    EDGE_TASK_DEPENDENCY
}

pub const fn task_tag_edge_entity_type() -> &'static str {
    EDGE_TASK_TAG
}

pub const fn tag_entity_type() -> &'static str {
    ENTITY_TAG
}

fn build_advice_envelopes(
    conn: &Connection,
    created_tasks: &[Value],
    include_advice: bool,
) -> Result<Vec<Value>, StoreError> {
    if !include_advice {
        return Ok(Vec::new());
    }
    created_tasks
        .iter()
        .map(|task| {
            let task_id = task.get("id").and_then(Value::as_str).ok_or_else(|| {
                StoreError::Invariant(
                    "batch_create_tasks: just-inserted task is missing string `id` for advice envelope".to_string(),
                )
            })?;
            Ok(json!({
                "task_id": task_id,
                "advice": task_create::build_task_intake_advice(conn, task)?,
            }))
        })
        .collect()
}

const fn plural_s(count: usize) -> &'static str {
    if count == 1 {
        ""
    } else {
        "s"
    }
}
