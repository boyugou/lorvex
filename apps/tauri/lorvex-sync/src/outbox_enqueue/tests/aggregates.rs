use super::support::{
    enqueue_entity_upsert, naming, params, parse_outbox_payload, seed_default_list_and_tasks,
    setup_hlc, test_db, EnqueueError, Value,
};

#[test]
fn aggregate_with_children_focus_schedule_carries_blocks() {
    let conn = test_db();
    let mut hlc = setup_hlc();
    let date = "2026-04-10";
    conn.execute(
        "INSERT INTO focus_schedule (date, rationale, timezone, version,
                                      created_at, updated_at)
         VALUES (?1, 'plan', 'UTC', '0000000000000_0000_0000000000000000',
                 '2026-04-10T00:00:00.000Z', '2026-04-10T00:00:00.000Z')",
        params![date],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO focus_schedule_blocks
             (schedule_date, position, block_type, start_time, end_time, title)
         VALUES (?1, 0, 'buffer', 540, 600, 'Warm up'),
                (?1, 1, 'buffer', 600, 660, 'Plan')",
        params![date],
    )
    .unwrap();

    enqueue_entity_upsert(
        &conn,
        naming::ENTITY_FOCUS_SCHEDULE,
        date,
        &mut hlc,
        "dev-001",
    )
    .expect("focus_schedule enqueue");

    let payload = parse_outbox_payload(&conn, naming::ENTITY_FOCUS_SCHEDULE, date);
    let blocks = payload
        .get("blocks")
        .and_then(Value::as_array)
        .expect("blocks must be present in focus_schedule payload");
    assert_eq!(blocks.len(), 2, "envelope must carry both seeded blocks");
    assert_eq!(blocks[0]["start_time"].as_i64(), Some(540));
    assert_eq!(blocks[1]["title"].as_str(), Some("Plan"));
}

#[test]
fn aggregate_with_children_current_focus_carries_task_ids() {
    let conn = test_db();
    let mut hlc = setup_hlc();
    let date = "2026-04-11";
    seed_default_list_and_tasks(
        &conn,
        &[
            "01966a3f-7c8b-7d4e-8f3a-000000002152",
            "01966a3f-7c8b-7d4e-8f3a-000000002153",
        ],
    );
    conn.execute(
        "INSERT INTO current_focus (date, briefing, timezone, version,
                                     created_at, updated_at)
         VALUES (?1, 'today', 'UTC', '0000000000000_0000_0000000000000000',
                 '2026-04-11T00:00:00.000Z', '2026-04-11T00:00:00.000Z')",
        params![date],
    )
    .unwrap();
    lorvex_store::current_focus_items::materialize_focus_items(
        &conn,
        date,
        &[
            "01966a3f-7c8b-7d4e-8f3a-000000002153".to_string(),
            "01966a3f-7c8b-7d4e-8f3a-000000002152".to_string(),
        ],
    )
    .unwrap();

    enqueue_entity_upsert(
        &conn,
        naming::ENTITY_CURRENT_FOCUS,
        date,
        &mut hlc,
        "dev-001",
    )
    .expect("current_focus enqueue");

    let payload = parse_outbox_payload(&conn, naming::ENTITY_CURRENT_FOCUS, date);
    let task_ids: Vec<&str> = payload["task_ids"]
        .as_array()
        .expect("task_ids must be present")
        .iter()
        .map(|v| v.as_str().unwrap())
        .collect();
    assert_eq!(
        task_ids,
        vec![
            "01966a3f-7c8b-7d4e-8f3a-000000002153",
            "01966a3f-7c8b-7d4e-8f3a-000000002152"
        ]
    );
}

#[test]
fn aggregate_with_children_daily_review_carries_links() {
    let conn = test_db();
    let mut hlc = setup_hlc();
    let date = "2026-04-12";
    seed_default_list_and_tasks(&conn, &["01966a3f-7c8b-7d4e-8f3a-000000002154"]);
    conn.execute(
        "INSERT INTO daily_reviews (date, summary, version, created_at, updated_at)
         VALUES (?1, 'good day', '0000000000000_0000_0000000000000000',
                 '2026-04-12T00:00:00.000Z', '2026-04-12T00:00:00.000Z')",
        params![date],
    )
    .unwrap();
    lorvex_store::daily_review_ops::materialize_review_task_links(
        &conn,
        date,
        &["01966a3f-7c8b-7d4e-8f3a-000000002154".to_string()],
    )
    .unwrap();
    lorvex_store::daily_review_ops::materialize_review_list_links(
        &conn,
        date,
        &["01966a3f-7c8b-7d4e-8f3a-000000002136".to_string()],
    )
    .unwrap();

    enqueue_entity_upsert(
        &conn,
        naming::ENTITY_DAILY_REVIEW,
        date,
        &mut hlc,
        "dev-001",
    )
    .expect("daily_review enqueue");

    let payload = parse_outbox_payload(&conn, naming::ENTITY_DAILY_REVIEW, date);
    assert_eq!(
        payload["linked_task_ids"]
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_str().unwrap())
            .collect::<Vec<_>>(),
        vec!["01966a3f-7c8b-7d4e-8f3a-000000002154"],
    );
    assert_eq!(
        payload["linked_list_ids"]
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_str().unwrap())
            .collect::<Vec<_>>(),
        vec!["01966a3f-7c8b-7d4e-8f3a-000000002136"],
    );
}

#[test]
fn aggregate_with_children_calendar_event_carries_attendees() {
    let conn = test_db();
    let mut hlc = setup_hlc();
    conn.execute(
        "INSERT INTO calendar_events
             (id, title, start_date, all_day, event_type, version,
              created_at, updated_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000002117', 'Sync test', '2026-04-13', 0, 'event',
                 '0000000000000_0000_0000000000000000',
                 '2026-04-13T00:00:00.000Z', '2026-04-13T00:00:00.000Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO calendar_event_attendees (event_id, attendee_id, email, name, status)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000002117', 'email:a@example.com', 'a@example.com', 'A', 'accepted'),
                ('01966a3f-7c8b-7d4e-8f3a-000000002117', 'email:b@example.com', 'b@example.com', 'B', 'tentative')",
        [],
    )
    .unwrap();

    enqueue_entity_upsert(
        &conn,
        naming::ENTITY_CALENDAR_EVENT,
        "01966a3f-7c8b-7d4e-8f3a-000000002117",
        &mut hlc,
        "dev-001",
    )
    .expect("calendar_event enqueue");

    let payload = parse_outbox_payload(
        &conn,
        naming::ENTITY_CALENDAR_EVENT,
        "01966a3f-7c8b-7d4e-8f3a-000000002117",
    );
    let attendees = payload["attendees"]
        .as_array()
        .expect("attendees must be present");
    assert_eq!(attendees.len(), 2);
    let emails: Vec<&str> = attendees
        .iter()
        .map(|a| a["email"].as_str().unwrap())
        .collect();
    assert!(emails.contains(&"a@example.com"));
    assert!(emails.contains(&"b@example.com"));
    // `all_day` must be a JSON bool, not an integer (apply pipeline
    // expects a typed boolean).
    assert_eq!(payload["all_day"], Value::Bool(false));
}

/// The four aggregates above all go through the same canonical
/// builder. This test guards against a future entity sneaking into
/// `AGGREGATE_ROOTS_WITH_EMBEDDED_CHILDREN` without a corresponding
/// arm in `build_aggregate_payload`; the builder hard-fails on a
/// missing arm and `read_entity_snapshot` propagates that as a
/// store error rather than silently shipping a child-less envelope.
#[test]
fn every_registered_aggregate_root_has_a_builder_arm() {
    let conn = test_db();
    // For each registered aggregate, calling the builder on a
    // missing id must return Ok(None) — never error and never
    // hit the missing-arm branch in the dispatcher (which would
    // imply the dispatcher forgot the arm).
    for kind in crate::payload_build::aggregate::AGGREGATE_ROOT_KINDS_WITH_EMBEDDED_CHILDREN {
        let et = kind.as_str();
        assert!(
            crate::payload_build::aggregate::build_aggregate_payload(&conn, et, "missing")
                .unwrap()
                .is_none(),
            "aggregate root {et} must round-trip through build_aggregate_payload",
        );
    }
    // Sanity: a non-aggregate type must NOT be registered.
    assert!(
        !crate::payload_build::aggregate::kind_is_aggregate_root_with_embedded_children(
            lorvex_domain::naming::EntityKind::Task
        )
    );
}

/// enqueueing a registered aggregate root for an id
/// whose parent header row does not exist must surface as the
/// standard `EntityNotFound`, never as a silent fallthrough to the
/// bare-columns reader. Before the fix, the bare-columns reader
/// would have produced `EntityNotFound` only because the parent
/// table also lacked the row; if the parent existed but the
/// builder returned None for any other reason, the bare-columns
/// reader would have happily shipped a child-less envelope.
#[test]
fn aggregate_with_children_missing_row_surfaces_entity_not_found() {
    let conn = test_db();
    let mut hlc = setup_hlc();
    for kind in crate::payload_build::aggregate::AGGREGATE_ROOT_KINDS_WITH_EMBEDDED_CHILDREN {
        let et = kind.as_str();
        let result = enqueue_entity_upsert(&conn, et, "missing-id", &mut hlc, "dev-001");
        match result {
            Err(EnqueueError::EntityNotFound {
                entity_type,
                entity_id,
            }) => {
                assert_eq!(entity_type, et);
                assert_eq!(entity_id, "missing-id");
            }
            Err(other) => panic!("expected EntityNotFound for missing {et}, got {other:?}"),
            Ok(()) => panic!(
                "expected EntityNotFound for missing {et}, got Ok — \
                 a child-less envelope may have been enqueued"
            ),
        }
    }
}
