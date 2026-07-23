use super::support::*;

/// a recurring event with an UNTIL date that has already
/// passed must NOT enter the timeline result set when the window is
/// after that UNTIL. Previously the recurring leg only filtered by
/// `start_date <= ?2`, so a 2010-anchored daily rule with
/// `UNTIL='2014-12-31'` was fetched on every 2026 timeline query and
/// expanded by `expand_row_for_range` (which then walked to UNTIL and
/// returned no occurrences — but the row was scanned regardless).
///
/// The fix derives `recurrence_end_date` from `json_extract(recurrence,
/// '$.UNTIL')` via a STORED generated column and adds the predicate
/// `(recurrence_end_date IS NULL OR recurrence_end_date >= ?1)` to the
/// recurring leg. This test pins the observable behavior end-to-end.
#[test]
fn timeline_prunes_recurring_event_whose_until_has_passed() {
    let conn = open_db_in_memory().unwrap();
    // A long-dead recurring rule (UNTIL well before the query window).
    insert_canonical_event(
        &conn,
        "expired",
        "Expired Standup",
        "2010-01-01",
        Some("09:00"),
        None,
        Some("09:30"),
        false,
        Some(r#"{"FREQ":"DAILY","INTERVAL":1,"UNTIL":"2014-12-31"}"#),
        None,
    );
    // A still-active rule that overlaps the window.
    insert_canonical_event(
        &conn,
        "active",
        "Active Standup",
        "2026-01-01",
        Some("10:00"),
        None,
        Some("10:30"),
        false,
        Some(r#"{"FREQ":"DAILY","INTERVAL":1}"#),
        None,
    );

    let items = get_calendar_timeline(
        &conn,
        "2026-03-01",
        "2026-03-07",
        CalendarAiAccessMode::Off,
        "UTC",
    )
    .expect("timeline query succeeds");

    // The expired rule must contribute zero items — neither its
    // historical occurrences nor any phantom 2026 expansions.
    assert!(
        items.iter().all(|i| i.title() != "Expired Standup"),
        "long-dead UNTIL-bounded recurrence must not enter the timeline (got {items:?})"
    );
    // The active rule must still expand into the window.
    assert!(
        items.iter().any(|i| i.title() == "Active Standup"),
        "unbounded recurrence must still produce occurrences in the window (got {items:?})"
    );
}

/// the STORED generated column must populate `recurrence_end_date`
/// from the `UNTIL` field — every existing INSERT in the codebase
/// leaves the column untouched and lets SQLite compute it. Pin the
/// storage contract: an INSERT supplying only `recurrence` lands the
/// right derived value, and an UPDATE that replaces the rule re-derives.
#[test]
fn recurrence_end_date_generated_column_mirrors_until_on_insert_and_update() {
    let conn = open_db_in_memory().unwrap();
    insert_canonical_event(
        &conn,
        "c1",
        "Daily",
        "2024-01-01",
        Some("09:00"),
        None,
        Some("09:30"),
        false,
        Some(r#"{"FREQ":"DAILY","INTERVAL":1,"UNTIL":"2024-06-30"}"#),
        None,
    );
    let cached: Option<String> = conn
        .query_row(
            "SELECT recurrence_end_date FROM calendar_events WHERE id = 'c1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        cached.as_deref(),
        Some("2024-06-30"),
        "STORED generated column must derive recurrence_end_date from json_extract($.UNTIL)"
    );

    // Replace the recurrence rule with a new UNTIL; the generated
    // column must refresh on the underlying recurrence change.
    conn.execute(
        "UPDATE calendar_events SET recurrence = ?1 WHERE id = 'c1'",
        rusqlite::params![r#"{"FREQ":"DAILY","INTERVAL":1,"UNTIL":"2025-12-31"}"#],
    )
    .unwrap();
    let updated: Option<String> = conn
        .query_row(
            "SELECT recurrence_end_date FROM calendar_events WHERE id = 'c1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        updated.as_deref(),
        Some("2025-12-31"),
        "STORED generated column must refresh when recurrence rule changes"
    );

    // Unbounded rule (no UNTIL) — cached column must clear to NULL so
    // the timeline range predicate `recurrence_end_date IS NULL` keeps
    // unbounded rules in scope.
    conn.execute(
        "UPDATE calendar_events SET recurrence = ?1 WHERE id = 'c1'",
        rusqlite::params![r#"{"FREQ":"DAILY","INTERVAL":1}"#],
    )
    .unwrap();
    let cleared: Option<String> = conn
        .query_row(
            "SELECT recurrence_end_date FROM calendar_events WHERE id = 'c1'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        cleared, None,
        "removing UNTIL must clear the cached recurrence_end_date to NULL"
    );
}

/// the generated column normalizes RFC 5545 BASIC-format UNTIL
/// (`YYYYMMDD` / `YYYYMMDDTHHMMSSZ`) into ISO `YYYY-MM-DD` before
/// storing into `recurrence_end_date`. Without this, an ICS feed that
/// supplies `UNTIL=20141231T235959Z` lands the literal string in the
/// column; the timeline pruning predicate `recurrence_end_date >= ?1`
/// then compares it lexically against the ISO `?1` and silently
/// drops or retains the rule based on lex order rather than calendar
/// order, breaking expansion.
#[test]
fn recurrence_end_date_generated_column_normalizes_rfc5545_basic_format() {
    let conn = open_db_in_memory().unwrap();

    // BASIC DATE form (`YYYYMMDD`) — must splice hyphens.
    insert_canonical_event(
        &conn,
        "basic-date",
        "Basic UNTIL",
        "2024-01-01",
        Some("09:00"),
        None,
        Some("09:30"),
        false,
        Some(r#"{"FREQ":"DAILY","UNTIL":"20240630"}"#),
        None,
    );
    let stored: Option<String> = conn
        .query_row(
            "SELECT recurrence_end_date FROM calendar_events WHERE id = 'basic-date'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        stored.as_deref(),
        Some("2024-06-30"),
        "RFC 5545 BASIC DATE UNTIL must normalize to ISO YYYY-MM-DD"
    );

    // BASIC DATE-TIME form (`YYYYMMDDTHHMMSSZ`) — must take the date
    // prefix and splice hyphens.
    insert_canonical_event(
        &conn,
        "basic-dt",
        "Basic UNTIL DT",
        "2024-01-01",
        Some("09:00"),
        None,
        Some("09:30"),
        false,
        Some(r#"{"FREQ":"DAILY","UNTIL":"20141231T235959Z"}"#),
        None,
    );
    let stored: Option<String> = conn
        .query_row(
            "SELECT recurrence_end_date FROM calendar_events WHERE id = 'basic-dt'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        stored.as_deref(),
        Some("2014-12-31"),
        "RFC 5545 BASIC DATE-TIME UNTIL must normalize to ISO YYYY-MM-DD"
    );

    // UPDATE path normalization — replacing the rule with a basic-format
    // UNTIL must re-derive into ISO.
    conn.execute(
        "UPDATE calendar_events SET recurrence = ?1 WHERE id = 'basic-date'",
        rusqlite::params![r#"{"FREQ":"DAILY","UNTIL":"20251231T120000Z"}"#],
    )
    .unwrap();
    let stored: Option<String> = conn
        .query_row(
            "SELECT recurrence_end_date FROM calendar_events WHERE id = 'basic-date'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        stored.as_deref(),
        Some("2025-12-31"),
        "UPDATE path must re-normalize BASIC DATE-TIME UNTIL to ISO"
    );

    // Malformed UNTIL — leave NULL so the recurring leg keeps the row
    // in scope and the query-time validator surfaces the bad rule.
    insert_canonical_event(
        &conn,
        "bad-until",
        "Bad UNTIL",
        "2024-01-01",
        Some("09:00"),
        None,
        Some("09:30"),
        false,
        Some(r#"{"FREQ":"DAILY","UNTIL":"not-a-date"}"#),
        None,
    );
    let stored: Option<String> = conn
        .query_row(
            "SELECT recurrence_end_date FROM calendar_events WHERE id = 'bad-until'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        stored, None,
        "malformed UNTIL must land NULL — query-time validator handles the error"
    );
}

/// provider-mirror parity. Subscribed feeds frequently
/// keep historical UNTIL-bounded recurrences (an old "Standup" series
/// from years ago that the ICS source never cleaned up); the same
/// pruning must apply to `provider_calendar_events` so they don't
/// dominate the row scan on every timeline query.
#[test]
fn timeline_prunes_provider_recurring_event_whose_until_has_passed() {
    let conn = open_db_in_memory().unwrap();
    insert_provider_event(
        &conn,
        "ical_subscription",
        "scope-a",
        "expired-key",
        "Old Subscribed Standup",
        "2015-01-01",
        Some("09:00"),
        None,
        Some("09:30"),
        false,
        Some(r#"{"FREQ":"DAILY","INTERVAL":1,"UNTIL":"2018-06-30"}"#),
        None,
    );
    insert_provider_event(
        &conn,
        "ical_subscription",
        "scope-a",
        "active-key",
        "Live Subscribed Standup",
        "2026-01-01",
        Some("10:00"),
        None,
        Some("10:30"),
        false,
        Some(r#"{"FREQ":"DAILY","INTERVAL":1}"#),
        None,
    );

    let items = get_calendar_timeline(
        &conn,
        "2026-03-01",
        "2026-03-07",
        CalendarAiAccessMode::FullDetails,
        "UTC",
    )
    .expect("timeline query succeeds");

    assert!(
        items.iter().all(|i| i.title() != "Old Subscribed Standup"),
        "long-dead provider UNTIL recurrence must be pruned (got {items:?})"
    );
    assert!(
        items.iter().any(|i| i.title() == "Live Subscribed Standup"),
        "unbounded provider recurrence must still expand into the window (got {items:?})"
    );
}
