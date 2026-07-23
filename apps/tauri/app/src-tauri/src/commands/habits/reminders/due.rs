use chrono::Datelike;
use rusqlite::{params, OptionalExtension};

use crate::db::get_read_conn;
use crate::error::{AppError, AppResult};

use super::model::{policy_from_row, DueHabitReminder, HabitReminderCandidate};

#[tauri::command]
pub fn get_due_habit_reminders() -> Result<Vec<DueHabitReminder>, String> {
    let result = (|| -> AppResult<Vec<DueHabitReminder>> {
        let conn = get_read_conn()?;
        get_due_habit_reminders_with_conn_at(&conn, chrono::Utc::now())
    })();

    result.map_err(String::from)
}

/// Return `Ok(true)` if a delivery row already exists for `policy_id`
/// whose `last_fired_at` falls on `local_day` in `timezone_name`.
///
/// This is the debounce for habit reminders: if it returns `true`, the
/// caller suppresses a duplicate fire. A silent `false` on a transient
/// SQLite error would cause a duplicate notification to the user, so
/// we propagate the error instead of swallowing it.
///
/// Note that only UNPARSEABLE `last_fired_at` strings fall through to
/// `false` — that's an explicit schema contract violation where the
/// schema's NOT NULL + CHECK constraints should already prevent it,
/// and where a fresh delivery is the correct failsafe (we can't tell
/// what day it was sent on, so we assume none).
pub(super) fn reminder_was_sent_on_local_day(
    conn: &rusqlite::Connection,
    policy_id: &str,
    timezone_name: &str,
    local_day: &str,
) -> AppResult<bool> {
    let last_fired_at: Option<String> = conn
        .query_row(
            "SELECT last_fired_at FROM habit_reminder_delivery_state WHERE policy_id = ?1",
            params![policy_id],
            |row| row.get(0),
        )
        .optional()?
        .flatten();
    let Some(last_fired_at) = last_fired_at.as_deref() else {
        return Ok(false);
    };
    let Some(parsed) = crate::commands::parse_rfc3339_utc(last_fired_at) else {
        return Ok(false);
    };
    let reminded_day = lorvex_domain::today_ymd_for_timezone_name(parsed, Some(timezone_name));
    Ok(reminded_day == local_day)
}

pub(super) fn get_due_habit_reminders_with_conn_at(
    conn: &rusqlite::Connection,
    now_utc: chrono::DateTime<chrono::Utc>,
) -> AppResult<Vec<DueHabitReminder>> {
    let tz_name = lorvex_workflow::timezone::anchored_timezone_name(conn)?;
    let (today, current_time) = due_habit_reminder_clock_at(now_utc, &tz_name)?;
    let today_date = chrono::NaiveDate::parse_from_str(&today, "%Y-%m-%d").map_err(|error| {
        AppError::Validation(format!("Invalid reminder day '{today}': {error}"))
    })?;

    let mut stmt = conn.prepare_cached(
        "SELECT p.id, p.habit_id, h.name, p.reminder_time, p.enabled, p.created_at, p.updated_at,
                h.frequency_type, h.per_period_target, h.day_of_month,
                (SELECT json_group_array(weekday) FROM (SELECT weekday FROM habit_weekdays
                   WHERE habit_id = h.id ORDER BY weekday)) AS weekdays,
                h.target_count \
         FROM habit_reminder_policies p \
         JOIN habits h ON h.id = p.habit_id \
         WHERE p.enabled = 1 AND p.reminder_time <= ?1 \
         ORDER BY p.reminder_time ASC",
    )?;

    let reminders = stmt
        .query_map(params![current_time], |row| {
            let weekdays_json: String = row.get(10)?;
            Ok(HabitReminderCandidate {
                policy: policy_from_row(row)?,
                frequency_type: row.get(7)?,
                per_period_target: row.get(8)?,
                day_of_month: row.get(9)?,
                weekdays: serde_json::from_str(&weekdays_json).unwrap_or_default(),
                target_count: row.get(11)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;

    // Propagate SQLite errors from `is_due` and `was_sent_on_local_day`
    // instead of silently skipping rows: a transient error in the debounce
    // query would otherwise flip "already sent" to "not sent" and fire a
    // duplicate user-facing notification on the next poll tick.
    let mut due_reminders: Vec<DueHabitReminder> = Vec::new();
    for reminder in reminders {
        if !habit_reminder_is_due(conn, &reminder, today_date)? {
            continue;
        }
        if reminder_was_sent_on_local_day(conn, &reminder.policy.id, &tz_name, &today)? {
            continue;
        }
        due_reminders.push(DueHabitReminder {
            policy: reminder.policy,
        });
    }
    Ok(due_reminders)
}

fn habit_reminder_is_due(
    conn: &rusqlite::Connection,
    reminder: &HabitReminderCandidate,
    today: chrono::NaiveDate,
) -> AppResult<bool> {
    let weekdays = if reminder.weekdays.is_empty() {
        None
    } else {
        Some(
            reminder
                .weekdays
                .iter()
                .filter_map(|index| lorvex_domain::habits::WeekDay::from_index(*index))
                .collect(),
        )
    };
    let cadence =
        lorvex_domain::HabitCadence::from_fields(&lorvex_domain::habits::HabitFrequencyFields {
            frequency_type: reminder.frequency_type.clone(),
            weekdays,
            per_period_target: reminder.per_period_target,
            day_of_month: reminder.day_of_month,
        })
        .map_err(AppError::from)?;
    // Gate on the reminder-day predicate, not the "scheduled" predicate:
    // a monthly habit is scheduled every day (a completion on any day
    // counts toward the month) but its reminder fires only on the
    // effective `day_of_month`, clamped to the month's last day.
    if !lorvex_domain::habits::is_habit_reminder_day(&cadence, today) {
        return Ok(false);
    }

    let required =
        lorvex_domain::habit_required_completions_per_period(&cadence, reminder.target_count);
    let habit_id_typed = lorvex_domain::HabitId::from_trusted(reminder.policy.habit_id.clone());
    let completed = current_habit_period_progress(conn, &habit_id_typed, &cadence, today)?;
    Ok(completed < required)
}

fn current_habit_period_progress(
    conn: &rusqlite::Connection,
    habit_id: &lorvex_domain::HabitId,
    cadence: &lorvex_domain::HabitCadence,
    today: chrono::NaiveDate,
) -> AppResult<i64> {
    if matches!(cadence, lorvex_domain::HabitCadence::Monthly { .. }) {
        // Monthly: sum completions for the entire current calendar month
        let month_start =
            chrono::NaiveDate::from_ymd_opt(today.year(), today.month(), 1).unwrap_or(today);
        let month_end = if today.month() == 12 {
            chrono::NaiveDate::from_ymd_opt(today.year() + 1, 1, 1)
        } else {
            chrono::NaiveDate::from_ymd_opt(today.year(), today.month() + 1, 1)
        }
        .map_or(today, |d| d - chrono::Duration::days(1));
        conn.query_row(
            "SELECT COALESCE(SUM(value), 0) FROM habit_completions
             WHERE habit_id = ?1 AND completed_date >= ?2 AND completed_date <= ?3",
            params![
                habit_id.as_str(),
                month_start.format("%Y-%m-%d").to_string(),
                month_end.format("%Y-%m-%d").to_string(),
            ],
            |row| row.get(0),
        )
        .map_err(AppError::from)
    } else if lorvex_domain::habit_uses_week_bucket(cadence) {
        let week_start =
            today - chrono::Duration::days(i64::from(today.weekday().num_days_from_monday()));
        let week_end = week_start + chrono::Duration::days(6);
        conn.query_row(
            "SELECT COALESCE(SUM(value), 0) FROM habit_completions
             WHERE habit_id = ?1 AND completed_date >= ?2 AND completed_date <= ?3",
            params![
                habit_id.as_str(),
                week_start.format("%Y-%m-%d").to_string(),
                week_end.format("%Y-%m-%d").to_string(),
            ],
            |row| row.get(0),
        )
        .map_err(AppError::from)
    } else {
        conn.query_row(
            "SELECT COALESCE(value, 0) FROM habit_completions
             WHERE habit_id = ?1 AND completed_date = ?2",
            params![habit_id.as_str(), today.format("%Y-%m-%d").to_string()],
            |row| row.get::<_, i64>(0),
        )
        .optional()
        .map_err(AppError::from)
        .map(|value| value.unwrap_or(0))
    }
}

pub(super) fn due_habit_reminder_clock_at(
    now_utc: chrono::DateTime<chrono::Utc>,
    timezone_name: &str,
) -> AppResult<(String, String)> {
    let timezone = lorvex_domain::parse_timezone_name(timezone_name).ok_or_else(|| {
        AppError::Internal(format!(
            "anchored_timezone_name returned invalid timezone '{timezone_name}'"
        ))
    })?;
    let now = now_utc.with_timezone(&timezone);
    Ok((
        now.format("%Y-%m-%d").to_string(),
        now.format("%H:%M").to_string(),
    ))
}
