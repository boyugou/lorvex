use rusqlite::params;

use super::super::*;
use super::support::{run_cancel_in_tx, run_completion_in_tx, test_conn, tid};
use lorvex_domain::naming::TaskStatus;
use lorvex_store::StoreError;

#[test]
fn completion_spawn_copies_only_pre_transition_active_reminders() {
    let conn = test_conn();
    lorvex_store::test_support::TaskBuilder::new("rem-copy-complete")
        .title("Reminder copy complete")
        .due_date(Some("2026-04-06"))
        .canonical_occurrence_date("2026-04-06")
        .recurrence(r#"{"FREQ":"WEEKLY","INTERVAL":1}"#)
        .recurrence_group_id("grp-rem-copy-complete")
        .version("0000000000000_0000_seed0001")
        .created_at("2026-03-30T00:00:00Z")
        .insert(&conn);
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES ('active-rem', 'rem-copy-complete', '2026-04-05T09:00:00Z',
            '0000000000000_0000_seed0002', '2026-03-30T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, cancelled_at, version, created_at)
         VALUES ('stale-cancelled-rem', 'rem-copy-complete', '2026-04-05T12:00:00Z', '2026-04-01T00:00:00Z',
            '0000000000000_0000_seed0003', '2026-03-30T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, dismissed_at, version, created_at)
         VALUES ('dismissed-rem', 'rem-copy-complete', '2026-04-05T15:00:00Z', '2026-04-01T01:00:00Z',
            '0000000000000_0000_seed0004', '2026-03-30T00:00:00Z')",
        [],
    )
    .unwrap();
    let result = run_completion_in_tx(
        &conn,
        "rem-copy-complete",
        "2026-04-06T10:00:00Z",
        "0000000000000_0000_test0052",
    )
    .unwrap();
    assert!(result.updated);
    let succ_id = result
        .spawned_successor_id
        .expect("completion should spawn a successor");
    assert_eq!(
        result.spawned_successor_reminder_ids.len(),
        1,
        "only the pre-transition active reminder should be copied"
    );
    let successor_reminders: Vec<(String, String)> = conn
        .prepare("SELECT id, reminder_at FROM task_reminders WHERE task_id = ?1 ORDER BY id ASC")
        .unwrap()
        .query_map(params![&succ_id], |row| Ok((row.get(0)?, row.get(1)?)))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap();
    assert_eq!(
        successor_reminders,
        vec![(
            result.spawned_successor_reminder_ids[0].clone(),
            "2026-04-12T09:00:00.000Z".to_string(),
        )]
    );
}
#[test]
fn cancel_skip_spawn_copies_only_pre_transition_active_reminders() {
    let conn = test_conn();
    lorvex_store::test_support::TaskBuilder::new("rem-copy-cancel")
        .title("Reminder copy cancel")
        .due_date(Some("2026-04-06"))
        .canonical_occurrence_date("2026-04-06")
        .recurrence(r#"{"FREQ":"WEEKLY","INTERVAL":1}"#)
        .recurrence_group_id("grp-rem-copy-cancel")
        .version("0000000000000_0000_seed0010")
        .created_at("2026-03-30T00:00:00Z")
        .insert(&conn);
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES ('active-rem-cancel', 'rem-copy-cancel', '2026-04-05T09:00:00Z',
            '0000000000000_0000_seed0011', '2026-03-30T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, cancelled_at, version, created_at)
         VALUES ('stale-cancelled-rem-cancel', 'rem-copy-cancel', '2026-04-05T12:00:00Z', '2026-04-01T00:00:00Z',
            '0000000000000_0000_seed0012', '2026-03-30T00:00:00Z')",
        [],
    )
    .unwrap();
    let result = run_cancel_in_tx(
        &conn,
        "rem-copy-cancel",
        "2026-04-06T10:00:00Z",
        "0000000000000_0000_test0053",
        false,
    )
    .unwrap();
    assert!(result.updated);
    let succ_id = result
        .spawned_successor_id
        .expect("skip-cancel should spawn a successor");
    assert_eq!(
        result.spawned_successor_reminder_ids.len(),
        1,
        "only the pre-transition active reminder should be copied on skip-cancel"
    );
    let successor_reminders: Vec<(String, String)> = conn
        .prepare("SELECT id, reminder_at FROM task_reminders WHERE task_id = ?1 ORDER BY id ASC")
        .unwrap()
        .query_map(params![&succ_id], |row| Ok((row.get(0)?, row.get(1)?)))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap();
    assert_eq!(
        successor_reminders,
        vec![(
            result.spawned_successor_reminder_ids[0].clone(),
            "2026-04-12T09:00:00.000Z".to_string(),
        )]
    );
}
#[test]
fn generic_completion_transition_copies_only_pre_transition_active_reminders() {
    let conn = test_conn();
    lorvex_store::test_support::TaskBuilder::new("rem-copy-generic-complete")
        .title("Reminder copy generic complete")
        .due_date(Some("2026-04-06"))
        .canonical_occurrence_date("2026-04-06")
        .recurrence(r#"{"FREQ":"WEEKLY","INTERVAL":1}"#)
        .recurrence_group_id("grp-rem-copy-generic-complete")
        .version("0000000000000_0000_seed0020")
        .created_at("2026-03-30T00:00:00Z")
        .insert(&conn);
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES ('active-rem-generic-complete', 'rem-copy-generic-complete', '2026-04-05T09:00:00Z',
            '0000000000000_0000_seed0021', '2026-03-30T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, cancelled_at, version, created_at)
         VALUES ('stale-cancelled-rem-generic-complete', 'rem-copy-generic-complete', '2026-04-05T12:00:00Z',
            '2026-04-01T00:00:00Z', '0000000000000_0000_seed0022', '2026-03-30T00:00:00Z')",
        [],
    )
    .unwrap();
    let result =
        lorvex_store::transaction::with_immediate_transaction::<_, StoreError>(&conn, |conn| {
            apply_lifecycle_transition(
                conn,
                &tid("rem-copy-generic-complete"),
                TaskStatus::Open,
                TaskStatus::Completed,
                "2026-04-06T10:00:00Z",
                "0000000000000_0000_test0054",
            )
        })
        .unwrap();
    let succ_id = result
        .spawned_successor_id
        .expect("generic completed transition should spawn a successor");
    assert_eq!(
        result.spawned_successor_reminder_ids.len(),
        1,
        "generic completed transition should carry forward only active reminders"
    );
    let successor_reminders: Vec<(String, String)> = conn
        .prepare("SELECT id, reminder_at FROM task_reminders WHERE task_id = ?1 ORDER BY id ASC")
        .unwrap()
        .query_map(params![&succ_id], |row| Ok((row.get(0)?, row.get(1)?)))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap();
    assert_eq!(
        successor_reminders,
        vec![(
            result.spawned_successor_reminder_ids[0].clone(),
            "2026-04-12T09:00:00.000Z".to_string(),
        )]
    );
}
#[test]
fn generic_cancel_transition_copies_only_pre_transition_active_reminders() {
    let conn = test_conn();
    lorvex_store::test_support::TaskBuilder::new("rem-copy-generic-cancel")
        .title("Reminder copy generic cancel")
        .due_date(Some("2026-04-06"))
        .canonical_occurrence_date("2026-04-06")
        .recurrence(r#"{"FREQ":"WEEKLY","INTERVAL":1}"#)
        .recurrence_group_id("grp-rem-copy-generic-cancel")
        .version("0000000000000_0000_seed0030")
        .created_at("2026-03-30T00:00:00Z")
        .insert(&conn);
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES ('active-rem-generic-cancel', 'rem-copy-generic-cancel', '2026-04-05T09:00:00Z',
            '0000000000000_0000_seed0031', '2026-03-30T00:00:00Z')",
        [],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, cancelled_at, version, created_at)
         VALUES ('stale-cancelled-rem-generic-cancel', 'rem-copy-generic-cancel', '2026-04-05T12:00:00Z',
            '2026-04-01T00:00:00Z', '0000000000000_0000_seed0032', '2026-03-30T00:00:00Z')",
        [],
    )
    .unwrap();
    let result =
        lorvex_store::transaction::with_immediate_transaction::<_, StoreError>(&conn, |conn| {
            apply_lifecycle_transition(
                conn,
                &tid("rem-copy-generic-cancel"),
                TaskStatus::Open,
                TaskStatus::Cancelled,
                "2026-04-06T10:00:00Z",
                "0000000000000_0000_test0055",
            )
        })
        .unwrap();
    let succ_id = result
        .spawned_successor_id
        .expect("generic cancelled transition should spawn a successor");
    assert_eq!(
        result.spawned_successor_reminder_ids.len(),
        1,
        "generic cancelled transition should carry forward only active reminders"
    );
    let successor_reminders: Vec<(String, String)> = conn
        .prepare("SELECT id, reminder_at FROM task_reminders WHERE task_id = ?1 ORDER BY id ASC")
        .unwrap()
        .query_map(params![&succ_id], |row| Ok((row.get(0)?, row.get(1)?)))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap();
    assert_eq!(
        successor_reminders,
        vec![(
            result.spawned_successor_reminder_ids[0].clone(),
            "2026-04-12T09:00:00.000Z".to_string(),
        )]
    );
}
