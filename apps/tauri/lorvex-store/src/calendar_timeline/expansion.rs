//! Range expansion for calendar events.
//!
//! Given a raw row (with recurrence data) and a date range, produce
//! individual `CalendarTimelineItem` occurrences.

use std::collections::HashSet;

use crate::error::StoreError;
use chrono::NaiveDate;
use lorvex_domain::time::Date;
use lorvex_domain::CalendarEventTiming;
use serde_json::Value;

use super::recurrence::{
    calculate_next_occurrence_date, count_end_date, first_occurrence_on_or_after,
    overlaps_calendar_range, parse_ymd,
};
use super::temporal::{overlaps_item_range, project_item_to_anchor, projection_buffer_days};
use super::types::CalendarTimelineItem;

/// Internal struct carrying a timeline item plus the recurrence fields
/// that are stripped before output.
pub(crate) struct RawCalendarRow {
    pub item: CalendarTimelineItem,
    pub recurrence: Option<String>,
    pub recurrence_exceptions: Option<String>,
}

/// Hard upper bound on instances expanded for a single recurrence
/// row in one call. Picked to cover all reasonable timeline-window
/// queries (e.g. ~13 years of daily occurrences) while preventing a
/// malformed RRULE — or a 100-year-window UI request — from pinning
/// the writer thread on this hot path. Hitting the cap is reported
/// via [`ExpandedCalendarRow::truncated_at_step_cap`], not an error.
pub(crate) const MAX_EXPANSION_STEPS: usize = 5_000;

/// Outcome of [`expand_row_for_range`]: the accumulated occurrence
/// list plus a flag the caller can surface to operators when the
/// expansion was truncated by the per-row step cap.
///
/// The cap is a defense against malformed RRULEs and pathological
/// long-window queries pinning the writer thread; it is not a UNTIL
/// boundary check. Returning a partial list + a truncated flag lets
/// the caller log once and still render what we computed. Raising
/// `StoreError::Invariant` instead would drop the event from the
/// timeline entirely (the tolerance wrapper
/// `extend_with_tolerant_expansion` would catch and log it), so a
/// 14-year daily habit (~5110 occurrences) would become invisible to
/// the user instead of merely cropped at the horizon.
pub(crate) struct ExpandedCalendarRow {
    pub items: Vec<CalendarTimelineItem>,
    /// `true` when the expansion stopped at [`MAX_EXPANSION_STEPS`]
    /// instead of running out of in-window occurrences naturally.
    pub truncated_at_step_cap: bool,
}

/// Expand a single raw row into zero or more `CalendarTimelineItem`s that
/// overlap `[from, to]`.
///
/// - Non-recurring events: returned if their span overlaps the range.
/// - Recurring events: each occurrence that falls within the range is
///   emitted as a separate item (with `start_date` / `end_date` adjusted).
///
/// Safety: iteration is capped at [`MAX_EXPANSION_STEPS`]. Hitting the
/// cap returns the partial result with `truncated_at_step_cap = true`
/// so the caller can log + render rather than dropping the row.
pub(crate) fn expand_row_for_range(
    row: &RawCalendarRow,
    from: NaiveDate,
    to: NaiveDate,
    anchor_timezone: &str,
) -> Result<ExpandedCalendarRow, StoreError> {
    let base_start = row.item.start_date().as_naive_date();
    let base_end = row
        .item
        .end_date()
        .map_or(base_start, |d| d.as_naive_date());
    let duration_days = (base_end - base_start).num_days().max(0);

    let recurrence = match row.recurrence.as_deref() {
        Some(raw) if !raw.trim().is_empty() => Some(raw.trim()),
        _ => None,
    };

    // ── Non-recurring ──────────────────────────────────────────────
    if recurrence.is_none() {
        let projected = project_item_to_anchor(&row.item, anchor_timezone)?;
        if overlaps_item_range(&projected, from, to) {
            return Ok(ExpandedCalendarRow {
                items: vec![projected],
                truncated_at_step_cap: false,
            });
        }
        return Ok(ExpandedCalendarRow {
            items: Vec::new(),
            truncated_at_step_cap: false,
        });
    }

    // The `is_none()` guard above already early-returned on absent
    // recurrence, so this `expect` is a documented invariant. A
    // future refactor that drops the guard fails here loudly instead
    // of silently passing `""` into `validate_recurrence_json` and
    // surfacing as an opaque "not valid JSON" downstream error.
    let recurrence = recurrence.expect("recurrence is Some after the is_none() early-return guard");
    let event_id = lorvex_domain::EventId::from_trusted(row.item.id.clone());
    validate_recurrence_json(recurrence, &event_id)?;

    let buffer_days = projection_buffer_days(&row.item);

    // ── COUNT-derived effective end ────────────────────────────────
    // `parse_ymd` is now `Result<NaiveDate, StoreError>`
    // — `count_end_date` already produced a value derived from typed
    // recurrence math, so a parse failure here is a true invariant
    // violation (somebody handed us a non-YMD string from inside the
    // store). Tolerate it via `.ok()` and fall back to no count
    // limit — the existing untruncated behaviour — but the upstream
    // bug surfaces in the error log path on the next round-trip.
    let count_limit = count_end_date(recurrence, &row.item.start_date().to_string())?
        .and_then(|d| parse_ymd(&d).ok());
    let effective_to = count_limit.map_or(to, |limit| to.min(limit));

    // If the count-limited series ended before the query window, skip.
    if count_limit.is_some_and(|limit| limit < from - chrono::Duration::days(duration_days)) {
        return Ok(ExpandedCalendarRow {
            items: Vec::new(),
            truncated_at_step_cap: false,
        });
    }

    // ── Parse exception dates ──────────────────────────────────────
    let excluded = parse_recurrence_exceptions(row.recurrence_exceptions.as_deref(), &event_id)?;

    // ── Find the first occurrence on or after the adjusted start ───
    let target_start = from - chrono::Duration::days(duration_days + buffer_days);
    let target_end = to + chrono::Duration::days(buffer_days);
    let Some(mut current_start) =
        first_occurrence_on_or_after(recurrence, base_start, target_start)?
    else {
        return Ok(ExpandedCalendarRow {
            items: Vec::new(),
            truncated_at_step_cap: false,
        });
    };

    let mut out = Vec::new();
    let mut truncated_at_step_cap = false;
    let mut guard = 0usize;

    while current_start <= effective_to + chrono::Duration::days(buffer_days) {
        guard += 1;
        if guard > MAX_EXPANSION_STEPS {
            // Cap reached. Real-world long-running daily series (e.g.
            // a 14-year habit, ~5110 occurrences) legitimately exceed
            // the 5 000-step budget, so we no longer surface this as
            // an `Invariant` — that caused the calling tolerance
            // wrapper to drop the event from the timeline entirely.
            // Return what we accumulated and let the caller decide
            // how to surface the truncation.
            truncated_at_step_cap = true;
            break;
        }

        let current_str = current_start.format("%Y-%m-%d").to_string();
        let current_end = current_start + chrono::Duration::days(duration_days);

        if !excluded.contains(&current_str)
            && overlaps_calendar_range(current_start, current_end, target_start, target_end)
        {
            // Rebuild the typed `CalendarEventTiming` for this
            // occurrence's date pair through the same gate that
            // every other construction site uses, instead of
            // mutating the legacy flat fields.
            // shifted `instance.start_date` / `instance.end_date`
            // directly; the typed enum now bundles those plus the
            // time-of-day pair, so the rebuild walks the original
            // timing's start/end times forward to the new dates.
            let mut instance = row.item.clone();
            let new_start_date = Date::from(current_start);
            let new_end_date = row
                .item
                .end_date()
                .is_some()
                .then(|| Date::from(current_end));
            let new_timing = CalendarEventTiming::from_flat_fields(
                new_start_date,
                row.item.start_time(),
                new_end_date,
                row.item.end_time(),
                row.item.all_day(),
            )
            .map_err(|err| {
                crate::error::StoreError::Validation(format!(
                    "expanded occurrence timing invalid for calendar event {}: {err}",
                    row.item.id
                ))
            })?;
            instance.timing = new_timing;
            let projected = project_item_to_anchor(&instance, anchor_timezone)?;
            if overlaps_item_range(&projected, from, to) {
                out.push(projected);
            }
        }

        let Some(next_str) = calculate_next_occurrence_date(recurrence, &current_str)? else {
            break;
        };
        let Ok(next_start) = parse_ymd(&next_str) else {
            break;
        };
        if next_start <= current_start {
            // Audit: the analogous condition at
            // `recurrence.rs:553-555` raises `Invariant` — mirror that
            // here so a malformed rule fails loudly instead of
            // truncating the timeline silently.
            return Err(crate::error::StoreError::Invariant(format!(
                "calendar recurrence rule did not advance past {current_str} for event '{}' \
                 — likely malformed RRULE",
                row.item.id
            )));
        }
        current_start = next_start;
    }

    Ok(ExpandedCalendarRow {
        items: out,
        truncated_at_step_cap,
    })
}

fn parse_recurrence_exceptions(
    raw: Option<&str>,
    event_id: &lorvex_domain::EventId,
) -> Result<HashSet<String>, StoreError> {
    // delegate to the canonical parser; map the typed
    // Validation error onto the local Serialization flavor with the
    // event id interpolated for diagnostics.
    // serde_json call lived in three places (this one, spawn_successor,
    // and recurrence_exceptions_common) — see crate-level
    // `recurrence_exceptions` module for the canonical home.
    crate::recurrence_exceptions::parse_exception_dates_as_set(raw).map_err(|e| {
        StoreError::Serialization(format!(
            "invalid recurrence_exceptions for calendar event {event_id}: {e}"
        ))
    })
}

fn validate_recurrence_json(
    raw: &str,
    event_id: &lorvex_domain::EventId,
) -> Result<(), StoreError> {
    match serde_json::from_str::<Value>(raw)? {
        Value::Object(_) => Ok(()),
        _ => Err(StoreError::Serialization(format!(
            "invalid recurrence rule for calendar event {event_id}: recurrence must be a JSON object"
        ))),
    }
}
