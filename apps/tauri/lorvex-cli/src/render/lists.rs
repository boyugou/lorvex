//! List-related render helpers (collection / detail / health snapshot).

use lorvex_store::repositories::list_repo;
use serde_json::json;
use std::fmt::Write;
use std::path::Path;

use crate::cli::OutputFormat;
use crate::commands::shared::render_query_envelope;
use crate::error::CliError;
use crate::models::{ListHealthSnapshot, ListSummary, TaskSummary};
use crate::render::format::{style_banner, style_empty_hint, style_priority};

pub(crate) fn render_list_collection(
    db_path: &Path,
    lists: &[list_repo::ListWithCounts],
    format: OutputFormat,
) -> Result<String, CliError> {
    let summaries = lists
        .iter()
        .map(|row| ListSummary {
            id: row.list.id.clone(),
            name: row.list.name.clone(),
            open_count: row.open_count,
            total_count: row.total_count,
            color: row.list.color.clone(),
            icon: row.list.icon.clone(),
        })
        .collect::<Vec<_>>();

    match format {
        OutputFormat::Text => {
            let mut rendered = format!(
                "{}\nDB: {}\n",
                style_banner("Lorvex Lists"),
                db_path.display(),
            );
            if summaries.is_empty() {
                rendered.push_str(&style_empty_hint(
                    "No lists yet — create one with `lorvex list create \"<name>\"`.",
                ));
            } else {
                for list in &summaries {
                    let _ = writeln!(
                        rendered,
                        "  - {}: {} (open: {}, total: {})",
                        list.id, list.name, list.open_count, list.total_count
                    );
                }
            }
            Ok(rendered)
        }
        OutputFormat::Json => render_query_envelope(
            "query.lists.collection",
            db_path,
            json!({ "lists": summaries }),
        ),
    }
}

pub(crate) fn render_list_health_snapshot(
    db_path: &Path,
    snapshot: &ListHealthSnapshot,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => {
            let mut rendered = format!(
                "Lorvex List Health\nDB: {}\nDate: {}\nLists: {} returned / {} total{}\n",
                db_path.display(),
                snapshot.date,
                snapshot.summary.returned_lists,
                snapshot.summary.total_lists,
                if snapshot.summary.truncated {
                    " (truncated)"
                } else {
                    ""
                },
            );
            if snapshot.lists.is_empty() {
                rendered.push_str(&style_empty_hint(
                    "No lists to score — create one with `lorvex list create \"<name>\"`, then capture tasks into it.",
                ));
            } else {
                for list in &snapshot.lists {
                    let _ = writeln!(
                        rendered,
                        "  - {}: {} (open: {}, overdue: {}, due today: {})",
                        list.id,
                        list.name,
                        list.open_count,
                        list.overdue_open_count,
                        list.due_today_open_count,
                    );
                }
            }
            Ok(rendered)
        }
        OutputFormat::Json => render_query_envelope(
            "query.lists.health",
            db_path,
            json!({
                "date": snapshot.date,
                "summary": snapshot.summary,
                "lists": snapshot.lists,
                "limits": snapshot.limits,
            }),
        ),
    }
}

pub(crate) fn render_list_detail(
    db_path: &Path,
    list: &list_repo::ListRow,
    tasks: &[TaskSummary],
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => {
            // `as_deref().unwrap_or("none")` borrows the description in
            // place. The previous `clone().unwrap_or_else(|| "none".to_string())`
            // allocated a fresh `String` for every present description AND for
            // every absent one — the `format!` call only needs a `&str`, so the
            // owned value was thrown away the moment it landed in the buffer.
            let mut rendered = format!(
                "Lorvex List\nDB: {}\nID: {}\nName: {}\nDescription: {}\n",
                db_path.display(),
                list.id,
                list.name,
                list.description.as_deref().unwrap_or("none"),
            );
            if tasks.is_empty() {
                rendered.push_str("Tasks:\n");
                rendered.push_str(&style_empty_hint(
                    "List is empty — capture a task into it with `lorvex task capture \"<title>\" --list <list-id>`.",
                ));
            } else {
                rendered.push_str("Tasks:\n");
                for task in tasks {
                    let mut suffix = format!(" [{}]", task.status);
                    if let Some(p) = task.priority {
                        let _ = write!(suffix, " {}", style_priority(Some(p)));
                    }
                    if let Some(ref due) = task.due_date {
                        let _ = write!(suffix, " due:{due}");
                    }
                    if let Some(planned) = task.planned_date {
                        // Only show planned date if it differs from due date
                        if task.due_date != Some(planned) {
                            let _ = write!(suffix, " planned:{planned}");
                        }
                    }
                    let short_id = if task.id.len() > 8 {
                        &task.id[..8]
                    } else {
                        &task.id
                    };
                    let _ = write!(suffix, " [{short_id}]");
                    let _ = writeln!(rendered, "  - {}{}", task.title, suffix);
                }
            }
            Ok(rendered)
        }
        OutputFormat::Json => render_query_envelope(
            "query.lists.detail",
            db_path,
            json!({
                "list": {
                    "id": list.id,
                    "name": list.name,
                    "color": list.color,
                    "icon": list.icon,
                    "description": list.description,
                    "ai_notes": list.ai_notes,
                    "created_at": list.created_at,
                    "updated_at": list.updated_at,
                    "version": list.version,
                },
                "tasks": tasks,
            }),
        ),
    }
}
