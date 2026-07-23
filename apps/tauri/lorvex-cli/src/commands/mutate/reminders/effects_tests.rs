use super::effects::MAX_TASK_REMINDERS_PER_TASK;
use super::effects::*;
use crate::commands::shared::test_support::{rid, seed_task, tid};
use lorvex_domain::naming::{ENTITY_TASK, ENTITY_TASK_REMINDER, OP_DELETE, OP_UPSERT};
use lorvex_runtime::read_local_change_seq;

const TASK_REMINDERS: &str = "01966a3f-7c8b-7d4e-8f3a-000000003e01";

#[test]
fn task_reminder_mutations_sync_log_and_anchor() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, TASK_REMINDERS, "Reminder task", "open");
    conn.execute(
        "INSERT OR REPLACE INTO preferences (key, value, version, updated_at)
         VALUES ('timezone', '\"America/New_York\"', '0000000000000_0000_0000000000000000', '2026-04-25T00:00:00Z')",
        [],
    )
    .expect("seed timezone preference");

    let start_seq = read_local_change_seq(&conn).expect("read local seq before reminders");
    let initial = vec![
        "2026-05-01T13:00:00Z".to_string(),
        "2026-05-01T21:00:00Z".to_string(),
    ];
    let set = set_task_reminders_with_conn(&mut conn, &tid(TASK_REMINDERS), &initial).expect("set");
    assert_eq!(set.reminders.len(), 2);
    assert_eq!(set.reminders[0].reminder_at, "2026-05-01T13:00:00Z");
    assert_eq!(
        set.reminders[0].original_local_time.as_deref(),
        Some("09:00")
    );
    assert_eq!(
        set.reminders[0].original_tz.as_deref(),
        Some("America/New_York")
    );

    let task_outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3",
            rusqlite::params![ENTITY_TASK, TASK_REMINDERS, OP_UPSERT],
            |row| row.get(0),
        )
        .expect("count task outbox");
    assert_eq!(task_outbox_count, 1);
    let reminder_upserts_after_set: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = ?1 AND operation = ?2",
            rusqlite::params![ENTITY_TASK_REMINDER, OP_UPSERT],
            |row| row.get(0),
        )
        .expect("count reminder upserts after set");
    assert_eq!(reminder_upserts_after_set, 2);
    assert_eq!(
        read_local_change_seq(&conn).expect("read local seq after set"),
        start_seq + 1
    );

    let added =
        add_task_reminder_with_conn(&mut conn, &tid(TASK_REMINDERS), "2026-05-02T14:30:00Z")
            .expect("add reminder");
    assert_eq!(added.reminders.len(), 3);
    let added_id = added
        .reminders
        .iter()
        .find(|reminder| reminder.reminder_at == "2026-05-02T14:30:00Z")
        .expect("added reminder")
        .id
        .clone();
    let added_upsert_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3",
            rusqlite::params![ENTITY_TASK_REMINDER, added_id, OP_UPSERT],
            |row| row.get(0),
        )
        .expect("count added reminder upsert");
    assert_eq!(added_upsert_count, 1);
    assert_eq!(
        read_local_change_seq(&conn).expect("read local seq after add"),
        start_seq + 2
    );

    let removed_id = set.reminders[0].id.clone();
    let removed =
        remove_task_reminder_with_conn(&mut conn, &tid(TASK_REMINDERS), &rid(&removed_id))
            .expect("remove reminder");
    assert_eq!(removed.reminders.len(), 2);
    assert!(removed
        .reminders
        .iter()
        .all(|reminder| reminder.id != removed_id));
    let removed_delete_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3",
            rusqlite::params![ENTITY_TASK_REMINDER, removed_id, OP_DELETE],
            |row| row.get(0),
        )
        .expect("count removed reminder delete");
    assert_eq!(removed_delete_count, 1);
    let reminder_delete_changelog_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog
             WHERE entity_type = ?1 AND operation = ?2",
            rusqlite::params![ENTITY_TASK_REMINDER, OP_DELETE],
            |row| row.get(0),
        )
        .expect("count reminder delete changelog");
    assert_eq!(reminder_delete_changelog_count, 1);
    assert_eq!(
        read_local_change_seq(&conn).expect("read local seq after remove"),
        start_seq + 3
    );

    let remaining_ids: Vec<String> = removed
        .reminders
        .iter()
        .map(|reminder| reminder.id.clone())
        .collect();
    let cleared =
        set_task_reminders_with_conn(&mut conn, &tid(TASK_REMINDERS), &[]).expect("clear");
    assert!(cleared.reminders.is_empty());
    for reminder_id in &remaining_ids {
        let delete_count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sync_outbox
                 WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3",
                rusqlite::params![ENTITY_TASK_REMINDER, reminder_id, OP_DELETE],
                |row| row.get(0),
            )
            .expect("count cleared reminder delete");
        assert_eq!(delete_count, 1, "missing delete for {reminder_id}");
    }
    let parent_changelog_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog
             WHERE entity_type = ?1 AND entity_id = ?2 AND operation = 'set_reminders'",
            [ENTITY_TASK, TASK_REMINDERS],
            |row| row.get(0),
        )
        .expect("count parent reminder changelog");
    assert_eq!(parent_changelog_count, 4);
    assert_eq!(
        read_local_change_seq(&conn).expect("read local seq after clear"),
        start_seq + 4
    );
}

#[test]
fn add_task_reminder_ignores_cancelled_and_dismissed_history_for_cap() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let task_id = "01949c00-0000-7000-8000-000000000050";
    seed_task(&conn, task_id, "Reminder history", "open");
    for index in 0..MAX_TASK_REMINDERS_PER_TASK {
        let dismissed_at: Option<&str> = (index % 2 == 0).then_some("2026-05-02T00:00:00Z");
        let cancelled_at: Option<&str> = (index % 2 == 1).then_some("2026-05-02T00:00:00Z");
        conn.execute(
            "INSERT INTO task_reminders
               (id, task_id, reminder_at, dismissed_at, cancelled_at, version, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, '2026-05-01T00:00:00Z')",
            rusqlite::params![
                format!("01949c00-0000-7000-8000-0000000001{index:02}"),
                task_id,
                format!("2026-05-01T{:02}:00:00Z", index % 24),
                dismissed_at,
                cancelled_at,
                format!("00000000000{index:02}_0000_0000000000000000"),
            ],
        )
        .expect("seed historical reminder");
    }

    let result = add_task_reminder_with_conn(&mut conn, &tid(task_id), "2026-05-03T09:00:00Z")
        .expect("historical reminders should not consume active cap");

    let active_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_reminders
             WHERE task_id = ?1
               AND dismissed_at IS NULL
               AND cancelled_at IS NULL",
            [task_id],
            |row| row.get(0),
        )
        .expect("count active reminders");
    assert_eq!(active_count, 1);
    assert_eq!(result.reminders.len(), MAX_TASK_REMINDERS_PER_TASK + 1);
}
