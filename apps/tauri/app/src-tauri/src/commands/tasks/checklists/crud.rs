//! Testable `_with_conn` cores for every checklist mutation. Each
//! routes through the helpers in `super::helpers` and the
//! envelope-emitting plumbing on `crate::commands` so the public
//! Tauri handlers in `super` stay tiny.

use rusqlite::{params, OptionalExtension};

use lorvex_domain::checklist::{
    validate_task_checklist_item_count, validate_task_checklist_item_text,
};
use lorvex_domain::TaskId;

use super::helpers::{
    checklist_item_from_row, list_items_with_conn, touch_parent_task_timestamp,
    update_item_positions,
};
use crate::commands::{
    enqueue_task_checklist_item_delete, enqueue_task_checklist_item_upsert, fetch_task_by_id,
    TaskChecklistItem,
};
use crate::error::{AppError, AppResult};

pub(crate) fn add_task_checklist_item_with_conn(
    conn: &rusqlite::Connection,
    task_id: &TaskId,
    text: &str,
    position: Option<i64>,
    now: &str,
) -> AppResult<TaskChecklistItem> {
    fetch_task_by_id(conn, task_id.as_str()).map(|_| ())?;
    // Scrub Unicode hygiene before length validation and storage so
    // checklist item text walks the same `sanitize_user_text` boundary
    // as the task title/body/ai_notes paths. Without this, a
    // bidi-override or ZWSP-laden checklist item would render
    // differently to the UI vs. the model exposing the same task
    // through MCP.
    let text = lorvex_domain::sanitize_user_text(text);
    let text = text.trim();
    validate_task_checklist_item_text(text)
        .map_err(|error| AppError::Validation(error.to_string()))?;

    let mut items = list_items_with_conn(conn, task_id)?;
    validate_task_checklist_item_count(items.len() + 1)
        .map_err(|error| AppError::Validation(error.to_string()))?;

    // Reject negative `position` explicitly so a caller-side
    // programming bug surfaces as a validation error rather than a
    // silent rewrite. An `as usize` cast would wrap negative inputs
    // to `usize::MAX`; the subsequent `.min(items.len())` clamp
    // would then mask the wrap as "append." `None` means "append"
    // by spec.
    let target = match position {
        Some(pos) => {
            if pos < 0 {
                return Err(AppError::Validation(format!(
                    "checklist position must be >= 0, got {pos}"
                )));
            }
            (pos as usize).min(items.len())
        }
        None => items.len(),
    };

    let id = lorvex_domain::new_entity_id_string();
    let version = crate::hlc::generate_version_result()?;
    conn.prepare_cached(
        "INSERT INTO task_checklist_items (
            id, task_id, position, text, completed_at, version, created_at, updated_at
         ) VALUES (?1, ?2, ?3, ?4, NULL, ?5, ?6, ?6)",
    )?
    .execute(params![
        id,
        task_id.as_str(),
        target as i64,
        text,
        version,
        now
    ])?;

    items.insert(
        target,
        TaskChecklistItem {
            id: id.clone(),
            task_id: task_id.as_str().to_string(),
            position: target as i64,
            text: text.to_string(),
            completed_at: None,
            version,
            created_at: now.to_string(),
            updated_at: now.to_string(),
        },
    );
    // Emit the new-row upsert envelope explicitly BEFORE running
    // `update_item_positions` so the envelope cannot ride on a side
    // effect of the position helper's per-item enqueue — a future
    // refactor that early-returns from the position helper for an
    // unchanged ordering would otherwise silently skip the new row's
    // envelope. Sibling helpers (e.g.
    // `update_task_checklist_item_text_with_conn` below) call the
    // upsert helper directly; matching that contract here makes the
    // position helper's coalesced re-enqueue harmless duplication
    // rather than load-bearing.
    enqueue_task_checklist_item_upsert(conn, &id)?;
    let ordered_ids: Vec<String> = items.into_iter().map(|item| item.id).collect();
    update_item_positions(conn, task_id, &ordered_ids, now)?;
    touch_parent_task_timestamp(conn, task_id, now)?;

    conn.prepare_cached(
        "SELECT id, task_id, position, text, completed_at, version, created_at, updated_at
         FROM task_checklist_items WHERE id = ?1",
    )?
    .query_row(params![id], checklist_item_from_row)
    .map_err(Into::into)
}

pub(crate) fn update_task_checklist_item_text_with_conn(
    conn: &rusqlite::Connection,
    item_id: &str,
    text: &str,
    now: &str,
) -> AppResult<TaskChecklistItem> {
    let current = conn
        .query_row(
            "SELECT id, task_id, position, text, completed_at, version, created_at, updated_at
             FROM task_checklist_items WHERE id = ?1",
            params![item_id],
            checklist_item_from_row,
        )
        .optional()?
        .ok_or_else(|| AppError::NotFound(format!("Checklist item not found: {item_id}")))?;

    // same Unicode-hygiene scrub as the create path
    // so update can never reintroduce bidi/ZWSP that the create path
    // strips. Without this, an update renames an item to a hostile
    // string the create wouldn't have accepted.
    let text = lorvex_domain::sanitize_user_text(text);
    let text = text.trim();
    validate_task_checklist_item_text(text)
        .map_err(|error| AppError::Validation(error.to_string()))?;
    let next_version = crate::hlc::generate_version_result()?;
    conn.prepare_cached(
        "UPDATE task_checklist_items
         SET text = ?2, updated_at = ?3, version = ?4
         WHERE id = ?1",
    )?
    .execute(params![item_id, text, now, next_version])?;
    enqueue_task_checklist_item_upsert(conn, item_id)?;
    touch_parent_task_timestamp(conn, &TaskId::from_trusted(current.task_id), now)?;

    conn.prepare_cached(
        "SELECT id, task_id, position, text, completed_at, version, created_at, updated_at
         FROM task_checklist_items WHERE id = ?1",
    )?
    .query_row(params![item_id], checklist_item_from_row)
    .map_err(Into::into)
}

pub(crate) fn set_task_checklist_item_completed_with_conn(
    conn: &rusqlite::Connection,
    item_id: &str,
    completed: bool,
    now: &str,
) -> AppResult<TaskChecklistItem> {
    let existing_task_id: String = conn
        .query_row(
            "SELECT task_id FROM task_checklist_items WHERE id = ?1",
            params![item_id],
            |row| row.get(0),
        )
        .optional()?
        .ok_or_else(|| AppError::NotFound(format!("Checklist item not found: {item_id}")))?;

    let completed_at = if completed {
        Some(now.to_string())
    } else {
        None
    };
    let version = crate::hlc::generate_version_result()?;
    conn.prepare_cached(
        "UPDATE task_checklist_items
         SET completed_at = ?2, updated_at = ?3, version = ?4
         WHERE id = ?1",
    )?
    .execute(params![item_id, completed_at, now, version])?;
    enqueue_task_checklist_item_upsert(conn, item_id)?;
    touch_parent_task_timestamp(conn, &TaskId::from_trusted(existing_task_id), now)?;

    conn.prepare_cached(
        "SELECT id, task_id, position, text, completed_at, version, created_at, updated_at
         FROM task_checklist_items WHERE id = ?1",
    )?
    .query_row(params![item_id], checklist_item_from_row)
    .map_err(Into::into)
}

pub(crate) fn remove_task_checklist_item_with_conn(
    conn: &rusqlite::Connection,
    item_id: &str,
    now: &str,
) -> AppResult<()> {
    let existing_task_id: String = conn
        .query_row(
            "SELECT task_id FROM task_checklist_items WHERE id = ?1",
            params![item_id],
            |row| row.get(0),
        )
        .optional()?
        .ok_or_else(|| AppError::NotFound(format!("Checklist item not found: {item_id}")))?;

    // snapshot the row BEFORE the DELETE so the typed
    // `DeleteEnvelope` carries the full checklist item state.
    let snapshot = crate::commands::load_task_checklist_item_pre_delete_snapshot(conn, item_id)?;
    conn.prepare_cached("DELETE FROM task_checklist_items WHERE id = ?1")?
        .execute(params![item_id])?;
    enqueue_task_checklist_item_delete(
        conn,
        crate::commands::DeleteEnvelope::new(item_id, snapshot),
    )?;

    let parent_task_id = TaskId::from_trusted(existing_task_id);
    let remaining = list_items_with_conn(conn, &parent_task_id)?;
    let ordered_ids: Vec<String> = remaining.into_iter().map(|item| item.id).collect();
    update_item_positions(conn, &parent_task_id, &ordered_ids, now)?;
    touch_parent_task_timestamp(conn, &parent_task_id, now)?;

    Ok(())
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
pub(crate) fn reorder_task_checklist_items_with_conn(
    conn: &rusqlite::Connection,
    task_id: &TaskId,
    item_ids: Vec<String>,
    now: &str,
) -> AppResult<Vec<TaskChecklistItem>> {
    fetch_task_by_id(conn, task_id.as_str()).map(|_| ())?;
    let existing = list_items_with_conn(conn, task_id)?;
    let existing_ids: Vec<String> = existing.iter().map(|item| item.id.clone()).collect();
    if existing_ids.len() != item_ids.len() || existing_ids.iter().any(|id| !item_ids.contains(id))
    {
        return Err(AppError::Validation(format!(
            "Checklist reorder for task {task_id} must include exactly the existing item ids"
        )));
    }

    update_item_positions(conn, task_id, &item_ids, now)?;
    touch_parent_task_timestamp(conn, task_id, now)?;

    list_items_with_conn(conn, task_id)
}
