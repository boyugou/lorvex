use super::support::*;

// ===========================================================================
// 8. current_focus apply with embedded task_ids
// ===========================================================================

#[test]
fn current_focus_apply_rebuilds_items() {
    let conn = test_db();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000312a");
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000312b");

    let payload = r#"{
        "briefing": "Focus on the report and review",
        "timezone": "America/New_York",
        "created_at": "2026-03-24T08:00:00.000Z",
        "updated_at": "2026-03-24T08:00:00.000Z",
        "task_ids": ["01966a3f-7c8b-7d4e-8f3a-00000000312a", "01966a3f-7c8b-7d4e-8f3a-00000000312b"]
    }"#;
    let env = upsert_envelope(naming::ENTITY_CURRENT_FOCUS, "2026-03-24", V2, payload);
    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);

    // Verify parent row.
    let briefing: String = conn
        .query_row(
            "SELECT briefing FROM current_focus WHERE date = '2026-03-24'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(briefing, "Focus on the report and review");

    // Verify materialized items.
    let item_count = count_rows(&conn, "current_focus_items", "date = '2026-03-24'");
    assert_eq!(item_count, 2);

    // Check ordering.
    let first_task: String = conn
        .query_row(
            "SELECT task_id FROM current_focus_items WHERE date = '2026-03-24' AND position = 0",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(first_task, "01966a3f-7c8b-7d4e-8f3a-00000000312a");
}

// ===========================================================================
// 9. focus_schedule apply with embedded blocks
// ===========================================================================

#[test]
fn focus_schedule_apply_rebuilds_blocks() {
    let conn = test_db();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000003136");

    let payload = r#"{
        "rationale": "Morning deep work, afternoon meetings",
        "timezone": "America/New_York",
        "created_at": "2026-03-24T07:00:00.000Z",
        "updated_at": "2026-03-24T07:00:00.000Z",
        "blocks": [
            {
                "block_type": "task",
                "start_time": 540,
                "end_time": 660,
                "task_id": "01966a3f-7c8b-7d4e-8f3a-000000003136",
                "title": "Deep work session"
            },
            {
                "block_type": "buffer",
                "start_time": 660,
                "end_time": 720,
                "title": "Break"
            }
        ]
    }"#;
    let env = upsert_envelope(naming::ENTITY_FOCUS_SCHEDULE, "2026-03-24", V2, payload);
    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);

    // Verify parent row.
    let rationale: String = conn
        .query_row(
            "SELECT rationale FROM focus_schedule WHERE date = '2026-03-24'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(rationale, "Morning deep work, afternoon meetings");

    // Verify blocks.
    let block_count = count_rows(
        &conn,
        "focus_schedule_blocks",
        "schedule_date = '2026-03-24'",
    );
    assert_eq!(block_count, 2);

    // Verify first block details.
    let (block_type, start, end): (String, i64, i64) = conn
        .query_row(
            "SELECT block_type, start_time, end_time FROM focus_schedule_blocks
             WHERE schedule_date = '2026-03-24' AND position = 0",
            [],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?)),
        )
        .unwrap();
    assert_eq!(block_type, "task");
    assert_eq!(start, 540);
    assert_eq!(end, 660);
}

// ===========================================================================
// 10. daily_review apply with embedded links
// ===========================================================================

#[test]
fn daily_review_apply_rebuilds_links() {
    let conn = test_db();
    seed_list(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000310e");
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000003132");
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000003133");

    let payload = r#"{
        "summary": "Productive day. Completed 5 tasks.",
        "mood": 4,
        "energy_level": 3,
        "wins": "Finished the report",
        "blockers": "None",
        "timezone": "America/New_York",
        "created_at": "2026-03-24T22:00:00.000Z",
        "updated_at": "2026-03-24T22:00:00.000Z",
        "linked_task_ids": ["01966a3f-7c8b-7d4e-8f3a-000000003132", "01966a3f-7c8b-7d4e-8f3a-000000003133"],
        "linked_list_ids": ["01966a3f-7c8b-7d4e-8f3a-00000000310e"]
    }"#;
    let env = upsert_envelope(naming::ENTITY_DAILY_REVIEW, "2026-03-24", V2, payload);
    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);

    // Verify parent row.
    let summary: String = conn
        .query_row(
            "SELECT summary FROM daily_reviews WHERE date = '2026-03-24'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(summary, "Productive day. Completed 5 tasks.");

    // Verify task links.
    let task_link_count = count_rows(
        &conn,
        "daily_review_task_links",
        "review_date = '2026-03-24'",
    );
    assert_eq!(task_link_count, 2);

    // Verify list links.
    let list_link_count = count_rows(
        &conn,
        "daily_review_list_links",
        "review_date = '2026-03-24'",
    );
    assert_eq!(list_link_count, 1);
}
