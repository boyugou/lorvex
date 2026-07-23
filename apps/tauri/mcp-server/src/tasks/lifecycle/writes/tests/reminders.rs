//! Reminder-mutation tools (#2975-H5): `remove_task_reminder` must
//! mint a fresh HLC version on the parent task.

use super::support::*;

/// pre-fix `remove_task_reminder` UPDATE wrote only
/// `updated_at`, leaving `version` stale. Pin the bump.
#[test]
#[serial_test::serial(hlc)]
fn remove_task_reminder_bumps_parent_task_version() {
    let conn = open_temp_db();
    let now = "2026-04-03T00:00:00Z";
    let initial_version = "0000000000000_0000_0000000000000000";
    seed_task_with_version(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000011b",
        "Task H5",
        initial_version,
        now,
    );
    // #3607 — `reminder_id` now flows through
    // `RemoveTaskReminderArgs::validate_shape()` which enforces UUID
    // format. Production reminder IDs are UUIDs (minted via `new_uuid`
    // in set/add reminder paths); the seed shortcut `'rem-h5'` was
    // never representative.
    const REMINDER_ID: &str = "01966a3f-7c8b-7d4e-8f3a-0000000005a1";
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES (?1, '01966a3f-7c8b-7d4e-8f3a-00000000011b', '2026-05-01T09:00:00Z', '0000000000000_0000_0000000000000000', ?2)",
        (REMINDER_ID, now),
    )
    .expect("insert reminder");

    let (before_version, _) =
        read_task_version_updated(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000011b");
    assert_eq!(before_version, initial_version);

    remove_task_reminder(
        &conn,
        RemoveTaskReminderArgs {
            task_id: "01966a3f-7c8b-7d4e-8f3a-00000000011b".to_string(),
            reminder_id: REMINDER_ID.to_string(),
            idempotency_key: None,
        },
    )
    .expect("remove reminder");

    let (after_version, _) =
        read_task_version_updated(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000011b");
    assert_ne!(
        after_version, initial_version,
        "remove_task_reminder must mint a fresh HLC version on the parent task"
    );
    assert!(
        after_version.as_str() > initial_version,
        "fresh HLC must be strictly greater than the seed (#2975-H5)"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn remove_task_reminder_rejects_stale_parent_version_without_deleting_reminder() {
    let conn = open_temp_db();
    let now = "2026-04-03T00:00:00Z";
    let stale_barrier = "9999999999999_0000_ffffffffffffffff";
    let task_id = "01966a3f-7c8b-7d4e-8f3a-00000000061b";
    seed_task_with_version(&conn, task_id, "Task stale reminder", stale_barrier, now);
    const REMINDER_ID: &str = "01966a3f-7c8b-7d4e-8f3a-0000000006a1";
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES (?1, ?2, '2026-05-01T09:00:00Z', '0000000000000_0000_0000000000000000', ?3)",
        (REMINDER_ID, task_id, now),
    )
    .expect("insert reminder");

    let err = remove_task_reminder(
        &conn,
        RemoveTaskReminderArgs {
            task_id: task_id.to_string(),
            reminder_id: REMINDER_ID.to_string(),
            idempotency_key: None,
        },
    )
    .expect_err("stale remove_task_reminder must reject");

    match err {
        McpError::Store(store_err)
            if matches!(*store_err, lorvex_store::StoreError::StaleVersion { .. }) =>
        {
            let lorvex_store::StoreError::StaleVersion { entity, id } = *store_err else {
                unreachable!()
            };
            assert_eq!(entity, lorvex_domain::naming::ENTITY_TASK);
            assert_eq!(id, task_id);
        }
        other => panic!("expected stale-version error, got {other:?}"),
    }

    let (reminder_count, version): (i64, String) = conn
        .query_row(
            "SELECT
                (SELECT COUNT(*) FROM task_reminders WHERE id = ?1),
                (SELECT version FROM tasks WHERE id = ?2)",
            (REMINDER_ID, task_id),
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read reminder after rejected removal");
    assert_eq!(reminder_count, 1);
    assert_eq!(version, stale_barrier);
}
