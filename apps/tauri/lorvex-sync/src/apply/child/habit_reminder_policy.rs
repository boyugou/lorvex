use lorvex_domain::ids::{HabitId, HabitReminderPolicyId};

use super::helpers::{required_bool_as_i64, required_str};
use super::*;

pub(crate) fn apply_habit_reminder_policy_upsert(
    conn: &Connection,
    entity_id: &str,
    payload: &str,
    version: &str,
    allow_equal_versions: LwwTieBreak,
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    // Issue #3285: parse the PK and the habit-id FK into typed
    // newtypes at handler entry. SQL bind sites use the rusqlite
    // ToSql impl on the newtype (zero-copy); dispatcher-validated
    // upstream so `from_trusted` skips a redundant parse.
    let id = HabitReminderPolicyId::from_trusted(entity_id.to_string());
    let val: serde_json::Value = serde_json::from_str(payload)?;

    let habit_id_str = required_str(&val, "habit_id", "habit_reminder_policy")?;
    let habit_id = HabitId::from_trusted(habit_id_str.to_string());
    let reminder_time = required_str(&val, "reminder_time", "habit_reminder_policy")?;
    // Tauri's `HabitReminderPolicy.enabled: bool` serializes to JSON
    // `true`/`false`, not 0/1. Coerce bool→i64 with
    // `required_bool_as_i64` so Tauri-originated envelopes apply on
    // remote peers; a plain `required_i64` would reject them and the
    // policy would silently never reach the cluster. Same pattern as
    // habit.archived (R4), calendar_event.all_day (R4), and
    // child-entity boolean columns (R8).
    let enabled = required_bool_as_i64(&val, "enabled", "habit_reminder_policy")?;
    let created_at = required_str(&val, "created_at", "habit_reminder_policy")?;
    let updated_at = required_str(&val, "updated_at", "habit_reminder_policy")?;

    // lifted to shared `LwwUpsertSpec`.
    static SQL_CACHE: std::sync::OnceLock<[String; 2]> = std::sync::OnceLock::new();
    let sql = crate::apply::LwwUpsertSpec {
        table: "habit_reminder_policies",
        columns: &[
            "id",
            "habit_id",
            "reminder_time",
            "enabled",
            "created_at",
            "updated_at",
            "version",
        ],
        conflict: &["id"],
        tie_break: allow_equal_versions,
    }
    .build_sql_cached(&SQL_CACHE);
    conn.prepare_cached(sql)?.execute(named_params! {
        ":id": &id,
        ":habit_id": &habit_id,
        ":reminder_time": reminder_time,
        ":enabled": enabled,
        ":created_at": created_at,
        ":updated_at": updated_at,
        ":version": version,
    })?;
    Ok(())
}

pub(crate) fn apply_habit_reminder_policy_delete(
    conn: &Connection,
    entity_id: &str,
    version: &str,
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    // Issue #3285: parse the PK into a typed `HabitReminderPolicyId`
    // at handler entry; the SQL bind threads it via the rusqlite
    // ToSql impl on the newtype.
    let id = HabitReminderPolicyId::from_trusted(entity_id.to_string());
    // route through `lww_gated_delete` so the in-row
    // LWW guard parses the typed HLC instead of byte-comparing the
    // string directly. See `lww/mod.rs::lww_gated_delete` for the
    // discipline rationale.
    crate::apply::lww_gated_delete(
        conn,
        "habit_reminder_policies",
        &["id"],
        &[id.as_str()],
        version,
    )?;
    Ok(())
}
