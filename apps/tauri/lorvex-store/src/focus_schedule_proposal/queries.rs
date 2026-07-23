//! SQL loaders backing the focus-schedule proposal: candidate tasks +
//! the working-hours preference.

use rusqlite::{types::Value as SqlValue, Connection, OptionalExtension};
use serde::Deserialize;

use lorvex_domain::time::TimeOfDay;
use lorvex_domain::{DEFAULT_WORKING_HOURS_END, DEFAULT_WORKING_HOURS_START};

use crate::error::StoreError;
use crate::TASK_ORDER_BY;

use super::time_utils::time_of_day_to_minutes;
use super::types::{FocusScheduleTask, FocusScheduleWorkingHours};

#[derive(Debug, Deserialize)]
struct WorkingHoursPreference {
    start: String,
    end: String,
}

pub(super) fn load_task_candidates(
    conn: &Connection,
    task_ids: &[String],
) -> Result<Vec<FocusScheduleTask>, StoreError> {
    let placeholders = lorvex_domain::sql_in_placeholders(task_ids.len(), 0);
    let sql = format!(
        "SELECT id, title, status, due_date, planned_date, priority, list_id, estimated_minutes \
         FROM tasks \
         WHERE id IN ({placeholders}) \
           AND status = ?{} \
           AND archived_at IS NULL \
         ORDER BY {}",
        task_ids.len() + 1,
        TASK_ORDER_BY
    );
    // perf: pre-size for `task_ids` placeholders + the trailing
    // `STATUS_OPEN` bind so the params Vec doesn't realloc on push.
    let mut values: Vec<SqlValue> = Vec::with_capacity(task_ids.len() + 1);
    values.extend(
        task_ids
            .iter()
            .map(|task_id| SqlValue::Text(task_id.clone())),
    );
    values.push(SqlValue::Text(
        lorvex_domain::naming::STATUS_OPEN.to_string(),
    ));
    let mut stmt = conn.prepare_cached(&sql)?;
    let rows = stmt.query_map(rusqlite::params_from_iter(values.iter()), |row| {
        Ok(FocusScheduleTask {
            id: row.get(0)?,
            title: row.get(1)?,
            status: row.get(2)?,
            due_date: row.get(3)?,
            planned_date: row.get(4)?,
            priority: row.get(5)?,
            list_id: row.get(6)?,
            estimated_minutes: row.get(7)?,
        })
    })?;

    rows.collect::<Result<Vec<_>, _>>()
        .map_err(StoreError::from)
}

pub(super) fn load_working_hours(
    conn: &Connection,
) -> Result<FocusScheduleWorkingHours, StoreError> {
    let raw: Option<String> = conn
        .query_row(
            "SELECT value FROM preferences WHERE key = ?1",
            [lorvex_domain::preference_keys::PREF_WORKING_HOURS],
            |row| row.get(0),
        )
        .optional()?;

    match raw {
        Some(value) => {
            let parsed: WorkingHoursPreference = serde_json::from_str(&value).map_err(|error| {
                StoreError::Validation(format!(
                    "working_hours preference must be a JSON object with string start/end: {error}"
                ))
            })?;
            let start = TimeOfDay::parse(&parsed.start).map_err(|_| {
                StoreError::Validation(format!(
                    "working_hours.start must be HH:MM, got '{}'",
                    parsed.start
                ))
            })?;
            let end = TimeOfDay::parse(&parsed.end).map_err(|_| {
                StoreError::Validation(format!(
                    "working_hours.end must be HH:MM, got '{}'",
                    parsed.end
                ))
            })?;
            if time_of_day_to_minutes(end) < time_of_day_to_minutes(start) {
                return Err(StoreError::Validation(
                    "working_hours.end must be after working_hours.start".to_string(),
                ));
            }
            Ok(FocusScheduleWorkingHours { start, end })
        }
        None => Ok(FocusScheduleWorkingHours {
            // Default constants are static `&str` shaped as `HH:MM`;
            // route through `TimeOfDay::parse` so the typed struct
            // stays the only construction surface and a future change
            // to the constant format fails loudly here instead of
            // silently storing a malformed value.
            start: TimeOfDay::parse(DEFAULT_WORKING_HOURS_START)
                .expect("DEFAULT_WORKING_HOURS_START must parse as HH:MM"),
            end: TimeOfDay::parse(DEFAULT_WORKING_HOURS_END)
                .expect("DEFAULT_WORKING_HOURS_END must parse as HH:MM"),
        }),
    }
}
