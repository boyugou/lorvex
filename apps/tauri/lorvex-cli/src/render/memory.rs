//! AI memory render helpers (collection / detail / history).

use serde_json::json;
use std::fmt::Write;
use std::path::Path;

use crate::cli::OutputFormat;
use crate::commands::shared::render_query_envelope;
use crate::error::CliError;
use crate::render::format::style_empty_hint;

pub(crate) fn render_memory_collection(
    db_path: &Path,
    entries: &[lorvex_store::repositories::memory_repo::MemoryEntry],
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => {
            let mut rendered = format!("Lorvex AI Memories\nDB: {}\n", db_path.display());
            if entries.is_empty() {
                rendered.push_str(&style_empty_hint(
                    "No AI memory yet — let your assistant capture facts via `memory_upsert`, or seed one with `lorvex memory set <key> <content>`.",
                ));
            } else {
                for entry in entries {
                    let preview = if entry.content.len() > 80 {
                        // Find the nearest char boundary at or before 80 bytes
                        // to avoid panicking on multi-byte UTF-8 content.
                        let end = (0..=80)
                            .rev()
                            .find(|&i| entry.content.is_char_boundary(i))
                            .unwrap_or(0);
                        format!("{}...", &entry.content[..end])
                    } else {
                        entry.content.clone()
                    };
                    let _ = writeln!(rendered, "  - {}: {}", entry.key, preview);
                }
            }
            Ok(rendered)
        }
        OutputFormat::Json => render_query_envelope(
            "query.memory.collection",
            db_path,
            json!({ "memories": entries }),
        ),
    }
}

pub(crate) fn render_memory_detail(
    db_path: &Path,
    entry: &lorvex_store::repositories::memory_repo::MemoryEntry,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => Ok(format!(
            "Lorvex Memory\nDB: {}\nKey: {}\nUpdated: {}\n\n{}\n",
            db_path.display(),
            entry.key,
            entry.updated_at.as_string(),
            entry.content,
        )),
        // wrap the entry in the query envelope
        // could not key on `.action` like every other render.
        OutputFormat::Json => {
            render_query_envelope("query.memory.detail", db_path, json!({ "memory": entry }))
        }
    }
}

pub(crate) fn render_memory_history(
    db_path: &Path,
    key: &str,
    revisions: &[lorvex_store::repositories::memory_revision_repo::MemoryRevision],
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => {
            let mut rendered = format!(
                "Lorvex Memory History\nDB: {}\nKey: {key}\n",
                db_path.display()
            );
            if revisions.is_empty() {
                rendered.push_str(&style_empty_hint(
                    "No revisions on record — history is appended each time the key is written, so check back after the next update.",
                ));
            } else {
                for revision in revisions {
                    let source = revision
                        .source_revision_id
                        .as_deref()
                        .map(|id| format!(" from {id}"))
                        .unwrap_or_default();
                    let _ = writeln!(
                        rendered,
                        "  - {}: {}{} by {} at {}",
                        revision.id,
                        revision.operation,
                        source,
                        revision.actor,
                        revision.created_at
                    );
                }
            }
            Ok(rendered)
        }
        OutputFormat::Json => render_query_envelope(
            "query.memory.history",
            db_path,
            json!({
                "key": key,
                "count": revisions.len(),
                "revisions": revisions,
            }),
        ),
    }
}
