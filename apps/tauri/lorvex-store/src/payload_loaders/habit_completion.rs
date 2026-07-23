use lorvex_domain::HabitId;
use rusqlite::{params, Connection, OptionalExtension, Row};
use serde_json::{json, Value};

use crate::error::StoreError;

pub const HABIT_COMPLETION_SELECT_COLUMNS: &str =
    "habit_id, completed_date, value, note, version, created_at, updated_at";

/// Primitive shared by the row-mapper and the
/// `DeletedHabitCompletionSnapshot` tombstone path.
pub fn habit_completion_payload(
    habit_id: &HabitId,
    completed_date: &str,
    value: i64,
    note: Option<&str>,
    version: &str,
    created_at: &str,
    updated_at: &str,
) -> Value {
    json!({
        "habit_id": habit_id,
        "completed_date": completed_date,
        "value": value,
        "note": note,
        "version": version,
        "created_at": created_at,
        "updated_at": updated_at,
    })
}

pub fn habit_completion_payload_from_row(row: &Row<'_>) -> rusqlite::Result<Value> {
    let habit_id: HabitId = row.get(0)?;
    let completed_date: String = row.get(1)?;
    let value: i64 = row.get(2)?;
    let note: Option<String> = row.get(3)?;
    let version: String = row.get(4)?;
    let created_at: String = row.get(5)?;
    let updated_at: String = row.get(6)?;
    Ok(habit_completion_payload(
        &habit_id,
        &completed_date,
        value,
        note.as_deref(),
        &version,
        &created_at,
        &updated_at,
    ))
}

pub fn load_habit_completion_sync_payload(
    conn: &Connection,
    habit_id: &HabitId,
    completed_date: &str,
) -> Result<Option<Value>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let sql = SQL.get_or_init(|| {
        format!(
            "SELECT {HABIT_COMPLETION_SELECT_COLUMNS} \
             FROM habit_completions WHERE habit_id = ?1 AND completed_date = ?2"
        )
    });
    Ok(conn
        .query_row(
            sql,
            params![habit_id, completed_date],
            habit_completion_payload_from_row,
        )
        .optional()?)
}
