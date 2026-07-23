use super::support::*;

#[test]
fn timeline_busy_only_redacts_provider_details() {
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
        "Secret Meeting",
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
        CalendarAiAccessMode::BusyOnly,
        "UTC",
    )
    .unwrap();
    assert_eq!(items.len(), 2);

    let canonical = items
        .iter()
        .find(|i| *i.source() == TimelineSource::Canonical)
        .unwrap();
    assert_eq!(
        canonical.title(),
        "Canonical Meeting",
        "Canonical event details should not be redacted"
    );

    let provider = items
        .iter()
        .find(|i| *i.source() == TimelineSource::Provider)
        .unwrap();
    assert_eq!(
        provider.title(),
        "Busy",
        "Provider title should be redacted to 'Busy'"
    );
    assert_eq!(
        provider.location(),
        None,
        "Provider location should be redacted"
    );
    assert_eq!(
        provider.person_name(),
        None,
        "Provider person_name should be redacted"
    );
    // Timing info should still be present.
    assert_eq!(
        provider.start_time(),
        Some(lorvex_domain::time::TimeOfDay::parse("14:00").unwrap())
    );
    assert_eq!(
        provider.end_time(),
        Some(lorvex_domain::time::TimeOfDay::parse("15:00").unwrap())
    );
}

#[test]
fn timeline_off_excludes_provider_entirely() {
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
        "eventkit",
        "default",
        "ev1",
        "Provider",
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
    assert_eq!(*items[0].source(), TimelineSource::Canonical);
}

#[test]
fn blocking_ranges_busy_only_redacts_provider_title() {
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
        "personal",
        "mtg1",
        "Secret Call",
        "2026-03-20",
        Some("13:00"),
        None,
        Some("14:00"),
        false,
        None,
        None,
    );

    let ranges =
        get_day_blocking_ranges(&conn, "2026-03-20", "UTC", CalendarAiAccessMode::BusyOnly)
            .unwrap();
    assert_eq!(ranges.len(), 2);

    let canonical = ranges
        .iter()
        .find(|r| r.source == TimelineSource::Canonical)
        .unwrap();
    assert_eq!(canonical.title, "Canonical Meeting");

    let provider = ranges
        .iter()
        .find(|r| r.source == TimelineSource::Provider)
        .unwrap();
    assert_eq!(
        provider.title, "Busy",
        "Provider blocking range title should be redacted to 'Busy'"
    );
    // Timing info should still be present.
    assert_eq!(provider.start_minutes, 13 * 60);
    assert_eq!(provider.end_minutes, 14 * 60);
}

#[test]
fn blocking_ranges_off_excludes_provider() {
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

    let ranges =
        get_day_blocking_ranges(&conn, "2026-03-20", "UTC", CalendarAiAccessMode::Off).unwrap();
    assert!(
        ranges.is_empty(),
        "Off mode should exclude provider events entirely"
    );
}
