//! Diagnostics tools.
//!
//! Owns the AI-side log surface (AI changelog and cross-source recent logs).

use crate::contract::{GetAiChangelogArgs, GetRecentLogsArgs};
use crate::system::logs;

crate::server::tool_macros::mcp_tools! {
    router = workflow_logs_tool_router;

    read get_ai_changelog(GetAiChangelogArgs) -> logs::get_ai_changelog;
        "Read the AI-authored operation changelog for recent write activity. This is the focused history surface for AI writes, with entries containing id, timestamp, operation, entity_type, entity_id, summary, and mcp_tool.";

    read get_recent_logs(GetRecentLogsArgs) -> logs::get_recent_logs;
        "Diagnostics/debugging tool: read the unified recent log stream across error_logs, ai_changelog, and sync_outbox. Use this when investigating runtime, sync, or AI-side issues that need cross-source context. Returns {count, truncated, redaction_applied, details_included, source_counts, malformed_source_counts, entries}.";
}
