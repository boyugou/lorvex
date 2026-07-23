//! Command handlers for the CLI's body / ai_notes / recurrence-exception
//! writes that mirror the matching MCP tools. Thin wrappers around the
//! canonical `*_with_conn` helpers in [`super::body_writes_effects`].

use crate::startup_maintenance::open_db_at_path;
use lorvex_domain::TaskId;
use lorvex_runtime::resolve_db_path;
use serde_json::json;

use crate::cli::OutputFormat;
use crate::commands::shared::render_mutation_envelope;
use crate::error::CliError;

use super::body_writes_effects::{
    add_ai_notes_with_conn, add_task_recurrence_exception_with_conn, append_to_task_body_with_conn,
    remove_task_recurrence_exception_with_conn,
};

#[cfg(test)]
#[path = "body_writes_tests.rs"]
mod tests;

fn render_task_write_envelope(
    action: &str,
    text_heading: &str,
    db_path: &std::path::Path,
    task: &lorvex_store::repositories::task::read::TaskRow,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => Ok(format!(
            "{text_heading}\nDB: {}\nTask: {} ({})\nStatus: {}\n",
            db_path.display(),
            task.core().title(),
            task.core().id(),
            task.core().status(),
        )),
        OutputFormat::Json => render_mutation_envelope(action, db_path, json!({ "task": task })),
    }
}

pub(crate) fn run_task_append_body(
    task_id: &str,
    text: &str,
    format: OutputFormat,
) -> Result<String, CliError> {
    let task_id = TaskId::from_trusted(task_id.to_string());
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;
    let task = append_to_task_body_with_conn(&mut conn, &task_id, text)?;
    render_task_write_envelope(
        "task.append_body",
        "Appended to Lorvex task body",
        &db_path,
        &task,
        format,
    )
}

pub(crate) fn run_task_add_ai_notes(
    task_id: &str,
    notes: &str,
    format: OutputFormat,
) -> Result<String, CliError> {
    let task_id = TaskId::from_trusted(task_id.to_string());
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;
    let task = add_ai_notes_with_conn(&mut conn, &task_id, notes)?;
    render_task_write_envelope(
        "task.add_ai_notes",
        "Appended Lorvex AI notes",
        &db_path,
        &task,
        format,
    )
}

pub(crate) fn run_task_add_recurrence_exception(
    task_id: &str,
    date: &str,
    format: OutputFormat,
) -> Result<String, CliError> {
    let task_id = TaskId::from_trusted(task_id.to_string());
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;
    let task = add_task_recurrence_exception_with_conn(&mut conn, &task_id, date)?;
    render_task_write_envelope(
        "task.recurrence_exception.add",
        "Added Lorvex task recurrence exception",
        &db_path,
        &task,
        format,
    )
}

pub(crate) fn run_task_remove_recurrence_exception(
    task_id: &str,
    date: &str,
    format: OutputFormat,
) -> Result<String, CliError> {
    let task_id = TaskId::from_trusted(task_id.to_string());
    let db_path = resolve_db_path();
    let mut conn = open_db_at_path(&db_path)?;
    let task = remove_task_recurrence_exception_with_conn(&mut conn, &task_id, date)?;
    render_task_write_envelope(
        "task.recurrence_exception.remove",
        "Removed Lorvex task recurrence exception",
        &db_path,
        &task,
        format,
    )
}
