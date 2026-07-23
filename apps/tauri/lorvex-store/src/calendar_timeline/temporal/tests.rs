use super::*;
use chrono::{Datelike, NaiveDate, Offset, Timelike};

/// Regression: US/Eastern observes DST spring-forward on the
/// second Sunday of March, where local time jumps from 1:59 AM
/// to 3:00 AM. A wall-clock reminder at 2:30 AM on that day never
/// exists in real time. The previous implementation returned
/// `None` and surfaced a validation error, so every recurring
/// event whose local hour landed in the gap silently failed to
/// project on the transition day. The new `resolve_local_datetime`
/// advances into the post-gap window and returns the first valid
/// moment.
#[test]
fn resolve_local_datetime_handles_spring_forward_gap() {
    let tz: chrono_tz::Tz = "America/New_York".parse().unwrap();
    // March 9, 2025 at 2:30 AM — inside the DST gap (1:59 AM → 3:00 AM).
    let naive = NaiveDate::from_ymd_opt(2025, 3, 9)
        .unwrap()
        .and_hms_opt(2, 30, 0)
        .unwrap();
    let resolved = resolve_local_datetime(naive, tz)
        .expect("DST gap must advance to a valid moment instead of returning None");
    // The result must land at or after 3:00 AM local on the same
    // date, since the wall clock skipped from 1:59 to 3:00.
    assert_eq!(resolved.year(), 2025);
    assert_eq!(resolved.month(), 3);
    assert_eq!(resolved.day(), 9);
    assert!(
        resolved.hour() >= 3,
        "expected post-gap hour >= 3, got {}:{}",
        resolved.hour(),
        resolved.minute()
    );
}

/// Regression: DST fall-back repeats the same wall-clock hour.
/// For an ambiguous 1:30 AM on the fall-back day, we prefer the
/// earliest (pre-transition) instant so a 1:30 AM reminder fires
/// exactly once at its first real-time occurrence — matching how
/// every major calendar client behaves.
#[test]
fn resolve_local_datetime_prefers_earliest_on_fall_back() {
    let tz: chrono_tz::Tz = "America/New_York".parse().unwrap();
    // November 2, 2025 at 1:30 AM — inside the DST fall-back window
    // (clock jumps from 2:00 AM EDT back to 1:00 AM EST).
    let naive = NaiveDate::from_ymd_opt(2025, 11, 2)
        .unwrap()
        .and_hms_opt(1, 30, 0)
        .unwrap();
    let resolved = resolve_local_datetime(naive, tz).expect("fall-back must resolve ambiguously");
    // The `earliest` branch is EDT (-04:00), so its UTC offset
    // seconds should be -14400. The `latest` branch would be EST
    // (-05:00) at -18000.
    assert_eq!(
        resolved.offset().fix().local_minus_utc(),
        -14400,
        "expected EDT (earliest) resolution for ambiguous fall-back time"
    );
}

/// Regression: a plain local time in a cooperative (non-DST)
/// timezone should round-trip exactly — no drift from the new
/// gap-handling path.
#[test]
fn resolve_local_datetime_returns_single_result_for_unambiguous_time() {
    let tz: chrono_tz::Tz = "UTC".parse().unwrap();
    let naive = NaiveDate::from_ymd_opt(2025, 6, 15)
        .unwrap()
        .and_hms_opt(14, 30, 0)
        .unwrap();
    let resolved = resolve_local_datetime(naive, tz).expect("UTC is always valid");
    assert_eq!(resolved.naive_local(), naive);
}

/// Regression for a recurring event at 09:00 NYC must
/// project to 09:00 in the anchor zone (also NYC) independently for
/// each occurrence date, even when the occurrences straddle a DST
/// transition. The expansion path mutates `instance.start_date` to
/// the occurrence date before calling `project_item_to_anchor`, so
/// each call gets a per-occurrence source datetime and
/// `resolve_local_datetime` picks up the correct EST/EDT offset.
///
/// Before the audit was filed, a worry was that the source offset
/// from the *anchor's* (first-occurrence) date would bleed into
/// later occurrences. This test pins that down by projecting three
/// instances — one before, one after, and one on the transition
/// day — through the function and asserting that the local
/// wall-clock time is preserved across the boundary.
#[test]
fn project_item_per_occurrence_preserves_wall_clock_across_dst() {
    use super::super::types::{CalendarTimelineItem, CalendarTimelineItemFields, TimelineSource};

    use lorvex_domain::time::{Date, TimeOfDay};

    let make = |start: &str, end: &str| {
        CalendarTimelineItem::new(CalendarTimelineItemFields {
            source: TimelineSource::Canonical,
            editable: false,
            id: "evt-1".to_string(),
            title: "NYC 9 AM standup".to_string(),
            start_date: Date::parse(start).unwrap(),
            start_time: Some(TimeOfDay::parse("09:00").unwrap()),
            end_date: Some(Date::parse(end).unwrap()),
            end_time: Some(TimeOfDay::parse("09:30").unwrap()),
            all_day: false,
            location: None,
            color: None,
            event_type: "meeting".to_string(),
            person_name: None,
            timezone: None,
            provider_kind: None,
            provider_scope: None,
            is_recurring: true,
            source_time_kind: Some("tzid".to_string()),
            source_tzid: Some("America/New_York".to_string()),
            url: None,
            attendees_json: None,
        })
        .expect("typed timing for DST regression fixture")
    };

    // Dates chosen to straddle the 2025 US spring-forward on 2025-03-09:
    // Mar 2 is EST (-05:00), Mar 16 is EDT (-04:00). If the projection
    // reused the anchor's offset across occurrences, the post-DST
    // occurrence would drift by one hour (08:00 or 10:00 instead of
    // 09:00). Each instance is rebuilt through the typed-timing gate
    // so the (date, date) pair is re-validated per occurrence — the
    // pre-#3287 mutate-clone idiom skipped that gate.
    let before = make("2025-03-02", "2025-03-02");
    let on_transition = make("2025-03-09", "2025-03-09");
    let after = make("2025-03-16", "2025-03-16");

    for (label, instance) in [
        ("pre-DST", before),
        ("on DST day", on_transition),
        ("post-DST", after),
    ] {
        let projected = super::project_item_to_anchor(&instance, "America/New_York")
            .expect("project per-occurrence");
        assert_eq!(
            projected.start_time(),
            Some(TimeOfDay::parse("09:00").unwrap()),
            "{label}: wall-clock 09:00 NYC must survive DST"
        );
        assert_eq!(
            projected.end_time(),
            Some(TimeOfDay::parse("09:30").unwrap()),
            "{label}: wall-clock 09:30 NYC must survive DST"
        );
    }
}
