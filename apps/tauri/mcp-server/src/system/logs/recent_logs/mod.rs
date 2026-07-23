mod ai_changelog;
mod error_logs;
mod sync_outbox;

use crate::contract::{
    GetRecentLogsArgs, LogLevelFilter, LogSourceFilter, RECENT_LOG_FETCH_CAP, RECENT_LOG_FETCH_MIN,
    RECENT_LOG_LIMIT_CAP, RECENT_LOG_LIMIT_DEFAULT,
};
use crate::error::McpError;
use crate::system::handler_support::{
    bounded_limit_or_default, merge_requested_levels, merge_requested_sources, next_offset_for_page,
};
use rusqlite::Connection;
use serde_json::{json, Value};
use std::collections::HashSet;

pub(super) struct RecentLogCollection<'a> {
    pub(super) since: Option<&'a str>,
    pub(super) fetch_limit: u32,
    pub(super) active_levels: &'a HashSet<LogLevelFilter>,
    pub(super) include_details: bool,
    pub(super) redact: bool,
    pub(super) source_counts: &'a mut Value,
    pub(super) malformed_source_counts: &'a mut Value,
    pub(super) merged: &'a mut Vec<Value>,
}

pub(crate) fn get_recent_logs(
    conn: &Connection,
    args: GetRecentLogsArgs,
) -> Result<String, McpError> {
    let GetRecentLogsArgs {
        limit,
        offset,
        since,
        level,
        levels,
        source,
        sources,
        include_details,
        redact,
    } = args;
    let limit = bounded_limit_or_default(limit, RECENT_LOG_LIMIT_DEFAULT, RECENT_LOG_LIMIT_CAP);
    let offset = offset.unwrap_or(0);
    // widen the per-source fetch envelope so the
    // post-merge slice has enough rows to skip past the requested
    // offset. The merge already over-fetches 3× to keep cross-source
    // ordering stable when sources skew toward one stream; add the
    // offset on top so deep pagination stays accurate.
    let fetch_limit = (limit.saturating_mul(3).saturating_add(offset))
        .clamp(RECENT_LOG_FETCH_MIN, RECENT_LOG_FETCH_CAP);
    let include_details = include_details.unwrap_or(false);
    let redact = redact.unwrap_or(true);

    let requested_levels = merge_requested_levels(level, levels);
    let requested_sources = merge_requested_sources(source, sources);
    let active_levels: HashSet<LogLevelFilter> = requested_levels.into_iter().collect();
    let active_sources: HashSet<LogSourceFilter> = requested_sources.into_iter().collect();

    let mut source_counts = json!({
        "error_log": 0,
        "ai_changelog": 0,
        "sync_outbox": 0,
    });
    let mut malformed_source_counts = json!({
        "error_log": 0,
        "ai_changelog": 0,
        "sync_outbox": 0,
    });
    let mut merged: Vec<Value> = Vec::new();
    let mut collection = RecentLogCollection {
        since: since.as_deref(),
        fetch_limit,
        active_levels: &active_levels,
        include_details,
        redact,
        source_counts: &mut source_counts,
        malformed_source_counts: &mut malformed_source_counts,
        merged: &mut merged,
    };

    if active_sources.contains(&LogSourceFilter::ErrorLog) {
        error_logs::append_error_log_entries(conn, &mut collection)?;
    }

    if active_sources.contains(&LogSourceFilter::AiChangelog) {
        ai_changelog::append_ai_changelog_entries(conn, &mut collection)?;
    }

    if active_sources.contains(&LogSourceFilter::SyncOutbox) {
        sync_outbox::append_sync_outbox_entries(conn, &mut collection)?;
    }

    merged.sort_by(|a, b| {
        let a_ts = a
            .get("timestamp")
            .and_then(Value::as_str)
            .unwrap_or_default();
        let b_ts = b
            .get("timestamp")
            .and_then(Value::as_str)
            .unwrap_or_default();
        b_ts.cmp(a_ts)
    });
    let offset_usize = usize::try_from(offset).unwrap_or(0);
    let limit_usize = usize::try_from(limit).unwrap_or(0);
    // skip leading rows up to `offset` then take
    // `limit`. Truncation tracks whether anything beyond the slice
    // remains, accounting for offset overflow.
    let total_after_skip = merged.len().saturating_sub(offset_usize);
    let truncated = total_after_skip > limit_usize;
    let entries: Vec<Value> = merged
        .into_iter()
        .skip(offset_usize)
        .take(limit_usize)
        .collect();
    let returned = entries.len() as i64;
    let consumed = i64::from(offset).saturating_add(returned);
    let next_offset = next_offset_for_page(truncated, consumed, returned);

    let payload = json!({
        "count": entries.len(),
        "limit": limit,
        "offset": offset,
        "truncated": truncated,
        "next_offset": next_offset,
        "redaction_applied": redact,
        "details_included": include_details,
        "source_counts": source_counts,
        "malformed_source_counts": malformed_source_counts,
        "entries": entries,
    });
    Ok(serde_json::to_string(&payload)?)
}
