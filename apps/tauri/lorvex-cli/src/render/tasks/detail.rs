//! Per-task detail card + post-action confirmation banner.

use lorvex_store::repositories::task::read;
use serde_json::json;
use std::path::Path;

use crate::cli::OutputFormat;
use crate::commands::shared::render_mutation_envelope;
use crate::error::CliError;

pub(crate) fn render_task_detail(
    task: &read::TaskRow,
    db_path: &Path,
    list_name: Option<&str>,
) -> String {
    let list_display = list_name.map_or_else(
        || task.core().list_id().to_string(),
        |name| format!("{name} ({})", task.core().list_id()),
    );
    // Borrow the optional fields with `as_deref().unwrap_or("none")` instead
    // of `.clone().unwrap_or_else(|| "none".to_string())` — the previous shape
    // allocated a fresh `String` for every present value (the clone) AND for
    // every absent one ("none" → owned). The borrowed form passes a `&str`
    // straight into the format machinery and skips both heap touches.
    let priority_display = task
        .core()
        .priority()
        .map_or(std::borrow::Cow::Borrowed("none"), |value| {
            std::borrow::Cow::Owned(value.to_string())
        });
    let due_display = task
        .scheduling()
        .due_date()
        .map_or(std::borrow::Cow::Borrowed("none"), |d| {
            std::borrow::Cow::Owned(d.to_string())
        });
    let planned_display = task
        .scheduling()
        .planned_date()
        .map_or(std::borrow::Cow::Borrowed("none"), |d| {
            std::borrow::Cow::Owned(d.to_string())
        });
    format!(
        "Lorvex Task\nDB: {}\nID: {}\nTitle: {}\nStatus: {}\nDue: {}\nPlanned: {}\nPriority: {}\nList: {}\nNotes: {}\n",
        db_path.display(),
        task.core().id(),
        task.core().title(),
        task.core().status(),
        due_display,
        planned_display,
        priority_display,
        list_display,
        task.core().ai_notes().unwrap_or("none"),
    )
}

pub(crate) fn render_task_action_result(
    action: &str,
    task_id: &str,
    title: &str,
    db_path: &Path,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => {
            // Human banner shows only the trailing verb so a caller-
            // supplied `"task.complete"` renders as `COMPLETE`, not
            // `TASK.COMPLETE`. The JSON path emits the full action
            // verbatim (see below) for machine consumers.
            let verb = action.rsplit_once('.').map_or(action, |(_, v)| v);
            Ok(format!(
                "{} task {}\nTitle: {}\nDB: {}",
                verb.to_ascii_uppercase(),
                task_id,
                title,
                db_path.display()
            ))
        }
        // route through render_mutation_envelope —
        // this is a write-side confirmation banner. Caller is
        // responsible for passing the canonical `<domain>.<verb>`
        // action string (e.g. `"task.capture"`, `"task.complete"`)
        // — the renderer does NOT re-namespace, so the wire shape
        // matches every other CLI mutation surface
        // (`list.delete`, `habit.complete`, `calendar.update`,
        // `task.set_recurrence`, …).
        OutputFormat::Json => render_mutation_envelope(
            action,
            db_path,
            json!({
                "task_id": task_id,
                "title": title,
            }),
        ),
    }
}
