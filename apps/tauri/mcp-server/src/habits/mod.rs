//! Habits domain modules — split from the old `server_habits` / `server_habit_reminders` tree.

mod queries;
pub(crate) mod reminders;
mod streaks;
mod writes;

use crate::error::McpError;
use rusqlite::OptionalExtension;
use rusqlite::Row;
use serde::{Deserialize, Serialize};

// Re-export public API
pub(crate) use queries::{get_habit_completions, get_habit_stats, get_habits_summary};
pub(crate) use writes::{
    batch_complete_habit, complete_habit, create_habit, delete_habit, uncomplete_habit,
    update_habit, CreateHabitParams, UpdateHabitParams,
};

#[derive(Debug, Serialize, Deserialize)]
pub(crate) struct Habit {
    pub id: String,
    pub name: String,
    pub icon: Option<String>,
    pub color: Option<String>,
    pub cue: Option<String>,
    pub frequency_type: String,
    /// The `weekly` weekday set, Monday-first (0=Mon … 6=Sun). Empty for
    /// every non-weekly cadence and for weekly-every-day. Materialized from
    /// the `habit_weekdays` child.
    pub weekdays: Vec<i64>,
    pub per_period_target: i64,
    pub day_of_month: Option<i64>,
    pub target_count: i64,
    pub archived: bool,
    pub created_at: String,
    pub updated_at: String,
}

impl Habit {
    /// Reconstruct the typed cadence from the DTO's typed columns + weekday
    /// set — used by the cadence-branching read paths (streaks, expected
    /// completion rate).
    fn cadence(&self) -> Result<lorvex_domain::habits::HabitCadence, McpError> {
        let weekdays: Option<Vec<lorvex_domain::habits::WeekDay>> = if self.weekdays.is_empty() {
            None
        } else {
            Some(
                self.weekdays
                    .iter()
                    .filter_map(|i| lorvex_domain::habits::WeekDay::from_index(*i))
                    .collect(),
            )
        };
        Ok(lorvex_domain::habits::HabitCadence::from_fields(
            &lorvex_domain::habits::HabitFrequencyFields {
                frequency_type: self.frequency_type.clone(),
                weekdays,
                per_period_target: self.per_period_target,
                day_of_month: self.day_of_month,
            },
        )?)
    }
}

#[derive(Debug, Serialize)]
pub(crate) struct HabitWithStats {
    #[serde(flatten)]
    pub habit: Habit,
    pub progress_kind: &'static str,
    pub current_streak: i64,
    // was `longest_streak`; renamed to match the shared
    // TS type (HabitWithStats.best_streak) and the Tauri IPC runtime
    // shape. Computed by compute_longest_streak under the hood — the
    // internal fn keeps its name; only the wire field is renamed.
    pub best_streak: i64,
    pub total_completions: i64,
    pub completion_rate_30d: f64,
    pub completions_today: i64,
}

#[derive(Debug, Serialize)]
pub(crate) struct HabitCompletion {
    pub habit_id: String,
    pub completed_date: String,
    pub value: i64,
    pub note: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

fn habit_from_row(row: &Row<'_>) -> rusqlite::Result<Habit> {
    // Column order mirrors `columns::HABITS`: 0 id, 1 name, 2 icon, 3 color,
    // 4 cue, 5 frequency_type, 6 per_period_target, 7 day_of_month,
    // 8 target_count, 9 archived, 10 created_at, 11 updated_at,
    // 12 version (skipped — not on the DTO), 13 weekdays (JSON int array).
    let weekdays_json: String = row.get(13)?;
    let weekdays: Vec<i64> = serde_json::from_str(&weekdays_json).map_err(|error| {
        rusqlite::Error::FromSqlConversionFailure(13, rusqlite::types::Type::Text, Box::new(error))
    })?;
    Ok(Habit {
        id: row.get(0)?,
        name: row.get(1)?,
        icon: row.get(2)?,
        color: row.get(3)?,
        cue: row.get(4)?,
        frequency_type: row.get(5)?,
        weekdays,
        per_period_target: row.get(6)?,
        day_of_month: row.get(7)?,
        target_count: row.get(8)?,
        archived: row.get(9)?,
        created_at: row.get(10)?,
        updated_at: row.get(11)?,
    })
}

pub(crate) const fn progress_kind_for_target_count(target_count: i64) -> &'static str {
    if target_count > 1 {
        "accumulative"
    } else {
        "binary"
    }
}

/// Canonical habit read projection — the [`lorvex_store::repositories::columns::HABITS`]
/// entry, which materializes the `weekly` weekday set as a JSON integer
/// array (last column). Used only for SELECT: it carries a subquery
/// expression that is not a valid INSERT column list, so writes bind the
/// physical columns explicitly.
const HABIT_SELECT_COLS: &str = lorvex_store::repositories::columns::HABITS.select_clause;

fn load_habit_optional(conn: &rusqlite::Connection, id: &str) -> Result<Option<Habit>, McpError> {
    Ok(conn
        .query_row(
            &format!("SELECT {HABIT_SELECT_COLS} FROM habits WHERE id = ?1"),
            rusqlite::params![id],
            habit_from_row,
        )
        .optional()?)
}

fn load_habit_required(conn: &rusqlite::Connection, id: &str) -> Result<Habit, McpError> {
    load_habit_optional(conn, id)?
        .ok_or_else(|| McpError::NotFound(format!("habit not found: {id}")))
}

fn load_habit_name_required(conn: &rusqlite::Connection, id: &str) -> Result<String, McpError> {
    conn.query_row(
        "SELECT name FROM habits WHERE id = ?1",
        rusqlite::params![id],
        |row| row.get(0),
    )
    .optional()?
    .ok_or_else(|| McpError::NotFound(format!("habit not found: {id}")))
}
