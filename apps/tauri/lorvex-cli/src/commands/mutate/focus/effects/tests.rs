use super::*;
use crate::commands::mutate::calendar::effects::{
    create_calendar_event_with_conn, CalendarEventCreateFields,
};
use crate::commands::shared::test_support::seed_task;
use lorvex_domain::naming::{ENTITY_CURRENT_FOCUS, ENTITY_FOCUS_SCHEDULE, ENTITY_PREFERENCE};
use lorvex_runtime::read_local_change_seq;

#[test]
fn focus_set_with_conn_materializes_items_and_enqueues_snapshot() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");

    seed_task(&conn, "task-focus-a", "Focus A", "open");
    seed_task(&conn, "task-focus-b", "Focus B", "open");

    let focus = set_current_focus_with_conn(
        &mut conn,
        Some("2026-06-01"),
        &["task-focus-a".to_string(), "task-focus-b".to_string()],
        Some("Protect maker time"),
    )
    .expect("set current focus");

    assert_eq!(focus.date, "2026-06-01");
    assert_eq!(focus.task_ids, vec!["task-focus-a", "task-focus-b"]);
    assert_eq!(focus.briefing.as_deref(), Some("Protect maker time"));

    let item_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus_items WHERE date = ?1",
            [&focus.date],
            |row| row.get(0),
        )
        .expect("count focus items");
    assert_eq!(item_count, 2);

    let payload: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2
             ORDER BY id DESC LIMIT 1",
            rusqlite::params![ENTITY_CURRENT_FOCUS, &focus.date],
            |row| row.get(0),
        )
        .expect("load current focus outbox payload");
    let payload: serde_json::Value = serde_json::from_str(&payload).expect("parse focus payload");
    assert_eq!(
        payload["task_ids"],
        serde_json::json!(["task-focus-a", "task-focus-b"])
    );
    assert_eq!(payload["briefing"], "Protect maker time");
    assert!(payload.get("created_at").is_some());
}

#[test]
fn focus_add_remove_and_clear_with_conn_updates_snapshot_and_change_seq() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");

    seed_task(&conn, "task-focus-a", "Focus A", "open");
    seed_task(&conn, "task-focus-b", "Focus B", "open");
    seed_task(&conn, "task-focus-c", "Focus C", "open");

    set_current_focus_with_conn(
        &mut conn,
        None,
        &["task-focus-a".to_string()],
        Some("Start here"),
    )
    .expect("seed current focus");
    add_to_current_focus_with_conn(
        &mut conn,
        None,
        &["task-focus-b".to_string(), "task-focus-c".to_string()],
        None,
    )
    .expect("add to current focus");

    let after_add = load_current_focus_view(&conn)
        .expect("load focus after add")
        .expect("focus should exist after add");
    assert_eq!(
        after_add.task_ids,
        vec![
            "task-focus-a".to_string(),
            "task-focus-b".to_string(),
            "task-focus-c".to_string()
        ]
    );

    let after_remove = remove_from_current_focus_with_conn(&mut conn, None, "task-focus-b")
        .expect("remove from current focus")
        .expect("focus should still exist after remove");
    assert_eq!(
        after_remove.task_ids,
        vec!["task-focus-a".to_string(), "task-focus-c".to_string()]
    );

    // clear now returns the pre-clear focus row
    // so callers can render or assert on what was removed. The
    // expected shape is `Some(focus)` because the previous `set` +
    // `add` + `remove` left two tasks in focus before this clear.
    let cleared = clear_current_focus_with_conn(&mut conn, None)
        .expect("clear current focus")
        .expect("clear should return the pre-clear focus row");
    assert_eq!(
        cleared.task_ids,
        vec!["task-focus-a".to_string(), "task-focus-c".to_string()]
    );
    let final_focus = load_current_focus_view(&conn).expect("load final focus");
    assert!(final_focus.is_none());

    let delete_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = ?1 AND operation = ?2",
            rusqlite::params![ENTITY_CURRENT_FOCUS, lorvex_domain::naming::OP_DELETE],
            |row| row.get(0),
        )
        .expect("count focus delete outbox entries");
    assert_eq!(delete_count, 1);

    let seq = read_local_change_seq(&conn).expect("read local change seq after focus updates");
    assert_eq!(seq, 4);
}

#[test]
fn focus_schedule_save_with_conn_materializes_syncs_and_applies_current_focus() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, "task-schedule-a", "Schedule A", "open");
    seed_task(&conn, "task-schedule-b", "Schedule B", "open");

    let schedule = save_focus_schedule_with_conn(
        &mut conn,
        Some("2026-06-05"),
        r#"[
            {"block_type":"task","task_id":"task-schedule-a","start_time":"09:00","end_time":"10:00"},
            {"block_type":"buffer","start_time":"10:00","end_time":"10:10"},
            {"block_type":"task","task_id":"task-schedule-b","start_time":"10:10","end_time":"11:00"},
            {"block_type":"event","title":"Lunch","start_time":"12:00","end_time":"12:30"}
        ]"#,
        Some("Batch the important work first."),
    )
    .expect("save focus schedule");

    assert_eq!(schedule.date, "2026-06-05");
    assert_eq!(schedule.blocks.len(), 4);
    assert_eq!(
        schedule.task_ids_applied.as_deref(),
        Some(&["task-schedule-a".to_string(), "task-schedule-b".to_string()][..])
    );

    let saved = get_focus_schedule_with_conn(&conn, Some("2026-06-05"))
        .expect("load saved schedule")
        .expect("schedule should exist");
    assert_eq!(
        saved.rationale.as_deref(),
        Some("Batch the important work first.")
    );
    assert_eq!(saved.blocks[0].start_time, "09:00");
    assert_eq!(saved.blocks[1].block_type, "buffer");

    let focus = load_current_focus_view_for_date(&conn, "2026-06-05")
        .expect("load current focus")
        .expect("current focus should exist");
    assert_eq!(
        focus.task_ids,
        vec!["task-schedule-a".to_string(), "task-schedule-b".to_string()]
    );

    let schedule_outbox: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            [ENTITY_FOCUS_SCHEDULE, "2026-06-05"],
            |row| row.get(0),
        )
        .expect("count schedule outbox");
    assert_eq!(schedule_outbox, 1);

    let focus_outbox: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            [ENTITY_CURRENT_FOCUS, "2026-06-05"],
            |row| row.get(0),
        )
        .expect("count current focus outbox");
    assert_eq!(focus_outbox, 1);

    let dashboard_outbox: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            [
                ENTITY_PREFERENCE,
                lorvex_domain::preference_keys::PREF_DASHBOARD_LAYOUT,
            ],
            |row| row.get(0),
        )
        .expect("count dashboard layout outbox");
    assert_eq!(dashboard_outbox, 1);

    let changelog_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE entity_type IN (?1, ?2)",
            [ENTITY_FOCUS_SCHEDULE, ENTITY_CURRENT_FOCUS],
            |row| row.get(0),
        )
        .expect("count schedule/focus changelog");
    assert_eq!(changelog_count, 2);
}

#[test]
fn focus_schedule_save_rejects_legacy_type_block_key() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, "task-schedule-a", "Schedule A", "open");

    let error = save_focus_schedule_with_conn(
        &mut conn,
        Some("2026-06-05"),
        r#"[
            {"type":"task","task_id":"task-schedule-a","start_time":"09:00","end_time":"10:00"}
        ]"#,
        None,
    )
    .expect_err("legacy type key must be rejected");

    assert!(
        matches!(error, crate::error::CliError::Validation(_)),
        "expected validation error, got {error:?}"
    );
    assert!(
        error.to_string().contains("block_type"),
        "error must point callers at canonical block_type: {error}"
    );
}

#[test]
fn focus_schedule_save_rejects_archived_task_blocks_without_partial_writes() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    lorvex_store::test_support::fixtures::TaskBuilder::new("task-archived-schedule")
        .title("Archived schedule task")
        .status(lorvex_domain::naming::STATUS_OPEN)
        .archived_at(Some("2026-06-04T12:00:00.000000Z"))
        .insert(&conn);

    let error = save_focus_schedule_with_conn(
        &mut conn,
        Some("2026-06-05"),
        r#"[
            {"block_type":"task","task_id":"task-archived-schedule","start_time":"09:00","end_time":"10:00"}
        ]"#,
        Some("Should not persist"),
    )
    .expect_err("archived task block should be rejected");

    assert!(
        error.to_string().contains("archived"),
        "error should identify archived task reference: {error}"
    );
    assert_invalid_schedule_left_no_writes(&conn, "2026-06-05");
}

#[test]
fn focus_schedule_save_rejects_missing_task_blocks_without_partial_writes() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");

    let error = save_focus_schedule_with_conn(
        &mut conn,
        Some("2026-06-05"),
        r#"[
            {"block_type":"task","task_id":"missing-schedule-task","start_time":"09:00","end_time":"10:00"}
        ]"#,
        Some("Should not persist"),
    )
    .expect_err("missing task block should be rejected");

    assert!(
        error.to_string().contains("missing") || error.to_string().contains("non-existent"),
        "error should identify missing task reference: {error}"
    );
    assert_invalid_schedule_left_no_writes(&conn, "2026-06-05");
}

fn assert_invalid_schedule_left_no_writes(conn: &rusqlite::Connection, date: &str) {
    let schedule_blocks: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM focus_schedule_blocks WHERE schedule_date = ?1",
            [date],
            |row| row.get(0),
        )
        .expect("count schedule blocks");
    assert_eq!(schedule_blocks, 0);

    let current_focus_items: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus_items WHERE date = ?1",
            [date],
            |row| row.get(0),
        )
        .expect("count current focus items");
    assert_eq!(current_focus_items, 0);

    let outbox_rows: i64 = conn
        .query_row("SELECT COUNT(*) FROM sync_outbox", [], |row| row.get(0))
        .expect("count sync outbox");
    assert_eq!(outbox_rows, 0);

    let changelog_rows: i64 = conn
        .query_row("SELECT COUNT(*) FROM ai_changelog", [], |row| row.get(0))
        .expect("count changelog");
    assert_eq!(changelog_rows, 0);
}

#[test]
fn focus_schedule_propose_with_conn_uses_focus_tasks_and_calendar_blockers() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, "task-propose-a", "Proposal A", "open");
    seed_task(&conn, "task-propose-b", "Proposal B", "open");
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at)
         VALUES (?1, ?2, '0000000000000_0000_0000000000000000', '2026-03-30T00:00:00Z')",
        [lorvex_domain::preference_keys::PREF_TIMEZONE, r#""UTC""#],
    )
    .expect("seed timezone preference");
    conn.execute(
        "UPDATE tasks SET estimated_minutes = CASE id
            WHEN 'task-propose-a' THEN 60
            WHEN 'task-propose-b' THEN 30
         END
         WHERE id IN ('task-propose-a', 'task-propose-b')",
        [],
    )
    .expect("set estimates");
    set_current_focus_with_conn(
        &mut conn,
        Some("2026-06-06"),
        &["task-propose-a".to_string(), "task-propose-b".to_string()],
        Some("Plan around calendar"),
    )
    .expect("set current focus");
    create_calendar_event_with_conn(
        &mut conn,
        &CalendarEventCreateFields {
            title: std::borrow::Cow::Borrowed("Team sync"),
            start_date: std::borrow::Cow::Borrowed("2026-06-06"),
            start_time: Some(std::borrow::Cow::Borrowed("10:00")),
            end_date: Some(std::borrow::Cow::Borrowed("2026-06-06")),
            end_time: Some(std::borrow::Cow::Borrowed("10:30")),
            all_day: false,
            description: None,
            location: None,
            url: None,
            color: None,
            recurrence: None,
            timezone: Some(std::borrow::Cow::Borrowed("UTC")),
            event_type: Some(std::borrow::Cow::Borrowed("event")),
            person_name: None,
        },
    )
    .expect("create calendar blocker");

    let proposal =
        propose_focus_schedule_with_conn(&conn, Some("2026-06-06")).expect("propose schedule");

    assert_eq!(
        proposal.date(),
        lorvex_domain::Date::parse("2026-06-06").unwrap()
    );
    assert_eq!(
        proposal.working_hours().start(),
        lorvex_domain::TimeOfDay::parse("09:00").unwrap()
    );
    assert_eq!(proposal.calendar_events_count(), 1);
    assert_eq!(
        proposal
            .slots()
            .iter()
            .map(|slot| slot.task().id())
            .collect::<Vec<_>>(),
        vec!["task-propose-a", "task-propose-b"]
    );
    assert_eq!(
        proposal.slots()[0].start_time(),
        lorvex_domain::TimeOfDay::parse("09:00").unwrap()
    );
    assert_eq!(
        proposal.slots()[0].end_time(),
        lorvex_domain::TimeOfDay::parse("10:00").unwrap()
    );
    assert_eq!(
        proposal.slots()[1].start_time(),
        lorvex_domain::TimeOfDay::parse("10:30").unwrap()
    );
    assert!(proposal.unscheduled().is_empty());
    assert!(proposal
        .blocks()
        .iter()
        .any(|block| { block.block_type() == "event" && block.title() == Some("Team sync") }));
}

/// clearing the focus must ship the FULL
/// pre-delete aggregate (header + child task_ids + computed
/// `tasks` summaries) as the tombstone outbox payload, NOT the
/// pre-fix `{date}`-only stub. Peers that missed the matching
/// upsert reconstruct briefing / timezone / created_at /
/// updated_at / task_ids from this payload for restore-from-trash
/// flows. Asserts the payload carries every aggregate field a
/// peer would need.
#[test]
fn current_focus_clear_tombstone_payload_carries_full_aggregate() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, "task-tomb-a", "Focus A", "open");
    seed_task(&conn, "task-tomb-b", "Focus B", "open");
    let _focus = set_current_focus_with_conn(
        &mut conn,
        Some("2026-07-01"),
        &["task-tomb-a".to_string(), "task-tomb-b".to_string()],
        Some("Make space"),
    )
    .expect("seed current focus");

    let cleared = clear_current_focus_with_conn(&mut conn, Some("2026-07-01"))
        .expect("clear focus")
        .expect("focus row should have existed pre-clear");
    assert_eq!(cleared.task_ids, vec!["task-tomb-a", "task-tomb-b"]);

    let payload: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3
             ORDER BY id DESC LIMIT 1",
            rusqlite::params![
                ENTITY_CURRENT_FOCUS,
                "2026-07-01",
                lorvex_domain::naming::OP_DELETE,
            ],
            |row| row.get(0),
        )
        .expect("load focus tombstone payload");
    let payload: serde_json::Value =
        serde_json::from_str(&payload).expect("parse tombstone payload");

    // Full aggregate fields, not the `{date}`-only stub.
    assert_eq!(payload["date"], serde_json::json!("2026-07-01"));
    assert_eq!(payload["briefing"], serde_json::json!("Make space"));
    assert!(
        payload.get("task_ids").is_some(),
        "tombstone payload must carry task_ids; got {payload}"
    );
    assert_eq!(
        payload["task_ids"],
        serde_json::json!(["task-tomb-a", "task-tomb-b"])
    );
    assert!(
        payload.get("created_at").is_some(),
        "tombstone payload must carry created_at; got {payload}"
    );
    assert!(
        payload.get("updated_at").is_some(),
        "tombstone payload must carry updated_at; got {payload}"
    );
    assert!(
        payload.get("timezone").is_some(),
        "tombstone payload must carry timezone; got {payload}"
    );
}

/// when `apply_remove` empties out the focus
/// (last task removed → cascade DELETE), the same tombstone
/// contract applies — full aggregate, not `{date}`-only.
#[test]
fn current_focus_remove_last_task_tombstone_payload_carries_full_aggregate() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    seed_task(&conn, "task-remove-last", "Single task", "open");
    let _focus = set_current_focus_with_conn(
        &mut conn,
        Some("2026-07-02"),
        &["task-remove-last".to_string()],
        Some("Just one"),
    )
    .expect("seed current focus");

    let after_remove =
        remove_from_current_focus_with_conn(&mut conn, Some("2026-07-02"), "task-remove-last")
            .expect("remove last task from focus");
    assert!(after_remove.is_none(), "removing last task clears focus");

    let payload: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2 AND operation = ?3
             ORDER BY id DESC LIMIT 1",
            rusqlite::params![
                ENTITY_CURRENT_FOCUS,
                "2026-07-02",
                lorvex_domain::naming::OP_DELETE,
            ],
            |row| row.get(0),
        )
        .expect("load remove-last tombstone payload");
    let payload: serde_json::Value =
        serde_json::from_str(&payload).expect("parse tombstone payload");
    assert_eq!(payload["date"], serde_json::json!("2026-07-02"));
    assert_eq!(payload["briefing"], serde_json::json!("Just one"));
    assert!(
        payload.get("created_at").is_some(),
        "tombstone payload must carry created_at; got {payload}"
    );
}
