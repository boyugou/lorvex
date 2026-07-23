//! Inline coverage for shared helpers and per-surface entry points.
//! Mirrors the convention used in `mcp-server/src/error/tests.rs` —
//! the parent `mod.rs` declares `#[cfg(test)] mod tests;` so this file
//! IS the tests submodule (no nested `mod tests { }` wrapper).

use lorvex_domain::CalendarAiAccessMode;

use super::super::recurrence::parse_ymd;
use super::blocking::{
    get_day_blocking_ranges, provider_stale_scopes, timeline_item_to_blocking_range,
};

/// a timed event with `start_time` set but `end_time`
/// missing must NOT synthesize a phantom 60-minute block. The
/// previous default (`start_minutes + 60`) painted an hour-long
/// busy window in the daily-schedule UI for events the source ICS
/// deliberately left timeless (RFC 5545 §3.6.1 point events).
#[test]
fn timeline_item_to_blocking_range_drops_point_event_without_end_time() {
    use crate::calendar_timeline::types::{
        CalendarTimelineItem, CalendarTimelineItemFields, TimelineSource,
    };
    let query_date = parse_ymd("2026-04-26").expect("parse date");
    let stale_scopes = std::collections::HashSet::new();
    use lorvex_domain::time::{Date, TimeOfDay};
    let item = CalendarTimelineItem::new(CalendarTimelineItemFields {
        source: TimelineSource::Canonical,
        editable: true,
        id: "evt-1".to_string(),
        title: "Point event".to_string(),
        start_date: Date::parse("2026-04-26").unwrap(),
        start_time: Some(TimeOfDay::parse("09:00").unwrap()),
        end_date: Some(Date::parse("2026-04-26").unwrap()),
        end_time: None, // <-- the bug surface
        all_day: false,
        location: None,
        color: None,
        event_type: "appointment".to_string(),
        person_name: None,
        timezone: None,
        provider_kind: None,
        provider_scope: None,
        is_recurring: false,
        source_time_kind: None,
        source_tzid: None,
        url: None,
        attendees_json: None,
    })
    .expect("typed timing for point-event fixture");
    let result = timeline_item_to_blocking_range(&item, query_date, &stale_scopes);
    assert!(
        result.is_none(),
        "timed event with no end_time must be a 0-length point event, not a phantom 60m block"
    );
}

/// a timed event WITH a real
/// `end_time` must still produce a blocking range with the
/// caller-supplied bounds. Pins that the new guard didn't
/// over-filter legitimate timed events.
#[test]
fn timeline_item_to_blocking_range_keeps_event_with_explicit_end_time() {
    use crate::calendar_timeline::types::{
        CalendarTimelineItem, CalendarTimelineItemFields, TimelineSource,
    };
    let query_date = parse_ymd("2026-04-26").expect("parse date");
    let stale_scopes = std::collections::HashSet::new();
    use lorvex_domain::time::{Date, TimeOfDay};
    let item = CalendarTimelineItem::new(CalendarTimelineItemFields {
        source: TimelineSource::Canonical,
        editable: true,
        id: "evt-2".to_string(),
        title: "Real meeting".to_string(),
        start_date: Date::parse("2026-04-26").unwrap(),
        start_time: Some(TimeOfDay::parse("10:00").unwrap()),
        end_date: Some(Date::parse("2026-04-26").unwrap()),
        end_time: Some(TimeOfDay::parse("11:30").unwrap()),
        all_day: false,
        location: None,
        color: None,
        event_type: "appointment".to_string(),
        person_name: None,
        timezone: None,
        provider_kind: None,
        provider_scope: None,
        is_recurring: false,
        source_time_kind: None,
        source_tzid: None,
        url: None,
        attendees_json: None,
    })
    .expect("typed timing for explicit-end-time fixture");
    let range = timeline_item_to_blocking_range(&item, query_date, &stale_scopes)
        .expect("real timed event must produce a blocking range");
    assert_eq!(range.start_minutes, 600);
    assert_eq!(range.end_minutes, 690);
}

#[test]
fn get_day_blocking_ranges_propagates_stale_scope_query_failures() {
    let conn = crate::open_db_in_memory().expect("open db");
    conn.execute("DROP TABLE provider_scope_runtime_state", [])
        .expect("drop provider scope state");

    let error = get_day_blocking_ranges(&conn, "2026-03-29", "UTC", CalendarAiAccessMode::Off)
        .expect_err("stale scope query should fail");

    let message = error.to_string();
    assert!(
        message.contains("provider_scope_runtime_state"),
        "unexpected error: {message}"
    );
}

/// Regression: `last_refresh_success_at` is stored in RFC 3339
/// form (`2026-04-10T12:34:56.789012Z`, T-separated) via
/// `sync_timestamp_now()`, but the stale-scope query previously
/// compared against `datetime('now', '-24 hours')` which returns a
/// SPACE-separated string. At position 10 `T (0x54)` sorts after
/// ` (0x20)`, so a row written just past 24 hours ago on the
/// same wall-clock date was incorrectly considered fresh —
/// skipping its background refresh. This is the same lex bug R5
/// fixed for retention cleanup. The fix uses
/// `strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-24 hours')` so both
/// sides share the `T` separator.
///
/// This test places a row 1 second past the 24-hour cutoff.
/// Both timestamps land on the same wall-clock date so the
/// date-prefix portion of the lex comparison is identical, and
/// the T-vs-space mismatch at position 10 is the only thing
/// driving the comparison. The buggy code would flip the
/// comparison and leave this row un-flagged. It's also paired
/// with a clearly-old (48-hour) row that catches the
/// common case (date-prefix differs; both code paths return it).
#[test]
fn provider_stale_scopes_flags_rows_older_than_24h_with_rfc3339_timestamps() {
    use chrono::{Duration, SecondsFormat, Utc};

    let conn = crate::open_db_in_memory().expect("open db");

    // Row 1: 24 hours and 1 minute old. Shares the same
    // wall-clock date as the SQL cutoff (by construction — both
    // are ~24h before now). Forces the T-vs-space bug boundary.
    //
    // the original 1-second margin could alias
    // against clock drift between the test's `Utc::now()` and
    // the SQL's own `now` evaluation (tens of ms gap is normal
    // under parallel CI load), producing a flaky test that
    // would pass locally and fail intermittently on CI near
    // local midnight. 1 minute is well outside any realistic
    // wall-clock drift while preserving the same-date-prefix
    // property that makes the T-vs-space bug observable.
    let now = Utc::now();
    let boundary_ts = (now - Duration::hours(24) - Duration::minutes(1))
        .to_rfc3339_opts(SecondsFormat::Micros, true);
    conn.execute(
        "INSERT INTO provider_scope_runtime_state
            (provider_kind, provider_scope, enabled, availability_state,
             last_refresh_attempt_at, last_refresh_success_at, last_refresh_result, last_error)
         VALUES ('eventkit', 'scope-boundary', 1, 'enabled', ?1, ?1, 'success', NULL)",
        [&boundary_ts],
    )
    .expect("insert boundary row");

    // Row 2: clearly 48 hours old. Date prefix differs from the
    // cutoff, so this row is flagged by both the buggy and fixed
    // code. Guards against the test accidentally passing because
    // the query crashed or returned nothing.
    let far_old_ts = (now - Duration::hours(48)).to_rfc3339_opts(SecondsFormat::Micros, true);
    conn.execute(
        "INSERT INTO provider_scope_runtime_state
            (provider_kind, provider_scope, enabled, availability_state,
             last_refresh_attempt_at, last_refresh_success_at, last_refresh_result, last_error)
         VALUES ('eventkit', 'scope-far-old', 1, 'enabled', ?1, ?1, 'success', NULL)",
        [&far_old_ts],
    )
    .expect("insert far-old row");

    // Row 3: 1 hour ago — must NOT be considered stale.
    let fresh_ts = (now - Duration::hours(1)).to_rfc3339_opts(SecondsFormat::Micros, true);
    conn.execute(
        "INSERT INTO provider_scope_runtime_state
            (provider_kind, provider_scope, enabled, availability_state,
             last_refresh_attempt_at, last_refresh_success_at, last_refresh_result, last_error)
         VALUES ('eventkit', 'scope-fresh', 1, 'enabled', ?1, ?1, 'success', NULL)",
        [&fresh_ts],
    )
    .expect("insert fresh row");

    let stale = provider_stale_scopes(&conn).expect("query should succeed");
    assert!(
        stale.contains(&("eventkit".to_string(), "scope-boundary".to_string())),
        "row 1s past the 24h cutoff must be reported as stale \
         (bug boundary: row and cutoff share the same date; T-vs-space \
         lex bug flips the comparison in buggy code); got {stale:?}"
    );
    assert!(
        stale.contains(&("eventkit".to_string(), "scope-far-old".to_string())),
        "48h-old row must be reported as stale; got {stale:?}"
    );
    assert!(
        !stale.contains(&("eventkit".to_string(), "scope-fresh".to_string())),
        "row from 1h ago must NOT be reported as stale; got {stale:?}"
    );
}
