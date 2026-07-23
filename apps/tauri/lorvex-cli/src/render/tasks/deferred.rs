//! Deferred-tasks browse-view renderer.

use serde_json::json;
use std::fmt::Write;
use std::path::Path;

use crate::cli::OutputFormat;
use crate::commands::shared::render_query_envelope;
use crate::error::CliError;
use crate::models::DeferredTasksSnapshot;
use crate::render::format::style_empty_hint;

pub(crate) fn render_deferred_tasks_snapshot(
    db_path: &Path,
    snapshot: &DeferredTasksSnapshot,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => {
            let list_filter = snapshot.list_id.as_deref().unwrap_or("all");
            let mut rendered = format!(
                "Lorvex Deferred Tasks\nDB: {}\nList: {}\nTasks: {} returned / {} total{}\n",
                db_path.display(),
                list_filter,
                snapshot.returned,
                snapshot.total_matching,
                if snapshot.truncated {
                    " (truncated)"
                } else {
                    ""
                },
            );
            if snapshot.tasks.is_empty() {
                rendered.push_str(&style_empty_hint(
                    "No deferred tasks — nothing has been pushed back recently. Defer one with `lorvex task defer <task-id> --to <date>`.",
                ));
            } else {
                for task in &snapshot.tasks {
                    let when = task
                        .planned_date
                        .or(task.due_date)
                        .map(|value| format!(", date: {value}"))
                        .unwrap_or_default();
                    let reason = task
                        .last_defer_reason
                        .as_deref()
                        .map(|value| format!(", reason: {value}"))
                        .unwrap_or_default();
                    let _ = writeln!(
                        rendered,
                        "  - {}: {} (deferred {}x{}{})",
                        task.id, task.title, task.defer_count, when, reason
                    );
                }
            }
            Ok(rendered)
        }
        OutputFormat::Json => render_query_envelope(
            "query.tasks.deferred",
            db_path,
            json!({
                "deferred_tasks": snapshot,
            }),
        ),
    }
}
