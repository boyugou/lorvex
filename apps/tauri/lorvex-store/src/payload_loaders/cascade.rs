use lorvex_domain::{EventId, HabitId, TaskId};
use rusqlite::{params, Connection};
use serde_json::Value;

use crate::error::StoreError;

use super::habit_completion::{habit_completion_payload_from_row, HABIT_COMPLETION_SELECT_COLUMNS};
use super::habit_reminder_policy::{
    habit_reminder_policy_payload_from_row, HABIT_REMINDER_POLICY_SELECT_COLUMNS,
};
use super::task_calendar_event_link::{
    task_calendar_event_link_payload_from_row, TASK_CALENDAR_EVENT_LINK_SELECT_COLUMNS,
};
use super::task_checklist_item::{
    task_checklist_item_payload_from_row, TASK_CHECKLIST_ITEM_SELECT_COLUMNS,
};
use super::task_dependency::{task_dependency_payload_from_row, TASK_DEPENDENCY_SELECT_COLUMNS};
use super::task_reminder::{task_reminder_payload_from_row, TASK_REMINDER_SELECT_COLUMNS};
use super::task_tag::{task_tag_payload_from_row, TASK_TAG_SELECT_COLUMNS};

// ---------------------------------------------------------------------------
// Batch pre-delete snapshot loaders
// ---------------------------------------------------------------------------
//
// Cascade-delete paths (task permanent-delete, list shelve, etc.) need
// the pre-delete payload for every child row before the SQLite
// FK CASCADE drops them, so the typed `DeleteEnvelope` carries the
// full row state instead of `{id}`. The pre-delete N+1 fix from
// `ba86b91e1` introduced 4 batch helpers in `app/src-tauri` that
// each issue one `WHERE id IN (?, ?, …)` scan and return a
// `HashMap<id, payload>`. They lived next to the runtime per-row
// helpers — but the column-list / row-mapper drift contract of this
// module pulls them down too: a future column addition lands in the
// `<entity>_SELECT_COLUMNS` constant + `<entity>_payload_from_row`
// mapper, and the batch loaders below pick up the change for free.
//
// The Tauri-side cascade callers re-export these via thin wrappers
// that translate `StoreError` into `AppError`. Every batch loader
// routes through `params_from_iter` uniformly so the two
// `child_items` loaders and the two `edge_snapshots` loaders share
// one canonical param-binding style.

/// Batch sibling of [`super::task_reminder::load_task_reminder_sync_payload`]: load
/// pre-delete snapshots for many `task_reminders` rows in one
/// indexed scan. Returns a `HashMap<id, payload>`; ids absent from
/// the table are absent from the map.
pub fn load_task_reminder_pre_delete_snapshots(
    conn: &Connection,
    reminder_ids: &[String],
) -> Result<std::collections::HashMap<String, Value>, StoreError> {
    let mut out = std::collections::HashMap::with_capacity(reminder_ids.len());
    if reminder_ids.is_empty() {
        return Ok(out);
    }
    let placeholders = lorvex_domain::sql_csv_placeholders(reminder_ids.len());
    let sql = format!(
        "SELECT {TASK_REMINDER_SELECT_COLUMNS} FROM task_reminders \
         WHERE id IN ({placeholders})"
    );
    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt.query_map(rusqlite::params_from_iter(reminder_ids.iter()), |row| {
        let id: String = row.get(0)?;
        Ok((id, task_reminder_payload_from_row(row)?))
    })?;
    for row in rows {
        let (id, payload) = row?;
        out.insert(id, payload);
    }
    Ok(out)
}

/// Batch sibling of [`super::task_checklist_item::load_task_checklist_item_sync_payload`].
pub fn load_task_checklist_item_pre_delete_snapshots(
    conn: &Connection,
    item_ids: &[String],
) -> Result<std::collections::HashMap<String, Value>, StoreError> {
    let mut out = std::collections::HashMap::with_capacity(item_ids.len());
    if item_ids.is_empty() {
        return Ok(out);
    }
    let placeholders = lorvex_domain::sql_csv_placeholders(item_ids.len());
    let sql = format!(
        "SELECT {TASK_CHECKLIST_ITEM_SELECT_COLUMNS} FROM task_checklist_items \
         WHERE id IN ({placeholders})"
    );
    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt.query_map(rusqlite::params_from_iter(item_ids.iter()), |row| {
        let id: String = row.get(0)?;
        Ok((id, task_checklist_item_payload_from_row(row)?))
    })?;
    for row in rows {
        let (id, payload) = row?;
        out.insert(id, payload);
    }
    Ok(out)
}

/// Batch sibling of [`super::task_tag::load_task_tag_sync_payload`]. Composite-key
/// edge — the result is keyed on `tag_id` within the fixed
/// `task_id` scope so the cascade caller can `.get(&tag_id)` per
/// tag without re-stringifying the composite key.
pub fn load_task_tag_pre_delete_snapshots(
    conn: &Connection,
    task_id: &TaskId,
    tag_ids: &[String],
) -> Result<std::collections::HashMap<String, Value>, StoreError> {
    let mut out = std::collections::HashMap::with_capacity(tag_ids.len());
    if tag_ids.is_empty() {
        return Ok(out);
    }
    let placeholders = lorvex_domain::sql_csv_placeholders(tag_ids.len());
    let sql = format!(
        "SELECT {TASK_TAG_SELECT_COLUMNS} FROM task_tags \
         WHERE task_id = ?1 AND tag_id IN ({placeholders})"
    );
    // Bind via &str references through `params_from_iter` so neither
    // `task_id` nor any element of `tag_ids` is cloned for the SQL
    // call — `&str: ToSql` makes the borrow path work without
    // sacrificing the unified binding shape.
    let params_iter = std::iter::once(task_id.as_str()).chain(tag_ids.iter().map(String::as_str));
    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt.query_map(rusqlite::params_from_iter(params_iter), |row| {
        // Column 1 is `tag_id` per `TASK_TAG_SELECT_COLUMNS` order.
        let tag_id: String = row.get(1)?;
        Ok((tag_id, task_tag_payload_from_row(row)?))
    })?;
    for row in rows {
        let (tag_id, payload) = row?;
        out.insert(tag_id, payload);
    }
    Ok(out)
}

/// Batch sibling of [`super::task_calendar_event_link::load_task_calendar_event_link_sync_payload`].
/// Composite-key edge — keyed on `calendar_event_id` within the
/// fixed `task_id` scope.
pub fn load_task_calendar_event_link_pre_delete_snapshots(
    conn: &Connection,
    task_id: &TaskId,
    calendar_event_ids: &[String],
) -> Result<std::collections::HashMap<String, Value>, StoreError> {
    let mut out = std::collections::HashMap::with_capacity(calendar_event_ids.len());
    if calendar_event_ids.is_empty() {
        return Ok(out);
    }
    let placeholders = lorvex_domain::sql_csv_placeholders(calendar_event_ids.len());
    let sql = format!(
        "SELECT {TASK_CALENDAR_EVENT_LINK_SELECT_COLUMNS} FROM task_calendar_event_links \
         WHERE task_id = ?1 AND calendar_event_id IN ({placeholders})"
    );
    let params_iter =
        std::iter::once(task_id.as_str()).chain(calendar_event_ids.iter().map(String::as_str));
    let mut stmt = conn.prepare(&sql)?;
    let rows = stmt.query_map(rusqlite::params_from_iter(params_iter), |row| {
        // Column 1 is `calendar_event_id` per
        // `TASK_CALENDAR_EVENT_LINK_SELECT_COLUMNS` order.
        let event_id: String = row.get(1)?;
        Ok((event_id, task_calendar_event_link_payload_from_row(row)?))
    })?;
    for row in rows {
        let (event_id, payload) = row?;
        out.insert(event_id, payload);
    }
    Ok(out)
}

// ---------------------------------------------------------------------------
// Per-task cascade scanners
// ---------------------------------------------------------------------------
//
// Each scanner walks the rows for one parent `task_id` and returns
// `Vec<(entity_id, payload)>` ready for the cascade tombstone loop.
// `entity_id` is the wire-format identity peers will see in the
// envelope: bare row id for non-edge entities, composite
// `task_id:other_id` for edges.
// `permanent_delete_task` cascade rolled its own SELECT-and-`json!`
// for each of these four child shapes; the scanners give every
// surface (CLI, MCP, Tauri) one source of truth for the cascade
// snapshot shape.

/// Snapshot every `task_tags` edge for the given `task_id`. Result
/// is keyed on the composite `{task_id}:{tag_id}` entity id.
pub fn load_task_tags_for_task(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<Vec<(String, Value)>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!("SELECT {TASK_TAG_SELECT_COLUMNS} FROM task_tags WHERE task_id = ?1")
    });
    let mut stmt = conn.prepare_cached(sql)?;
    let rows = stmt.query_map(params![task_id], |row| {
        let task_id_val: String = row.get(0)?;
        let tag_id_val: String = row.get(1)?;
        let entity_id = format!("{task_id_val}:{tag_id_val}");
        Ok((entity_id, task_tag_payload_from_row(row)?))
    })?;
    rows.collect::<rusqlite::Result<Vec<_>>>()
        .map_err(StoreError::from)
}

/// Snapshot every `task_calendar_event_links` edge for the given
/// `task_id`. Result keyed on the composite
/// `{task_id}:{calendar_event_id}` entity id.
pub fn load_task_calendar_event_links_for_task(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<Vec<(String, Value)>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!(
            "SELECT {TASK_CALENDAR_EVENT_LINK_SELECT_COLUMNS} FROM task_calendar_event_links \
             WHERE task_id = ?1"
        )
    });
    let mut stmt = conn.prepare_cached(sql)?;
    let rows = stmt.query_map(params![task_id], |row| {
        let task_id_val: String = row.get(0)?;
        let event_id_val: String = row.get(1)?;
        let entity_id = format!("{task_id_val}:{event_id_val}");
        Ok((entity_id, task_calendar_event_link_payload_from_row(row)?))
    })?;
    rows.collect::<rusqlite::Result<Vec<_>>>()
        .map_err(StoreError::from)
}

/// Snapshot every `task_dependencies` edge that touches the given
/// `task_id`, in either direction. Result keyed on the composite
/// `{task_id}:{depends_on_task_id}` entity id.
pub fn load_task_dependencies_for_task(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<Vec<(String, Value)>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!(
            "SELECT {TASK_DEPENDENCY_SELECT_COLUMNS} FROM task_dependencies \
             WHERE task_id = ?1 OR depends_on_task_id = ?1 \
             ORDER BY task_id, depends_on_task_id"
        )
    });
    let mut stmt = conn.prepare_cached(sql)?;
    let rows = stmt.query_map(params![task_id], |row| {
        let task_id_val: String = row.get(0)?;
        let depends_on_task_id_val: String = row.get(1)?;
        let entity_id = format!("{task_id_val}:{depends_on_task_id_val}");
        Ok((entity_id, task_dependency_payload_from_row(row)?))
    })?;
    rows.collect::<rusqlite::Result<Vec<_>>>()
        .map_err(StoreError::from)
}

/// Snapshot every `task_checklist_items` row for the given `task_id`.
/// Result keyed on the bare row id.
pub fn load_task_checklist_items_for_task(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<Vec<(String, Value)>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!(
            "SELECT {TASK_CHECKLIST_ITEM_SELECT_COLUMNS} FROM task_checklist_items \
             WHERE task_id = ?1"
        )
    });
    let mut stmt = conn.prepare_cached(sql)?;
    let rows = stmt.query_map(params![task_id], |row| {
        let id: String = row.get(0)?;
        Ok((id, task_checklist_item_payload_from_row(row)?))
    })?;
    rows.collect::<rusqlite::Result<Vec<_>>>()
        .map_err(StoreError::from)
}

/// Snapshot every `task_calendar_event_links` edge for the given
/// `calendar_event_id`. Result keyed on the composite
/// `{task_id}:{calendar_event_id}` entity id.
pub fn load_task_calendar_event_links_for_calendar_event(
    conn: &Connection,
    event_id: &EventId,
) -> Result<Vec<(String, Value)>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!(
            "SELECT {TASK_CALENDAR_EVENT_LINK_SELECT_COLUMNS} FROM task_calendar_event_links \
             WHERE calendar_event_id = ?1 \
             ORDER BY task_id, calendar_event_id"
        )
    });
    let mut stmt = conn.prepare_cached(sql)?;
    let rows = stmt.query_map(params![event_id], |row| {
        let task_id_val: String = row.get(0)?;
        let event_id_val: String = row.get(1)?;
        let entity_id = format!("{task_id_val}:{event_id_val}");
        Ok((entity_id, task_calendar_event_link_payload_from_row(row)?))
    })?;
    rows.collect::<rusqlite::Result<Vec<_>>>()
        .map_err(StoreError::from)
}

/// Snapshot every `habit_completions` edge for the given `habit_id`.
/// Result keyed on the composite `{habit_id}:{completed_date}` entity
/// id.
pub fn load_habit_completions_for_habit(
    conn: &Connection,
    habit_id: &HabitId,
) -> Result<Vec<(String, Value)>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!(
            "SELECT {HABIT_COMPLETION_SELECT_COLUMNS} FROM habit_completions \
             WHERE habit_id = ?1 \
             ORDER BY completed_date"
        )
    });
    let mut stmt = conn.prepare_cached(sql)?;
    let rows = stmt.query_map(params![habit_id], |row| {
        let habit_id_val: String = row.get(0)?;
        let completed_date: String = row.get(1)?;
        let entity_id = format!("{habit_id_val}:{completed_date}");
        Ok((entity_id, habit_completion_payload_from_row(row)?))
    })?;
    rows.collect::<rusqlite::Result<Vec<_>>>()
        .map_err(StoreError::from)
}

/// Snapshot every `habit_reminder_policies` row for the given
/// `habit_id`. Result keyed on the bare row id.
pub fn load_habit_reminder_policies_for_habit(
    conn: &Connection,
    habit_id: &HabitId,
) -> Result<Vec<(String, Value)>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!(
            "SELECT {HABIT_REMINDER_POLICY_SELECT_COLUMNS} FROM habit_reminder_policies \
             WHERE habit_id = ?1 \
             ORDER BY id"
        )
    });
    let mut stmt = conn.prepare_cached(sql)?;
    let rows = stmt.query_map(params![habit_id], |row| {
        let id: String = row.get(0)?;
        Ok((id, habit_reminder_policy_payload_from_row(row)?))
    })?;
    rows.collect::<rusqlite::Result<Vec<_>>>()
        .map_err(StoreError::from)
}

/// Snapshot every `task_reminders` row for the given `task_id`.
/// Result keyed on the bare row id.
pub fn load_task_reminders_for_task(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<Vec<(String, Value)>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!(
            "SELECT {TASK_REMINDER_SELECT_COLUMNS} FROM task_reminders \
             WHERE task_id = ?1"
        )
    });
    let mut stmt = conn.prepare_cached(sql)?;
    let rows = stmt.query_map(params![task_id], |row| {
        let id: String = row.get(0)?;
        Ok((id, task_reminder_payload_from_row(row)?))
    })?;
    rows.collect::<rusqlite::Result<Vec<_>>>()
        .map_err(StoreError::from)
}
