use rusqlite::params;

use super::support::{run_completion_in_tx, test_conn};

#[test]
fn cadence_uses_canonical_occurrence_date_not_deferred_due_date() {
    let conn = test_conn();
    // Create a monthly recurring task due on the 15th.
    // canonical_occurrence_date = 2026-03-15 (the stable anchor).
    // due_date = 2026-03-25 (deferred by the user).
    lorvex_store::test_support::TaskBuilder::new("monthly-task")
        .title("Monthly Report")
        .due_date(Some("2026-03-25"))
        .canonical_occurrence_date("2026-03-15")
        .recurrence(r#"{"FREQ":"MONTHLY","INTERVAL":1}"#)
        .recurrence_group_id("grp-monthly")
        .created_at("2026-03-10T00:00:00Z")
        .insert(&conn);
    // Complete via shared lifecycle transition.
    let result = run_completion_in_tx(
        &conn,
        "monthly-task",
        "2026-03-25T10:00:00Z",
        "0000000000000_0000_test0001",
    )
    .unwrap();
    assert!(result.updated);
    assert!(
        result.spawned_successor_id.is_some(),
        "should spawn successor"
    );
    let successor_id = result.spawned_successor_id.unwrap();
    let (
        successor_due,
        successor_canonical,
        successor_instance_key,
        successor_spawned_from,
    ): (String, String, Option<String>, Option<String>) =
        conn.query_row(
            "SELECT due_date, canonical_occurrence_date, recurrence_instance_key, spawned_from FROM tasks WHERE id = ?1",
            [&successor_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
        ).unwrap();
    // The successor's cadence should be anchored to April 15 (next monthly
    // occurrence after March 15), NOT April 25 (which would happen if the
    // deferred due_date was used as the cadence anchor).
    assert_eq!(
        successor_due, "2026-04-15",
        "successor due_date should be April 15 (from cadence, not deferred date)"
    );
    assert_eq!(
        successor_canonical, "2026-04-15",
        "successor canonical_occurrence_date should match"
    );
    assert_eq!(
        successor_instance_key.as_deref(),
        Some("grp-monthly:2026-04-15"),
        "instance key uses canonical occurrence date"
    );
    assert_eq!(
        successor_spawned_from.as_deref(),
        Some("monthly-task"),
        "successor must preserve explicit spawned_from lineage"
    );
}
#[test]
fn completion_transition_does_not_spawn_when_no_recurrence() {
    let conn = test_conn();
    lorvex_store::test_support::TaskBuilder::new("non-recurring")
        .title("One-off task")
        .created_at("2026-03-10T00:00:00Z")
        .insert(&conn);
    let result = run_completion_in_tx(
        &conn,
        "non-recurring",
        "2026-03-25T10:00:00Z",
        "0000000000000_0000_test0002",
    )
    .unwrap();
    assert!(result.updated);
    assert!(result.spawned_successor_id.is_none());
}

#[test]
fn spawn_skips_exdate_dates() {
    let conn = test_conn();
    // Create a DAILY recurring task starting 2026-04-04 with an exception on 2026-04-05.
    lorvex_store::test_support::TaskBuilder::new("daily-exdate")
        .title("Daily with exception")
        .due_date(Some("2026-04-04"))
        .canonical_occurrence_date("2026-04-04")
        .recurrence(r#"{"FREQ":"DAILY","INTERVAL":1}"#)
        .recurrence_group_id("grp-daily-exdate")
        .recurrence_exceptions(r#"["2026-04-05"]"#)
        .created_at("2026-04-01T00:00:00Z")
        .insert(&conn);
    // Complete the task.
    let result = run_completion_in_tx(
        &conn,
        "daily-exdate",
        "2026-04-04T18:00:00Z",
        "0000000000000_0000_test0010",
    )
    .unwrap();
    assert!(result.updated);
    let successor_id = result
        .spawned_successor_id
        .expect("should spawn a successor");
    // The successor should skip 2026-04-05 (EXDATE) and land on 2026-04-06.
    let successor_due: String = conn
        .query_row(
            "SELECT due_date FROM tasks WHERE id = ?1",
            [&successor_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        successor_due, "2026-04-06",
        "successor should skip EXDATE 2026-04-05 and land on 2026-04-06"
    );
}
#[test]
fn spawn_with_count_decrements() {
    let conn = test_conn();
    // Create a DAILY recurring task with COUNT=3.
    lorvex_store::test_support::TaskBuilder::new("count-3")
        .title("Count-limited")
        .due_date(Some("2026-04-04"))
        .canonical_occurrence_date("2026-04-04")
        .recurrence(r#"{"FREQ":"DAILY","INTERVAL":1,"COUNT":3}"#)
        .recurrence_group_id("grp-count")
        .created_at("2026-04-01T00:00:00Z")
        .insert(&conn);
    // --- Complete task #1 (COUNT=3 -> successor gets COUNT=2) ---
    let r1 = run_completion_in_tx(
        &conn,
        "count-3",
        "2026-04-04T18:00:00Z",
        "0000000000000_0000_test0020",
    )
    .unwrap();
    assert!(r1.updated);
    let succ1_id = r1
        .spawned_successor_id
        .expect("should spawn successor with COUNT=2");
    let succ1_recurrence: String = conn
        .query_row(
            "SELECT recurrence FROM tasks WHERE id = ?1",
            [&succ1_id],
            |row| row.get(0),
        )
        .unwrap();
    let succ1_rule: serde_json::Value = serde_json::from_str(&succ1_recurrence).unwrap();
    assert_eq!(
        succ1_rule["COUNT"], 2,
        "first successor should have COUNT=2"
    );
    // --- Complete task #2 (COUNT=2 -> successor gets COUNT=1) ---
    let r2 = run_completion_in_tx(
        &conn,
        &succ1_id,
        "2026-04-05T18:00:00Z",
        "0000000000000_0000_test0021",
    )
    .unwrap();
    assert!(r2.updated);
    let succ2_id = r2
        .spawned_successor_id
        .expect("should spawn successor with COUNT=1");
    let succ2_recurrence: String = conn
        .query_row(
            "SELECT recurrence FROM tasks WHERE id = ?1",
            [&succ2_id],
            |row| row.get(0),
        )
        .unwrap();
    let succ2_rule: serde_json::Value = serde_json::from_str(&succ2_recurrence).unwrap();
    assert_eq!(
        succ2_rule["COUNT"], 1,
        "second successor should have COUNT=1"
    );
    // --- Complete task #3 (COUNT=1 -> no further successor) ---
    let r3 = run_completion_in_tx(
        &conn,
        &succ2_id,
        "2026-04-06T18:00:00Z",
        "0000000000000_0000_test0022",
    )
    .unwrap();
    assert!(r3.updated);
    assert!(
        r3.spawned_successor_id.is_none(),
        "should NOT spawn a successor when COUNT is exhausted"
    );
}

#[test]
fn spawn_with_uncapped_task_count_decrements() {
    let conn = test_conn();
    lorvex_store::test_support::TaskBuilder::new("count-1001")
        .title("Long count series")
        .due_date(Some("2026-04-04"))
        .canonical_occurrence_date("2026-04-04")
        .recurrence(r#"{"FREQ":"DAILY","INTERVAL":1,"COUNT":1001}"#)
        .recurrence_group_id("grp-count-large")
        .created_at("2026-04-01T00:00:00Z")
        .insert(&conn);

    let result = run_completion_in_tx(
        &conn,
        "count-1001",
        "2026-04-04T18:00:00Z",
        "0000000000000_0000_test0023",
    )
    .expect("COUNT above expansion cap should still spawn task successor");

    let successor_id = result
        .spawned_successor_id
        .expect("COUNT=1001 should spawn COUNT=1000 successor");
    let successor_recurrence: String = conn
        .query_row(
            "SELECT recurrence FROM tasks WHERE id = ?1",
            [&successor_id],
            |row| row.get(0),
        )
        .unwrap();
    let successor_rule: serde_json::Value = serde_json::from_str(&successor_recurrence).unwrap();
    assert_eq!(successor_rule["COUNT"], 1000);
    assert_eq!(successor_rule["FREQ"], "DAILY");
    assert_eq!(successor_rule["INTERVAL"], 1);
}

#[test]
fn spawn_preserves_canonical_occurrence_date_independence() {
    let conn = test_conn();
    // Create a WEEKLY recurring task with canonical_occurrence_date on Friday 2026-03-20.
    // But the user deferred it: due_date is 2026-03-25 (Wednesday).
    lorvex_store::test_support::TaskBuilder::new("weekly-deferred")
        .title("Weekly Deferred")
        .due_date(Some("2026-03-25"))
        .canonical_occurrence_date("2026-03-20")
        .recurrence(r#"{"FREQ":"WEEKLY","INTERVAL":1}"#)
        .recurrence_group_id("grp-weekly-defer")
        .created_at("2026-03-10T00:00:00Z")
        .insert(&conn);
    // Complete on the deferred date.
    let result = run_completion_in_tx(
        &conn,
        "weekly-deferred",
        "2026-03-25T18:00:00Z",
        "0000000000000_0000_test0030",
    )
    .unwrap();
    assert!(result.updated);
    let successor_id = result
        .spawned_successor_id
        .expect("should spawn a successor");
    let (successor_due, successor_canonical): (String, String) = conn
        .query_row(
            "SELECT due_date, canonical_occurrence_date FROM tasks WHERE id = ?1",
            [&successor_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    // The successor should follow the original weekly cadence from 2026-03-20
    // (i.e. next occurrence is 2026-03-27, one week after the canonical anchor),
    // NOT 2026-04-01 (one week after the deferred due_date 2026-03-25).
    assert_eq!(
        successor_due, "2026-03-27",
        "successor due_date should follow original cadence (2026-03-27), not deferred date + 1 week"
    );
    assert_eq!(
        successor_canonical, "2026-03-27",
        "successor canonical_occurrence_date should match the cadence-derived date"
    );
}
#[test]
fn spawn_with_until_stops_after_bound() {
    let conn = test_conn();
    // Create a DAILY recurring task with UNTIL=2026-04-06, starting 2026-04-04.
    lorvex_store::test_support::TaskBuilder::new("until-task")
        .title("Until Limited")
        .due_date(Some("2026-04-04"))
        .canonical_occurrence_date("2026-04-04")
        .recurrence(r#"{"FREQ":"DAILY","INTERVAL":1,"UNTIL":"2026-04-06"}"#)
        .recurrence_group_id("grp-until")
        .created_at("2026-04-01T00:00:00Z")
        .insert(&conn);
    // Complete #1 (2026-04-04): successor should land on 2026-04-05.
    let r1 = run_completion_in_tx(
        &conn,
        "until-task",
        "2026-04-04T18:00:00Z",
        "0000000000000_0000_test0040",
    )
    .unwrap();
    assert!(r1.updated);
    let succ1_id = r1
        .spawned_successor_id
        .expect("should spawn for 2026-04-05");
    let succ1_due: String = conn
        .query_row(
            "SELECT due_date FROM tasks WHERE id = ?1",
            [&succ1_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(succ1_due, "2026-04-05");
    // Complete #2 (2026-04-05): successor should land on 2026-04-06 (the UNTIL date).
    let r2 = run_completion_in_tx(
        &conn,
        &succ1_id,
        "2026-04-05T18:00:00Z",
        "0000000000000_0000_test0041",
    )
    .unwrap();
    assert!(r2.updated);
    let succ2_id = r2
        .spawned_successor_id
        .expect("should spawn for 2026-04-06 (== UNTIL)");
    let succ2_due: String = conn
        .query_row(
            "SELECT due_date FROM tasks WHERE id = ?1",
            [&succ2_id],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(succ2_due, "2026-04-06");
    // Complete #3 (2026-04-06): next would be 2026-04-07, which exceeds UNTIL.
    let r3 = run_completion_in_tx(
        &conn,
        &succ2_id,
        "2026-04-06T18:00:00Z",
        "0000000000000_0000_test0042",
    )
    .unwrap();
    assert!(r3.updated);
    assert!(
        r3.spawned_successor_id.is_none(),
        "should NOT spawn a successor past the UNTIL date"
    );
}

// -----------------------------------------------------------------------
// planned_date offset preservation contract tests
// -----------------------------------------------------------------------
#[test]
fn spawn_preserves_planned_date_offset() {
    let conn = test_conn();
    // Weekly task due Sunday, planned Thursday (offset = -3 days from cadence anchor)
    lorvex_store::test_support::TaskBuilder::new("offset-task")
        .title("Offset task")
        .due_date(Some("2026-04-06"))
        .planned_date(Some("2026-04-03"))
        .canonical_occurrence_date("2026-04-06")
        .recurrence(r#"{"FREQ":"WEEKLY","INTERVAL":1}"#)
        .recurrence_group_id("grp-offset")
        .created_at("2026-03-30T00:00:00Z")
        .insert(&conn);
    let result = run_completion_in_tx(
        &conn,
        "offset-task",
        "2026-04-04T10:00:00Z",
        "0000000000000_0000_test0050",
    )
    .unwrap();
    assert!(result.updated);
    let succ_id = result.spawned_successor_id.expect("should spawn successor");
    let (succ_due, succ_planned): (String, Option<String>) = conn
        .query_row(
            "SELECT due_date, planned_date FROM tasks WHERE id = ?1",
            params![succ_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(
        succ_due, "2026-04-13",
        "successor due_date should be next Sunday"
    );
    assert_eq!(
        succ_planned.as_deref(),
        Some("2026-04-10"),
        "successor planned_date should be next Thursday (offset = -3 days from cadence)"
    );
}
#[test]
fn spawn_without_planned_date_leaves_null() {
    let conn = test_conn();
    lorvex_store::test_support::TaskBuilder::new("no-plan")
        .title("No plan")
        .due_date(Some("2026-04-06"))
        .canonical_occurrence_date("2026-04-06")
        .recurrence(r#"{"FREQ":"WEEKLY","INTERVAL":1}"#)
        .recurrence_group_id("grp-noplan")
        .created_at("2026-03-30T00:00:00Z")
        .insert(&conn);
    let result = run_completion_in_tx(
        &conn,
        "no-plan",
        "2026-04-06T10:00:00Z",
        "0000000000000_0000_test0051",
    )
    .unwrap();
    let succ_id = result.spawned_successor_id.expect("should spawn");
    let succ_planned: Option<String> = conn
        .query_row(
            "SELECT planned_date FROM tasks WHERE id = ?1",
            params![succ_id],
            |row| row.get(0),
        )
        .unwrap();
    assert!(
        succ_planned.is_none(),
        "successor planned_date should be NULL when parent had none"
    );
}

/// Reopening a recurring parent must cancel only its explicit
/// `spawned_from` successors. Independently-authored recurring tasks
/// that share title, recurrence, and list attributes are not lineage
/// successors and must survive the reopen untouched.
#[test]
fn reopen_does_not_cancel_unrelated_same_title_recurring_task() {
    use super::support::run_reopen_in_tx;

    let conn = test_conn();
    // Seed a real list so the FK on tasks.list_id is satisfied.
    lorvex_store::test_support::ListBuilder::new("list-X")
        .name("Inbox")
        .version("0000000000000_0000_0000000000000aaa")
        .created_at("2026-04-01T00:00:00Z")
        .insert(&conn);
    // Parent: a completed daily recurring task in group A.
    lorvex_store::test_support::TaskBuilder::new("parent-A")
        .title("Daily standup")
        .status(lorvex_domain::naming::STATUS_COMPLETED)
        .list_id(Some("list-X"))
        .due_date(Some("2026-04-04"))
        .canonical_occurrence_date("2026-04-04")
        .recurrence(r#"{"FREQ":"DAILY","INTERVAL":1}"#)
        .recurrence_group_id("grp-project-A")
        .completed_at(Some("2026-04-04T08:00:00Z"))
        .created_at("2026-04-01T00:00:00Z")
        .insert(&conn);
    // Unrelated open recurring task: same title, recurrence, and list,
    // but no spawned_from lineage from the reopened parent.
    lorvex_store::test_support::TaskBuilder::new("unrelated-B")
        .title("Daily standup")
        .list_id(Some("list-X"))
        .due_date(Some("2026-04-05"))
        .canonical_occurrence_date("2026-04-05")
        .recurrence(r#"{"FREQ":"DAILY","INTERVAL":1}"#)
        .recurrence_group_id("grp-project-B")
        .version("0000000000000_0000_0000000000000001")
        .created_at("2026-04-01T00:00:00Z")
        .insert(&conn);

    let result = run_reopen_in_tx(
        &conn,
        "parent-A",
        lorvex_domain::naming::STATUS_COMPLETED,
        "2026-04-05T10:00:00Z",
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
    )
    .unwrap();
    assert!(result.updated);
    assert!(
        result.transition.cancelled_successor_ids.is_empty(),
        "reopen must NOT cancel unrelated tasks without spawned_from lineage; \
         got cancelled_successor_ids = {:?}",
        result.transition.cancelled_successor_ids,
    );
    let unrelated_status: String = conn
        .query_row(
            "SELECT status FROM tasks WHERE id = 'unrelated-B'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        unrelated_status, "open",
        "the unrelated task must remain open"
    );
}

/// A same-series-looking task without explicit lineage is not a
/// successor under the current recurrence contract. Reopen cleanup must
/// not recover old rows by title/rule/list/group heuristics.
#[test]
fn reopen_ignores_same_group_task_without_spawned_from() {
    use super::support::run_reopen_in_tx;

    let conn = test_conn();
    lorvex_store::test_support::ListBuilder::new("list-Y")
        .name("Inbox")
        .version("0000000000000_0000_0000000000000bbb")
        .created_at("2026-04-08T00:00:00Z")
        .insert(&conn);
    lorvex_store::test_support::TaskBuilder::new("parent-A2")
        .title("Daily standup")
        .status(lorvex_domain::naming::STATUS_COMPLETED)
        .list_id(Some("list-Y"))
        .due_date(Some("2026-04-10"))
        .canonical_occurrence_date("2026-04-10")
        .recurrence(r#"{"FREQ":"DAILY","INTERVAL":1}"#)
        .recurrence_group_id("grp-project-shared")
        .completed_at(Some("2026-04-10T08:00:00Z"))
        .version("0000000000000_0000_0000000000000010")
        .created_at("2026-04-08T00:00:00Z")
        .insert(&conn);
    // Same-series-looking row: identical recurrence_group_id, but no
    // spawned_from lineage from the reopened parent.
    lorvex_store::test_support::TaskBuilder::new("legacy-succ")
        .title("Daily standup")
        .list_id(Some("list-Y"))
        .due_date(Some("2026-04-11"))
        .canonical_occurrence_date("2026-04-11")
        .recurrence(r#"{"FREQ":"DAILY","INTERVAL":1}"#)
        .recurrence_group_id("grp-project-shared")
        .version("0000000000000_0000_0000000000000011")
        .created_at("2026-04-08T00:00:00Z")
        .insert(&conn);

    let result = run_reopen_in_tx(
        &conn,
        "parent-A2",
        lorvex_domain::naming::STATUS_COMPLETED,
        "2026-04-11T10:00:00Z",
        "0000000000000_0000_b0b0b0b0b0b0b0b0",
    )
    .unwrap();
    assert!(result.updated);
    assert!(
        result.transition.cancelled_successor_ids.is_empty(),
        "same-group row without spawned_from lineage must not be cancelled; \
         got cancelled_successor_ids = {:?}",
        result.transition.cancelled_successor_ids,
    );
    let legacy_status: String = conn
        .query_row(
            "SELECT status FROM tasks WHERE id = 'legacy-succ'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(legacy_status, "open");
}
