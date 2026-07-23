use crate::error::StoreError;
use chrono::{NaiveDate, NaiveDateTime, TimeZone};
use lorvex_domain::time::{Date, TimeOfDay};

use super::types::CalendarTimelineItem;

#[derive(Debug, Clone, PartialEq, Eq)]
enum TemporalSemantics {
    Floating,
    Utc,
    Tzid(String),
}

fn temporal_semantics(item: &CalendarTimelineItem) -> TemporalSemantics {
    if item.all_day() || item.start_time().is_none() {
        return TemporalSemantics::Floating;
    }

    match item.source_time_kind.as_deref() {
        Some("utc") => TemporalSemantics::Utc,
        Some("tzid") => item
            .source_tzid
            .clone()
            .map_or(TemporalSemantics::Floating, TemporalSemantics::Tzid),
        Some(_) => TemporalSemantics::Floating,
        None => match item.timezone.as_deref() {
            Some("UTC") => TemporalSemantics::Utc,
            Some(tz) if !tz.is_empty() => TemporalSemantics::Tzid(tz.to_string()),
            _ => TemporalSemantics::Floating,
        },
    }
}

pub(crate) fn projection_buffer_days(item: &CalendarTimelineItem) -> i64 {
    if item.all_day() || item.start_time().is_none() {
        return 0;
    }
    match temporal_semantics(item) {
        TemporalSemantics::Floating => 0,
        TemporalSemantics::Utc | TemporalSemantics::Tzid(_) => 1,
    }
}

pub(crate) fn overlaps_item_range(
    item: &CalendarTimelineItem,
    from: NaiveDate,
    to: NaiveDate,
) -> bool {
    let start = item.start_date().as_naive_date();
    let end = item.end_date().map_or(start, |d| d.as_naive_date());
    start <= to && end >= from
}

pub(crate) fn project_item_to_anchor(
    item: &CalendarTimelineItem,
    anchor_timezone: &str,
) -> Result<CalendarTimelineItem, StoreError> {
    if item.all_day() || item.start_time().is_none() {
        return Ok(item.clone());
    }

    // since the timeline item now carries a typed
    // `CalendarEventTiming` enum, the parse-from-string error arms
    // that lived here only fired on legacy `String`-shaped fields and
    // were unreachable in practice (the loaders already routed every
    // value through `parse_ymd` / `parse_from_str` before constructing
    // the item). The typed enum moves that contract into the
    // construction site, leaving this function focused on the
    // local→anchor projection it's actually responsible for.
    let source_start_date = item.start_date().as_naive_date();
    let source_start_time = item
        .start_time()
        .ok_or_else(|| {
            // `item.all_day() || item.start_time().is_none()` returned
            // early above, so this branch is unreachable. Keep the
            // typed error surface here defensively in case the
            // early-return contract changes in the future.
            StoreError::Validation(format!("missing start_time for calendar event {}", item.id))
        })?
        .as_naive_time();
    let source_end_date = item
        .end_date()
        .map_or(source_start_date, |d| d.as_naive_date());
    let source_end_time = item.end_time().map(|t| t.as_naive_time());

    let semantics = temporal_semantics(item);
    if semantics == TemporalSemantics::Floating {
        return Ok(item.clone());
    }

    let event_id = lorvex_domain::EventId::from_trusted(item.id.clone());
    let anchor_tz = parse_timezone(anchor_timezone, "anchor timezone", &event_id)?;

    let anchor_start = convert_naive_to_anchor(
        source_start_date.and_time(source_start_time),
        &semantics,
        anchor_tz,
        &event_id,
    )?;

    let anchor_end = source_end_time
        .map(|end_time| {
            convert_naive_to_anchor(
                source_end_date.and_time(end_time),
                &semantics,
                anchor_tz,
                &event_id,
            )
        })
        .transpose()?;

    let new_start_date = Date::from(anchor_start.date_naive());
    let new_start_time = Some(TimeOfDay::from(anchor_start.time()));
    let new_end_date = anchor_end.map(|dt| Date::from(dt.date_naive()));
    let new_end_time = anchor_end.map(|dt| TimeOfDay::from(dt.time()));

    // Re-validate the projected (start, end) pair through the typed
    // gate so any future change to the projection math (e.g. a buggy
    // anchor that produces `end < start`) trips the typed validity
    // contract instead of silently emitting a corrupt timing.
    let projected_timing = lorvex_domain::CalendarEventTiming::from_flat_fields(
        new_start_date,
        new_start_time,
        new_end_date,
        new_end_time,
        false,
    )
    .map_err(|err| {
        StoreError::Validation(format!(
            "projected timing invalid for calendar event {}: {err}",
            item.id
        ))
    })?;

    let mut projected = item.clone();
    projected.timing = projected_timing;
    Ok(projected)
}

/// Resolve a naive local datetime in the given timezone, tolerating
/// DST transitions:
///
/// - **Ambiguous (fall-back)**: two candidates exist because the same
///   wall-clock hour repeats. Prefer the earliest (pre-transition
///   instant) — matches most calendar clients' interpretation of a
///   "2:30 AM" reminder landing on the first 2:30 AM of that day.
/// - **Nonexistent (spring-forward gap)**: no candidate exists because
///   the wall-clock hour was skipped (e.g. 2:30 AM never happened on
///   the DST transition day). The function shifts forward until the
///   wall-clock time becomes valid again (typically +1 hour), landing
///   the event at the first moment after the gap closes. Returning
///   an error instead would silently drop every recurring 2:30 AM
///   event in DST-observing zones on the transition day.
fn resolve_local_datetime(
    naive: NaiveDateTime,
    tz: chrono_tz::Tz,
) -> Option<chrono::DateTime<chrono_tz::Tz>> {
    match tz.from_local_datetime(&naive) {
        chrono::LocalResult::Single(dt) => Some(dt),
        chrono::LocalResult::Ambiguous(earliest, _latest) => Some(earliest),
        chrono::LocalResult::None => {
            // Spring-forward gap: advance the naive time in 15-minute
            // steps until we land on a valid wall-clock moment. The
            // cap at 120 steps (30 hours) is a safety net — no real DST
            // transition skips more than ~2 hours.
            let mut candidate = naive;
            for _ in 0..120 {
                candidate += chrono::Duration::minutes(15);
                if let chrono::LocalResult::Single(dt) = tz.from_local_datetime(&candidate) {
                    return Some(dt);
                }
                if let chrono::LocalResult::Ambiguous(earliest, _) =
                    tz.from_local_datetime(&candidate)
                {
                    return Some(earliest);
                }
            }
            None
        }
    }
}

fn convert_naive_to_anchor(
    naive: NaiveDateTime,
    semantics: &TemporalSemantics,
    anchor_tz: chrono_tz::Tz,
    event_id: &lorvex_domain::EventId,
) -> Result<chrono::DateTime<chrono_tz::Tz>, StoreError> {
    match semantics {
        TemporalSemantics::Floating => resolve_local_datetime(naive, anchor_tz).ok_or_else(|| {
            StoreError::Validation(format!(
                "invalid floating local datetime for calendar event {event_id}: {naive}"
            ))
        }),
        TemporalSemantics::Utc => Ok(chrono::Utc
            .from_utc_datetime(&naive)
            .with_timezone(&anchor_tz)),
        TemporalSemantics::Tzid(source_tzid) => {
            let source_tz = parse_timezone(source_tzid, "source timezone", event_id)?;
            let source_dt = resolve_local_datetime(naive, source_tz).ok_or_else(|| {
                StoreError::Validation(format!(
                    "invalid source local datetime for calendar event {event_id}: {naive}"
                ))
            })?;
            Ok(source_dt.with_timezone(&anchor_tz))
        }
    }
}

fn parse_timezone(
    value: &str,
    field: &str,
    event_id: &lorvex_domain::EventId,
) -> Result<chrono_tz::Tz, StoreError> {
    value.parse().map_err(|_| {
        StoreError::Validation(format!(
            "invalid {field} for calendar event {event_id}: {value}"
        ))
    })
}

#[cfg(test)]
mod tests;
