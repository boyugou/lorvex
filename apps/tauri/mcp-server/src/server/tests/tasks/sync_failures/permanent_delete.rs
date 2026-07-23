use super::support::*;

#[test]
#[serial_test::serial(hlc)]
fn permanent_delete_task_rolls_back_when_current_focus_cleanup_fails() {
    let server = make_server();
    seed_task(
        &server,
        "task-delete-focus-cleanup-failure",
        "Delete Focus Cleanup Failure",
        "open",
        None,
        None,
        None,
        0,
    );
    seed_current_focus_item(&server, "2026-04-02", "task-delete-focus-cleanup-failure");
    archive_task_for_test(&server, "task-delete-focus-cleanup-failure");
    install_delete_failure_trigger(
        &server,
        "fail_delete_current_focus_item_cleanup",
        "current_focus_items",
    );

    let err = server
        .permanent_delete_task(Parameters(PermanentDeleteTaskArgs {
            id: "task-delete-focus-cleanup-failure".to_string(),
            dry_run: false,
            idempotency_key: None,
        }))
        .expect_err("permanent delete should fail when current focus cleanup fails");

    assert_is_tool_error(&err);
    assert!(task_exists(&server, "task-delete-focus-cleanup-failure"));
    assert_eq!(
        current_focus_item_count(&server, "task-delete-focus-cleanup-failure"),
        1
    );
}

#[test]
#[serial_test::serial(hlc)]
fn permanent_delete_task_rolls_back_when_focus_schedule_cleanup_fails() {
    let server = make_server();
    seed_task(
        &server,
        "task-delete-schedule-cleanup-failure",
        "Delete Schedule Cleanup Failure",
        "open",
        None,
        None,
        None,
        0,
    );
    seed_focus_schedule_block(
        &server,
        "2026-04-03",
        "task-delete-schedule-cleanup-failure",
    );
    archive_task_for_test(&server, "task-delete-schedule-cleanup-failure");
    install_delete_failure_trigger(
        &server,
        "fail_delete_focus_schedule_block_cleanup",
        "focus_schedule_blocks",
    );

    let err = server
        .permanent_delete_task(Parameters(PermanentDeleteTaskArgs {
            id: "task-delete-schedule-cleanup-failure".to_string(),
            dry_run: false,
            idempotency_key: None,
        }))
        .expect_err("permanent delete should fail when focus schedule cleanup fails");

    assert_is_tool_error(&err);
    assert!(task_exists(&server, "task-delete-schedule-cleanup-failure"));
    assert_eq!(
        focus_schedule_block_count(&server, "task-delete-schedule-cleanup-failure"),
        1
    );
}

#[test]
#[serial_test::serial(hlc)]
fn permanent_delete_task_enqueues_plan_aggregate_repairs_after_plan_ref_cleanup() {
    let server = make_server();
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000110",
        "Delete Plan Repair",
        "open",
        None,
        None,
        None,
        0,
    );
    seed_current_focus_item(
        &server,
        "2026-04-04",
        "01966a3f-7c8b-7d4e-8f3a-000000000110",
    );
    seed_focus_schedule_block(
        &server,
        "2026-04-05",
        "01966a3f-7c8b-7d4e-8f3a-000000000110",
    );
    archive_task_for_test(&server, "01966a3f-7c8b-7d4e-8f3a-000000000110");

    server
        .permanent_delete_task(Parameters(PermanentDeleteTaskArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-000000000110".to_string(),
            dry_run: false,
            idempotency_key: None,
        }))
        .expect("permanent_delete_task should succeed");

    assert_eq!(
        current_focus_item_count(&server, "01966a3f-7c8b-7d4e-8f3a-000000000110"),
        0,
        "local current_focus soft refs should be removed"
    );
    assert_eq!(
        focus_schedule_block_count(&server, "01966a3f-7c8b-7d4e-8f3a-000000000110"),
        0,
        "local focus_schedule soft refs should be removed"
    );
    assert!(
        count_outbox_entries(&server, ENTITY_CURRENT_FOCUS, "2026-04-04", "upsert") >= 1,
        "MCP permanent_delete_task must sync repaired current_focus aggregate"
    );
    assert!(
        count_outbox_entries(&server, ENTITY_FOCUS_SCHEDULE, "2026-04-05", "upsert") >= 1,
        "MCP permanent_delete_task must sync repaired focus_schedule aggregate"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn permanent_delete_task_rolls_back_when_plan_aggregate_repair_enqueue_fails() {
    let server = make_server();
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000120",
        "Delete Plan Repair Failure",
        "open",
        None,
        None,
        None,
        0,
    );
    seed_current_focus_item(
        &server,
        "2026-04-06",
        "01966a3f-7c8b-7d4e-8f3a-000000000120",
    );
    seed_focus_schedule_block(
        &server,
        "2026-04-07",
        "01966a3f-7c8b-7d4e-8f3a-000000000120",
    );
    archive_task_for_test(&server, "01966a3f-7c8b-7d4e-8f3a-000000000120");
    install_sync_outbox_entity_failure_trigger(
        &server,
        "fail_focus_schedule_aggregate_repair",
        ENTITY_FOCUS_SCHEDULE,
    );

    let err = server
        .permanent_delete_task(Parameters(PermanentDeleteTaskArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-000000000120".to_string(),
            dry_run: false,
            idempotency_key: None,
        }))
        .expect_err("permanent delete should fail when plan aggregate repair enqueue fails");

    assert_is_tool_error(&err);
    assert!(task_exists(&server, "01966a3f-7c8b-7d4e-8f3a-000000000120"));
    assert_eq!(
        current_focus_item_count(&server, "01966a3f-7c8b-7d4e-8f3a-000000000120"),
        1,
        "current_focus soft-ref cleanup must roll back"
    );
    assert_eq!(
        focus_schedule_block_count(&server, "01966a3f-7c8b-7d4e-8f3a-000000000120"),
        1,
        "focus_schedule soft-ref cleanup must roll back"
    );
    assert_eq!(
        count_outbox_entries(&server, ENTITY_CURRENT_FOCUS, "2026-04-06", "upsert"),
        0,
        "earlier aggregate repairs must roll back when a later repair enqueue fails"
    );
}

/// `permanent_delete_task` must reject a live (non-
/// archived) task so the destructive two-step Trash flow can't be
/// bypassed by the assistant calling the hard-delete tool directly.
#[test]
#[serial_test::serial(hlc)]
fn permanent_delete_task_rejects_live_task_without_archive() {
    let server = make_server();
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000111",
        "Live Delete Rejected",
        "open",
        None,
        None,
        None,
        0,
    );

    let err = server
        .permanent_delete_task(Parameters(PermanentDeleteTaskArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-000000000111".to_string(),
            dry_run: false,
            idempotency_key: None,
        }))
        .expect_err("permanent_delete_task should reject non-archived task");

    assert!(
        err.contains("archive_task"),
        "error should reference archive_task, got: {err}"
    );
    assert!(task_exists(&server, "01966a3f-7c8b-7d4e-8f3a-000000000111"));
}

#[test]
#[serial_test::serial(hlc)]
fn permanent_delete_task_emits_child_delete_envelopes_and_tombstones() {
    let server = make_server();
    seed_list(&server, "list-delete-cascade");
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-00000000010f",
        "Delete Cascade",
        "open",
        Some("list-delete-cascade"),
        None,
        None,
        0,
    );
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000c01",
        "Dependency Source",
        "open",
        Some("list-delete-cascade"),
        None,
        None,
        0,
    );
    seed_task(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000c02",
        "Dependency Target",
        "open",
        Some("list-delete-cascade"),
        None,
        None,
        0,
    );
    archive_task_for_test(&server, "01966a3f-7c8b-7d4e-8f3a-00000000010f");

    server
        .with_conn(|conn| {
            conn.execute(
                "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
                 VALUES ('01966a3f-7c8b-7d4e-8f3a-000000001201', 'Delete Cascade Tag', 'delete cascade tag',
                         '0000000000000_0000_0000000000000000', '2026-03-01T00:00:00Z', '2026-03-01T00:00:00Z')",
                [],
            )
            .map_err(to_error_message)?;
            conn.execute(
                "INSERT INTO task_tags (task_id, tag_id, version, created_at)
                 VALUES ('01966a3f-7c8b-7d4e-8f3a-00000000010f', '01966a3f-7c8b-7d4e-8f3a-000000001201',
                         '0000000000000_0000_0000000000000000', '2026-03-01T00:00:00Z')",
                [],
            )
            .map_err(to_error_message)?;
            conn.execute(
                "INSERT INTO task_checklist_items
                    (id, task_id, position, text, version, created_at, updated_at)
                 VALUES ('01966a3f-7c8b-7d4e-8f3a-000000001202', '01966a3f-7c8b-7d4e-8f3a-00000000010f', 0, 'Checklist',
                         '0000000000000_0000_0000000000000000', '2026-03-01T00:00:00Z', '2026-03-01T00:00:00Z')",
                [],
            )
            .map_err(to_error_message)?;
            conn.execute(
                "INSERT INTO calendar_events
                    (id, title, start_date, all_day, version, created_at, updated_at)
                 VALUES ('01966a3f-7c8b-7d4e-8f3a-000000001203', 'Delete Cascade Event', '2026-04-12', 1,
                         '0000000000000_0000_0000000000000000', '2026-03-01T00:00:00Z', '2026-03-01T00:00:00Z')",
                [],
            )
            .map_err(to_error_message)?;
            conn.execute(
                "INSERT INTO task_calendar_event_links
                    (task_id, calendar_event_id, version, created_at, updated_at)
                 VALUES ('01966a3f-7c8b-7d4e-8f3a-00000000010f', '01966a3f-7c8b-7d4e-8f3a-000000001203',
                         '0000000000000_0000_0000000000000000', '2026-03-01T00:00:00Z',
                         '2026-03-01T00:00:00Z')",
                [],
            )
            .map_err(to_error_message)?;
            Ok(())
        })
        .expect("seed cascaded child rows");
    insert_task_reminder(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000001204",
        "01966a3f-7c8b-7d4e-8f3a-00000000010f",
        "2026-04-20T09:00:00Z",
    );
    insert_task_dependency(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-00000000010f",
        "01966a3f-7c8b-7d4e-8f3a-000000000c02",
    );
    insert_task_dependency(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-000000000c01",
        "01966a3f-7c8b-7d4e-8f3a-00000000010f",
    );

    let payload = server
        .permanent_delete_task(Parameters(PermanentDeleteTaskArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-00000000010f".to_string(),
            dry_run: false,
            idempotency_key: None,
        }))
        .expect("permanent_delete_task should succeed");
    let result: Value = serde_json::from_str(&payload).expect("valid delete result json");
    assert_eq!(result["id"], "01966a3f-7c8b-7d4e-8f3a-00000000010f");
    assert_eq!(result["deleted"], true);
    assert!(!task_exists(
        &server,
        "01966a3f-7c8b-7d4e-8f3a-00000000010f"
    ));

    let expected = [
        (
            EDGE_TASK_TAG,
            "01966a3f-7c8b-7d4e-8f3a-00000000010f:01966a3f-7c8b-7d4e-8f3a-000000001201",
        ),
        (
            ENTITY_TASK_CHECKLIST_ITEM,
            "01966a3f-7c8b-7d4e-8f3a-000000001202",
        ),
        (ENTITY_TASK_REMINDER, "01966a3f-7c8b-7d4e-8f3a-000000001204"),
        (
            EDGE_TASK_CALENDAR_EVENT_LINK,
            "01966a3f-7c8b-7d4e-8f3a-00000000010f:01966a3f-7c8b-7d4e-8f3a-000000001203",
        ),
        (
            EDGE_TASK_DEPENDENCY,
            "01966a3f-7c8b-7d4e-8f3a-00000000010f:01966a3f-7c8b-7d4e-8f3a-000000000c02",
        ),
        (
            EDGE_TASK_DEPENDENCY,
            "01966a3f-7c8b-7d4e-8f3a-000000000c01:01966a3f-7c8b-7d4e-8f3a-00000000010f",
        ),
    ];

    for (entity_type, entity_id) in expected {
        assert!(
            count_outbox_entries(&server, entity_type, entity_id, "delete") >= 1,
            "expected delete outbox entry for {entity_type}/{entity_id}"
        );
        assert_eq!(
            count_tombstones(&server, entity_type, entity_id),
            1,
            "expected tombstone for {entity_type}/{entity_id}"
        );
    }
}
