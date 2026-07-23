use crate::error::McpError;
use lorvex_domain::HabitId;
use lorvex_store::with_deferred_read_transaction;
use lorvex_workflow::timezone::today_ymd_for_conn;
use rusqlite::{params, Connection, OptionalExtension};
use serde_json::json;
use std::collections::HashMap;

use super::streaks::{compute_longest_streak, compute_streak};
use super::{
    habit_from_row, load_habit_name_required, load_habit_required, progress_kind_for_target_count,
    Habit, HabitCompletion, HabitWithStats, HABIT_SELECT_COLS,
};

pub(crate) fn get_habit_stats(conn: &Connection, habit_id: &HabitId) -> Result<String, McpError> {
    let habit = load_habit_required(conn, habit_id.as_str())?;

    let today = today_ymd_for_conn(conn)?;

    let total_completions: i64 = conn.query_row(
        "SELECT COALESCE(SUM(value), 0) FROM habit_completions WHERE habit_id = ?1",
        params![habit_id.as_str()],
        |row| row.get(0),
    )?;

    let completions_today: i64 = conn
        .query_row(
            "SELECT COALESCE(value, 0) FROM habit_completions WHERE habit_id = ?1 AND completed_date = ?2",
            params![habit_id.as_str(), today],
            |row| row.get(0),
        )
        .optional()?
        .unwrap_or(0);

    // 30-day completion rate (cadence- and target-aware denominator)
    let completions_30d: i64 = conn.query_row(
        "SELECT COALESCE(SUM(value), 0) FROM habit_completions
             WHERE habit_id = ?1 AND completed_date > date(?2, '-30 days')",
        params![habit_id.as_str(), today],
        |row| row.get(0),
    )?;
    let cadence = habit.cadence()?;
    let expected_30d =
        lorvex_domain::habit_expected_completions_in_days(&cadence, habit.target_count, 30);
    let completion_rate_30d = if expected_30d > 0.0 {
        completions_30d as f64 / expected_30d
    } else {
        0.0
    };

    // Current streak and longest streak (frequency-aware) — no row limit so streaks >365 compute correctly
    let mut streak_stmt = conn.prepare_cached(
        "SELECT completed_date FROM habit_completions
             WHERE habit_id = ?1 ORDER BY completed_date DESC",
    )?;
    let dates: Vec<String> = streak_stmt
        .query_map(params![habit_id.as_str()], |row| row.get(0))?
        .collect::<Result<Vec<_>, _>>()?;

    let current_streak = compute_streak(&dates, &today, &habit.frequency_type, habit.target_count)?;
    let best_streak = compute_longest_streak(&dates, &habit.frequency_type, habit.target_count)?;

    let stats = HabitWithStats {
        progress_kind: progress_kind_for_target_count(habit.target_count),
        habit,
        current_streak,
        best_streak,
        total_completions,
        completion_rate_30d,
        completions_today,
    };

    Ok(serde_json::to_string(&stats)?)
}

/// Returns all habits with their statistics in a single call, avoiding the N+1 pattern.
/// Uses 5 batched SQL queries instead of 4×N.
pub(crate) fn get_habits_summary(
    conn: &Connection,
    include_archived: bool,
) -> Result<String, McpError> {
    // pin the snapshot so the habits list, per-habit
    // aggregates, and streak dates all reflect the same DB state. Without
    // this, a concurrent writer inserting a completion between the habit
    // fetch and the completion aggregates can produce a habit whose
    // streak does not match its completion totals.
    with_deferred_read_transaction(conn, |conn| {
        let today = today_ymd_for_conn(conn)?;

        // 1. Fetch all habits
        // Two-shape format: `archive_filter` is one of two `&'static str`
        // values keyed on `include_archived`, so the rendered SQL takes
        // one of two stable shapes for the process lifetime.
        static SQL_ALL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
        static SQL_ACTIVE: std::sync::OnceLock<String> = std::sync::OnceLock::new();
        let render = |archive_filter: &str| {
            format!(
                "SELECT {HABIT_SELECT_COLS} FROM habits {archive_filter} ORDER BY created_at ASC"
            )
        };
        let sql = if include_archived {
            SQL_ALL.get_or_init(|| render(""))
        } else {
            SQL_ACTIVE.get_or_init(|| render("WHERE archived = 0"))
        };
        let mut stmt = conn.prepare_cached(sql)?;
        let habits: Vec<Habit> = stmt
            .query_map([], habit_from_row)?
            .collect::<Result<Vec<_>, _>>()?;

        if habits.is_empty() {
            return Ok(serde_json::to_string(&Vec::<HabitWithStats>::new())?);
        }

        // 2. Total completions per habit (all time)
        let total_map: HashMap<String, i64> = conn
            .prepare_cached(
                "SELECT habit_id, COALESCE(SUM(value), 0) FROM habit_completions GROUP BY habit_id",
            )?
            .query_map([], |row| {
                Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?))
            })?
            .collect::<Result<HashMap<_, _>, _>>()?;

        // 3. Completions_today per habit
        let today_map: HashMap<String, i64> = conn
        .prepare_cached(
            "SELECT habit_id, COALESCE(value, 0) FROM habit_completions WHERE completed_date = ?1",
        )?
        .query_map(params![today], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?))
        })?
        .collect::<Result<HashMap<_, _>, _>>()?;

        // 4. Completion value in last 30 days per habit
        let d30_map: HashMap<String, i64> = conn
            .prepare_cached(
                "SELECT habit_id, COALESCE(SUM(value), 0) FROM habit_completions
             WHERE completed_date > date(?1, '-30 days') GROUP BY habit_id",
            )?
            .query_map(params![today], |row| {
                Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?))
            })?
            .collect::<Result<HashMap<_, _>, _>>()?;

        // 5. All completion dates for streak computation — no date cutoff so streaks >365 days are correct
        let mut dates_map: HashMap<String, Vec<String>> = HashMap::new();
        conn.prepare_cached(
            "SELECT habit_id, completed_date FROM habit_completions
         ORDER BY habit_id, completed_date DESC",
        )?
        .query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?
        .collect::<Result<Vec<_>, _>>()?
        .into_iter()
        .for_each(|(habit_id, date)| {
            dates_map.entry(habit_id).or_default().push(date);
        });

        // 6. Assemble results
        let empty_dates: Vec<String> = Vec::new();
        let result: Vec<HabitWithStats> = habits
            .into_iter()
            .map(|habit| {
                let total = *total_map.get(&habit.id).unwrap_or(&0);
                let today_count = *today_map.get(&habit.id).unwrap_or(&0);
                let completions_30d = *d30_map.get(&habit.id).unwrap_or(&0);
                let cadence = habit.cadence()?;
                let expected_30d = lorvex_domain::habit_expected_completions_in_days(
                    &cadence,
                    habit.target_count,
                    30,
                );
                let completion_rate_30d = if expected_30d > 0.0 {
                    completions_30d as f64 / expected_30d
                } else {
                    0.0
                };
                let dates = dates_map.get(&habit.id).unwrap_or(&empty_dates);
                let current_streak =
                    compute_streak(dates, &today, &habit.frequency_type, habit.target_count)?;
                let best_streak =
                    compute_longest_streak(dates, &habit.frequency_type, habit.target_count)?;
                Ok(HabitWithStats {
                    progress_kind: progress_kind_for_target_count(habit.target_count),
                    habit,
                    current_streak,
                    best_streak,
                    total_completions: total,
                    completion_rate_30d,
                    completions_today: today_count,
                })
            })
            .collect::<Result<Vec<_>, McpError>>()?;

        Ok(serde_json::to_string(&result)?)
    })
}

pub(crate) fn get_habit_completions(
    conn: &Connection,
    habit_id: &HabitId,
    days: Option<i64>,
) -> Result<String, McpError> {
    // Verify habit exists
    let _habit_name = load_habit_name_required(conn, habit_id.as_str())?;

    let limit_days = days.unwrap_or(30).clamp(1, 365);
    let today = today_ymd_for_conn(conn)?;

    let mut stmt = conn.prepare_cached(
        "SELECT habit_id, completed_date, value, note, created_at, updated_at
             FROM habit_completions
             WHERE habit_id = ?1 AND completed_date >= date(?2, ?3)
             ORDER BY completed_date DESC",
    )?;

    let completions: Vec<HabitCompletion> = stmt
        .query_map(
            params![habit_id.as_str(), today, format!("-{limit_days} days")],
            |row| {
                Ok(HabitCompletion {
                    habit_id: row.get(0)?,
                    completed_date: row.get(1)?,
                    value: row.get(2)?,
                    note: row.get(3)?,
                    created_at: row.get(4)?,
                    updated_at: row.get(5)?,
                })
            },
        )?
        .collect::<Result<Vec<_>, _>>()?;

    Ok(serde_json::to_string(&json!({
        "habit_id": habit_id.as_str(),
        "days": limit_days,
        "completions": completions,
    }))?)
}

#[cfg(test)]
mod tests;
