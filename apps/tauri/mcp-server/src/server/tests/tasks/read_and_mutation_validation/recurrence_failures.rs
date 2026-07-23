use super::*;
use lorvex_domain::Patch;

#[test]
#[serial_test::serial(hlc)]
fn update_task_recurrence_propagates_today_resolution_failures() {
    let server = make_server();
    seed_task(
        &server,
        "task-update-recurrence-failure",
        "Recurrence Failure",
        "open",
        None,
        Some("2026-03-20"),
        None,
        0,
    );

    // Use with_writer_no_savepoint to get raw connection access for destructive
    // DDL (DROP TABLE) followed by assertions on the same connection.
    server
        .with_writer_no_savepoint(|conn| {
            conn.execute("DROP TABLE preferences", [])
                .map_err(to_error_message)?;

            let _err = crate::tasks::mutations::update_task(
                conn,
                UpdateTaskArgs {
                    id: "task-update-recurrence-failure".to_string(),
                    title: None,
                    body: Patch::Unset,
                    raw_input: None,
                    ai_notes: Patch::Unset,
                    status: None,
                    list_id: None,
                    tags_set: None,
                    tags_add: None,
                    tags_remove: None,
                    priority: None,
                    due_date: Patch::Unset,
                    due_time: Patch::Unset,
                    estimated_minutes: Patch::Unset,
                    recurrence: Patch::Set(crate::contract::RecurrenceRuleArgs {
                        freq: crate::contract::RecurrenceFreq::Daily,
                        interval: Some(1),
                        byday: None,
                        bymonth: None,
                        bymonthday: None,
                        bysetpos: None,
                        wkst: None,
                        until: None,
                        count: None,
                    }),
                    depends_on: None,
                    depends_on_add: None,
                    depends_on_remove: None,
                    planned_date: Patch::Unset,
                    idempotency_key: None,
                },
            )
            .expect_err("missing preferences table should fail recurrence update");

            let recurrence: Option<String> = conn
                .query_row(
                    "SELECT recurrence FROM tasks WHERE id = ?1",
                    ["task-update-recurrence-failure"],
                    |row: &rusqlite::Row<'_>| row.get(0),
                )
                .expect("load task recurrence after failed update");
            assert!(
                recurrence.is_none(),
                "recurrence should remain unset after failed update: {recurrence:?}"
            );
            Ok(())
        })
        .expect("test");
}

#[test]
#[serial_test::serial(hlc)]
fn batch_update_tasks_recurrence_propagates_today_resolution_failures() {
    let server = make_server();
    seed_task(
        &server,
        "task-batch-recurrence-failure",
        "Batch Recurrence Failure",
        "open",
        None,
        Some("2026-03-20"),
        None,
        0,
    );

    server
        .with_writer_no_savepoint(|conn| {
            conn.execute("DROP TABLE preferences", [])
                .map_err(to_error_message)?;

            let _err = crate::tasks::batch::batch_update_tasks(
                conn,
                BatchUpdateTasksArgs {
                    updates: vec![BatchUpdateTaskPatch {
                        id: "task-batch-recurrence-failure".to_string(),
                        title: None,
                        body: Patch::Unset,
                        raw_input: None,
                        ai_notes: Patch::Unset,
                        status: None,
                        list_id: None,
                        tags_set: None,
                        tags_add: None,
                        tags_remove: None,
                        priority: None,
                        due_date: Patch::Unset,
                        due_time: Patch::Unset,
                        estimated_minutes: Patch::Unset,
                        recurrence: Patch::Set(crate::contract::RecurrenceRuleArgs {
                            freq: crate::contract::RecurrenceFreq::Daily,
                            interval: Some(1),
                            byday: None,
                            bymonth: None,
                            bymonthday: None,
                            bysetpos: None,
                            wkst: None,
                            until: None,
                            count: None,
                        }),
                        depends_on: None,
                        depends_on_add: None,
                        depends_on_remove: None,
                        planned_date: Patch::Unset,
                    }],
                    dry_run: false,
                },
            )
            .expect_err("missing preferences table should fail batch recurrence update");

            let recurrence: Option<String> = conn
                .query_row(
                    "SELECT recurrence FROM tasks WHERE id = ?1",
                    ["task-batch-recurrence-failure"],
                    |row: &rusqlite::Row<'_>| row.get(0),
                )
                .expect("load task recurrence after failed batch update");
            assert!(
                recurrence.is_none(),
                "recurrence should remain unset after failed batch update: {recurrence:?}"
            );
            Ok(())
        })
        .expect("test");
}
