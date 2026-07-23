use super::super::*;
use super::support::*;
use lorvex_domain::Patch;

#[test]
fn update_task_with_conn_updates_core_fields_and_syncs() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let task_id = "01949c00-0000-7000-8000-000000000058";
    let list_id = "01949c00-0000-7000-8000-000000000059";
    seed_task(&conn, task_id, "Original", "open");
    lorvex_store::test_support::ListBuilder::new(list_id)
        .name("Updated List")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-03-30T00:00:00Z")
        .insert(&conn);

    let updated = update_task_with_conn(
        &mut conn,
        &tid(task_id),
        &TaskUpdateFields {
            title: Some("Updated title"),
            body: Patch::Set("Updated body"),
            ai_notes: Patch::Set("Assistant notes"),
            status: None,
            raw_input: None,
            list_id: Some(list_id),
            priority: Patch::Set(1),
            due_date: Patch::Set("2026-05-01"),
            due_time: Patch::Set("09:30"),
            planned_date: Patch::Set("2026-04-30"),
            estimated_minutes: Patch::Set(45),
            tags_set: None,
            tags_add: None,
            tags_remove: None,
            depends_on_set: None,
            depends_on_add: None,
            depends_on_remove: None,
            recurrence: lorvex_domain::Patch::Unset,
            idempotency_key: None,
        },
    )
    .expect("update task");

    assert_eq!(updated.core().title(), "Updated title");
    assert_eq!(updated.core().body(), Some("Updated body"));
    assert_eq!(updated.core().ai_notes(), Some("Assistant notes"));
    assert_eq!(updated.core().list_id(), list_id);
    assert_eq!(updated.core().priority(), Some(1));
    assert_eq!(
        updated.scheduling().due_date(),
        Some(lorvex_domain::Date::parse("2026-05-01").unwrap())
    );
    assert_eq!(
        updated.scheduling().due_time(),
        Some(lorvex_domain::TimeOfDay::parse("09:30").unwrap())
    );
    assert_eq!(
        updated.scheduling().planned_date(),
        Some(lorvex_domain::Date::parse("2026-04-30").unwrap())
    );
    assert_eq!(updated.scheduling().estimated_minutes(), Some(45));

    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            [ENTITY_TASK, task_id],
            |row| row.get(0),
        )
        .expect("count sync outbox entries");
    assert_eq!(outbox_count, 1);
    let changelog_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE operation = 'update' AND entity_type = ?1 AND entity_id = ?2",
            [ENTITY_TASK, task_id],
            |row| row.get(0),
        )
        .expect("count changelog entries");
    assert_eq!(changelog_count, 1);

    let seq = read_local_change_seq(&conn).expect("read local change seq");
    assert_eq!(seq, 1);
}

#[test]
fn update_task_with_conn_reports_lww_loser_as_conflict() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000c001",
        "Future version",
        "open",
    );
    conn.execute(
        "UPDATE tasks
         SET version = '9999999999999_9999_9999999999999999'
         WHERE id = '01966a3f-7c8b-7d4e-8f3a-00000000c001'",
        [],
    )
    .expect("seed future task version");

    let err = update_task_with_conn(
        &mut conn,
        &tid("01966a3f-7c8b-7d4e-8f3a-00000000c001"),
        &TaskUpdateFields {
            title: Some("Should not win"),
            ..TaskUpdateFields::default()
        },
    )
    .expect_err("stale local update must lose to future stored version");

    // After #3389 the store layer raises `StoreError::StaleVersion`
    // directly (instead of returning a 0-rows-changed sentinel that
    // the CLI re-wrapped into `CliError::Conflict`). Both shapes carry
    // the same retryable-EX_TEMPFAIL semantics via `store_exit_code`.
    assert!(
        matches!(
            &err,
            crate::error::CliError::Store(e)
                if matches!(**e, lorvex_store::StoreError::StaleVersion { .. })
        ),
        "expected retryable StaleVersion, got {err:?}"
    );
    let title_after: String = conn
        .query_row(
            "SELECT title FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-00000000c001'",
            [],
            |row| row.get(0),
        )
        .expect("load title");
    assert_eq!(title_after, "Future version");
}

#[test]
fn update_task_with_conn_supports_status_and_raw_input() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let task_id = "01949c00-0000-7000-8000-000000000060";
    seed_task(&conn, task_id, "Capture", "open");

    let updated = update_task_with_conn(
        &mut conn,
        &tid(task_id),
        &TaskUpdateFields {
            status: Some("completed"),
            raw_input: Some("captured phrasing"),
            ..TaskUpdateFields::default()
        },
    )
    .expect("update status and raw input");

    assert_eq!(updated.core().status(), "completed");
    assert_eq!(updated.core().raw_input(), Some("captured phrasing"));
    assert!(
        updated.lifecycle().completed_at().is_some(),
        "status transition should stamp completed_at"
    );
    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            [ENTITY_TASK, task_id],
            |row| row.get(0),
        )
        .expect("count task outbox entries");
    assert_eq!(outbox_count, 1);
}

#[test]
fn update_task_with_conn_status_completion_flushes_lifecycle_side_effects() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let task_id = "01949c00-0000-7000-8000-000000000061";
    let reminder_id = "01949c00-0000-7000-8000-000000000062";
    seed_task(&conn, task_id, "Complete via update", "open");
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES (?1, ?2, '2026-05-02T09:00:00Z',
                 '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z')",
        [reminder_id, task_id],
    )
    .expect("seed reminder");

    let updated = update_task_with_conn(
        &mut conn,
        &tid(task_id),
        &TaskUpdateFields {
            status: Some("completed"),
            ..TaskUpdateFields::default()
        },
    )
    .expect("complete via update");

    assert_eq!(updated.core().status(), "completed");
    let reminder_cancelled_at: Option<String> = conn
        .query_row(
            "SELECT cancelled_at FROM task_reminders WHERE id = ?1",
            [reminder_id],
            |row| row.get(0),
        )
        .expect("load reminder cancellation");
    assert!(
        reminder_cancelled_at.is_some(),
        "status update must run lifecycle reminder cancellation"
    );
    let reminder_outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            [ENTITY_TASK_REMINDER, reminder_id],
            |row| row.get(0),
        )
        .expect("count reminder outbox");
    assert_eq!(
        reminder_outbox_count, 1,
        "status update must flush reminder side-effect envelope"
    );
}

#[test]
fn update_task_with_conn_status_open_restores_cancelled_reminders() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let task_id = "01949c00-0000-7000-8000-000000000041";
    let reminder_id = "01949c00-0000-7000-8000-000000000042";
    seed_task(&conn, task_id, "Reopen via update", "completed");
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, cancelled_at, version, created_at)
         VALUES (?1, ?2, '2026-05-02T09:00:00Z',
                 '2026-05-01T09:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0',
                 '2026-04-01T08:00:00Z')",
        [reminder_id, task_id],
    )
    .expect("seed cancelled reminder");

    let updated = update_task_with_conn(
        &mut conn,
        &tid(task_id),
        &TaskUpdateFields {
            status: Some("open"),
            ..TaskUpdateFields::default()
        },
    )
    .expect("reopen via update");

    assert_eq!(updated.core().status(), "open");
    let reminder_cancelled_at: Option<String> = conn
        .query_row(
            "SELECT cancelled_at FROM task_reminders WHERE id = ?1",
            [reminder_id],
            |row| row.get(0),
        )
        .expect("load reminder cancellation");
    assert!(
        reminder_cancelled_at.is_none(),
        "status=open update must restore cancelled reminders"
    );
    let reminder_outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            [ENTITY_TASK_REMINDER, reminder_id],
            |row| row.get(0),
        )
        .expect("count reminder outbox");
    assert_eq!(
        reminder_outbox_count, 1,
        "status=open update must flush restored reminder envelope"
    );
}

#[test]
fn update_task_with_conn_status_open_cancels_successor_before_due_date_patch() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let parent_id = "01949c00-0000-7000-8000-000000000054";
    let successor_id = "01949c00-0000-7000-8000-000000000055";
    let recurrence_group_id = "01949c00-0000-7000-8000-000000000056";
    seed_task(&conn, parent_id, "Reopen series via update", "completed");
    seed_task(&conn, successor_id, "Reopen series via update", "open");
    conn.execute(
        "UPDATE tasks
         SET due_date = '2026-05-01',
             canonical_occurrence_date = '2026-05-01',
             recurrence_group_id = ?2,
             recurrence = '{\"FREQ\":\"DAILY\",\"INTERVAL\":1}'
         WHERE id = ?1",
        [parent_id, recurrence_group_id],
    )
    .expect("seed parent recurrence");
    conn.execute(
        "UPDATE tasks
         SET due_date = '2026-05-02',
             canonical_occurrence_date = '2026-05-02',
             recurrence_group_id = ?2,
             recurrence = '{\"FREQ\":\"DAILY\",\"INTERVAL\":1}',
             spawned_from = ?3
         WHERE id = ?1",
        [successor_id, recurrence_group_id, parent_id],
    )
    .expect("seed spawned successor");

    let updated = update_task_with_conn(
        &mut conn,
        &tid(parent_id),
        &TaskUpdateFields {
            status: Some("open"),
            due_date: Patch::Set("2026-05-03"),
            ..TaskUpdateFields::default()
        },
    )
    .expect("reopen and reschedule parent");

    assert_eq!(updated.core().status(), "open");
    assert_eq!(
        updated.scheduling().due_date(),
        Some(lorvex_domain::Date::parse("2026-05-03").unwrap())
    );
    let successor_status: String = conn
        .query_row(
            "SELECT status FROM tasks WHERE id = ?1",
            [successor_id],
            |row| row.get(0),
        )
        .expect("load successor status");
    assert_eq!(
        successor_status, "cancelled",
        "reopen must cancel existing successor using the original parent occurrence date"
    );
}

#[test]
fn update_task_with_conn_rejects_invalid_status_before_sql() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, "task-bad-status", "Bad status", "open");

    let error = update_task_with_conn(
        &mut conn,
        &tid("task-bad-status"),
        &TaskUpdateFields {
            status: Some("all"),
            ..TaskUpdateFields::default()
        },
    )
    .expect_err("invalid status should fail at validation boundary");

    assert!(
        matches!(error, crate::error::CliError::Validation(_)),
        "expected validation error, got {error:?}"
    );
    let status_after: String = conn
        .query_row(
            "SELECT status FROM tasks WHERE id = 'task-bad-status'",
            [],
            |row| row.get(0),
        )
        .expect("load status");
    assert_eq!(status_after, "open");
}

#[test]
fn update_task_with_conn_rejects_clearing_due_date_on_recurring_task() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let task_id = "01949c00-0000-7000-8000-000000000063";
    let recurrence_group_id = "01949c00-0000-7000-8000-000000000064";
    seed_task(&conn, task_id, "Recurring", "open");
    conn.execute(
        "UPDATE tasks
         SET due_date = '2026-05-01',
             canonical_occurrence_date = '2026-05-01',
             recurrence_group_id = ?2,
             recurrence = '{\"FREQ\":\"DAILY\",\"INTERVAL\":1}'
         WHERE id = ?1",
        [task_id, recurrence_group_id],
    )
    .expect("seed recurring task");

    let error = update_task_with_conn(
        &mut conn,
        &tid(task_id),
        &TaskUpdateFields {
            title: Some("Should roll back"),
            due_date: Patch::Clear,
            ..TaskUpdateFields::default()
        },
    )
    .expect_err("recurring task due date cannot be cleared");

    assert!(
        matches!(error, crate::error::CliError::Validation(_)),
        "expected validation error, got {error:?}"
    );
    let (title_after, due_date_after): (String, Option<String>) = conn
        .query_row(
            "SELECT title, due_date FROM tasks WHERE id = ?1",
            [task_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load task after failed update");
    assert_eq!(title_after, "Recurring");
    assert_eq!(due_date_after.as_deref(), Some("2026-05-01"));
}

#[test]
fn trash_and_defer_lww_losers_report_conflict() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, "task-archive-future", "Archive future", "open");
    seed_task(&conn, "task-restore-future", "Restore future", "open");
    seed_task(&conn, "task-defer-future", "Defer future", "open");
    conn.execute(
        "UPDATE tasks
         SET version = '9999999999999_9999_9999999999999999'
         WHERE id IN ('task-archive-future', 'task-defer-future')",
        [],
    )
    .expect("seed future open versions");
    conn.execute(
        "UPDATE tasks
         SET archived_at = '2026-04-30T00:00:00Z',
             version = '9999999999999_9999_9999999999999999'
         WHERE id = 'task-restore-future'",
        [],
    )
    .expect("seed future archived version");

    for (label, result) in [
        (
            "archive",
            archive_task_with_conn(&conn, &tid("task-archive-future")).map(|_| ()),
        ),
        (
            "restore",
            restore_task_from_trash_with_conn(&conn, &tid("task-restore-future")).map(|_| ()),
        ),
        (
            "defer",
            defer_task_with_conn(&conn, &tid("task-defer-future"), Some(1), None, None).map(|_| ()),
        ),
    ] {
        // archive + restore route through `apply_task_update` and so
        // raise `StoreError::StaleVersion` after the #3389 RETURNING
        // migration; defer goes through `lorvex_workflow::task_deferral`
        // which still uses the older 0-rows-changed sentinel and
        // surfaces as `CliError::Conflict`. Both shapes are retryable
        // LWW losers from the caller's perspective; the test asserts
        // the union until the workflow path is migrated separately.
        let is_stale_version = matches!(
            &result,
            Err(crate::error::CliError::Store(e))
                if matches!(**e, lorvex_store::StoreError::StaleVersion { .. })
        );
        let is_conflict = matches!(result, Err(crate::error::CliError::Conflict(_)));
        assert!(
            is_stale_version || is_conflict,
            "{label} should report LWW loser as StaleVersion or Conflict, got {result:?}"
        );
    }
}

#[test]
fn update_task_with_conn_clears_nullable_fields() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let task_id = "01949c00-0000-7000-8000-000000000065";
    seed_task(&conn, task_id, "Original", "open");
    conn.execute(
        "UPDATE tasks SET body = 'body', ai_notes = 'notes', priority = 2, due_date = '2026-05-01',
         due_time = '09:30', planned_date = '2026-04-30', estimated_minutes = 45
         WHERE id = ?1",
        [task_id],
    )
    .expect("seed nullable fields");

    let updated = update_task_with_conn(
        &mut conn,
        &tid(task_id),
        &TaskUpdateFields {
            body: Patch::Clear,
            ai_notes: Patch::Clear,
            priority: Patch::Clear,
            due_date: Patch::Clear,
            due_time: Patch::Clear,
            planned_date: Patch::Clear,
            estimated_minutes: Patch::Clear,
            ..TaskUpdateFields::default()
        },
    )
    .expect("clear task fields");

    assert_eq!(updated.core().body(), None);
    assert_eq!(updated.core().ai_notes(), None);
    assert_eq!(updated.core().priority(), None);
    assert_eq!(updated.scheduling().due_date(), None);
    assert_eq!(updated.scheduling().due_time(), None);
    assert_eq!(updated.scheduling().planned_date(), None);
    assert_eq!(updated.scheduling().estimated_minutes(), None);
}
