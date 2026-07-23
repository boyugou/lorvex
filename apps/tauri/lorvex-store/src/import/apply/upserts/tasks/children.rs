use rusqlite::{Connection, OptionalExtension};

use lorvex_domain::canonicalize_rfc3339_instant;
use lorvex_domain::checklist::validate_task_checklist_item_text;
use lorvex_domain::sanitize_user_text;

use super::super::{import_lww_upsert, LwwUpsertSpec, UpsertResult};
use crate::import::apply::helpers::{
    invalid_payload, optional_string_field, optional_sync_timestamp_field, required_i64_field,
    required_string_field, required_sync_timestamp_field, VersionedJsonlLine,
};
use crate::import::ImportError;

fn reminder_instant_key(value: &str) -> String {
    canonicalize_rfc3339_instant(value).unwrap_or_else(|| value.to_string())
}

pub(in crate::import::apply::upserts) fn upsert_task_reminder(
    conn: &Connection,
    entry: &VersionedJsonlLine,
) -> Result<UpsertResult, ImportError> {
    let p = &entry.payload;
    let id = required_string_field(p, "id", "task_reminder payload")?;
    let version = entry.version.as_str();
    let task_id = required_string_field(p, "task_id", "task_reminder payload")?;
    let reminder_at_raw = required_string_field(p, "reminder_at", "task_reminder payload")?;
    let reminder_at = canonicalize_rfc3339_instant(&reminder_at_raw).ok_or_else(|| {
        invalid_payload(format!(
            "task_reminder payload.reminder_at must be a valid RFC 3339 datetime, got '{reminder_at_raw}'"
        ))
    })?;
    let created_at = required_sync_timestamp_field(p, "created_at", "task_reminder payload")?;
    let dismissed_at = optional_sync_timestamp_field(p, "dismissed_at", "task_reminder payload")?;
    let cancelled_at = optional_sync_timestamp_field(p, "cancelled_at", "task_reminder payload")?;
    // local wall-clock anchor columns. Older exports
    // omit them entirely — treat missing as NULL.
    let original_local_time =
        optional_string_field(p, "original_local_time", "task_reminder payload")?;
    let original_tz = optional_string_field(p, "original_tz", "task_reminder payload")?;

    let previous_reminder_at: Option<String> = conn
        .query_row(
            "SELECT reminder_at FROM task_reminders WHERE id = ?1",
            [&id],
            |row| row.get(0),
        )
        .optional()?;

    let result = import_lww_upsert(
        conn,
        &LwwUpsertSpec {
            table: "task_reminders",
            id_col: "id",
            id_val: &id,
            version,
            insert_sql:
                "INSERT INTO task_reminders (id, task_id, reminder_at, dismissed_at, cancelled_at,
                 created_at, original_local_time, original_tz, version)
                 VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9)",
            update_sql: "UPDATE task_reminders SET task_id=?2, reminder_at=?3, dismissed_at=?4,
                 cancelled_at=?5, created_at=?6, original_local_time=?7, original_tz=?8,
                 version=?9 WHERE id=?1",
        },
        rusqlite::params![
            id,
            task_id,
            reminder_at,
            dismissed_at,
            cancelled_at,
            created_at,
            original_local_time,
            original_tz,
            version,
        ],
    )?;

    if matches!(result, UpsertResult::Updated) {
        let stored_reminder_at: Option<String> = conn
            .query_row(
                "SELECT reminder_at FROM task_reminders WHERE id = ?1",
                [&id],
                |row| row.get(0),
            )
            .optional()?;
        if let (Some(previous), Some(stored)) = (previous_reminder_at, stored_reminder_at) {
            if reminder_instant_key(&previous) != reminder_instant_key(&stored) {
                conn.prepare_cached(
                    "DELETE FROM task_reminder_delivery_state WHERE reminder_id = ?1",
                )?
                .execute([&id])?;
            }
        }
    }

    Ok(result)
}

pub(in crate::import::apply::upserts) fn upsert_task_checklist_item(
    conn: &Connection,
    entry: &VersionedJsonlLine,
) -> Result<UpsertResult, ImportError> {
    let p = &entry.payload;
    let id = required_string_field(p, "id", "task_checklist_item payload")?;
    let version = entry.version.as_str();
    let task_id = required_string_field(p, "task_id", "task_checklist_item payload")?;
    let position = required_i64_field(p, "position", "task_checklist_item payload")?;
    let text = sanitize_user_text(&required_string_field(
        p,
        "text",
        "task_checklist_item payload",
    )?);
    validate_task_checklist_item_text(&text)
        .map_err(|error| invalid_payload(format!("task_checklist_item payload.text {error}")))?;
    let completed_at =
        optional_sync_timestamp_field(p, "completed_at", "task_checklist_item payload")?;
    let created_at = required_sync_timestamp_field(p, "created_at", "task_checklist_item payload")?;
    let updated_at = required_sync_timestamp_field(p, "updated_at", "task_checklist_item payload")?;

    import_lww_upsert(
        conn,
        &LwwUpsertSpec {
            table: "task_checklist_items",
            id_col: "id",
            id_val: &id,
            version,
            insert_sql: "INSERT INTO task_checklist_items (
                    id, task_id, position, text, completed_at, created_at, updated_at, version
                 ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            update_sql: "UPDATE task_checklist_items
                 SET task_id = ?2, position = ?3, text = ?4, completed_at = ?5,
                     created_at = ?6, updated_at = ?7, version = ?8
                 WHERE id = ?1",
        },
        rusqlite::params![
            id,
            task_id,
            position,
            text,
            completed_at,
            created_at,
            updated_at,
            version,
        ],
    )
}
