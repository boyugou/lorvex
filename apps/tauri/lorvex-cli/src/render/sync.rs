//! Sync / changelog render helpers.

use lorvex_store::repositories::ai_changelog_query::AiChangelogEntry;
use lorvex_store::SyncStatusSnapshot;
use serde_json::json;
use std::fmt::Write;
use std::path::Path;

use crate::cli::OutputFormat;
use crate::commands::shared::render_query_envelope;
use crate::error::CliError;
use crate::models::PendingOutboxEntry;
use crate::render::format::style_empty_hint;

pub(crate) fn render_pending_outbox_entries(
    db_path: &Path,
    entries: &[PendingOutboxEntry],
    limit: u32,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => {
            let mut rendered = format!(
                "Lorvex Pending Sync Outbox\nDB: {}\nEntries: {} returned (limit {})\n",
                db_path.display(),
                entries.len(),
                limit,
            );
            if entries.is_empty() {
                rendered.push_str(&style_empty_hint(
                    "Outbox is empty — sync caught up. Force a push with `lorvex sync push` if expected entries are missing.",
                ));
            } else {
                for entry in entries {
                    let retry = if entry.retry_count > 0 {
                        format!(", retries: {}", entry.retry_count)
                    } else {
                        String::new()
                    };
                    let _ = writeln!(
                        rendered,
                        "  - #{} {}:{} {} (created: {}{})",
                        entry.id,
                        entry.entity_type,
                        entry.entity_id,
                        entry.operation,
                        entry.created_at,
                        retry,
                    );
                }
            }
            Ok(rendered)
        }
        // #3033-M6: route through the canonical envelope helper so a
        // future wire-format bump (e.g. a `cli_version` discriminator)
        // applies uniformly across read and write surfaces. The
        // `query.sync.outbox.pending` action name is a `query.*`
        // namespace so consumers can still distinguish read from write
        // by `.action` prefix.
        OutputFormat::Json => render_query_envelope(
            "query.sync.outbox.pending",
            db_path,
            json!({
                "limit": limit,
                "count": entries.len(),
                "entries": entries,
            }),
        ),
    }
}

pub(crate) fn render_sync_status(
    db_path: &Path,
    status: &SyncStatusSnapshot,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => {
            let mut rendered = format!(
                "Lorvex Sync Status\nDB: {}\nBackend: {}{}\nDevice: {}\n",
                db_path.display(),
                status.sync_backend_kind_effective,
                if status.sync_backend_kind_malformed {
                    " (malformed preference)"
                } else {
                    ""
                },
                status.device_id.as_deref().unwrap_or("none"),
            );
            let _ = writeln!(
                rendered,
                "Outbox: pending {}, retrying {}, failed {}",
                status.pending_count, status.retrying_count, status.failed_count,
            );
            let _ = writeln!(
                rendered,
                "Pending inbox: {}\nTombstones: {}\nConflicts: {}",
                status.pending_inbox_count, status.tombstone_count, status.conflict_log_count,
            );
            let _ = writeln!(
                rendered,
                "iCal subscriptions: {} total, {} failing",
                status.ical_subscription_total_count, status.ical_subscription_failing_count,
            );
            if status.reseed_required {
                rendered.push_str("Reseed required: yes\n");
            }
            if let Some(error) = &status.last_error {
                let _ = writeln!(rendered, "Last error: {error}");
            }
            if let Some(last_success_at) = &status.last_success_at {
                let _ = writeln!(rendered, "Last success: {last_success_at}");
            }
            Ok(rendered)
        }
        // #3033-M6: same canonical envelope as the sibling renders.
        OutputFormat::Json => {
            render_query_envelope("query.sync.status", db_path, json!({ "status": status }))
        }
    }
}

pub(crate) fn render_ai_changelog(
    db_path: &Path,
    entries: &[AiChangelogEntry],
    limit: u32,
    format: OutputFormat,
) -> Result<String, CliError> {
    match format {
        OutputFormat::Text => {
            let mut rendered = format!(
                "Lorvex AI Changelog\nDB: {}\nEntries: {} returned (limit {})\n",
                db_path.display(),
                entries.len(),
                limit
            );
            if entries.is_empty() {
                rendered.push_str(&style_empty_hint(
                    "No AI changelog entries yet — every MCP write logs here. Issue a write through your assistant to see it.",
                ));
            } else {
                for entry in entries {
                    let entity_id = entry
                        .entity_id
                        .as_deref()
                        .map(|value| format!(" entity_id={value}"))
                        .unwrap_or_default();
                    let tool = entry
                        .mcp_tool
                        .as_deref()
                        .map(|value| format!(" tool={value}"))
                        .unwrap_or_default();
                    let _ = writeln!(
                        rendered,
                        "  - {} [{}] {} {}{}{} - {}",
                        entry.id,
                        entry.timestamp,
                        entry.operation,
                        entry.entity_type,
                        entity_id,
                        tool,
                        entry.summary
                    );
                }
            }
            Ok(rendered)
        }
        // #3033-M6: route through the canonical envelope helper.
        OutputFormat::Json => render_query_envelope(
            "query.sync.changelog",
            db_path,
            json!({
                "limit": limit,
                "count": entries.len(),
                "entries": entries,
            }),
        ),
    }
}
