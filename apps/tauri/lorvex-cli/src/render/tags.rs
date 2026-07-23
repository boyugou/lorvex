//! Tag-collection render helper.

use serde_json::json;
use std::fmt::Write;
use std::path::Path;

use crate::cli::OutputFormat;
use crate::commands::shared::render_query_envelope;
use crate::error::CliError;
use crate::models::TagSummary;
use crate::render::format::style_empty_hint;

pub(crate) fn render_tag_collection(
    db_path: &Path,
    tags: &[TagSummary],
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => {
            let mut rendered = format!("Lorvex Tags\nDB: {}\n", db_path.display());
            if tags.is_empty() {
                rendered.push_str(&style_empty_hint(
                    "No tags yet — assistants can attach tags via `task_update`, or add them on a task with `lorvex task update <id> --add-tag <name>`.",
                ));
            } else {
                for tag in tags {
                    let _ = writeln!(
                        rendered,
                        "  - {} ({} task{})",
                        tag.display_name,
                        tag.task_count,
                        if tag.task_count == 1 { "" } else { "s" },
                    );
                }
            }
            Ok(rendered)
        }
        OutputFormat::Json => {
            render_query_envelope("query.tags.collection", db_path, json!({ "tags": tags }))
        }
    }
}
