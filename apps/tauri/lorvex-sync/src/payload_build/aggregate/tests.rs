use super::{build_aggregate_payload, AGGREGATE_ROOT_KINDS_WITH_EMBEDDED_CHILDREN};
use lorvex_domain::naming::{
    ENTITY_CALENDAR_EVENT, ENTITY_CURRENT_FOCUS, ENTITY_DAILY_REVIEW, ENTITY_FOCUS_SCHEDULE,
};
use lorvex_store::open_db_in_memory;
use lorvex_store::test_support::{ListBuilder, TaskBuilder};
use rusqlite::{params, Connection};
use serde_json::Value;

fn seed_schedule_header(conn: &Connection, date: &str) {
    conn.execute(
        "INSERT INTO focus_schedule (date, rationale, timezone, version, created_at, updated_at)
         VALUES (?1, 'rationale', 'UTC', '0000000000000_0000_0000000000000000',
                 '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')",
        params![date],
    )
    .unwrap();
}

#[test]
fn current_focus_payload_embeds_task_ids_in_position_order() {
    let conn = open_db_in_memory().unwrap();
    let date = "2026-04-01";
    conn.execute(
        "INSERT INTO current_focus (date, briefing, timezone, version, created_at, updated_at)
         VALUES (?1, 'brief', 'UTC', '0000000000000_0000_0000000000000000',
                 '2026-04-01T00:00:00.000Z', '2026-04-01T00:00:00.000Z')",
        params![date],
    )
    .unwrap();
    // Insert tasks then focus items; rely on the storage primitives for materialization.
    ListBuilder::new("list-default")
        .name("L")
        .created_at("2026-04-01T00:00:00.000Z")
        .or_ignore(true)
        .insert(&conn);
    for tid in ["t-2", "t-1"] {
        TaskBuilder::new(tid)
            .title("T")
            .list_id(Some("list-default"))
            .created_at("2026-04-01T00:00:00.000Z")
            .insert(&conn);
    }
    lorvex_store::current_focus_items::materialize_focus_items(
        &conn,
        date,
        &["t-2".to_string(), "t-1".to_string()],
    )
    .unwrap();

    let payload = build_aggregate_payload(&conn, ENTITY_CURRENT_FOCUS, date)
        .unwrap()
        .expect("aggregate payload should be present");
    let task_ids = payload.get("task_ids").and_then(Value::as_array).unwrap();
    assert_eq!(
        task_ids
            .iter()
            .map(|v| v.as_str().unwrap())
            .collect::<Vec<_>>(),
        vec!["t-2", "t-1"],
    );
}

#[test]
fn focus_schedule_payload_embeds_blocks() {
    let conn = open_db_in_memory().unwrap();
    let date = "2026-04-02";
    seed_schedule_header(&conn, date);
    conn.execute(
        "INSERT INTO focus_schedule_blocks
             (schedule_date, position, block_type, start_time, end_time, title)
         VALUES (?1, 0, 'buffer', 540, 600, 'Warm up'),
                (?1, 1, 'buffer', 600, 660, 'Plan')",
        params![date],
    )
    .unwrap();
    let payload = build_aggregate_payload(&conn, ENTITY_FOCUS_SCHEDULE, date)
        .unwrap()
        .expect("focus_schedule payload");
    let blocks = payload.get("blocks").and_then(Value::as_array).unwrap();
    assert_eq!(blocks.len(), 2);
    assert_eq!(blocks[0]["start_time"].as_i64(), Some(540));
    assert_eq!(blocks[1]["title"].as_str(), Some("Plan"));
}

#[test]
fn daily_review_payload_embeds_links() {
    let conn = open_db_in_memory().unwrap();
    let date = "2026-04-03";
    conn.execute(
        "INSERT INTO daily_reviews (date, summary, version, created_at, updated_at)
         VALUES (?1, 'summary', '0000000000000_0000_0000000000000000',
                 '2026-04-03T00:00:00.000Z', '2026-04-03T00:00:00.000Z')",
        params![date],
    )
    .unwrap();
    ListBuilder::new("list-x")
        .name("X")
        .created_at("2026-04-03T00:00:00.000Z")
        .insert(&conn);
    TaskBuilder::new("t-x")
        .title("T")
        .list_id(Some("list-x"))
        .created_at("2026-04-03T00:00:00.000Z")
        .insert(&conn);
    lorvex_store::daily_review_ops::materialize_review_task_links(
        &conn,
        date,
        &["t-x".to_string()],
    )
    .unwrap();
    lorvex_store::daily_review_ops::materialize_review_list_links(
        &conn,
        date,
        &["list-x".to_string()],
    )
    .unwrap();

    let payload = build_aggregate_payload(&conn, ENTITY_DAILY_REVIEW, date)
        .unwrap()
        .expect("daily_review payload");
    assert_eq!(
        payload["linked_task_ids"]
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_str().unwrap())
            .collect::<Vec<_>>(),
        vec!["t-x"],
    );
    assert_eq!(
        payload["linked_list_ids"]
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_str().unwrap())
            .collect::<Vec<_>>(),
        vec!["list-x"],
    );
}

#[test]
fn calendar_event_payload_embeds_attendees() {
    let conn = open_db_in_memory().unwrap();
    conn.execute(
        "INSERT INTO calendar_events
             (id, title, start_date, all_day, event_type, series_id,
              recurrence_instance_date, version, created_at, updated_at)
         VALUES ('evt-1', 'Standup', '2026-04-04', 0, 'event',
                 'series-1', '2026-04-04',
                 '0000000000000_0000_0000000000000000',
                 '2026-04-04T00:00:00.000Z', '2026-04-04T00:00:00.000Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO calendar_event_attendees (event_id, attendee_id, email, name, status)
         VALUES ('evt-1', 'email:a@example.com', 'a@example.com', 'A', 'accepted')",
        [],
    )
    .unwrap();
    let payload = build_aggregate_payload(&conn, ENTITY_CALENDAR_EVENT, "evt-1")
        .unwrap()
        .expect("calendar_event payload");
    let attendees = payload["attendees"].as_array().unwrap();
    assert_eq!(attendees.len(), 1);
    assert_eq!(attendees[0]["email"].as_str(), Some("a@example.com"));
    assert_eq!(payload["all_day"], Value::Bool(false));
    assert_eq!(payload["series_id"].as_str(), Some("series-1"));
    assert_eq!(
        payload["recurrence_instance_date"].as_str(),
        Some("2026-04-04")
    );
}

#[test]
fn non_aggregate_types_return_none() {
    let conn = open_db_in_memory().unwrap();
    assert!(build_aggregate_payload(&conn, "task", "task-x")
        .unwrap()
        .is_none());
    assert!(build_aggregate_payload(&conn, "list", "list-x")
        .unwrap()
        .is_none());
    assert!(build_aggregate_payload(&conn, "habit", "h-x")
        .unwrap()
        .is_none());
    assert!(build_aggregate_payload(&conn, "preference", "theme")
        .unwrap()
        .is_none());
}

#[test]
fn known_aggregates_return_none_when_row_missing() {
    let conn = open_db_in_memory().unwrap();
    for kind in AGGREGATE_ROOT_KINDS_WITH_EMBEDDED_CHILDREN {
        let et = kind.as_str();
        assert!(
            build_aggregate_payload(&conn, et, "missing-id")
                .unwrap()
                .is_none(),
            "expected None for missing {et}"
        );
    }
}

/// every entity_type registered in
/// `AGGREGATE_ROOTS_WITH_EMBEDDED_CHILDREN` MUST have a matching
/// dispatch arm in `build_aggregate_payload`. The dispatcher hard-
/// fails if a future maintainer adds a new entry to the registry
/// without wiring up the builder; this test pre-empts that mistake
/// by asserting every registered type round-trips cleanly to either
/// `Ok(Some(_))` (row present) or `Ok(None)` (row missing) — never
/// the `Err(StoreError::Invariant)` that signals a missing arm.
#[test]
fn every_registered_aggregate_resolves_through_a_builder_arm() {
    let conn = open_db_in_memory().unwrap();
    for kind in AGGREGATE_ROOT_KINDS_WITH_EMBEDDED_CHILDREN {
        let et = kind.as_str();
        let result = build_aggregate_payload(&conn, et, "missing-id");
        match result {
            Ok(_) => {}
            Err(err) => {
                panic!("registered aggregate {et} reached the missing-arm branch: {err}")
            }
        }
    }
}
