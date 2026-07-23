//! Habit render helpers (collection / stats / completion result).

use serde_json::json;
use std::fmt::Write;
use std::path::Path;

use crate::cli::OutputFormat;
use crate::commands::shared::{render_mutation_envelope, render_query_envelope};
use crate::error::CliError;
use crate::models::HabitSummary;
use crate::render::format::{style_banner, style_empty_hint};

pub(crate) fn render_habit_collection(
    db_path: &Path,
    today: &str,
    habits: &[HabitSummary],
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => {
            let mut rendered = format!(
                "{}\nDB: {}\n",
                style_banner(&format!("Lorvex Habits ({today})")),
                db_path.display(),
            );
            if habits.is_empty() {
                rendered.push_str(&style_empty_hint(
                    "No habits yet — create one with `lorvex habit create \"<title>\" --cadence daily`.",
                ));
            } else {
                for habit in habits {
                    let icon = habit.icon.as_deref().unwrap_or("");
                    let icon_prefix = if icon.is_empty() {
                        String::new()
                    } else {
                        format!("{icon} ")
                    };
                    // bind the formatted progress to a
                    // local before the if-else so all three arms are
                    // genuinely `&str`. The previous form relied on
                    // a `format!()` temporary having its lifetime
                    // extended to the enclosing block — fragile under
                    // any small refactor (extracting a helper, hoisting
                    // the expression) and non-idiomatic for readers
                    // expecting all arms to be the same type.
                    let progress = format!("{}/{}", habit.completions_today, habit.target_count);
                    let status: &str = if habit.completions_today >= habit.target_count {
                        "done"
                    } else if habit.completions_today > 0 {
                        &progress
                    } else {
                        "pending"
                    };
                    let _ = writeln!(
                        rendered,
                        "  - {}{} [{}] ({})",
                        icon_prefix, habit.name, status, habit.frequency_type
                    );
                }
            }
            Ok(rendered)
        }
        OutputFormat::Json => render_query_envelope(
            "query.habits.collection",
            db_path,
            json!({
                "today": today,
                "habits": habits,
            }),
        ),
    }
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn render_habit_stats(
    db_path: &Path,
    habit_id: &str,
    habit_name: &str,
    total_completions: i64,
    completions_today: i64,
    completions_period: i64,
    period_days: i64,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => Ok(format!(
            "Lorvex Habit Stats\nDB: {}\nID: {}\nName: {}\nTotal completions: {}\nToday: {}\nLast {} days: {}\n",
            db_path.display(),
            habit_id,
            habit_name,
            total_completions,
            completions_today,
            period_days,
            completions_period,
        )),
        OutputFormat::Json => render_query_envelope(
            "query.habits.stats",
            db_path,
            json!({
                "habit_id": habit_id,
                "habit_name": habit_name,
                "total_completions": total_completions,
                "completions_today": completions_today,
                "period_days": period_days,
                "completions_period": completions_period,
            }),
        ),
    }
}

pub(crate) fn render_habit_complete_result(
    db_path: &Path,
    habit_id: &str,
    habit_name: &str,
    completed_date: &str,
    value: i64,
    note: Option<&str>,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => {
            let note_line = note
                .map(|value| format!("Note: {value}\n"))
                .unwrap_or_default();
            Ok(format!(
                "COMPLETE habit {}\nName: {}\nDate: {}\nValue: {}\n{}DB: {}",
                habit_id,
                habit_name,
                completed_date,
                value,
                note_line,
                db_path.display()
            ))
        }
        OutputFormat::Json => render_mutation_envelope(
            "mutation.habits.complete",
            db_path,
            json!({
                "habit_id": habit_id,
                "habit_name": habit_name,
                "completed_date": completed_date,
                "value": value,
                "note": note,
            }),
        ),
    }
}
