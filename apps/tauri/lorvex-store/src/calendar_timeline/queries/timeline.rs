//! `get_calendar_timeline` — range projection across canonical and
//! provider calendar events, with recurrence expansion and access-mode
//! redaction applied before the merged result is sorted.

use crate::error::StoreError;
use chrono::NaiveDate;
use lorvex_domain::naming::AVAILABILITY_STATE_ENABLED;
use lorvex_domain::CalendarAiAccessMode;
use rusqlite::Connection;

use super::super::expansion::RawCalendarRow;
use super::super::recurrence::parse_ymd;
use super::super::types::{CalendarTimelineItem, TimelineSource};
use super::{extend_with_tolerant_expansion, redact_provider_details};

/// Retrieve all calendar-event occurrences that overlap `[from, to]`.
///
/// The `access_mode` parameter controls provider-event inclusion and
/// detail redaction:
///
/// - `Off` — only canonical events are returned (provider data excluded).
/// - `BusyOnly` — provider events are included but detail fields (title,
///   location, person_name) are redacted to "Busy".
/// - `FullDetails` — provider events are included with full details.
///
/// Recurring events are expanded into individual occurrences.  The result
/// is sorted by `(start_date, start_time NULLS LAST, title)`.
pub fn get_calendar_timeline(
    conn: &Connection,
    from: &str,
    to: &str,
    access_mode: CalendarAiAccessMode,
    anchor_timezone: &str,
) -> Result<Vec<CalendarTimelineItem>, StoreError> {
    let from_date = parse_ymd(from)
        .map_err(|_| StoreError::Validation("from: invalid YYYY-MM-DD".to_string()))?;
    let to_date =
        parse_ymd(to).map_err(|_| StoreError::Validation("to: invalid YYYY-MM-DD".to_string()))?;

    let mut items = query_canonical_timeline(conn, from_date, to_date, anchor_timezone)?;

    if access_mode.includes_provider() {
        let mut provider_items =
            query_provider_timeline(conn, from_date, to_date, anchor_timezone)?;
        if !access_mode.includes_details() {
            for item in &mut provider_items {
                redact_provider_details(item);
            }
        }
        items.extend(provider_items);
    }

    // Sort: start_date ASC, start_time ASC (NULLS LAST), title ASC.
    items.sort_by(|a, b| {
        a.start_date()
            .cmp(&b.start_date())
            .then_with(|| match (a.start_time(), b.start_time()) {
                (Some(at), Some(bt)) => at.cmp(&bt),
                (Some(_), None) => std::cmp::Ordering::Less,
                (None, Some(_)) => std::cmp::Ordering::Greater,
                (None, None) => std::cmp::Ordering::Equal,
            })
            .then_with(|| a.title.cmp(&b.title))
    });

    Ok(items)
}

/// Query and expand canonical `calendar_events`.
///
/// the WHERE clause is split into a UNION ALL of three
/// index-friendly legs so the planner can use
/// `idx_calendar_events_recurring_start` (partial index on
/// `start_date WHERE recurrence IS NOT NULL`) for the recurring leg
/// and `idx_calendar_events_range_start` for the fixed-span leg.
/// The previous shape with `COALESCE(end_date, start_date) >= ?1`
/// was non-sargable and forced a full residual filter over every
/// row with `start_date <= ?2`. The Rust caller sorts the merged
/// result, so SQL ORDER BY is unnecessary (and would force a TEMP
/// B-TREE filesort across the UNION).
///
/// the recurring leg additionally prunes rules that have
/// already terminated via UNTIL by intersecting with the derived
/// `recurrence_end_date` column (a STORED generated column in the
/// schema — see `001_schema.sql`). A rule with
/// `UNTIL='2014-12-31'` no longer enters the result set when the
/// timeline window is in 2026, so Rust-side `expand_row_for_range` is
/// not invoked at all on those rows. The condition is
/// `recurrence_end_date IS NULL OR recurrence_end_date >= ?1` because
/// NULL covers two unbounded shapes — open-ended rules and
/// COUNT-bounded rules whose effective end can't be computed in pure
/// SQL — and we must not prune those.
///
/// The three legs are mutually exclusive:
///   - recurrence IS NOT NULL                       → recurring leg
///   - recurrence IS NULL AND end_date IS NOT NULL  → fixed-span leg
///   - recurrence IS NULL AND end_date IS NULL      → single-day leg
// Read date/time fields as raw strings inside the rusqlite mapper so
// a malformed `start_date` / `start_time` value (e.g. legacy peer
// import that sneaked past the schema CHECK, or hand-edited DB)
// surfaces as a `Some(Err)` we can log + skip per-row, instead of
// aborting the entire timeline query at the first bad row. The
// typed `Date` / `TimeOfDay` parsers are then applied below in the
// typed-conversion fallible block. Pre-typed-newtype the loader
// accepted any string and the parse error only fired in
// `project_item_to_anchor`; that's the contract the
// `timeline_skips_event_with_invalid_*` regression test pins.
type RawCanonicalTuple = (
    String,
    String,
    Option<String>,
    Option<String>,
    Option<String>,
    String,
    Option<String>,
    Option<String>,
    Option<String>,
    bool,
    Option<String>,
    Option<String>,
    String,
    Option<String>,
    Option<String>,
);

pub(super) fn query_canonical_timeline(
    conn: &Connection,
    from_date: NaiveDate,
    to_date: NaiveDate,
    anchor_timezone: &str,
) -> Result<Vec<CalendarTimelineItem>, StoreError> {
    let from_wide = (from_date - chrono::Duration::days(1))
        .format("%Y-%m-%d")
        .to_string();
    let to_wide = (to_date + chrono::Duration::days(1))
        .format("%Y-%m-%d")
        .to_string();
    let mut stmt = conn.prepare_cached(
        "SELECT id, title, recurrence, \
                (SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]') \
                 FROM calendar_event_recurrence_exceptions WHERE event_id = calendar_events.id), \
                timezone, \
                start_date, start_time, end_date, end_time, all_day, location, color, \
                event_type, person_name, url \
         FROM calendar_events \
         WHERE recurrence IS NOT NULL AND start_date <= ?2 \
           AND (recurrence_end_date IS NULL OR recurrence_end_date >= ?1) \
         UNION ALL \
         SELECT id, title, recurrence, \
                (SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]') \
                 FROM calendar_event_recurrence_exceptions WHERE event_id = calendar_events.id), \
                timezone, \
                start_date, start_time, end_date, end_time, all_day, location, color, \
                event_type, person_name, url \
         FROM calendar_events \
         WHERE recurrence IS NULL AND start_date <= ?2 \
           AND end_date IS NOT NULL AND end_date >= ?1 \
         UNION ALL \
         SELECT id, title, recurrence, \
                (SELECT NULLIF(json_group_array(exception_date ORDER BY exception_date), '[]') \
                 FROM calendar_event_recurrence_exceptions WHERE event_id = calendar_events.id), \
                timezone, \
                start_date, start_time, end_date, end_time, all_day, location, color, \
                event_type, person_name, url \
         FROM calendar_events \
         WHERE recurrence IS NULL AND end_date IS NULL \
           AND start_date BETWEEN ?1 AND ?2",
    )?;

    let rows = stmt.query_map(rusqlite::params![from_wide, to_wide], |row| {
        Ok::<RawCanonicalTuple, _>((
            row.get(0)?,
            row.get(1)?,
            row.get(2)?,
            row.get(3)?,
            row.get(4)?,
            row.get(5)?,
            row.get(6)?,
            row.get(7)?,
            row.get(8)?,
            row.get(9)?,
            row.get(10)?,
            row.get(11)?,
            row.get(12)?,
            row.get(13)?,
            row.get(14)?,
        ))
    })?;

    let mut items = Vec::new();
    for row in rows {
        let raw = row?;
        let raw_id = raw.0.clone();
        // The per-row try-block keeps the existing tolerant-skip
        // contract: a malformed `start_date` / `start_time` value (or
        // a typed-timing rule violation flagged by
        // `CalendarEventTiming::from_flat_fields`) drops just this
        // row to the error log instead of aborting the whole timeline
        // query. Pinned by the `timeline_skips_event_with_invalid_*`
        // regression suite.
        let parsed = (|| {
            let start_date = lorvex_domain::time::Date::parse(&raw.5).ok()?;
            let start_time = match raw.6.as_deref() {
                Some(s) => Some(lorvex_domain::time::TimeOfDay::parse(s).ok()?),
                None => None,
            };
            let end_date = match raw.7.as_deref() {
                Some(s) => Some(lorvex_domain::time::Date::parse(s).ok()?),
                None => None,
            };
            let end_time = match raw.8.as_deref() {
                Some(s) => Some(lorvex_domain::time::TimeOfDay::parse(s).ok()?),
                None => None,
            };
            let timing = lorvex_domain::CalendarEventTiming::from_flat_fields(
                start_date, start_time, end_date, end_time, raw.9,
            )
            .ok()?;
            Some(RawCalendarRow {
                item: CalendarTimelineItem {
                    source: TimelineSource::Canonical,
                    editable: true,
                    id: raw.0,
                    title: raw.1,
                    timing,
                    location: raw.10,
                    color: raw.11,
                    event_type: raw.12,
                    person_name: raw.13,
                    timezone: raw.4,
                    is_recurring: raw.2.is_some(),
                    provider_kind: None,
                    provider_scope: None,
                    source_time_kind: None,
                    source_tzid: None,
                    url: raw.14,
                    attendees_json: None,
                },
                recurrence: raw.2,
                recurrence_exceptions: raw.3,
            })
        })();
        let Some(row) = parsed else {
            crate::error::log::append_error_log_best_effort(
                conn,
                "calendar_timeline.malformed_row",
                &format!("skipped canonical event {raw_id}: invalid start_date/end_date/time"),
                None,
                Some("warn"),
            );
            continue;
        };
        extend_with_tolerant_expansion(
            conn,
            &mut items,
            &row,
            from_date,
            to_date,
            anchor_timezone,
        )?;
    }
    Ok(items)
}

// see canonical query above — read date/time columns
// as raw strings inside the rusqlite mapper, then attempt the
// typed conversion below in a per-row fallible block so a single
// malformed row gets logged + skipped instead of aborting the
// query.
type RawProviderTuple = (
    String,
    String,
    String,
    String,
    String,
    Option<String>,
    Option<String>,
    Option<String>,
    bool,
    Option<String>,
    Option<String>,
    Option<String>,
    Option<String>,
    String,
    Option<String>,
    Option<String>,
    String,
    Option<String>,
    Option<String>,
);

/// Query and expand `provider_calendar_events`.
pub(super) fn query_provider_timeline(
    conn: &Connection,
    from_date: NaiveDate,
    to_date: NaiveDate,
    anchor_timezone: &str,
) -> Result<Vec<CalendarTimelineItem>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let from_wide = (from_date - chrono::Duration::days(1))
        .format("%Y-%m-%d")
        .to_string();
    let to_wide = (to_date + chrono::Duration::days(1))
        .format("%Y-%m-%d")
        .to_string();
    // same UNION ALL split as the canonical timeline so
    // the planner can use `idx_provider_events_recurring_start` for
    // the recurring leg and `idx_provider_events_range_start` for
    // the fixed-span leg. The Rust caller sorts the merged result.
    //
    // the recurring leg additionally prunes by
    // `recurrence_end_date` so historical UNTIL-bounded rules from
    // subscribed feeds (e.g. an old "Standup — UNTIL 2018" series) no
    // longer enter the result set when the window is in 2026. NULL
    // covers unbounded and COUNT-only rules, which must not be pruned.
    let sql = SQL.get_or_init(|| {
        format!(
            "SELECT pce.provider_kind, pce.provider_scope, pce.provider_event_key, \
                    pce.title, pce.start_date, pce.start_time, pce.end_date, pce.end_time, \
                    pce.all_day, pce.location, pce.color, pce.recurrence, pce.recurrence_exceptions, \
                    pce.event_type, pce.person_name, pce.timezone, \
                    pce.source_time_kind, pce.source_tzid, pce.attendees_json \
             FROM provider_calendar_events pce \
             WHERE pce.recurrence IS NOT NULL AND pce.start_date <= ?2 \
               AND (pce.recurrence_end_date IS NULL OR pce.recurrence_end_date >= ?1) \
               AND EXISTS ( \
                   SELECT 1 FROM provider_scope_runtime_state psr \
                   WHERE psr.provider_kind = pce.provider_kind \
                     AND psr.provider_scope = pce.provider_scope \
                     AND psr.availability_state = '{AVAILABILITY_STATE_ENABLED}' \
                     AND psr.last_refresh_success_at IS NOT NULL \
               ) \
             UNION ALL \
             SELECT pce.provider_kind, pce.provider_scope, pce.provider_event_key, \
                    pce.title, pce.start_date, pce.start_time, pce.end_date, pce.end_time, \
                    pce.all_day, pce.location, pce.color, pce.recurrence, pce.recurrence_exceptions, \
                    pce.event_type, pce.person_name, pce.timezone, \
                    pce.source_time_kind, pce.source_tzid, pce.attendees_json \
             FROM provider_calendar_events pce \
             WHERE pce.recurrence IS NULL AND pce.start_date <= ?2 \
               AND pce.end_date IS NOT NULL AND pce.end_date >= ?1 \
               AND EXISTS ( \
                   SELECT 1 FROM provider_scope_runtime_state psr \
                   WHERE psr.provider_kind = pce.provider_kind \
                     AND psr.provider_scope = pce.provider_scope \
                     AND psr.availability_state = '{AVAILABILITY_STATE_ENABLED}' \
                     AND psr.last_refresh_success_at IS NOT NULL \
               ) \
             UNION ALL \
             SELECT pce.provider_kind, pce.provider_scope, pce.provider_event_key, \
                    pce.title, pce.start_date, pce.start_time, pce.end_date, pce.end_time, \
                    pce.all_day, pce.location, pce.color, pce.recurrence, pce.recurrence_exceptions, \
                    pce.event_type, pce.person_name, pce.timezone, \
                    pce.source_time_kind, pce.source_tzid, pce.attendees_json \
             FROM provider_calendar_events pce \
             WHERE pce.recurrence IS NULL AND pce.end_date IS NULL \
               AND pce.start_date BETWEEN ?1 AND ?2 \
               AND EXISTS ( \
                   SELECT 1 FROM provider_scope_runtime_state psr \
                   WHERE psr.provider_kind = pce.provider_kind \
                     AND psr.provider_scope = pce.provider_scope \
                     AND psr.availability_state = '{AVAILABILITY_STATE_ENABLED}' \
                     AND psr.last_refresh_success_at IS NOT NULL \
               )"
        )
    });
    let mut stmt = conn.prepare_cached(sql)?;

    let rows = stmt.query_map(rusqlite::params![from_wide, to_wide], |row| {
        Ok::<RawProviderTuple, _>((
            row.get(0)?,
            row.get(1)?,
            row.get(2)?,
            row.get(3)?,
            row.get(4)?,
            row.get(5)?,
            row.get(6)?,
            row.get(7)?,
            row.get(8)?,
            row.get(9)?,
            row.get(10)?,
            row.get(11)?,
            row.get(12)?,
            row.get(13)?,
            row.get(14)?,
            row.get(15)?,
            row.get(16)?,
            row.get(17)?,
            row.get(18)?,
        ))
    })?;

    let mut items = Vec::new();
    for row in rows {
        let raw = row?;
        let composite_id = format!("{}:{}:{}", raw.0, raw.1, raw.2);
        let composite_id_for_log = composite_id.clone();
        let parsed = (|| {
            let start_date = lorvex_domain::time::Date::parse(&raw.4).ok()?;
            let start_time = match raw.5.as_deref() {
                Some(s) => Some(lorvex_domain::time::TimeOfDay::parse(s).ok()?),
                None => None,
            };
            let end_date = match raw.6.as_deref() {
                Some(s) => Some(lorvex_domain::time::Date::parse(s).ok()?),
                None => None,
            };
            let end_time = match raw.7.as_deref() {
                Some(s) => Some(lorvex_domain::time::TimeOfDay::parse(s).ok()?),
                None => None,
            };
            // typed-timing gate; failure (illegal
            // `(all_day, time)` combination, end < start, etc.) drops
            // this provider row through the same log-and-skip path
            // the date/time parse failures take.
            let timing = lorvex_domain::CalendarEventTiming::from_flat_fields(
                start_date, start_time, end_date, end_time, raw.8,
            )
            .ok()?;
            Some(RawCalendarRow {
                item: CalendarTimelineItem {
                    source: TimelineSource::Provider,
                    editable: false,
                    id: composite_id,
                    title: raw.3,
                    timing,
                    location: raw.9,
                    color: raw.10,
                    event_type: raw.13,
                    person_name: raw.14,
                    timezone: raw.15,
                    is_recurring: raw.11.is_some(),
                    provider_kind: Some(raw.0),
                    provider_scope: Some(raw.1),
                    source_time_kind: Some(raw.16),
                    source_tzid: raw.17,
                    url: None,
                    attendees_json: raw.18,
                },
                recurrence: raw.11,
                recurrence_exceptions: raw.12,
            })
        })();
        let Some(row) = parsed else {
            crate::error::log::append_error_log_best_effort(
                conn,
                "calendar_timeline.malformed_row",
                &format!(
                    "skipped provider event {composite_id_for_log}: invalid start_date/end_date/time"
                ),
                None,
                Some("warn"),
            );
            continue;
        };
        extend_with_tolerant_expansion(
            conn,
            &mut items,
            &row,
            from_date,
            to_date,
            anchor_timezone,
        )?;
    }
    Ok(items)
}
