//! Minimal VEVENT extraction from ICS feed bodies.
//!
//! `parse_ics_events` walks unfolded RFC 5545 lines and accumulates one
//! [`ParsedEvent`] per `BEGIN:VEVENT` / `END:VEVENT` block. Per-event
//! field caps come from `lorvex_domain::validation` so the ICS surface
//! enforces the same length contracts as local writes.
//! Truncated payloads (unbalanced VEVENT counts) are rejected up-front
//! via [`super::truncation::detect_ics_truncation`].
//!
//! [`rrule_to_json`] is the typed-encoding pass that turns a raw
//! `RRULE:` value into the recurrence-engine's expected JSON shape.

use super::truncation::{detect_ics_truncation, IcsTruncationReason, ICS_TRUNCATION_MESSAGE};
use super::tzid::{noop_unknown_tzid_sink, UnknownTzidSink};
use super::vtimezone::parse_vtimezone_blocks;
use super::CalendarSubscriptionError;

mod builder;
mod datetime;
mod dedupe;
mod metadata;
mod model;
mod properties;
mod rrule;

use builder::EventBuilder;
use dedupe::merge_duplicate_events;
use metadata::{extract_calendar_method, extract_x_wr_timezone, unfold_lines};
use model::MAX_VEVENTS_PER_FEED;
pub use model::{IcsParseReport, IcsParseWarning, ParsedEvent};
#[cfg(test)]
pub(crate) use properties::{extract_ics_param, unescape_ics};
pub use rrule::{rrule_to_json, rrule_to_json_with_warnings};

/// Upper bound on ATTENDEE lines per VEVENT. A hostile feed could
/// otherwise allocate unbounded `(String, Option<String>, Option<String>)`
/// tuples during parse.
///
/// Public so the native-calendar IPC boundary
/// (`platform::windows_calendar`) can apply the same cap. Every
/// attendee write path shares this cap so the shadow row count stays
/// bounded regardless of whether the event entered via ICS
/// subscription or WinRT Appointments.
pub const MAX_ATTENDEES_PER_EVENT: usize = 500;

/// Upper bound on free-text single-line VEVENT fields (LOCATION,
/// ORGANIZER, URL). Same unit (Unicode chars) as the title validator.
pub(crate) const MAX_ICS_SHORT_FIELD_LENGTH: usize = lorvex_domain::validation::MAX_TITLE_LENGTH;

pub fn parse_ics_events(content: &str) -> Result<Vec<ParsedEvent>, CalendarSubscriptionError> {
    parse_ics_events_with_diagnostics(content, &noop_unknown_tzid_sink).map(|report| report.events)
}

pub fn parse_ics_events_with_diagnostics(
    content: &str,
    unknown_tzid_sink: UnknownTzidSink<'_>,
) -> Result<IcsParseReport, CalendarSubscriptionError> {
    // Strip UTF-8 BOM if present (some Windows calendar tools emit it)
    let content = content.strip_prefix('\u{FEFF}').unwrap_or(content);

    // defense-in-depth against a truncated payload
    // reaching the parser. `fetch_ics_content` enforces the same
    // invariant one level up so production paths reject truncation
    // before they allocate any parser state, but keeping the check
    // here protects future callers (in-memory tests, offline-import
    // tooling, direct unit tests) from the silent-drop failure mode.
    // Only the VEVENT-balance check runs here —
    // the `END:VCALENDAR` requirement is a fetch-layer concern (some
    // legitimate unit-test fixtures emit loose VEVENT fragments).
    if let Err(IcsTruncationReason::UnbalancedVeventCount { begins, ends }) =
        detect_ics_truncation(content)
    {
        return Err(CalendarSubscriptionError::Validation(format!(
            "{ICS_TRUNCATION_MESSAGE}: unbalanced VEVENT markers ({begins} BEGIN:VEVENT vs {ends} END:VEVENT)"
        )));
    }

    // Unfold once, then do TWO passes:
    //   pass 1 — collect every BEGIN:VTIMEZONE block into a
    //            per-feed registry of `tzid -> ResolvedTimezone`.
    //   pass 2 — extract VEVENTs, resolving DTSTART/DTEND through
    //            the registry FIRST, falling back to chrono-tz /
    //            Windows-shim / UTC as before.
    // The second pass needs the unfolded line list anyway, so the
    // double scan adds only O(n) work per fetch (one pass, two
    // visits) and keeps the blocks-vs-events parse strictly
    // separated.
    let unfolded = unfold_lines(content);
    let registry = parse_vtimezone_blocks(&unfolded);

    // scan calendar-level metadata before
    // walking VEVENTs. Two pieces of context the parser needs:
    //
    //   * `METHOD:CANCEL` — the entire feed is a cancellation
    //     payload (e.g. an organizer publishing a meeting-cancelled
    //     batch). The audit notes this surface fell through silently:
    //     CANCEL feeds were being upserted into the cache as ordinary
    //     events. Treating CANCEL as "no events to import" lets the
    //     diff-delete pass clean up the affected scope without
    //     special-casing every VEVENT downstream.
    //
    //   * `X-WR-TIMEZONE` — Google Calendar exports embed a single
    //     calendar-level zone instead of per-VEVENT TZID parameters.
    //     The audit flagged this as silently dropping events into
    //     "floating" mode (no projection-time conversion). Capture
    //     the value here and let `EventBuilder::build` apply it as
    //     the default for events whose DTSTART has no TZID and no
    //     `Z` suffix.
    let calendar_method = extract_calendar_method(&unfolded);
    if matches!(calendar_method.as_deref(), Some("CANCEL")) {
        return Ok(IcsParseReport {
            events: Vec::new(),
            warnings: Vec::new(),
        });
    }
    let x_wr_timezone = extract_x_wr_timezone(&unfolded);

    let mut events = Vec::new();
    let mut warnings = Vec::new();
    let mut in_event = false;
    let mut current: Option<EventBuilder> = None;
    let mut cap_warned = false;

    for line in &unfolded {
        let line = line.trim();
        if line == "BEGIN:VEVENT" {
            in_event = true;
            current = Some(EventBuilder::default());
        } else if line == "END:VEVENT" {
            in_event = false;
            if let Some(builder) = current.take() {
                // cap the per-feed VEVENT count so a
                // pathologically large or hostile body cannot expand
                // into hundreds of MB of `ParsedEvent` state inside
                // the writer transaction. We still pay the parse cost
                // for the trailing events (cheap) but never allocate
                // their `ParsedEvent` value.
                if events.len() >= MAX_VEVENTS_PER_FEED {
                    if !cap_warned {
                        warnings.push(IcsParseWarning::new(
                            "VEVENT cap reached; dropping remaining events",
                            format!("max_events={MAX_VEVENTS_PER_FEED}"),
                        ));
                        cap_warned = true;
                    }
                    continue;
                }
                // Skip individual malformed events instead of failing the entire feed.
                // One bad VEVENT should not prevent importing hundreds of valid ones.
                match builder.build(&registry, x_wr_timezone.as_deref(), unknown_tzid_sink) {
                    Ok(Some(event)) => events.push(event),
                    Ok(None) => {} // STATUS:CANCELLED → drop
                    Err(e) => warnings.push(IcsParseWarning::new(
                        "malformed VEVENT dropped",
                        e.to_string(),
                    )),
                }
            }
        } else if in_event {
            if let Some(ref mut builder) = current {
                builder.parse_line(line);
            }
        }
    }

    // multi-VEVENT same-UID merge ordering.
    // RFC 5545 §3.8.7.4 says when a calendar object contains more than
    // one component with the same UID + RECURRENCE-ID composite, the
    // version with the highest SEQUENCE wins; ties break on the latest
    // DTSTAMP; tertiary tie-break is "later in document wins" so the
    // last bytes the publisher emitted are authoritative.
    //
    // `sync_subscription_content_inner` already had the side effect
    // of "last wins" on the upsert path — but it was a coincidence of
    // SQLite ON CONFLICT semantics, not a deliberate merge. A feed
    // that emitted the SEQUENCE=2 override BEFORE the SEQUENCE=5
    // override would persist the SEQUENCE=2 record, silently dropping
    // the more recent edit. Resolve here so the apply pipeline sees
    // exactly one canonical event per composite key.
    Ok(IcsParseReport {
        events: merge_duplicate_events(events),
        warnings,
    })
}
