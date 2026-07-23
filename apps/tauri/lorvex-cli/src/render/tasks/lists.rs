//! Task list/collection/snapshot renderers.
//!
//! Three surfaces share a near-identical text shape (banner → empty
//! hint → bulleted rows) but diverge on JSON envelope action and on
//! which row metadata is shown — per-item `when`, vs. status/priority/list,
//! etc. Co-located here because they share the empty-hint
//! lookup tables in `super::hints`; the section/collection
//! helpers are pair-used by the focus/dashboard surfaces upstream.

use serde_json::json;
use std::fmt::Write;
use std::path::Path;

use crate::cli::OutputFormat;
use crate::commands::shared::render_query_envelope;
use crate::error::CliError;
use crate::models::{TaskListItem, TaskListSnapshot, TaskSummary};
use crate::render::format::{style_banner, style_empty_hint, style_priority, style_section_header};

use super::hints::{empty_hint_for_collection, empty_hint_for_section};

pub(crate) fn render_task_section(title: &str, items: &[TaskListItem]) -> String {
    let mut rendered = String::new();
    let _ = write!(rendered, "\n{}:\n", style_section_header(title));
    if items.is_empty() {
        rendered.push_str(&style_empty_hint(empty_hint_for_section(title)));
        return rendered;
    }
    for item in items {
        let when = item
            .when
            .as_deref()
            .map(|value| format!(" ({value})"))
            .unwrap_or_default();
        let _ = writeln!(rendered, "  - {}: {}{}", item.id, item.title, when);
    }
    rendered
}

pub(crate) fn render_task_collection(
    label: &str,
    db_path: &Path,
    tasks: Vec<TaskSummary>,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => {
            let mut rendered = format!(
                "{}\nDB: {}\n",
                style_banner(&format!("Lorvex {label}")),
                db_path.display(),
            );
            if tasks.is_empty() {
                rendered.push_str(&style_empty_hint(empty_hint_for_collection(label)));
            } else {
                for task in tasks {
                    let when = task
                        .planned_date
                        .or(task.due_date)
                        .map(|value| format!(" ({value})"))
                        .unwrap_or_default();
                    let _ = writeln!(rendered, "  - {}: {}{}", task.id, task.title, when);
                }
            }
            Ok(rendered)
        }
        // route through render_query_envelope so the
        // wire shape `{action, db_path, ...payload}` stays consistent
        // with the mutation envelope and downstream `jq '.action'`
        // works.
        OutputFormat::Json => render_query_envelope(
            "query.tasks.collection",
            db_path,
            json!({
                "label": label,
                "tasks": tasks,
            }),
        ),
    }
}

pub(crate) fn render_task_list_snapshot(
    db_path: &Path,
    snapshot: &TaskListSnapshot,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => {
            let mut rendered = format!(
                "{}\nDB: {}\nTasks: {} returned / {} total{}\n",
                style_banner("Lorvex Tasks"),
                db_path.display(),
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
                    "No tasks match this filter — drop the `--status` / `--list` constraints, or widen the query with `lorvex task ls --include-completed`.",
                ));
            } else {
                for task in &snapshot.tasks {
                    let when = task
                        .planned_date
                        .or(task.due_date)
                        .map(|value| format!(", date: {value}"))
                        .unwrap_or_default();
                    let priority = task
                        .priority
                        .map(|value| format!(", {}", style_priority(Some(value))))
                        .unwrap_or_default();
                    let _ = writeln!(
                        rendered,
                        "  - {}: {} ({}, list: {}{}{})",
                        task.id, task.title, task.status, task.list_id, priority, when
                    );
                }
            }
            Ok(rendered)
        }
        OutputFormat::Json => render_query_envelope(
            "query.tasks.list",
            db_path,
            json!({
                "task_list": snapshot,
            }),
        ),
    }
}
