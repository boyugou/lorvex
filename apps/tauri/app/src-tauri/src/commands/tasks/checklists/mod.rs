//! Task checklist subsystem — per-task `task_checklist_items` rows
//! (the structured replacement for `- [ ] ...` markdown bullets in
//! the task body) and the IPC commands that mutate them.
//!
//! #3303 P2 split — the previous 547-LOC `checklists.rs` mixed
//! every concern into a single file. The split groups the four
//! private helpers, the five `_with_conn` cores (which the test
//! suite exercises directly), and the five `#[tauri::command]`
//! wrappers into their own siblings:
//!
//!   * `helpers` — `checklist_item_from_row`, `list_items_with_conn`,
//!     `update_item_positions` (LWW-gated reorder UPDATE),
//!     `touch_parent_task_timestamp` (canonical parent
//!     `apply_task_update` patch).
//!   * `crud` — `add_*`, `update_*`, `set_*`, `remove_*`,
//!     `reorder_*_with_conn` cores. All `pub(crate)` because the
//!     wider test suite (`commands::tests::task_commands`) imports
//!     them directly.
//!   * `mod.rs` (this file) — the five Tauri command entry points
//!     (validate UUIDv7 ids, take the writer mutex, and delegate
//!     to the matching `_with_conn` core).

mod crud;
mod helpers;

pub(crate) use crud::{
    add_task_checklist_item_with_conn, remove_task_checklist_item_with_conn,
    reorder_task_checklist_items_with_conn, set_task_checklist_item_completed_with_conn,
    update_task_checklist_item_text_with_conn,
};

use rusqlite::{params, OptionalExtension};

use crate::commands::{sync_timestamp_now, with_immediate_transaction, TaskChecklistItem};
use crate::db::get_conn;
use crate::error::{AppError, AppResult};
use crate::event_bus;

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn add_task_checklist_item(task_id: String, text: String) -> Result<TaskChecklistItem, String> {
    // task ids are UUIDv7 — shape-check at the IPC
    // boundary so the FK-bound checklist writer never sees a
    // malformed parent id.
    let task_id_str = crate::commands::shared::validate_uuid_id(&task_id, "task_id")?;
    let task_id = lorvex_domain::TaskId::from_trusted(task_id_str);
    let result = (|| -> AppResult<TaskChecklistItem> {
        let conn = get_conn()?;
        let now = sync_timestamp_now();
        with_immediate_transaction(&conn, |conn| {
            add_task_checklist_item_with_conn(conn, &task_id, &text, None, &now)
        })
    })();

    result
        .inspect(|_| {
            event_bus::emit_data_changed(event_bus::Entity::Task);
        })
        .map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn update_task_checklist_item_text(
    task_id: String,
    item_id: String,
    text: String,
) -> Result<TaskChecklistItem, String> {
    // shape-check both UUIDv7 ids at the IPC boundary.
    let task_id = crate::commands::shared::validate_uuid_id(&task_id, "task_id")?;
    let item_id = crate::commands::shared::validate_uuid_id(&item_id, "item_id")?;
    let result = (|| -> AppResult<TaskChecklistItem> {
        let conn = get_conn()?;
        let now = sync_timestamp_now();
        with_immediate_transaction(&conn, |conn| {
            let current = conn
                .query_row(
                    "SELECT task_id FROM task_checklist_items WHERE id = ?1",
                    params![item_id],
                    |row| row.get::<_, String>(0),
                )
                .optional()?
                .ok_or_else(|| {
                    AppError::NotFound(format!("Checklist item not found: {item_id}"))
                })?;
            if current != task_id {
                return Err(AppError::Validation(format!(
                    "Checklist item {item_id} does not belong to task {task_id}"
                )));
            }
            update_task_checklist_item_text_with_conn(conn, &item_id, &text, &now)
        })
    })();

    result
        .inspect(|_| {
            event_bus::emit_data_changed(event_bus::Entity::Task);
        })
        .map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn set_task_checklist_item_completed(
    task_id: String,
    item_id: String,
    completed: bool,
) -> Result<TaskChecklistItem, String> {
    // shape-check both UUIDv7 ids at the IPC boundary.
    let task_id = crate::commands::shared::validate_uuid_id(&task_id, "task_id")?;
    let item_id = crate::commands::shared::validate_uuid_id(&item_id, "item_id")?;
    let result = (|| -> AppResult<TaskChecklistItem> {
        let conn = get_conn()?;
        let now = sync_timestamp_now();
        with_immediate_transaction(&conn, |conn| {
            let existing_task_id: String = conn
                .query_row(
                    "SELECT task_id FROM task_checklist_items WHERE id = ?1",
                    params![item_id],
                    |row| row.get(0),
                )
                .optional()?
                .ok_or_else(|| {
                    AppError::NotFound(format!("Checklist item not found: {item_id}"))
                })?;
            if existing_task_id != task_id {
                return Err(AppError::Validation(format!(
                    "Checklist item {item_id} does not belong to task {task_id}"
                )));
            }
            set_task_checklist_item_completed_with_conn(conn, &item_id, completed, &now)
        })
    })();

    result
        .inspect(|_| {
            event_bus::emit_data_changed(event_bus::Entity::Task);
        })
        .map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn remove_task_checklist_item(task_id: String, item_id: String) -> Result<(), String> {
    // shape-check both UUIDv7 ids at the IPC boundary
    // before the destructive writer.
    let task_id = crate::commands::shared::validate_uuid_id(&task_id, "task_id")?;
    let item_id = crate::commands::shared::validate_uuid_id(&item_id, "item_id")?;
    let result = (|| -> AppResult<()> {
        let conn = get_conn()?;
        let now = sync_timestamp_now();
        with_immediate_transaction(&conn, |conn| {
            let existing_task_id: String = conn
                .query_row(
                    "SELECT task_id FROM task_checklist_items WHERE id = ?1",
                    params![item_id],
                    |row| row.get(0),
                )
                .optional()?
                .ok_or_else(|| {
                    AppError::NotFound(format!("Checklist item not found: {item_id}"))
                })?;
            if existing_task_id != task_id {
                return Err(AppError::Validation(format!(
                    "Checklist item {item_id} does not belong to task {task_id}"
                )));
            }
            remove_task_checklist_item_with_conn(conn, &item_id, &now)
        })
    })();

    result
        .map(|_| {
            event_bus::emit_data_changed(event_bus::Entity::Task);
        })
        .map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn reorder_task_checklist_items(
    task_id: String,
    item_ids: Vec<String>,
) -> Result<Vec<TaskChecklistItem>, String> {
    // cap the input batch at the IPC boundary BEFORE
    // touching the per-row UUID validator so a runaway caller can't
    // pin the validator on millions of strings. The legitimate UI
    // shape is one task's checklist items (tens at most).
    //
    // also reject the empty-Vec case. Reordering
    // zero items is a no-op write transaction — accept it from the
    // IPC layer and we still open a writer, generate a version,
    // touch updated_at, and ship a sync envelope for nothing. The
    // legitimate "the user has no checklist items" path never
    // invokes this command at all.
    if item_ids.is_empty() {
        return Err("item_ids must not be empty".to_string());
    }
    if item_ids.len() > crate::commands::shared::MAX_IPC_BATCH_ITEMS {
        return Err(format!(
            "item_ids count {} exceeds maximum {}",
            item_ids.len(),
            crate::commands::shared::MAX_IPC_BATCH_ITEMS
        ));
    }
    // shape-check the parent UUID and every child item
    // UUID at the IPC boundary so the reorder writer never sees a
    // malformed id in the position-rewrite loop.
    let task_id_str = crate::commands::shared::validate_uuid_id(&task_id, "task_id")?;
    let task_id = lorvex_domain::TaskId::from_trusted(task_id_str);
    let item_ids = item_ids
        .iter()
        .map(|raw| crate::commands::shared::validate_uuid_id(raw, "item_id"))
        .collect::<Result<Vec<_>, _>>()?;
    let result = (|| -> AppResult<Vec<TaskChecklistItem>> {
        let conn = get_conn()?;
        let now = sync_timestamp_now();
        with_immediate_transaction(&conn, |conn| {
            reorder_task_checklist_items_with_conn(conn, &task_id, item_ids, &now)
        })
    })();

    result
        .inspect(|_| {
            event_bus::emit_data_changed(event_bus::Entity::Task);
        })
        .map_err(String::from)
}
