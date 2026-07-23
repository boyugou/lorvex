//! `defer_task`: stale-version rejection (no side effects) and the
//! reminder-shift cascade (parent task + reminder outbox).

use super::support::*;

#[test]
#[serial_test::serial(hlc)]
fn defer_task_rejects_stale_version_without_side_effects() {
    let conn = open_temp_db();
    let now = "2026-04-20T00:00:00Z";
    lorvex_store::test_support::TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-000000000118")
        .title("Stale defer")
        .status("open")
        .planned_date(Some("2030-04-17"))
        .due_date(Some("2030-04-17"))
        .version("9999999999999_0000_ffffffffffffffff")
        .created_at(now)
        .insert(&conn);

    conn.execute_batch("BEGIN IMMEDIATE;")
        .expect("begin immediate");
    let error = defer_task(
        &conn,
        DeferTaskArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-000000000118".to_string(),
            until_date: "2030-04-20".to_string(),
            reason: Some("should not apply".to_string()),
            structured_reason: None,
            idempotency_key: None,
        },
    )
    .expect_err("stale defer must reject");
    conn.execute_batch("COMMIT;")
        .expect("commit unchanged transaction");

    match error {
        McpError::Store(store_err)
            if matches!(*store_err, lorvex_store::StoreError::StaleVersion { .. }) =>
        {
            let lorvex_store::StoreError::StaleVersion { entity, id } = *store_err else {
                unreachable!()
            };
            assert_eq!(entity, "task");
            assert_eq!(id, "01966a3f-7c8b-7d4e-8f3a-000000000118");
        }
        other => panic!("expected task StaleVersion, got {other:?}"),
    }

    let (planned_date, defer_count, ai_notes): (Option<String>, i64, Option<String>) = conn
        .query_row(
            "SELECT planned_date, defer_count, ai_notes FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000118'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("load task after stale defer");
    assert_eq!(planned_date.as_deref(), Some("2030-04-17"));
    assert_eq!(defer_count, 0);
    assert!(ai_notes.is_none());

    let side_effect_count: i64 = conn
        .query_row(
            "SELECT
                (SELECT COUNT(*) FROM sync_outbox WHERE entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000118') +
                (SELECT COUNT(*) FROM ai_changelog WHERE entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000118')",
            [],
            |row| row.get(0),
        )
        .expect("count side effects");
    assert_eq!(
        side_effect_count, 0,
        "rejected defer must not enqueue sync or changelog side effects"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn defer_task_shifts_pending_reminder_and_enqueues_reminder_outbox() {
    let conn = open_temp_db();
    let now = "2026-04-20T00:00:00Z";
    lorvex_store::test_support::TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-000000000119")
        .title("Reminder defer")
        .status("open")
        .planned_date(Some("2030-04-17"))
        .due_date(Some("2030-04-17"))
        .version("0000000000000_0000_0000000000000000")
        .created_at(now)
        .insert(&conn);
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000000f01', '01966a3f-7c8b-7d4e-8f3a-000000000119', '2030-04-17T13:45:00.000000Z',
                 '0000000000000_0000_0000000000000000', ?1)",
        [now],
    )
    .expect("insert reminder");

    conn.execute_batch("BEGIN IMMEDIATE;")
        .expect("begin immediate");
    defer_task(
        &conn,
        DeferTaskArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-000000000119".to_string(),
            until_date: "2030-04-20".to_string(),
            reason: None,
            structured_reason: None,
            idempotency_key: None,
        },
    )
    .expect("defer task");
    conn.execute_batch("COMMIT;").expect("commit defer");

    let reminder_at: String = conn
        .query_row(
            "SELECT reminder_at FROM task_reminders WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000f01'",
            [],
            |row| row.get(0),
        )
        .expect("load reminder timestamp");
    assert!(
        reminder_at.starts_with("2030-04-20T13:45:00"),
        "expected reminder to shift +3 days, got {reminder_at}"
    );

    let reminder_outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            rusqlite::params![
                lorvex_domain::naming::ENTITY_TASK_REMINDER,
                "01966a3f-7c8b-7d4e-8f3a-000000000f01"
            ],
            |row| row.get(0),
        )
        .expect("count reminder outbox rows");
    assert_eq!(reminder_outbox_count, 1);
}

#[test]
#[serial_test::serial(hlc)]
fn defer_task_with_reason_writes_ai_notes() {
    let conn = open_temp_db();
    let now = "2026-04-20T00:00:00Z";
    lorvex_store::test_support::TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-00000000012a")
        .title("Reason defer")
        .status("open")
        .version("0000000000000_0000_0000000000000000")
        .created_at(now)
        .insert(&conn);

    conn.execute_batch("BEGIN IMMEDIATE;")
        .expect("begin immediate");
    defer_task(
        &conn,
        DeferTaskArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-00000000012a".to_string(),
            until_date: "2030-04-20".to_string(),
            reason: Some("waiting on review".to_string()),
            structured_reason: None,
            idempotency_key: None,
        },
    )
    .expect("defer task with reason");
    conn.execute_batch("COMMIT;").expect("commit defer");

    let ai_notes: Option<String> = conn
        .query_row(
            "SELECT ai_notes
             FROM tasks
             WHERE id = '01966a3f-7c8b-7d4e-8f3a-00000000012a'",
            [],
            |row| row.get(0),
        )
        .expect("load deferred task notes");

    assert_eq!(
        ai_notes.as_deref(),
        Some("Deferred (#1): waiting on review")
    );
}
