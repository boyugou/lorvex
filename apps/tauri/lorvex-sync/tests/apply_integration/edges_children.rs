use super::support::*;

// ===========================================================================
// 11. task_tag edge apply
// ===========================================================================

#[test]
fn task_tag_edge_apply() {
    let conn = test_db();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000003139");
    seed_tag(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000003122",
        "urgent",
        "urgent",
    );

    let payload = r#"{
        "task_id": "01966a3f-7c8b-7d4e-8f3a-000000003139",
        "tag_id": "01966a3f-7c8b-7d4e-8f3a-000000003122",
        "created_at": "2026-03-20T10:00:00.000Z"
    }"#;
    let env = upsert_envelope(
        naming::EDGE_TASK_TAG,
        "01966a3f-7c8b-7d4e-8f3a-000000003139:01966a3f-7c8b-7d4e-8f3a-000000003122",
        V2,
        payload,
    );
    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);

    // Verify row exists.
    let exists = count_rows(
        &conn,
        "task_tags",
        "task_id = '01966a3f-7c8b-7d4e-8f3a-000000003139' AND tag_id = '01966a3f-7c8b-7d4e-8f3a-000000003122'",
    );
    assert_eq!(exists, 1);
}

// ===========================================================================
// 12. task_dependency edge apply
// ===========================================================================

#[test]
fn task_dependency_edge_apply() {
    let conn = test_db();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000003130");
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000003131");

    let payload = r#"{
        "task_id": "01966a3f-7c8b-7d4e-8f3a-000000003130",
        "depends_on_task_id": "01966a3f-7c8b-7d4e-8f3a-000000003131",
        "created_at": "2026-03-20T10:00:00.000Z"
    }"#;
    let env = upsert_envelope(
        naming::EDGE_TASK_DEPENDENCY,
        "01966a3f-7c8b-7d4e-8f3a-000000003130:01966a3f-7c8b-7d4e-8f3a-000000003131",
        V2,
        payload,
    );
    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);

    // Verify row exists.
    let exists = count_rows(
        &conn,
        "task_dependencies",
        "task_id = '01966a3f-7c8b-7d4e-8f3a-000000003130' AND depends_on_task_id = '01966a3f-7c8b-7d4e-8f3a-000000003131'",
    );
    assert_eq!(exists, 1);
}

// ===========================================================================
// 13. Edge delete: task_tag
// ===========================================================================

#[test]
fn edge_delete_task_tag() {
    let conn = test_db();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000003134");
    seed_tag(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000311f",
        "review",
        "review",
    );

    // First, create the edge.
    let payload = r#"{
        "task_id": "01966a3f-7c8b-7d4e-8f3a-000000003134",
        "tag_id": "01966a3f-7c8b-7d4e-8f3a-00000000311f",
        "created_at": "2026-03-20T10:00:00.000Z"
    }"#;
    let env_create = upsert_envelope(
        naming::EDGE_TASK_TAG,
        "01966a3f-7c8b-7d4e-8f3a-000000003134:01966a3f-7c8b-7d4e-8f3a-00000000311f",
        V2,
        payload,
    );
    apply_envelope(&conn, &env_create).unwrap();
    assert_eq!(
        count_rows(
            &conn,
            "task_tags",
            "task_id = '01966a3f-7c8b-7d4e-8f3a-000000003134' AND tag_id = '01966a3f-7c8b-7d4e-8f3a-00000000311f'"
        ),
        1
    );

    // Now delete the edge.
    let env_delete = delete_envelope(
        naming::EDGE_TASK_TAG,
        "01966a3f-7c8b-7d4e-8f3a-000000003134:01966a3f-7c8b-7d4e-8f3a-00000000311f",
        V3,
    );
    let result = apply_envelope(&conn, &env_delete).unwrap();
    assert_eq!(result, ApplyResult::Applied);

    // Verify row is removed.
    assert_eq!(
        count_rows(
            &conn,
            "task_tags",
            "task_id = '01966a3f-7c8b-7d4e-8f3a-000000003134' AND tag_id = '01966a3f-7c8b-7d4e-8f3a-00000000311f'"
        ),
        0
    );
}

// ===========================================================================
// 14. task_reminder child entity upsert
// ===========================================================================

#[test]
fn task_reminder_upsert() {
    let conn = test_db();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000003138");

    let payload = r#"{
        "task_id": "01966a3f-7c8b-7d4e-8f3a-000000003138",
        "reminder_at": "2026-03-25T09:00:00.000Z",
        "created_at": "2026-03-20T10:00:00.000Z",
        "updated_at": "2026-03-20T10:00:00.000Z"
    }"#;
    let env = upsert_envelope(
        naming::ENTITY_TASK_REMINDER,
        "01966a3f-7c8b-7d4e-8f3a-00000000310f",
        V2,
        payload,
    );
    let result = apply_envelope(&conn, &env).unwrap();
    assert_eq!(result, ApplyResult::Applied);

    // Verify row.
    let (task_id, reminder_at): (String, String) = conn
        .query_row(
            "SELECT task_id, reminder_at FROM task_reminders WHERE id = '01966a3f-7c8b-7d4e-8f3a-00000000310f'",
            [],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .unwrap();
    assert_eq!(task_id, "01966a3f-7c8b-7d4e-8f3a-000000003138");
    assert_eq!(reminder_at, "2026-03-25T09:00:00.000Z");
}

// ===========================================================================
// 15. child entity upsert
// ===========================================================================
