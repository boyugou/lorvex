use super::support::*;

#[test]
fn timeline_projects_provider_tzid_occurrence_into_anchor_day() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO provider_calendar_events
             (provider_kind, provider_scope, provider_event_key, title, start_date, start_time,
              end_date, end_time, all_day, recurrence, event_type, timezone,
              source_time_kind, source_tzid, last_seen_at, last_refreshed_at)
         VALUES
             ('google_calendar', 'work', 'late-la-sync', 'Late LA Sync', '2026-03-03', '22:00',
              '2026-03-03', '23:00', 0, '{\"FREQ\":\"WEEKLY\",\"INTERVAL\":1}', 'event',
              'America/Los_Angeles', 'tzid', 'America/Los_Angeles',
              '2026-03-25T00:00:00Z', '2026-03-25T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT OR IGNORE INTO provider_scope_runtime_state \
             (provider_kind, provider_scope, enabled, availability_state, last_refresh_success_at)
         VALUES ('google_calendar', 'work', 1, 'enabled', '2026-03-25T00:00:00.000Z')",
        [],
    )
    .unwrap();

    let items = get_calendar_timeline(
        &conn,
        "2026-03-04",
        "2026-03-04",
        CalendarAiAccessMode::FullDetails,
        "America/New_York",
    )
    .unwrap();

    assert_eq!(
        items.len(),
        1,
        "cross-day provider occurrence should land on anchor day"
    );
    let item = &items[0];
    assert_eq!(
        item.start_date(),
        lorvex_domain::time::Date::parse("2026-03-04").unwrap()
    );
    assert_eq!(
        item.start_time(),
        Some(lorvex_domain::time::TimeOfDay::parse("01:00").unwrap())
    );
    assert_eq!(
        item.end_time(),
        Some(lorvex_domain::time::TimeOfDay::parse("02:00").unwrap())
    );
}

#[test]
fn blocking_ranges_project_provider_tzid_occurrence_into_anchor_day() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO provider_calendar_events
             (provider_kind, provider_scope, provider_event_key, title, start_date, start_time,
              end_date, end_time, all_day, recurrence, event_type, timezone,
              source_time_kind, source_tzid, last_seen_at, last_refreshed_at)
         VALUES
             ('google_calendar', 'work', 'late-la-sync', 'Late LA Sync', '2026-03-03', '22:00',
              '2026-03-03', '23:00', 0, '{\"FREQ\":\"WEEKLY\",\"INTERVAL\":1}', 'event',
              'America/Los_Angeles', 'tzid', 'America/Los_Angeles',
              '2026-03-25T00:00:00Z', '2026-03-25T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT OR IGNORE INTO provider_scope_runtime_state \
             (provider_kind, provider_scope, enabled, availability_state, last_refresh_success_at)
         VALUES ('google_calendar', 'work', 1, 'enabled', '2026-03-25T00:00:00.000Z')",
        [],
    )
    .unwrap();

    let ranges = get_day_blocking_ranges(
        &conn,
        "2026-03-04",
        "America/New_York",
        CalendarAiAccessMode::FullDetails,
    )
    .unwrap();

    assert_eq!(ranges.len(), 1);
    assert_eq!(ranges[0].start_minutes, 60);
    assert_eq!(ranges[0].end_minutes, 120);
}

#[test]
fn timeline_projects_canonical_explicit_timezone_into_anchor_day() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO calendar_events
             (id, title, start_date, start_time, end_date, end_time, all_day, timezone,
              event_type, version, created_at, updated_at)
         VALUES
             ('canon-tz-1', 'Red-eye planning', '2026-03-03', '22:30', '2026-03-03', '23:30',
              0, 'America/Los_Angeles', 'event',
              '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();

    let items = get_calendar_timeline(
        &conn,
        "2026-03-04",
        "2026-03-04",
        CalendarAiAccessMode::Off,
        "America/New_York",
    )
    .unwrap();

    assert_eq!(items.len(), 1);
    assert_eq!(items[0].start_date().to_string(), "2026-03-04");
    assert_eq!(
        items[0].start_time().map(|t| t.to_string()),
        Some("01:30".to_string())
    );
    assert_eq!(
        items[0].end_time().map(|t| t.to_string()),
        Some("02:30".to_string())
    );
}

/// Audit (#2864): a single event with malformed timezone / start_time
/// must NOT abort the entire timeline query. The offending event is
/// silently skipped (with a warning logged to `error_logs`); the rest
/// of the timeline still renders. Previously the propagated
/// `Validation` error blanked the calendar UI for the user.
#[test]
fn timeline_skips_event_with_invalid_anchor_timezone() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO calendar_events
             (id, title, start_date, start_time, end_date, end_time, all_day, timezone,
              event_type, version, created_at, updated_at)
         VALUES
             ('c1', 'Canonical Meeting', '2026-03-20', '10:00', '2026-03-20', '11:00',
              0, 'America/Los_Angeles', 'event',
              '0000000000000_0000_0000000000000000', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
        [],
    )
    .unwrap();

    let result = get_calendar_timeline(
        &conn,
        "2026-03-20",
        "2026-03-20",
        CalendarAiAccessMode::Off,
        "Mars/Phobos",
    );

    let items = result.expect("malformed anchor timezone must NOT abort the entire query");
    assert!(
        items.is_empty(),
        "the only event was malformed; query returns empty (event skipped + logged)"
    );
}

#[test]
fn timeline_skips_event_with_invalid_source_timezone() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO provider_calendar_events
             (provider_kind, provider_scope, provider_event_key, title, start_date, start_time,
              end_date, end_time, all_day, event_type, timezone, source_time_kind, source_tzid,
              last_seen_at, last_refreshed_at)
         VALUES
             ('google_calendar', 'work', 'bad-source-tz', 'Broken TZ', '2026-03-20', '10:00',
              '2026-03-20', '11:00', 0, 'event', 'Mars/Phobos', 'tzid', 'Mars/Phobos',
              '2026-03-25T00:00:00Z', '2026-03-25T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT OR IGNORE INTO provider_scope_runtime_state \
             (provider_kind, provider_scope, enabled, availability_state, last_refresh_success_at)
         VALUES ('google_calendar', 'work', 1, 'enabled', '2026-03-25T00:00:00.000Z')",
        [],
    )
    .unwrap();

    let result = get_calendar_timeline(
        &conn,
        "2026-03-20",
        "2026-03-20",
        CalendarAiAccessMode::FullDetails,
        "UTC",
    );

    let items = result.expect("malformed source timezone must NOT abort the entire query");
    assert!(items.is_empty(), "offending event skipped (logged)");
}

#[test]
fn timeline_skips_event_with_invalid_start_time() {
    let conn = open_db_in_memory().unwrap();
    insert_canonical_event(
        &conn,
        "c1",
        "Broken Start Time",
        "2026-03-20",
        Some("25:00"),
        None,
        Some("11:00"),
        false,
        None,
        None,
    );

    let result = get_calendar_timeline(
        &conn,
        "2026-03-20",
        "2026-03-20",
        CalendarAiAccessMode::Off,
        "UTC",
    );

    let items = result.expect("malformed start_time must NOT abort the entire query");
    assert!(items.is_empty(), "offending event skipped (logged)");
}

// ---------------------------------------------------------------------------
// `recurrence_end_date` UNTIL pruning
// ---------------------------------------------------------------------------
