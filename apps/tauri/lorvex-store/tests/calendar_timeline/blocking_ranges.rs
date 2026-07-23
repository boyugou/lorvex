use super::support::*;

#[test]
fn blocking_ranges_includes_provider_events() {
    let conn = open_db_in_memory().unwrap();
    insert_provider_event(
        &conn,
        "eventkit",
        "personal",
        "mtg1",
        "Provider Call",
        "2026-03-20",
        Some("13:00"),
        None,
        Some("14:00"),
        false,
        None,
        None,
    );

    let ranges = get_day_blocking_ranges(
        &conn,
        "2026-03-20",
        "UTC",
        CalendarAiAccessMode::FullDetails,
    )
    .unwrap();
    assert_eq!(ranges.len(), 1);
    assert_eq!(ranges[0].title, "Provider Call");
    assert_eq!(ranges[0].start_minutes, 13 * 60);
    assert_eq!(ranges[0].end_minutes, 14 * 60);
}

#[test]
fn blocking_ranges_skips_all_day_events() {
    let conn = open_db_in_memory().unwrap();
    insert_canonical_event(
        &conn,
        "c1",
        "Birthday",
        "2026-03-20",
        None,
        None,
        None,
        true,
        None,
        None,
    );
    insert_canonical_event(
        &conn,
        "c2",
        "Meeting",
        "2026-03-20",
        Some("10:00"),
        None,
        Some("11:00"),
        false,
        None,
        None,
    );

    let ranges =
        get_day_blocking_ranges(&conn, "2026-03-20", "UTC", CalendarAiAccessMode::Off).unwrap();
    assert_eq!(
        ranges.len(),
        1,
        "All-day event should not create a blocking range"
    );
    assert_eq!(ranges[0].title, "Meeting");
}

#[test]
fn blocking_ranges_canonical_event_id_set_for_canonical_only() {
    let conn = open_db_in_memory().unwrap();
    insert_canonical_event(
        &conn,
        "c1",
        "Canonical",
        "2026-03-20",
        Some("10:00"),
        None,
        Some("11:00"),
        false,
        None,
        None,
    );
    insert_provider_event(
        &conn,
        "google_calendar",
        "work",
        "p1",
        "Provider",
        "2026-03-20",
        Some("14:00"),
        None,
        Some("15:00"),
        false,
        None,
        None,
    );

    let ranges = get_day_blocking_ranges(
        &conn,
        "2026-03-20",
        "UTC",
        CalendarAiAccessMode::FullDetails,
    )
    .unwrap();
    assert_eq!(ranges.len(), 2);

    let canonical = ranges.iter().find(|r| r.title == "Canonical").unwrap();
    let provider = ranges.iter().find(|r| r.title == "Provider").unwrap();

    assert_eq!(canonical.canonical_event_id, Some("c1".to_string()));
    assert_eq!(provider.canonical_event_id, None);
}

#[test]
fn blocking_ranges_respects_recurrence_exceptions() {
    let conn = open_db_in_memory().unwrap();
    // Daily event with March 20 excluded.
    insert_canonical_event(
        &conn,
        "c1",
        "Daily",
        "2026-03-18",
        Some("09:00"),
        None,
        Some("09:30"),
        false,
        Some(r#"{"FREQ":"DAILY","INTERVAL":1}"#),
        Some(r#"["2026-03-20"]"#),
    );

    // March 20 should be excluded.
    let ranges =
        get_day_blocking_ranges(&conn, "2026-03-20", "UTC", CalendarAiAccessMode::Off).unwrap();
    assert!(
        ranges.is_empty(),
        "Excluded date should not create a blocking range"
    );

    // March 19 should still work.
    let ranges =
        get_day_blocking_ranges(&conn, "2026-03-19", "UTC", CalendarAiAccessMode::Off).unwrap();
    assert_eq!(ranges.len(), 1);
    assert_eq!(ranges[0].title, "Daily");
}

// `blocking_ranges_reject_malformed_recurrence_exceptions_json`
// retired in #4585: with EXDATE rows normalized into
// `calendar_event_recurrence_exceptions`, malformed JSON cannot
// land in storage — `json_group_array` builds the projection
// from individual date rows. The malformed-input branch is now
// rejected at the write boundary (the
// `replace_event_exceptions_from_json` helper), not at read.

#[test]
fn blocking_ranges_reject_malformed_recurrence_rule_json() {
    let conn = open_db_in_memory().unwrap();
    insert_canonical_event(
        &conn,
        "c1",
        "Daily",
        "2026-03-18",
        Some("09:00"),
        None,
        Some("09:30"),
        false,
        Some(r#"{"FREQ":"DAILY""#),
        None,
    );

    let result = get_day_blocking_ranges(&conn, "2026-03-20", "UTC", CalendarAiAccessMode::Off);

    assert!(
        result.is_err(),
        "expected malformed recurrence rule to fail blocking query"
    );
}

#[test]
fn blocking_ranges_multi_day_event_does_not_double_count() {
    let conn = open_db_in_memory().unwrap();
    // A 3-day all-day event should not appear in blocking ranges at all.
    insert_canonical_event(
        &conn,
        "c1",
        "Conference",
        "2026-03-18",
        None,
        Some("2026-03-20"),
        None,
        true,
        None,
        None,
    );

    let ranges =
        get_day_blocking_ranges(&conn, "2026-03-19", "UTC", CalendarAiAccessMode::Off).unwrap();
    assert!(
        ranges.is_empty(),
        "Multi-day all-day event should not block time slots"
    );
}

#[test]
fn blocking_ranges_default_end_time_when_missing() {
    let conn = open_db_in_memory().unwrap();
    // a timed event with `start_time` set but no
    // `end_time` is an RFC 5545 §3.6.1 point event (zero length).
    // The previous code synthesized a phantom 60-minute block which
    // painted an hour-long busy window in the daily-schedule UI for
    // events the source ICS deliberately left timeless. Confirm the
    // new behavior: the event drops out of the blocking-range vector
    // entirely so the schedule pane stays clear.
    insert_canonical_event(
        &conn,
        "c1",
        "Open-ended",
        "2026-03-20",
        Some("15:00"),
        None,
        None,
        false,
        None,
        None,
    );

    let ranges =
        get_day_blocking_ranges(&conn, "2026-03-20", "UTC", CalendarAiAccessMode::Off).unwrap();
    assert!(
        ranges.is_empty(),
        "timed event with no end_time must drop out of blocking ranges (got {ranges:?})"
    );
}

// ---------------------------------------------------------------------------
// BusyOnly access mode tests
// ---------------------------------------------------------------------------
