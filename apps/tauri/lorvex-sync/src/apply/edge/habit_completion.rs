use rusqlite::{named_params, Connection};

use lorvex_domain::ids::HabitId;

use super::super::{ApplyError, LwwTieBreak};
use super::helpers::{optional_str, required_i64, required_str, split_composite_id};

// ---------------------------------------------------------------------------
// habit_completion (PK = (habit_id, completed_date))
// ---------------------------------------------------------------------------

pub(crate) fn apply_habit_completion_upsert(
    conn: &Connection,
    entity_id: &str,
    payload: &str,
    version: &str,
    allow_equal_versions: LwwTieBreak,
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    let val: serde_json::Value = serde_json::from_str(payload)?;

    // Issue #3285 phase 3: parse the habit-id component into the typed
    // `HabitId` newtype at handler entry. `completed_date` is a date
    // string (not an entity id) so it stays `&str`. SQL bind sites use
    // the rusqlite ToSql impl on the newtype; dispatcher-validated
    // upstream so `from_trusted` skips a redundant parse.
    let (habit_id_str, completed_date) = split_composite_id(entity_id)?;
    let habit_id = HabitId::from_trusted(habit_id_str.to_string());
    let value = required_i64(&val, "value", "habit_completion")?;
    let note = optional_str(&val, "note", "habit_completion")?;
    let created_at = required_str(&val, "created_at", "habit_completion")?;
    let updated_at = required_str(&val, "updated_at", "habit_completion")?;

    // lifted to shared `LwwUpsertSpec`.
    static SQL_CACHE: std::sync::OnceLock<[String; 2]> = std::sync::OnceLock::new();
    let sql = crate::apply::LwwUpsertSpec {
        table: "habit_completions",
        columns: &[
            "habit_id",
            "completed_date",
            "value",
            "note",
            "created_at",
            "updated_at",
            "version",
        ],
        conflict: &["habit_id", "completed_date"],
        tie_break: allow_equal_versions,
    }
    .build_sql_cached(&SQL_CACHE);
    conn.prepare_cached(sql)?.execute(named_params! {
        ":habit_id": &habit_id,
        ":completed_date": completed_date,
        ":value": value,
        ":note": note,
        ":created_at": created_at,
        ":updated_at": updated_at,
        ":version": version,
    })?;
    Ok(())
}

pub(crate) fn apply_habit_completion_delete(
    conn: &Connection,
    entity_id: &str,
    version: &str,
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    // Issue #3285 phase 3: parse the habit-id component into the typed
    // `HabitId` once at handler entry. `completed_date` is a date string
    // and stays `&str`.
    let (habit_id_str, completed_date) = split_composite_id(entity_id)?;
    let habit_id = HabitId::from_trusted(habit_id_str.to_string());
    // route through `lww_gated_delete` so the in-row
    // LWW guard parses the typed HLC instead of byte-comparing the
    // string directly. See `lww/mod.rs::lww_gated_delete` for the
    // discipline rationale.
    crate::apply::lww_gated_delete(
        conn,
        "habit_completions",
        &["habit_id", "completed_date"],
        &[habit_id.as_str(), completed_date],
        version,
    )?;
    Ok(())
}
