use crate::startup_maintenance::open_db_at_path;
use lorvex_domain::{ReminderId, TaskId};
use lorvex_runtime::resolve_db_path;
use serde_json::json;
use std::fmt::Write;

use crate::cli::OutputFormat;
use crate::commands::shared::render_mutation_envelope;
use crate::models::TaskReminderMutationResult;

pub(crate) mod effects;
#[cfg(test)]
mod effects_tests;
use effects::{
    add_task_reminder_with_conn, remove_task_reminder_with_conn, set_task_reminders_with_conn,
};

fn render_task_reminder_mutation(
    action: &str,
    text_heading: &str,
    db_path: &std::path::Path,
    result: TaskReminderMutationResult,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    match format {
        OutputFormat::Text => {
            let mut output = format!(
                "{text_heading}\nDB: {}\nTask: {} ({})\nReminders: {}\n",
                db_path.display(),
                result.task.core().title(),
                result.task.core().id(),
                result.reminders.len()
            );
            for reminder in result.reminders {
                let _ = writeln!(output, "- {}: {}", reminder.id, reminder.reminder_at);
            }
            Ok(output)
        }
        // canonical mutation envelope.
        OutputFormat::Json => {
            render_mutation_envelope(action, db_path, json!({ "task_reminder_mutation": result }))
        }
    }
}

pub(crate) fn run_task_reminder_set(
    task_id: &str,
    reminders: &[String],
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let task_id = TaskId::from_trusted(task_id.to_string());
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;
    let result = set_task_reminders_with_conn(&mut conn, &task_id, reminders)?;
    render_task_reminder_mutation(
        "task.reminder.set",
        "Set Lorvex task reminders",
        &db_path,
        result,
        format,
    )
}

pub(crate) fn run_task_reminder_clear(
    task_id: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let task_id = TaskId::from_trusted(task_id.to_string());
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;
    let result = set_task_reminders_with_conn(&mut conn, &task_id, &[])?;
    render_task_reminder_mutation(
        "task.reminder.clear",
        "Cleared Lorvex task reminders",
        &db_path,
        result,
        format,
    )
}

pub(crate) fn run_task_reminder_add(
    task_id: &str,
    reminder_at: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let task_id = TaskId::from_trusted(task_id.to_string());
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;
    let result = add_task_reminder_with_conn(&mut conn, &task_id, reminder_at)?;
    render_task_reminder_mutation(
        "task.reminder.add",
        "Added Lorvex task reminder",
        &db_path,
        result,
        format,
    )
}

pub(crate) fn run_task_reminder_remove(
    task_id: &str,
    reminder_id: &str,
    format: OutputFormat,
) -> Result<String, crate::error::CliError> {
    let task_id = TaskId::from_trusted(task_id.to_string());
    let reminder_id = ReminderId::from_trusted(reminder_id.to_string());
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;
    let result = remove_task_reminder_with_conn(&mut conn, &task_id, &reminder_id)?;
    render_task_reminder_mutation(
        "task.reminder.remove",
        "Removed Lorvex task reminder",
        &db_path,
        result,
        format,
    )
}
