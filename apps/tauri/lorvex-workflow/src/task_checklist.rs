use std::collections::HashSet;

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, OP_DELETE, OP_UPSERT};
use lorvex_domain::{
    validate_task_checklist_item_count, validate_task_checklist_item_text, ChecklistItemId, TaskId,
};
use lorvex_store::payload_loaders::load_task_checklist_item_sync_payload;
use lorvex_store::StoreError;
use rusqlite::{params, Connection};
use serde_json::Value;

use crate::task_response::{load_enriched_task_json, task_title};

#[derive(Debug, Clone)]
pub struct AddTaskChecklistItemInput {
    pub task_id: TaskId,
    pub text: String,
    pub position: Option<u32>,
}

#[derive(Debug, Clone)]
pub struct UpdateTaskChecklistItemInput {
    pub item_id: ChecklistItemId,
    pub text: String,
}

#[derive(Debug, Clone)]
pub struct ToggleTaskChecklistItemInput {
    pub item_id: ChecklistItemId,
    pub completed: bool,
}

#[derive(Debug, Clone)]
pub struct RemoveTaskChecklistItemInput {
    pub item_id: ChecklistItemId,
}

#[derive(Debug, Clone)]
pub struct ReorderTaskChecklistItemsInput {
    pub task_id: TaskId,
    pub item_ids: Vec<ChecklistItemId>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ChecklistSyncOperation {
    Upsert,
    Delete,
}

impl ChecklistSyncOperation {
    #[must_use]
    pub const fn as_str(&self) -> &'static str {
        match self {
            Self::Upsert => OP_UPSERT,
            Self::Delete => OP_DELETE,
        }
    }
}

#[derive(Debug, Clone)]
pub struct ChecklistItemSyncChange {
    pub item_id: String,
    pub operation: ChecklistSyncOperation,
    pub snapshot: Option<Value>,
}

#[derive(Debug, Clone)]
pub struct TaskChecklistMutationResult {
    pub task_id: String,
    pub before_task: Value,
    pub after_task: Value,
    pub summary: String,
    pub item_sync_changes: Vec<ChecklistItemSyncChange>,
}

fn fetch_checklist_item_identity(
    conn: &Connection,
    item_id: &ChecklistItemId,
) -> Result<(TaskId, String, i64, bool), StoreError> {
    conn.prepare_cached(
        "SELECT task_id, text, position, completed_at IS NOT NULL
         FROM task_checklist_items WHERE id = ?1",
    )?
    .query_row(params![item_id], |row| {
        let task_id: String = row.get(0)?;
        Ok((
            TaskId::from_trusted(task_id),
            row.get(1)?,
            row.get(2)?,
            row.get(3)?,
        ))
    })
    .map_err(|error| match error {
        rusqlite::Error::QueryReturnedNoRows => StoreError::NotFound {
            entity: "checklist item",
            id: item_id.to_string(),
        },
        other => StoreError::from(other),
    })
}

fn fetch_checklist_ids_for_task(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<Vec<ChecklistItemId>, StoreError> {
    let mut stmt = conn.prepare_cached(
        "SELECT id
         FROM task_checklist_items
         WHERE task_id = ?1
         ORDER BY position ASC, created_at ASC, id ASC",
    )?;
    let ids = stmt
        .query_map(params![task_id], |row| {
            let id: String = row.get(0)?;
            Ok(ChecklistItemId::from_trusted(id))
        })?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(ids)
}

fn touch_task_lww(
    conn: &Connection,
    task_id: &TaskId,
    version: &str,
    now: &str,
) -> Result<(), StoreError> {
    match conn
        .prepare_cached(
            "UPDATE tasks
         SET version = ?1, updated_at = ?2
         WHERE id = ?3 AND ?1 > version
         RETURNING 1",
        )?
        .query_row(params![version, now, task_id], |_row| Ok(()))
    {
        Ok(()) => Ok(()),
        Err(rusqlite::Error::QueryReturnedNoRows) => Err(StoreError::StaleVersion {
            entity: ENTITY_TASK,
            id: task_id.to_string(),
        }),
        Err(error) => Err(StoreError::from(error)),
    }
}

fn item_upsert_change(item_id: &ChecklistItemId) -> ChecklistItemSyncChange {
    ChecklistItemSyncChange {
        item_id: item_id.to_string(),
        operation: ChecklistSyncOperation::Upsert,
        snapshot: None,
    }
}

pub fn add_task_checklist_item(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    input: AddTaskChecklistItemInput,
) -> Result<TaskChecklistMutationResult, StoreError> {
    let AddTaskChecklistItemInput {
        task_id,
        text,
        position,
    } = input;
    let text = lorvex_domain::sanitize_user_text(&text);
    validate_task_checklist_item_text(&text)?;

    let before = load_enriched_task_json(conn, &task_id)?;
    let title = task_title(&before).to_string();
    let existing_ids = fetch_checklist_ids_for_task(conn, &task_id)?;
    validate_task_checklist_item_count(existing_ids.len() + 1)?;

    let insert_index = position.map_or(existing_ids.len(), |value| value as usize);
    if insert_index > existing_ids.len() {
        return Err(StoreError::Validation(format!(
            "checklist insert position {insert_index} is out of range for task '{task_id}' with {} items",
            existing_ids.len()
        )));
    }

    let now = lorvex_domain::sync_timestamp_now();
    let item_id = ChecklistItemId::new();
    let mut ordered_ids = existing_ids;
    ordered_ids.insert(insert_index, item_id.clone());

    let parent_version = hlc.next_version_string();
    touch_task_lww(conn, &task_id, &parent_version, &now)?;

    let mut update_stmt = conn.prepare_cached(
        "UPDATE task_checklist_items
         SET position = ?1, version = ?2, updated_at = ?3
         WHERE id = ?4",
    )?;
    let mut insert_stmt = conn.prepare_cached(
        "INSERT INTO task_checklist_items (
            id, task_id, position, text, completed_at, version, created_at, updated_at
         ) VALUES (?1, ?2, ?3, ?4, NULL, ?5, ?6, ?6)",
    )?;

    for (index, existing_item_id) in ordered_ids.iter().enumerate() {
        let version = hlc.next_version_string();
        if existing_item_id == &item_id {
            insert_stmt.execute(params![item_id, task_id, index as i64, text, version, now])?;
        } else {
            update_stmt.execute(params![index as i64, version, now, existing_item_id])?;
        }
    }

    let after = load_enriched_task_json(conn, &task_id)?;
    let changed = ordered_ids.iter().map(item_upsert_change).collect();

    Ok(TaskChecklistMutationResult {
        task_id: task_id.to_string(),
        before_task: before,
        after_task: after,
        summary: format!("Added checklist item '{text}' for '{title}'"),
        item_sync_changes: changed,
    })
}

pub fn update_task_checklist_item(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    input: UpdateTaskChecklistItemInput,
) -> Result<TaskChecklistMutationResult, StoreError> {
    let UpdateTaskChecklistItemInput { item_id, text } = input;
    let text = lorvex_domain::sanitize_user_text(&text);
    validate_task_checklist_item_text(&text)?;

    let (task_id, previous_text, _position, _completed) =
        fetch_checklist_item_identity(conn, &item_id)?;
    let before = load_enriched_task_json(conn, &task_id)?;
    let title = task_title(&before).to_string();
    let now = lorvex_domain::sync_timestamp_now();
    let parent_version = hlc.next_version_string();
    touch_task_lww(conn, &task_id, &parent_version, &now)?;
    let version = hlc.next_version_string();

    conn.prepare_cached(
        "UPDATE task_checklist_items
         SET text = ?1, version = ?2, updated_at = ?3
         WHERE id = ?4",
    )?
    .execute(params![text, version, now, item_id])?;

    let after = load_enriched_task_json(conn, &task_id)?;
    Ok(TaskChecklistMutationResult {
        task_id: task_id.to_string(),
        before_task: before,
        after_task: after,
        summary: format!("Updated checklist item '{previous_text}' for '{title}'"),
        item_sync_changes: vec![item_upsert_change(&item_id)],
    })
}

pub fn toggle_task_checklist_item(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    input: ToggleTaskChecklistItemInput,
) -> Result<TaskChecklistMutationResult, StoreError> {
    let ToggleTaskChecklistItemInput { item_id, completed } = input;
    let (task_id, text, _position, _was_completed) = fetch_checklist_item_identity(conn, &item_id)?;
    let before = load_enriched_task_json(conn, &task_id)?;
    let title = task_title(&before).to_string();
    let now = lorvex_domain::sync_timestamp_now();
    let parent_version = hlc.next_version_string();
    touch_task_lww(conn, &task_id, &parent_version, &now)?;
    let version = hlc.next_version_string();
    let completed_at = completed.then(|| now.clone());

    conn.prepare_cached(
        "UPDATE task_checklist_items
         SET completed_at = ?1, version = ?2, updated_at = ?3
         WHERE id = ?4",
    )?
    .execute(params![completed_at, version, now, item_id])?;

    let action = if completed { "Completed" } else { "Reopened" };
    let after = load_enriched_task_json(conn, &task_id)?;
    Ok(TaskChecklistMutationResult {
        task_id: task_id.to_string(),
        before_task: before,
        after_task: after,
        summary: format!("{action} checklist item '{text}' for '{title}'"),
        item_sync_changes: vec![item_upsert_change(&item_id)],
    })
}

pub fn remove_task_checklist_item(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    input: RemoveTaskChecklistItemInput,
) -> Result<TaskChecklistMutationResult, StoreError> {
    let RemoveTaskChecklistItemInput { item_id } = input;
    let (task_id, text, _position, _completed) = fetch_checklist_item_identity(conn, &item_id)?;
    let deleted_snapshot = load_task_checklist_item_sync_payload(conn, &item_id)?;
    let before = load_enriched_task_json(conn, &task_id)?;
    let title = task_title(&before).to_string();
    let now = lorvex_domain::sync_timestamp_now();
    let parent_version = hlc.next_version_string();
    touch_task_lww(conn, &task_id, &parent_version, &now)?;

    conn.prepare_cached("DELETE FROM task_checklist_items WHERE id = ?1")?
        .execute(params![item_id])?;

    let remaining_ids = fetch_checklist_ids_for_task(conn, &task_id)?;
    let mut update_stmt = conn.prepare_cached(
        "UPDATE task_checklist_items
         SET position = ?1, version = ?2, updated_at = ?3
         WHERE id = ?4",
    )?;
    for (index, remaining_item_id) in remaining_ids.iter().enumerate() {
        let version = hlc.next_version_string();
        update_stmt.execute(params![index as i64, version, now, remaining_item_id])?;
    }

    let after = load_enriched_task_json(conn, &task_id)?;
    let mut item_sync_changes = Vec::with_capacity(remaining_ids.len() + 1);
    item_sync_changes.push(ChecklistItemSyncChange {
        item_id: item_id.to_string(),
        operation: ChecklistSyncOperation::Delete,
        snapshot: deleted_snapshot,
    });
    item_sync_changes.extend(remaining_ids.iter().map(item_upsert_change));

    Ok(TaskChecklistMutationResult {
        task_id: task_id.to_string(),
        before_task: before,
        after_task: after,
        summary: format!("Removed checklist item '{text}' for '{title}'"),
        item_sync_changes,
    })
}

pub fn reorder_task_checklist_items(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    input: ReorderTaskChecklistItemsInput,
) -> Result<TaskChecklistMutationResult, StoreError> {
    let ReorderTaskChecklistItemsInput { task_id, item_ids } = input;
    let before = load_enriched_task_json(conn, &task_id)?;
    let title = task_title(&before).to_string();
    let existing_ids = fetch_checklist_ids_for_task(conn, &task_id)?;

    if item_ids.len() != existing_ids.len() {
        return Err(StoreError::Validation(format!(
            "reorder_task_checklist_items requires exactly {} ids for task '{task_id}', got {}",
            existing_ids.len(),
            item_ids.len()
        )));
    }

    let existing_set: HashSet<&str> = existing_ids.iter().map(ChecklistItemId::as_str).collect();
    let requested_set: HashSet<&str> = item_ids.iter().map(ChecklistItemId::as_str).collect();
    if existing_set != requested_set || requested_set.len() != item_ids.len() {
        return Err(StoreError::Validation(format!(
            "reorder_task_checklist_items must contain every checklist item for task '{task_id}' exactly once"
        )));
    }

    let now = lorvex_domain::sync_timestamp_now();
    let parent_version = hlc.next_version_string();
    touch_task_lww(conn, &task_id, &parent_version, &now)?;
    let mut update_stmt = conn.prepare_cached(
        "UPDATE task_checklist_items
         SET position = ?1, version = ?2, updated_at = ?3
         WHERE id = ?4 AND task_id = ?5",
    )?;
    for (index, item_id) in item_ids.iter().enumerate() {
        let version = hlc.next_version_string();
        update_stmt.execute(params![index as i64, version, now, item_id, task_id])?;
    }

    let after = load_enriched_task_json(conn, &task_id)?;
    let item_sync_changes = item_ids.iter().map(item_upsert_change).collect();

    Ok(TaskChecklistMutationResult {
        task_id: task_id.to_string(),
        before_task: before,
        after_task: after,
        summary: format!("Reordered checklist items for '{title}'"),
        item_sync_changes,
    })
}
