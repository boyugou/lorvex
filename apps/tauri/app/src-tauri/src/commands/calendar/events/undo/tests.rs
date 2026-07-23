use super::snapshot::{capture_calendar_event_snapshot, capture_list_snapshot};
use super::token::{build_undo_token, EntitySnapshot, EntityUndoToken};
use super::{undo_delete_entity_internal, RestoredEntity};

use crate::error::AppError;
use crate::test_support::test_conn;
use lorvex_domain::CanonicalCalendarEventType;
use rusqlite::params;

use super::super::CalendarEvent;

fn seed_event(conn: &rusqlite::Connection, id: &str, title: &str) {
    conn.execute(
        "INSERT INTO calendar_events
            (id, title, start_date, all_day, version, created_at, updated_at, event_type)
         VALUES (?1, ?2, '2026-04-20', 1,
                 '0000000000000_0000_seedcalseedcalse',
                 '2026-04-19T08:00:00Z', '2026-04-19T08:00:00Z', 'event')",
        params![id, title],
    )
    .expect("seed event");
}

#[test]
fn happy_path_round_trip_restores_event() {
    crate::hlc::ensure_hlc_for_test();
    let conn = test_conn();
    let event_id = lorvex_domain::new_entity_id_string();
    seed_event(&conn, &event_id, "Standup");

    let snapshot = capture_calendar_event_snapshot(&conn, &event_id).expect("snapshot");
    // Mimic a delete by removing the row.
    conn.execute(
        "DELETE FROM calendar_events WHERE id = ?1",
        params![event_id],
    )
    .unwrap();

    let token = build_undo_token(snapshot).expect("token");
    let now = lorvex_domain::format_sync_timestamp(chrono::Utc::now());
    let restored = undo_delete_entity_internal(&conn, &token, &now).expect("undo should succeed");
    let value = match restored {
        RestoredEntity::CalendarEvent(v) => v,
        RestoredEntity::List(_) => panic!("expected CalendarEvent variant"),
    };
    assert_eq!(
        value.get("id").and_then(|v| v.as_str()),
        Some(event_id.as_str())
    );
    assert_eq!(value.get("title").and_then(|v| v.as_str()), Some("Standup"));

    // Outbox should carry a fresh upsert envelope.
    let upsert_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'calendar_event' \
             AND entity_id = ?1 AND operation = 'upsert'",
            params![event_id],
            |row| row.get(0),
        )
        .unwrap();
    assert!(
        upsert_count >= 1,
        "expected at least one upsert envelope, found {upsert_count}"
    );
}

#[test]
fn expired_token_is_rejected() {
    crate::hlc::ensure_hlc_for_test();
    let conn = test_conn();
    let token = EntityUndoToken {
        snapshot: EntitySnapshot::CalendarEvent {
            event: Box::new(CalendarEvent {
                id: "e".into(),
                title: "x".into(),
                description: None,
                recurrence: None,
                recurrence_exceptions: None,
                timezone: None,
                start_date: "2026-04-20".into(),
                start_time: None,
                end_date: None,
                end_time: None,
                all_day: true,
                location: None,
                url: None,
                color: None,
                event_type: CanonicalCalendarEventType::Event,
                person_name: None,
                created_at: "2026-04-19T08:00:00Z".into(),
                updated_at: "2026-04-19T08:00:00Z".into(),
                attendees: None,
            }),
            linked_task_ids: vec![],
        },
        expires_at: lorvex_domain::format_sync_timestamp(
            chrono::Utc::now() - chrono::Duration::seconds(60),
        ),
    };
    let token_str = serde_json::to_string(&token).unwrap();
    let now = lorvex_domain::format_sync_timestamp(chrono::Utc::now());
    let err = undo_delete_entity_internal(&conn, &token_str, &now)
        .expect_err("expired token must reject");
    match err {
        AppError::Validation(msg) => assert!(msg.contains("expired"), "got: {msg}"),
        other => panic!("expected Validation, got {other:?}"),
    }
}

#[test]
fn list_round_trip_restores_row_and_enqueues_upsert() {
    // #3420: snapshot the list, delete it, replay via the
    // undo token. The restored row must reappear in `lists` and
    // a fresh upsert envelope must hit `sync_outbox`.
    crate::hlc::ensure_hlc_for_test();
    let conn = test_conn();
    let list_id = "01966a3f-7c8b-7d4e-8f3a-00000000b101";
    conn.execute(
        "INSERT INTO lists (id, name, color, icon, description, ai_notes, created_at, updated_at, version) \
         VALUES (?1, ?2, NULL, NULL, NULL, NULL, '2026-04-19T08:00:00Z', '2026-04-19T08:00:00Z', \
                 '0000000000000_0000_seedlistseedlist')",
        params![list_id, "Original"],
    )
    .expect("seed list");

    let snapshot = capture_list_snapshot(&conn, list_id).expect("snapshot");
    conn.execute("DELETE FROM lists WHERE id = ?1", params![list_id])
        .unwrap();
    let token = build_undo_token(snapshot).expect("token");
    let now = lorvex_domain::format_sync_timestamp(chrono::Utc::now());
    let restored = undo_delete_entity_internal(&conn, &token, &now).expect("undo");
    let value = match restored {
        RestoredEntity::List(v) => v,
        RestoredEntity::CalendarEvent(_) => panic!("expected List variant"),
    };
    assert_eq!(value.get("id").and_then(|v| v.as_str()), Some(list_id));
    assert_eq!(value.get("name").and_then(|v| v.as_str()), Some("Original"));

    let row_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM lists WHERE id = ?1",
            params![list_id],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(row_count, 1, "list row must be restored");

    let upsert_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = 'list' \
             AND entity_id = ?1 AND operation = 'upsert'",
            params![list_id],
            |r| r.get(0),
        )
        .unwrap();
    assert!(
        upsert_count >= 1,
        "expected at least one upsert envelope, found {upsert_count}"
    );
}

#[test]
fn calendar_event_undo_preserves_original_created_at() {
    // #3434: snapshot-undo must not rewrite `created_at` to the
    // moment of restoration — the row's birth-time is part of its
    // identity and feeds analytics + sort orders.
    crate::hlc::ensure_hlc_for_test();
    let conn = test_conn();
    let event_id = lorvex_domain::new_entity_id_string();
    let original_created_at = "2026-04-19T08:00:00Z";
    seed_event(&conn, &event_id, "Standup");

    let snapshot = capture_calendar_event_snapshot(&conn, &event_id).expect("snapshot");
    conn.execute(
        "DELETE FROM calendar_events WHERE id = ?1",
        params![event_id],
    )
    .unwrap();

    let token = build_undo_token(snapshot).expect("token");
    // Use a strictly-later `now` so the test can detect a
    // regression that would stamp the restored row's `created_at`
    // with `now` instead of preserving the snapshot value.
    let now = "2026-04-20T10:00:00Z".to_string();
    let restored = undo_delete_entity_internal(&conn, &token, &now).expect("undo should succeed");
    let value = match restored {
        RestoredEntity::CalendarEvent(v) => v,
        RestoredEntity::List(_) => panic!("expected CalendarEvent variant"),
    };
    assert_eq!(
        value.get("created_at").and_then(|v| v.as_str()),
        Some(original_created_at),
        "undo must preserve the snapshot's original created_at"
    );
    assert_eq!(
        value.get("updated_at").and_then(|v| v.as_str()),
        Some(now.as_str()),
        "undo must refresh updated_at to the undo moment"
    );

    // Also confirm via direct DB read so we know the value was
    // persisted, not just echoed through `restored`.
    let persisted_created_at: String = conn
        .query_row(
            "SELECT created_at FROM calendar_events WHERE id = ?1",
            params![event_id],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(persisted_created_at, original_created_at);
}

#[test]
fn list_undo_preserves_original_created_at() {
    // #3434: same invariant as the calendar event test above.
    crate::hlc::ensure_hlc_for_test();
    let conn = test_conn();
    let list_id = "01966a3f-7c8b-7d4e-8f3a-00000000b102";
    // List repo normalizes timestamps to canonical millisecond-Z
    // form on read, so seed in that form to keep the assertion
    // byte-stable. The bug under test is "row's birth-time
    // survives the undo round-trip", which is independent of the
    // canonicalization layer.
    let original_created_at = "2026-04-19T08:00:00.000Z";
    conn.execute(
        "INSERT INTO lists (id, name, color, icon, description, ai_notes, created_at, updated_at, version) \
         VALUES (?1, ?2, NULL, NULL, NULL, NULL, ?3, ?3, \
                 '0000000000000_0000_seedlistseedlist')",
        params![list_id, "Original", original_created_at],
    )
    .expect("seed list");

    let snapshot = capture_list_snapshot(&conn, list_id).expect("snapshot");
    conn.execute("DELETE FROM lists WHERE id = ?1", params![list_id])
        .unwrap();
    let token = build_undo_token(snapshot).expect("token");
    let now = "2026-04-20T10:00:00.000Z".to_string();
    let restored = undo_delete_entity_internal(&conn, &token, &now).expect("undo");
    let value = match restored {
        RestoredEntity::List(v) => v,
        RestoredEntity::CalendarEvent(_) => panic!("expected List variant"),
    };
    assert_eq!(
        value.get("created_at").and_then(|v| v.as_str()),
        Some(original_created_at),
        "undo must preserve the snapshot's original created_at"
    );
    assert_eq!(
        value.get("updated_at").and_then(|v| v.as_str()),
        Some(now.as_str()),
        "undo must refresh updated_at to the undo moment"
    );

    let persisted_created_at: String = conn
        .query_row(
            "SELECT created_at FROM lists WHERE id = ?1",
            params![list_id],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(persisted_created_at, original_created_at);
}

/// A deleted calendar event that carried attendees must have those
/// attendees restored by undo. The cascade delete on
/// `calendar_events` clears `calendar_event_attendees`, so
/// `restore_calendar_event` must re-insert both the event row and
/// its attendees; otherwise undo reappears the event with an empty
/// attendee list.
#[test]
fn undo_restores_attendee_rows() {
    crate::hlc::ensure_hlc_for_test();
    let conn = test_conn();
    let event_id = lorvex_domain::new_entity_id_string();
    seed_event(&conn, &event_id, "Standup");
    // Seed two attendees directly so the snapshot's read path
    // picks them up via `load_event_attendees`.
    conn.execute(
        "INSERT INTO calendar_event_attendees (event_id, attendee_id, email, name, status) \
         VALUES (?1, 'email:alice@example.com', 'alice@example.com', 'Alice', 'accepted'),
                (?1, 'email:bob@example.com', 'bob@example.com', 'Bob', 'tentative')",
        params![event_id],
    )
    .expect("seed attendees");

    let snapshot = capture_calendar_event_snapshot(&conn, &event_id).expect("snapshot");
    // The cascade delete clears the event AND its attendees, as
    // it would in production.
    conn.execute(
        "DELETE FROM calendar_events WHERE id = ?1",
        params![event_id],
    )
    .unwrap();
    let attendees_after_delete: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM calendar_event_attendees WHERE event_id = ?1",
            params![event_id],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(attendees_after_delete, 0, "cascade must wipe attendees");

    let token = build_undo_token(snapshot).expect("token");
    let now = lorvex_domain::format_sync_timestamp(chrono::Utc::now());
    let restored = undo_delete_entity_internal(&conn, &token, &now).expect("undo should succeed");
    match restored {
        RestoredEntity::CalendarEvent(_) => {}
        RestoredEntity::List(_) => panic!("expected CalendarEvent variant"),
    }

    // The two attendee rows are back, keyed by normalized email
    // with names + statuses intact.
    let mut rows: Vec<(String, Option<String>, Option<String>)> = conn
        .prepare(
            "SELECT email, name, status FROM calendar_event_attendees \
             WHERE event_id = ?1 ORDER BY email",
        )
        .unwrap()
        .query_map(params![event_id], |row| {
            Ok((row.get(0)?, row.get(1)?, row.get(2)?))
        })
        .unwrap()
        .map(Result::unwrap)
        .collect();
    rows.sort();
    assert_eq!(
        rows,
        vec![
            (
                "alice@example.com".to_string(),
                Some("Alice".to_string()),
                Some("accepted".to_string()),
            ),
            (
                "bob@example.com".to_string(),
                Some("Bob".to_string()),
                Some("tentative".to_string()),
            ),
        ],
        "undo must replay every attendee row, not just the event",
    );
}

#[test]
fn malformed_token_is_rejected() {
    let conn = test_conn();
    let now = lorvex_domain::format_sync_timestamp(chrono::Utc::now());
    let err = undo_delete_entity_internal(&conn, "not-json", &now)
        .expect_err("malformed token must reject");
    assert!(matches!(err, AppError::Validation(_)));
}
