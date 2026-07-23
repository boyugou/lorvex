//! IPC test coverage for `create_calendar_event`.
//! The Tauri-side create path wraps input validation + recurrence
//! normalization + sync_outbox enqueue — none of which had direct
//! unit tests. We cover: happy path, empty-title + overlong-title
//! rejection, bogus IANA timezone rejection.

use lorvex_domain::naming::ENTITY_CALENDAR_EVENT;
use rusqlite::params;

use super::{create_calendar_event_internal, CreateCalendarEventArgs};
use crate::error::AppError;
use crate::test_support::test_conn;

fn base_args(title: &str, start_date: &str) -> CreateCalendarEventArgs {
    CreateCalendarEventArgs {
        title: title.to_string(),
        recurrence: None,
        timezone: None,
        start_date: start_date.to_string(),
        start_time: Some("09:00".to_string()),
        end_date: None,
        end_time: Some("10:00".to_string()),
        all_day: None,
        description: None,
        location: None,
        url: None,
        color: None,
        event_type: None,
        person_name: None,
    }
}

#[test]
fn create_calendar_event_internal_happy_path_persists_row_and_enqueues_outbox() {
    let conn = test_conn();
    let event = create_calendar_event_internal(
        &conn,
        base_args("Team sync", "2026-05-01"),
        "2026-04-20T09:00:00Z".to_string(),
    )
    .expect("create should succeed");

    assert_eq!(event.title, "Team sync");
    assert_eq!(event.start_date, "2026-05-01");
    assert_eq!(event.start_time.as_deref(), Some("09:00"));

    // Row materialized.
    let title: String = conn
        .query_row(
            "SELECT title FROM calendar_events WHERE id = ?1",
            params![event.id],
            |row| row.get(0),
        )
        .expect("load stored event");
    assert_eq!(title, "Team sync");

    // Sync outbox row emitted.
    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2",
            params![ENTITY_CALENDAR_EVENT, event.id],
            |row| row.get(0),
        )
        .expect("count outbox rows");
    assert!(outbox_count >= 1);
}

#[test]
fn create_calendar_event_internal_rejects_empty_title() {
    let conn = test_conn();
    let error = create_calendar_event_internal(
        &conn,
        base_args("   ", "2026-05-01"),
        "2026-04-20T09:00:00Z".to_string(),
    )
    .expect_err("empty title should be rejected");

    match error {
        AppError::Validation(message) => {
            assert!(message.contains("title"), "unexpected: {message}");
        }
        other => panic!("expected Validation, got {other:?}"),
    }

    // No row should have been written.
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM calendar_events", [], |row| row.get(0))
        .expect("count events");
    assert_eq!(count, 0);
}

#[test]
fn create_calendar_event_internal_rejects_timed_without_start_time() {
    // Regression: the EventForm's older "quick-add a title + date with
    // no time, leave all-day off" shape used to bubble up from the
    // domain's `CalendarEventTiming::from_flat_fields` as a
    // `StoreError` → `AppError::Internal`, which the IPC envelope
    // sanitized to "An internal error occurred." with no hint of the
    // real cause. The frontend now auto-promotes the "no time"
    // shape into an all-day event, but if any other caller (CLI,
    // MCP, programmatic test fixture) sends `all_day = false`
    // without a `start_time`, the workflow normalization must
    // surface a typed Validation error rather than an internal one.
    let conn = test_conn();
    let mut args = base_args("Quick add", "2026-05-24");
    args.all_day = Some(false);
    args.start_time = None;
    args.end_time = None;

    let error = create_calendar_event_internal(&conn, args, "2026-04-20T09:00:00Z".to_string())
        .expect_err("non-all-day with no start_time should be rejected");

    match error {
        AppError::Validation(message) => {
            assert!(
                message.contains("all-day") || message.contains("start time"),
                "expected hint about all-day or start time, got: {message}",
            );
        }
        other => panic!("expected Validation, got {other:?}"),
    }

    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM calendar_events", [], |row| row.get(0))
        .expect("count events");
    assert_eq!(count, 0);
}

#[test]
fn create_calendar_event_internal_rejects_invalid_timezone() {
    let conn = test_conn();
    let mut args = base_args("Offsite", "2026-05-01");
    args.timezone = Some("America/Not_A_Real_Zone".to_string());

    let error = create_calendar_event_internal(&conn, args, "2026-04-20T09:00:00Z".to_string())
        .expect_err("invalid timezone should be rejected");

    match error {
        AppError::Validation(message) => {
            assert!(message.contains("timezone"), "unexpected: {message}");
        }
        other => panic!("expected Validation, got {other:?}"),
    }
}

#[test]
fn create_calendar_event_internal_rejects_overlong_title() {
    let conn = test_conn();
    let long_title = "x".repeat(lorvex_domain::validation::MAX_TITLE_LENGTH + 1);
    let error = create_calendar_event_internal(
        &conn,
        base_args(&long_title, "2026-05-01"),
        "2026-04-20T09:00:00Z".to_string(),
    )
    .expect_err("overlong title should be rejected");

    match error {
        AppError::Validation(message) => {
            assert!(message.contains("maximum length"), "unexpected: {message}");
        }
        other => panic!("expected Validation, got {other:?}"),
    }
}

#[test]
fn create_calendar_event_rejects_dst_skipped_local_time() {
    // 2026-03-08 02:30 in America/New_York falls in the spring-forward
    // gap. The create path must refuse and surface a descriptive error
    // rather than silently snapping to 01:00 or 03:00 local.
    let conn = test_conn();
    let mut args = base_args("Spring-forward event", "2026-03-08");
    args.timezone = Some("America/New_York".to_string());
    args.start_time = Some("02:30".to_string());
    args.end_time = Some("03:30".to_string());

    let error = create_calendar_event_internal(&conn, args, "2026-03-01T09:00:00Z".to_string())
        .expect_err("DST-skipped start time must be rejected");

    match error {
        AppError::Validation(message) => {
            assert!(
                message.contains("does not exist")
                    || message.contains("daylight-saving")
                    || message.contains("spring-forward"),
                "expected DST-gap validation message, got: {message}"
            );
            assert!(
                message.contains("America/New_York"),
                "expected timezone in message, got: {message}"
            );
        }
        other => panic!("expected Validation, got {other:?}"),
    }

    // No calendar_events row and no outbox row should have landed.
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM calendar_events", [], |row| row.get(0))
        .expect("count events");
    assert_eq!(count, 0, "failed create must not persist any row");
    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = ?1",
            params![ENTITY_CALENDAR_EVENT],
            |row| row.get(0),
        )
        .expect("count outbox rows");
    assert_eq!(outbox_count, 0, "failed create must not enqueue outbox row");
}

#[test]
fn create_calendar_event_accepts_ambiguous_with_warning() {
    // 2026-11-01 01:30 in America/New_York falls in
    // the fall-back ambiguity. The event is accepted (using the
    // earlier occurrence, matching the store's existing
    // convention) but an error_logs row at `warn` level must be
    // emitted so the user can see the ambiguity in
    // Settings → Diagnostics.
    let conn = test_conn();
    let mut args = base_args("Fall-back event", "2026-11-01");
    args.timezone = Some("America/New_York".to_string());
    args.start_time = Some("01:30".to_string());
    args.end_time = Some("02:30".to_string());

    let event = create_calendar_event_internal(&conn, args, "2026-10-20T09:00:00Z".to_string())
        .expect("ambiguous wall-clock must be accepted");

    assert_eq!(event.start_time.as_deref(), Some("01:30"));
    assert_eq!(event.timezone.as_deref(), Some("America/New_York"));

    // Row materialized.
    let persisted_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM calendar_events WHERE id = ?1",
            params![event.id],
            |row| row.get(0),
        )
        .expect("count events");
    assert_eq!(persisted_count, 1);

    // error_logs row emitted at warn level.
    let (level, source, message): (String, String, String) = conn
        .query_row(
            "SELECT level, source, message FROM error_logs
             WHERE source = 'calendar_events.dst_ambiguous'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("one error_logs row for DST ambiguity");
    assert_eq!(level, "warn");
    assert_eq!(source, "calendar_events.dst_ambiguous");
    assert!(
        message.contains("America/New_York") && message.contains("01:30"),
        "unexpected warn message: {message}"
    );
}
