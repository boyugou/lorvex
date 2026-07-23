use super::support::*;

#[test]
fn timeline_includes_both_canonical_and_provider_events() {
    let conn = open_db_in_memory().unwrap();
    insert_canonical_event(
        &conn,
        "c1",
        "Canonical Meeting",
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
        "eventkit",
        "default",
        "ev1",
        "Provider Meeting",
        "2026-03-20",
        Some("14:00"),
        None,
        Some("15:00"),
        false,
        None,
        None,
    );

    let items = get_calendar_timeline(
        &conn,
        "2026-03-20",
        "2026-03-20",
        CalendarAiAccessMode::FullDetails,
        "UTC",
    )
    .unwrap();
    assert_eq!(items.len(), 2);
    assert!(items
        .iter()
        .any(|i| i.title() == "Canonical Meeting" && *i.source() == TimelineSource::Canonical));
    assert!(items
        .iter()
        .any(|i| i.title() == "Provider Meeting" && *i.source() == TimelineSource::Provider));
}

#[test]
fn timeline_excludes_provider_scope_before_first_successful_refresh() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO provider_calendar_events \
             (provider_kind, provider_scope, provider_event_key, title, start_date, all_day, event_type, \
              last_seen_at, last_refreshed_at) \
         VALUES ('ical_subscription', 'pending-scope', 'pending-event', 'Pending Feed Event', \
                 '2026-03-20', 0, 'event', '2026-03-20T00:00:00Z', '2026-03-20T00:00:00Z')",
        [],
    )
    .expect("insert provider event");
    conn.execute(
        "INSERT INTO provider_scope_runtime_state \
             (provider_kind, provider_scope, enabled, availability_state, last_refresh_success_at) \
         VALUES ('ical_subscription', 'pending-scope', 1, 'enabled', NULL)",
        [],
    )
    .expect("insert pending provider state");

    let items = get_calendar_timeline(
        &conn,
        "2026-03-20",
        "2026-03-20",
        CalendarAiAccessMode::FullDetails,
        "UTC",
    )
    .unwrap();

    assert!(
        items.is_empty(),
        "enabled provider scopes are not trusted for timeline occupancy until the first successful refresh"
    );
}

#[test]
fn timeline_excludes_provider_when_not_requested() {
    let conn = open_db_in_memory().unwrap();
    insert_canonical_event(
        &conn,
        "c1",
        "Canonical Meeting",
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
        "eventkit",
        "default",
        "ev1",
        "Provider Meeting",
        "2026-03-20",
        Some("14:00"),
        None,
        Some("15:00"),
        false,
        None,
        None,
    );

    let items = get_calendar_timeline(
        &conn,
        "2026-03-20",
        "2026-03-20",
        CalendarAiAccessMode::Off,
        "UTC",
    )
    .unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0].title(), "Canonical Meeting");
    assert_eq!(*items[0].source(), TimelineSource::Canonical);
}

#[test]
fn search_calendar_events_returns_matching_canonical_rows_from_fts_rowids() {
    let conn = open_db_in_memory().unwrap();
    insert_canonical_event(
        &conn,
        "c-search",
        "Ops calendar review",
        "2026-04-22",
        Some("10:30"),
        None,
        Some("11:00"),
        false,
        None,
        None,
    );

    let results = search_calendar_events(
        &conn,
        &lorvex_domain::query::CalendarSearchPredicate {
            query: "ops".to_string(),
            from: Some("2026-04-22".to_string()),
            to: Some("2026-04-22".to_string()),
        },
        10,
    )
    .expect("search calendar events");

    assert_eq!(results.len(), 1);
    assert_eq!(results[0].id, "c-search");
    assert_eq!(results[0].title, "Ops calendar review");
}

#[test]
fn timeline_expands_recurring_canonical_event() {
    let conn = open_db_in_memory().unwrap();
    insert_canonical_event(
        &conn,
        "c1",
        "Daily Standup",
        "2026-03-01",
        Some("09:00"),
        None,
        Some("09:15"),
        false,
        Some(r#"{"FREQ":"DAILY","INTERVAL":1}"#),
        None,
    );

    // Query a 5-day window.
    let items = get_calendar_timeline(
        &conn,
        "2026-03-03",
        "2026-03-07",
        CalendarAiAccessMode::Off,
        "UTC",
    )
    .unwrap();
    assert_eq!(items.len(), 5, "Expected 5 occurrences in a 5-day window");
    assert_eq!(items[0].start_date().to_string(), "2026-03-03");
    assert_eq!(items[4].start_date().to_string(), "2026-03-07");
    // All should be canonical and editable.
    for item in &items {
        assert_eq!(*item.source(), TimelineSource::Canonical);
        assert!(item.editable());
    }
}

#[test]
fn timeline_expands_recurring_provider_event() {
    let conn = open_db_in_memory().unwrap();
    insert_provider_event(
        &conn,
        "google_calendar",
        "work",
        "meeting1",
        "Weekly Sync",
        "2026-03-02",
        Some("14:00"),
        None,
        Some("15:00"),
        false,
        Some(r#"{"FREQ":"WEEKLY","INTERVAL":1}"#),
        None,
    );

    // Query a 3-week window starting from the base date.
    let items = get_calendar_timeline(
        &conn,
        "2026-03-02",
        "2026-03-22",
        CalendarAiAccessMode::FullDetails,
        "UTC",
    )
    .unwrap();
    assert_eq!(items.len(), 3, "Expected 3 weekly occurrences");
    assert_eq!(items[0].start_date().to_string(), "2026-03-02");
    assert_eq!(items[1].start_date().to_string(), "2026-03-09");
    assert_eq!(items[2].start_date().to_string(), "2026-03-16");
    for item in &items {
        assert_eq!(*item.source(), TimelineSource::Provider);
        assert!(!item.editable());
    }
}

#[test]
fn timeline_expands_leap_day_yearly_recurrence_without_feb_28_shadow() {
    let conn = open_db_in_memory().unwrap();
    insert_canonical_event(
        &conn,
        "leap-birthday",
        "Leap birthday",
        "2024-02-29",
        None,
        None,
        None,
        true,
        Some(r#"{"FREQ":"YEARLY","INTERVAL":1,"BYMONTH":[2],"BYMONTHDAY":29}"#),
        None,
    );

    let items = get_calendar_timeline(
        &conn,
        "2025-02-01",
        "2028-03-01",
        CalendarAiAccessMode::Off,
        "UTC",
    )
    .unwrap();

    let dates: Vec<String> = items
        .iter()
        .map(|item| item.start_date().to_string())
        .collect();
    assert_eq!(dates, vec!["2028-02-29"]);
}

#[test]
fn timeline_expands_monthly_byday_bysetpos_recurrence() {
    let conn = open_db_in_memory().unwrap();
    insert_canonical_event(
        &conn,
        "first-monday",
        "First Monday planning",
        "2026-01-05",
        Some("09:00"),
        None,
        Some("10:00"),
        false,
        Some(r#"{"FREQ":"MONTHLY","INTERVAL":1,"BYDAY":["MO"],"BYSETPOS":[1]}"#),
        None,
    );

    let items = get_calendar_timeline(
        &conn,
        "2026-02-01",
        "2026-04-30",
        CalendarAiAccessMode::Off,
        "UTC",
    )
    .unwrap();

    let dates: Vec<String> = items
        .iter()
        .map(|item| item.start_date().to_string())
        .collect();
    assert_eq!(dates, vec!["2026-02-02", "2026-03-02", "2026-04-06"]);
}

// `timeline_rejects_malformed_recurrence_exceptions_json` retired
// in #4585: EXDATE rows are normalized into
// `calendar_event_recurrence_exceptions`, so the read projection
// rebuilds well-formed JSON from individual rows. The
// malformed-JSON branch the test pinned is rejected at the write
// boundary (`replace_event_exceptions_from_json`) rather than at
// read.

#[test]
fn timeline_rejects_malformed_recurrence_rule_json() {
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

    let result = get_calendar_timeline(
        &conn,
        "2026-03-20",
        "2026-03-20",
        CalendarAiAccessMode::Off,
        "UTC",
    );

    assert!(
        result.is_err(),
        "expected malformed recurrence rule to fail timeline query"
    );
}

#[test]
fn timeline_with_empty_provider_table_returns_only_canonical() {
    let conn = open_db_in_memory().unwrap();
    insert_canonical_event(
        &conn,
        "c1",
        "Solo Event",
        "2026-03-15",
        Some("10:00"),
        None,
        Some("11:00"),
        false,
        None,
        None,
    );

    // FullDetails but no provider events exist — should not error.
    let items = get_calendar_timeline(
        &conn,
        "2026-03-15",
        "2026-03-15",
        CalendarAiAccessMode::FullDetails,
        "UTC",
    )
    .unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0].title(), "Solo Event");
}
