//! Human-UI habit mutations (issue #2411).
//!
//! Until now, habit creation and deletion went exclusively through the
//! MCP `habit_create` / `habit_delete` tools. Standalone users (no MCP
//! assistant connected) had no way to create a habit from the app, so
//! the Habits tab was effectively dead weight for them.
//!
//! These Tauri commands mirror the MCP writes in `mcp-server/src/
//! server_habits/writes.rs` -- same validation, same HLC versioning,
//! same outbox enqueue semantics -- minus the `ai_changelog` write,
//! because `crate::invariants::log_change` on the app side is an
//! intentional no-op (human actions are not AI history). The sync
//! outbox write is still made so peers see the change.

use lorvex_domain::naming::{ENTITY_HABIT, OP_DELETE, OP_UPSERT};
use lorvex_domain::HabitFrequencyType;
use lorvex_sync::outbox_enqueue::{
    tombstone_completions_for_habit_delete, tombstone_reminder_policies_for_habit_delete,
};
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};

use crate::commands::enqueue_to_outbox_typed;
use crate::commands::{sync_timestamp_now, with_immediate_transaction};
use crate::db::get_conn;
use crate::error::{AppError, AppResult};
use crate::event_bus;
use crate::hlc::generate_version_result;

/// Canonical habit read projection — [`lorvex_store::repositories::columns::HABITS`]
/// `select_clause` (with `version` + the materialized `weekdays` array).
/// The INSERT path binds explicit physical columns instead, because the
/// projection's trailing `weekdays` entry is a `json_group_array`
/// subquery, not an insertable column.
const HABIT_SELECT_COLS: &str = lorvex_store::repositories::columns::HABITS.select_clause;

#[derive(Debug, Serialize, Deserialize)]
pub struct Habit {
    pub id: String,
    pub name: String,
    pub icon: Option<String>,
    pub color: Option<String>,
    pub cue: Option<String>,
    pub frequency_type: HabitFrequencyType,
    /// `weekly` weekday set, Monday-first (0=Mon … 6=Sun). Empty for every
    /// non-weekly cadence and for weekly-every-day.
    pub weekdays: Vec<i64>,
    /// Completions required per week for a `times_per_week` cadence.
    pub per_period_target: i64,
    /// Reminder day-of-month for a `monthly` cadence (1–31), or `None`.
    pub day_of_month: Option<i64>,
    pub target_count: i64,
    pub archived: bool,
    pub created_at: String,
    pub updated_at: String,
}

fn habit_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<Habit> {
    let raw_frequency_type: String = row.get(5)?;
    // The schema CHECK on `habits.frequency_type` already enforces the
    // closed vocabulary. A foreign peer that wrote a future variant
    // surfaces here as a `FromSqlConversionFailure`; the rusqlite shape
    // is deliberate so the rest of the pipeline (`AppError::from`) maps
    // it onto a structured error.
    let frequency_type = HabitFrequencyType::parse(&raw_frequency_type).ok_or_else(|| {
        rusqlite::Error::FromSqlConversionFailure(
            5,
            rusqlite::types::Type::Text,
            format!(
                "habits.frequency_type carries unknown value '{raw_frequency_type}' (expected daily/weekly/monthly/times_per_week)"
            )
            .into(),
        )
    })?;
    // The projection materializes the `weekly` weekday set as a JSON
    // integer array (index 13); a daily cadence yields `"[]"`.
    let weekdays_json: String = row.get(13)?;
    let weekdays: Vec<i64> = serde_json::from_str(&weekdays_json).unwrap_or_default();
    Ok(Habit {
        id: row.get(0)?,
        name: row.get(1)?,
        icon: row.get(2)?,
        color: row.get(3)?,
        cue: row.get(4)?,
        frequency_type,
        weekdays,
        per_period_target: row.get(6)?,
        day_of_month: row.get(7)?,
        target_count: row.get(8)?,
        archived: row.get::<_, i64>(9)? != 0,
        created_at: row.get(10)?,
        updated_at: row.get(11)?,
    })
}

/// Delete-then-insert the `habit_weekdays` rows for one habit from a
/// Monday-first weekday-index set. Parent-owned materialization: the rows
/// carry no version and are never synced independently.
fn rebuild_habit_weekdays(
    conn: &rusqlite::Connection,
    habit_id: &str,
    weekdays: &[lorvex_domain::habits::WeekDay],
) -> AppResult<()> {
    conn.execute(
        "DELETE FROM habit_weekdays WHERE habit_id = ?1",
        params![habit_id],
    )
    .map_err(AppError::from)?;
    for day in weekdays {
        conn.execute(
            "INSERT OR IGNORE INTO habit_weekdays (habit_id, weekday) VALUES (?1, ?2)",
            params![habit_id, day.as_index()],
        )
        .map_err(AppError::from)?;
    }
    Ok(())
}

fn load_habit_sync_payload_required(
    conn: &rusqlite::Connection,
    habit_id: &lorvex_domain::HabitId,
) -> AppResult<serde_json::Value> {
    lorvex_store::payload_loaders::load_habit_sync_payload(conn, habit_id)?
        .ok_or_else(|| AppError::NotFound(format!("habit not found: {habit_id}")))
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
#[allow(clippy::too_many_arguments)]
#[allow(clippy::too_many_arguments)]
pub fn create_habit(
    name: String,
    icon: Option<String>,
    color: Option<String>,
    cue: Option<String>,
    frequency_type: Option<String>,
    weekdays: Option<Vec<i64>>,
    per_period_target: Option<i64>,
    day_of_month: Option<i64>,
    target_count: Option<i64>,
) -> Result<Habit, String> {
    let conn = get_conn().map_err(String::from)?;
    let habit = with_immediate_transaction(&conn, |conn| {
        create_habit_with_conn(
            conn,
            CreateHabitParams {
                name: &name,
                icon: icon.as_deref(),
                color: color.as_deref(),
                cue: cue.as_deref(),
                frequency_type: frequency_type.as_deref(),
                weekdays: weekdays.as_deref(),
                per_period_target,
                day_of_month,
                target_count,
            },
        )
    })
    .map_err(String::from)?;

    event_bus::emit_data_changed(event_bus::Entity::Habit);
    Ok(habit)
}

pub(crate) struct CreateHabitParams<'a> {
    pub name: &'a str,
    pub icon: Option<&'a str>,
    pub color: Option<&'a str>,
    pub cue: Option<&'a str>,
    pub frequency_type: Option<&'a str>,
    /// `weekly` weekday indices, Monday-first (0=Mon … 6=Sun).
    pub weekdays: Option<&'a [i64]>,
    /// `times_per_week` completions-per-week target.
    pub per_period_target: Option<i64>,
    /// `monthly` reminder day-of-month (1–31).
    pub day_of_month: Option<i64>,
    pub target_count: Option<i64>,
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
pub(crate) fn create_habit_with_conn(
    conn: &rusqlite::Connection,
    params_in: CreateHabitParams<'_>,
) -> AppResult<Habit> {
    // Bridge the IPC's typed cadence fields into the typed primitive at
    // the boundary. A `None` frequency_type defaults to daily after
    // validation; a present type is validated with its detail (weekday
    // set / per-period target / day-of-month) via `from_fields`.
    let frequency = match params_in.frequency_type {
        Some(ft) => {
            let weekdays = params_in.weekdays.map(|indices| {
                indices
                    .iter()
                    .filter_map(|index| lorvex_domain::habits::WeekDay::from_index(*index))
                    .collect()
            });
            let fields = lorvex_domain::habits::HabitFrequencyFields {
                frequency_type: ft.to_string(),
                weekdays,
                per_period_target: params_in.per_period_target.unwrap_or(1),
                day_of_month: params_in.day_of_month,
            };
            Some(
                lorvex_domain::habits::HabitCadence::from_fields(&fields)
                    .map_err(AppError::from)?,
            )
        }
        None => None,
    };
    let validated = lorvex_domain::habits::validate_habit_create_draft(
        lorvex_domain::habits::HabitCreateDraft {
            name: params_in.name,
            icon: params_in.icon,
            color: params_in.color,
            cue: params_in.cue,
            frequency,
            target_count: params_in.target_count,
        },
    )
    .map_err(AppError::from)?;
    let cadence_fields = validated.frequency().to_fields();

    // dedup is enforced at the schema layer via
    // `idx_habits_lookup_key_active` (UNIQUE on `lookup_key` WHERE
    // archived = 0). We pre-check with an O(1) indexed lookup so we
    // can return a friendly Validation error; the UNIQUE index is
    // the actual contract — even if a concurrent writer races us
    // between the SELECT and the INSERT, the INSERT will fail the
    // CHECK and bubble up as an AppError. `lookup_key` is the
    // NFKC + Unicode case-fold + whitespace-collapse of `name`,
    // identical to the tag dedup pipeline (#2820).
    let collision: Option<String> = conn
        .query_row(
            "SELECT name FROM habits WHERE lookup_key = ?1 AND archived = 0",
            params![validated.lookup_key()],
            |row| row.get::<_, String>(0),
        )
        .optional()
        .map_err(AppError::from)?;
    if let Some(existing_name) = collision {
        return Err(AppError::Validation(format!(
            "a habit named '{existing_name}' already exists (case-insensitive Unicode match for '{}')",
            validated.name()
        )));
    }

    let id = lorvex_domain::new_entity_id_string();
    let now = sync_timestamp_now();
    let version = generate_version_result()?;

    conn.execute(
        "INSERT INTO habits (id, name, icon, color, cue, frequency_type, per_period_target,
             day_of_month, target_count, archived, created_at, updated_at, lookup_key,
             version)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, 0, ?10, ?10, ?11, ?12)",
        params![
            id,
            validated.name(),
            validated.icon(),
            validated.color(),
            validated.cue(),
            &cadence_fields.frequency_type,
            cadence_fields.per_period_target,
            cadence_fields.day_of_month,
            validated.target_count(),
            now,
            validated.lookup_key(),
            version
        ],
    )
    .map_err(AppError::from)?;

    // Materialize the `weekly` weekday set into the `habit_weekdays`
    // child (empty for every non-weekly cadence and for weekly-every-day).
    rebuild_habit_weekdays(conn, &id, cadence_fields.weekdays.as_deref().unwrap_or(&[]))?;

    let habit: Habit = conn
        .query_row(
            &format!("SELECT {HABIT_SELECT_COLS} FROM habits WHERE id = ?1"),
            params![id],
            habit_from_row,
        )
        .map_err(AppError::from)?;
    let habit_id = lorvex_domain::HabitId::from_trusted(habit.id.clone());
    let habit_payload = load_habit_sync_payload_required(conn, &habit_id)?;

    enqueue_to_outbox_typed(conn, ENTITY_HABIT, &habit.id, OP_UPSERT, &habit_payload)?;

    Ok(habit)
}

#[derive(Debug, Serialize)]
pub struct DeleteHabitResult {
    pub deleted: bool,
    pub id: String,
    pub name: String,
    pub completions_destroyed: i64,
    pub reminder_policies_destroyed: i64,
}

#[allow(clippy::needless_pass_by_value)] // Tauri IPC: deserialized owned args required
#[tauri::command]
pub fn delete_habit(habit_id: String) -> Result<DeleteHabitResult, String> {
    // habit ids are UUIDv7 — shape-check before the
    // destructive writer so a malformed id is rejected at the IPC
    // boundary instead of falling through to "habit not found".
    let habit_id_str = crate::commands::shared::validate_uuid_id(&habit_id, "habit_id")?;
    let habit_id = lorvex_domain::HabitId::from_trusted(habit_id_str);
    let conn = get_conn().map_err(String::from)?;
    let result = with_immediate_transaction(&conn, |conn| delete_habit_with_conn(conn, &habit_id))
        .map_err(String::from)?;

    event_bus::emit_data_changed(event_bus::Entity::Habit);
    Ok(result)
}

pub(crate) fn delete_habit_with_conn(
    conn: &rusqlite::Connection,
    habit_id: &lorvex_domain::HabitId,
) -> AppResult<DeleteHabitResult> {
    let habit: Habit = conn
        .query_row(
            &format!("SELECT {HABIT_SELECT_COLS} FROM habits WHERE id = ?1"),
            params![habit_id.as_str()],
            habit_from_row,
        )
        .optional()
        .map_err(AppError::from)?
        .ok_or_else(|| AppError::NotFound(format!("habit not found: {habit_id}")))?;
    let habit_payload = load_habit_sync_payload_required(conn, habit_id)?;

    let child_tombstone_version = generate_version_result()?;
    let completions =
        tombstone_completions_for_habit_delete(conn, habit_id, &child_tombstone_version).map_err(
            |error| {
                AppError::Internal(format!(
                    "habit delete completion tombstone write failed: {error}"
                ))
            },
        )?;
    let reminder_policies =
        tombstone_reminder_policies_for_habit_delete(conn, habit_id, &child_tombstone_version)
            .map_err(|error| {
                AppError::Internal(format!(
                    "habit delete reminder policy tombstone write failed: {error}"
                ))
            })?;

    let completions_destroyed = completions.len() as i64;
    let reminder_policies_destroyed = reminder_policies.len() as i64;

    let delete_version = generate_version_result()?;
    lorvex_store::repositories::lww_delete::execute_lww_delete_by_id(
        conn,
        "habits",
        "id",
        ENTITY_HABIT,
        habit_id.as_str(),
        &delete_version,
    )
    .map_err(AppError::from)?;

    // Drop the cached best-streak for this habit (issue #2291). Even
    // though the habit is gone, the cache is keyed by id and a future
    // habit with the same id (e.g. sync replay) should not inherit a
    // stale value.
    super::commands::invalidate_best_streak_cache(habit_id);

    for completion in &completions {
        let entity_id = completion.entity_id();
        let payload = completion.payload();
        enqueue_to_outbox_typed(
            conn,
            lorvex_domain::naming::EDGE_HABIT_COMPLETION,
            &entity_id,
            OP_DELETE,
            &payload,
        )?;
    }
    for policy in &reminder_policies {
        let payload = policy.payload();
        enqueue_to_outbox_typed(
            conn,
            lorvex_domain::naming::ENTITY_HABIT_REMINDER_POLICY,
            policy.id.as_str(),
            OP_DELETE,
            &payload,
        )?;
    }

    enqueue_to_outbox_typed(
        conn,
        ENTITY_HABIT,
        habit_id.as_str(),
        OP_DELETE,
        &habit_payload,
    )?;

    Ok(DeleteHabitResult {
        deleted: true,
        id: habit_id.as_str().to_string(),
        name: habit.name,
        completions_destroyed,
        reminder_policies_destroyed,
    })
}

#[cfg(test)]
mod tests;
