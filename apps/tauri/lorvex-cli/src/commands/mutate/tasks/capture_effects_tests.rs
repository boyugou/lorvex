use super::capture_effects::*;
use lorvex_domain::naming::{EDGE_TASK_TAG, ENTITY_TASK};
use lorvex_runtime::read_local_change_seq;

#[test]
fn create_captured_task_with_conn_writes_task_outbox_and_change_seq() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    // The schema seeds 'inbox' list + default_list_id preference,
    // so no extra seeding is needed.

    let task_id = create_captured_task_with_conn(
        &mut conn,
        "Ship CLI capture",
        CaptureTaskOptions::default(),
    )
    .expect("capture task");

    let (stored_title, stored_list_id): (String, String) = conn
        .query_row(
            "SELECT title, list_id FROM tasks WHERE id = ?1",
            [&task_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load stored task");
    assert_eq!(stored_title, "Ship CLI capture");
    assert_eq!(stored_list_id, "inbox");

    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            [ENTITY_TASK, task_id.as_str()],
            |row| row.get(0),
        )
        .expect("count sync outbox entries");
    assert_eq!(outbox_count, 1);

    let seq = read_local_change_seq(&conn).expect("read local change seq");
    assert_eq!(seq, 1);
}

#[test]
fn create_captured_task_with_conn_rejects_blank_title() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");

    let error = create_captured_task_with_conn(&mut conn, "   ", CaptureTaskOptions::default())
        .expect_err("blank titles should fail");
    assert!(error.to_string().contains("task title must not be empty"));
}

#[test]
fn create_captured_task_with_conn_uses_seeded_inbox_by_default() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");

    // With the seeded Inbox list, capture should succeed without any extra setup.
    let task_id = create_captured_task_with_conn(
        &mut conn,
        "Needs classification",
        CaptureTaskOptions::default(),
    )
    .expect("capture with seeded inbox should succeed");
    let list_id: String = conn
        .query_row(
            "SELECT list_id FROM tasks WHERE id = ?1",
            [&task_id],
            |row| row.get(0),
        )
        .expect("load task list_id");
    assert_eq!(list_id, "inbox");
}

#[test]
fn create_captured_task_with_conn_persists_structured_fields() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");

    let task_id = create_captured_task_with_conn(
        &mut conn,
        "Structured capture",
        CaptureTaskOptions {
            priority: Some(2),
            due_date: Some("2026-05-01"),
            planned_date: Some("2026-04-30"),
            estimated_minutes: Some(45),
            tags: Some(&[
                "Work".to_string(),
                "work".to_string(),
                "Deep Work".to_string(),
            ]),
            ..CaptureTaskOptions::default()
        },
    )
    .expect("capture task");

    let (priority, due_date, planned_date, estimated_minutes): (
        Option<i64>,
        Option<String>,
        Option<String>,
        Option<i64>,
    ) = conn
        .query_row(
            "SELECT priority, due_date, planned_date, estimated_minutes FROM tasks WHERE id = ?1",
            [&task_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        )
        .expect("load stored task fields");
    assert_eq!(priority, Some(2));
    assert_eq!(due_date.as_deref(), Some("2026-05-01"));
    assert_eq!(planned_date.as_deref(), Some("2026-04-30"));
    assert_eq!(estimated_minutes, Some(45));

    let tags: Vec<String> = {
        let mut stmt = conn
            .prepare(
                "SELECT t.display_name
                 FROM task_tags tt
                 JOIN tags t ON t.id = tt.tag_id
                 WHERE tt.task_id = ?1
                 ORDER BY t.display_name",
            )
            .expect("prepare tag query");
        stmt.query_map([&task_id], |row| row.get::<_, String>(0))
            .expect("query tags")
            .collect::<Result<Vec<_>, _>>()
            .expect("collect tags")
    };
    assert_eq!(tags, vec!["deep work".to_string(), "work".to_string()]);

    let edge_outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1",
            [EDGE_TASK_TAG],
            |row| row.get(0),
        )
        .expect("count task-tag edge outbox entries");
    assert_eq!(edge_outbox_count, 2);
}
