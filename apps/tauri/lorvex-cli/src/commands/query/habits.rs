use crate::startup_maintenance::open_db_at_path;
use lorvex_runtime::resolve_db_path;
use rusqlite::OptionalExtension;
use serde_json::json;
use std::fmt::Write;

use crate::cli::OutputFormat;
use crate::commands::mutate::habits::effects::list_habit_reminder_policies_with_conn;
use crate::commands::shared::render_query_envelope;
use crate::commands::shared::today_ymd_for_conn;
use crate::render::{render_habit_collection, render_habit_stats};

pub(crate) fn run_habits(format: OutputFormat) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let today = today_ymd_for_conn(&conn)?;

    let mut stmt = conn.prepare(
        "SELECT id, name, icon, color, cue, frequency_type, \
                target_count, archived, created_at, updated_at \
         FROM habits WHERE archived = 0 ORDER BY created_at ASC",
    )?;
    let habits: Vec<crate::models::HabitSummary> = stmt
        .query_map([], |row| {
            Ok(crate::models::HabitSummary {
                id: row.get(0)?,
                name: row.get(1)?,
                icon: row.get(2)?,
                frequency_type: row.get(5)?,
                target_count: row.get(6)?,
                completions_today: 0, // filled below
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;

    // Load today's completions in one query
    let mut today_map = std::collections::HashMap::new();
    let mut today_stmt = conn.prepare(
        "SELECT habit_id, COALESCE(value, 0) FROM habit_completions WHERE completed_date = ?1",
    )?;
    let today_rows = today_stmt.query_map(rusqlite::params![today], |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?))
    })?;
    for row in today_rows {
        let (habit_id, value) = row?;
        today_map.insert(habit_id, value);
    }

    let habits: Vec<crate::models::HabitSummary> = habits
        .into_iter()
        .map(|mut h| {
            h.completions_today = *today_map.get(&h.id).unwrap_or(&0);
            h
        })
        .collect();

    render_habit_collection(&db_path, &today, &habits, format)
}

pub(crate) fn run_habit_reminder_policies(
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;
    let policies = list_habit_reminder_policies_with_conn(&conn)?;

    match format {
        OutputFormat::Text => {
            let mut rendered = format!(
                "Lorvex Habit Reminder Policies\nDB: {}\nCount: {}\n",
                db_path.display(),
                policies.len()
            );
            if policies.is_empty() {
                rendered.push_str("  - none\n");
            } else {
                for policy in &policies {
                    let state = if policy.enabled {
                        "enabled"
                    } else {
                        "disabled"
                    };
                    let _ = writeln!(
                        rendered,
                        "  - {}: {} at {} ({})",
                        policy.id, policy.habit_name, policy.reminder_time, state
                    );
                }
            }
            Ok(rendered)
        }
        OutputFormat::Json => render_query_envelope(
            "query.habit.reminder_policies",
            &db_path,
            json!({ "habit_reminder_policies": policies }),
        ),
    }
}

pub(crate) fn run_habit_stats(
    habit_id: &str,
    days: Option<i64>,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let db_path = resolve_db_path();
    let conn = open_db_at_path(&db_path)?;

    let today = today_ymd_for_conn(&conn)?;

    // Verify habit exists
    let habit_name: String = conn
        .query_row(
            "SELECT name FROM habits WHERE id = ?1",
            rusqlite::params![habit_id],
            |row| row.get(0),
        )
        .optional()?
        .ok_or_else(|| crate::error::CliError::NotFound(format!("habit '{habit_id}' not found")))?;

    let total_completions: i64 = conn.query_row(
        "SELECT COALESCE(SUM(value), 0) FROM habit_completions WHERE habit_id = ?1",
        rusqlite::params![habit_id],
        |row| row.get(0),
    )?;

    let completions_today: i64 = conn
        .query_row(
            "SELECT COALESCE(value, 0) FROM habit_completions WHERE habit_id = ?1 AND completed_date = ?2",
            rusqlite::params![habit_id, today],
            |row| row.get(0),
        )
        .optional()?
        .unwrap_or(0);

    let limit_days = days.unwrap_or(30).clamp(1, 365);

    let completions_period: i64 = conn.query_row(
        "SELECT COALESCE(SUM(value), 0) FROM habit_completions \
         WHERE habit_id = ?1 AND completed_date > date(?2, ?3)",
        rusqlite::params![habit_id, today, format!("-{limit_days} days")],
        |row| row.get(0),
    )?;

    render_habit_stats(
        &db_path,
        habit_id,
        &habit_name,
        total_completions,
        completions_today,
        completions_period,
        limit_days,
        format,
    )
}
