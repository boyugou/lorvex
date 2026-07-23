//! `get_day_blocking_ranges` — derives schedulable-minute occupancy
//! windows for a single date from the same projected-occurrence stream
//! used by the timeline query, then merges overlapping ranges so
//! duplicate provider observations don't double-count as separate
//! blockers.

use crate::error::StoreError;
use chrono::{NaiveDate, Timelike};
use lorvex_domain::CalendarAiAccessMode;
use rusqlite::Connection;

use super::super::recurrence::parse_ymd;
use super::super::types::{BlockingEventRange, CalendarTimelineItem, TimelineSource};
use super::redact_provider_details;
use super::timeline::{query_canonical_timeline, query_provider_timeline};

/// Retrieve time ranges that block scheduling on a single `date`.
///
/// Blocking ranges are derived from the same projected occurrence stream as
/// the timeline query, so recurring membership and timezone projection use a
/// single shared source of truth. All-day events are excluded because they
/// block the date, not a schedulable minute window.
///
/// The `access_mode` parameter controls provider-event inclusion and
/// detail redaction (same semantics as `get_calendar_timeline`).
///
/// `anchor_timezone` is the user's IANA timezone (e.g. `"America/New_York"`).
/// All occurrence projection happens into this timezone before blocking
/// windows are computed.
///
/// The result is sorted by `(start_minutes ASC, end_minutes DESC)`.
pub fn get_day_blocking_ranges(
    conn: &Connection,
    date: &str,
    anchor_timezone: &str,
    access_mode: CalendarAiAccessMode,
) -> Result<Vec<BlockingEventRange>, StoreError> {
    let query_date = parse_ymd(date)
        .map_err(|_| StoreError::Validation("date: invalid YYYY-MM-DD".to_string()))?;

    let stale_scopes = provider_stale_scopes(conn)?;

    let mut items = query_canonical_timeline(conn, query_date, query_date, anchor_timezone)?;

    if access_mode.includes_provider() {
        let mut provider_items =
            query_provider_timeline(conn, query_date, query_date, anchor_timezone)?;
        if !access_mode.includes_details() {
            for item in &mut provider_items {
                redact_provider_details(item);
            }
        }
        items.extend(provider_items);
    }

    let mut ranges = Vec::new();
    for item in items {
        if let Some(range) = timeline_item_to_blocking_range(&item, query_date, &stale_scopes) {
            ranges.push(range);
        }
    }

    ranges.sort_by(|a, b| {
        a.start_minutes
            .cmp(&b.start_minutes)
            .then(b.end_minutes.cmp(&a.end_minutes))
    });

    // Normalize occupancy: merge overlapping ranges so duplicate provider
    // observations don't double-count as separate blockers (spec doc 14/19).
    let ranges = normalize_blocking_occupancy(ranges);

    Ok(ranges)
}

pub(super) fn timeline_item_to_blocking_range(
    item: &CalendarTimelineItem,
    query_date: NaiveDate,
    stale_scopes: &std::collections::HashSet<(String, String)>,
) -> Option<BlockingEventRange> {
    if item.all_day() {
        return None;
    }

    // dates are typed `Date` so corrupt rows are
    // already rejected at construction; the previous `.ok()?` on
    // a runtime parse no longer applies.
    let start_date = item.start_date().as_naive_date();
    let end_date = item.end_date().map_or(start_date, |d| d.as_naive_date());
    if start_date > query_date || end_date < query_date {
        return None;
    }

    let start_minutes = if start_date < query_date {
        0
    } else {
        let start_time = item.start_time()?;
        let nt = start_time.as_naive_time();
        i64::from(nt.hour() * 60 + nt.minute())
    };

    let end_minutes = if end_date > query_date {
        1440
    } else if let Some(end_time) = item.end_time() {
        let nt = end_time.as_naive_time();
        i64::from(nt.hour() * 60 + nt.minute())
    } else {
        // a timed event without explicit `end_time` is a
        // RFC 5545 §3.6.1 "point event" — anchored at the start, no
        // duration. The previous `start_minutes + 60` fallback drew
        // a phantom 60-minute busy window in the daily-schedule UI
        // for events that the source ICS deliberately left timeless.
        // Treat as zero-length and let the guard below filter it
        // out so the schedule pane doesn't paint a fake block.
        start_minutes
    };

    // collapse the previous `end_minutes <= 0 ||
    // start_minutes >= 1440` guard into a single non-positive-window
    // check. Zero-length point events (`end == start`) and any range
    // that ends at or before its start contribute no blockable
    // minutes, so they must NOT enter the blocking-range vector.
    if end_minutes <= start_minutes || start_minutes >= 1440 {
        return None;
    }

    let stale = item
        .provider_kind
        .as_ref()
        .zip(item.provider_scope.as_ref())
        .is_some_and(|(kind, scope)| stale_scopes.contains(&(kind.clone(), scope.clone())));

    Some(BlockingEventRange {
        source: item.source.clone(),
        canonical_event_id: (item.source == TimelineSource::Canonical).then(|| item.id.clone()),
        title: item.title.clone(),
        start_minutes: start_minutes.max(0),
        end_minutes: end_minutes.min(1440),
        stale,
    })
}

pub(super) fn provider_stale_scopes(
    conn: &Connection,
) -> Result<std::collections::HashSet<(String, String)>, StoreError> {
    // IMPORTANT: `last_refresh_success_at` is stored via
    // `sync_timestamp_now()` in RFC 3339 form
    // (`2026-04-10T11:34:56.789012Z`, T-separated, microsecond
    // precision). `datetime('now', '-24 hours')` returns a
    // SPACE-separated string (`2026-04-10 12:34:56`) with only
    // second precision. A string comparison `col < cutoff` then
    // compares `T (0x54)` against ` ` (0x20) at position 10, so a
    // row written 25 hours ago on the same wall-clock date as now
    // is incorrectly considered fresh — skipping its background
    // refresh. This is the same lex bug R5 fixed for retention
    // cleanup. Use `strftime('%Y-%m-%dT%H:%M:%fZ', ...)` so the
    // cutoff shares the T separator and the comparison proceeds
    // through the time portion correctly.
    Ok(conn
        .prepare_cached(
            "SELECT provider_kind, provider_scope FROM provider_scope_runtime_state \
         WHERE last_refresh_success_at IS NOT NULL \
           AND last_refresh_success_at < strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-24 hours')",
        )
        .and_then(|mut stmt| {
            let rows = stmt.query_map([], |row| Ok((row.get(0)?, row.get(1)?)))?;
            rows.collect::<Result<std::collections::HashSet<_>, _>>()
        })?)
}

/// Merge overlapping blocking ranges into non-overlapping occupancy.
/// When two ranges overlap (e.g., same event from EventKit and .ics),
/// the merged range preserves the earliest start and latest end.
/// Canonical events are preferred over provider events for the merged title.
fn normalize_blocking_occupancy(sorted: Vec<BlockingEventRange>) -> Vec<BlockingEventRange> {
    if sorted.len() <= 1 {
        return sorted;
    }
    let mut result: Vec<BlockingEventRange> = Vec::with_capacity(sorted.len());
    for range in sorted {
        if let Some(last) = result.last_mut() {
            if range.start_minutes < last.end_minutes {
                // Overlapping — extend the current range.
                if range.end_minutes > last.end_minutes {
                    last.end_minutes = range.end_minutes;
                }
                // Prefer canonical event identity over provider.
                if last.canonical_event_id.is_none() && range.canonical_event_id.is_some() {
                    last.canonical_event_id = range.canonical_event_id;
                    last.title = range.title;
                    last.source = range.source;
                }
                continue;
            }
        }
        result.push(range);
    }
    result
}
