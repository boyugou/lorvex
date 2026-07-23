//! Task reminder snapshot renderer.

use serde_json::json;
use std::fmt::Write;
use std::path::Path;

use crate::cli::OutputFormat;
use crate::commands::shared::render_query_envelope;
use crate::error::CliError;
use crate::models::TaskReminderSnapshot;
use crate::render::format::style_empty_hint;

pub(crate) fn render_task_reminder_snapshot(
    label: &str,
    db_path: &Path,
    snapshot: &TaskReminderSnapshot,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => {
            let window = snapshot
                .hours_window
                .map(|hours| format!("\nWindow: next {hours}h"))
                .unwrap_or_default();
            let total = if snapshot.total_matching < 0 {
                "unknown".to_string()
            } else {
                snapshot.total_matching.to_string()
            };
            let mut rendered = format!(
                "Lorvex {label} Reminders\nDB: {}{}\nReminders: {} returned / {} total{}\n",
                db_path.display(),
                window,
                snapshot.returned,
                total,
                if snapshot.truncated {
                    " (truncated)"
                } else {
                    ""
                },
            );
            if snapshot.reminders.is_empty() {
                rendered.push_str(&style_empty_hint(
                    "No reminders in window — schedule one with `lorvex task remind <task-id> --at <iso>`.",
                ));
            } else {
                for reminder in &snapshot.reminders {
                    let due_date = reminder
                        .task_due_date
                        .as_ref()
                        .map(|value| format!(", task due: {value}"))
                        .unwrap_or_default();
                    let _ = writeln!(
                        rendered,
                        "  - {}: {} -> {} ({}, state: {}{})",
                        reminder.id,
                        reminder.reminder_at,
                        reminder.task_title,
                        reminder.task_id,
                        reminder.delivery_state,
                        due_date,
                    );
                }
            }
            Ok(rendered)
        }
        OutputFormat::Json => render_query_envelope(
            "query.tasks.reminders",
            db_path,
            json!({
                "label": label,
                "task_reminders": snapshot,
            }),
        ),
    }
}
