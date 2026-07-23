use rusqlite::{params, Connection};

use super::support::{run_completion_in_tx, test_conn};

// -----------------------------------------------------------------------
// focus-plan rewire on recurrence spawn
// -----------------------------------------------------------------------
/// Seed a parent recurring task that will complete on `due_date` and spawn
/// a successor for the next day. `now` is the completion timestamp; the
/// completion function resolves "today" to the YMD of `now` (UTC fallback,
/// since no timezone preference row is seeded).
fn seed_daily_parent(conn: &Connection, task_id: &str, due_date: &str, created_at: &str) {
    lorvex_store::test_support::TaskBuilder::new(task_id)
        .title("Daily")
        .due_date(Some(due_date))
        .canonical_occurrence_date(due_date)
        .recurrence(r#"{"FREQ":"DAILY","INTERVAL":1}"#)
        .recurrence_group_id("grp-rewire")
        .created_at(created_at)
        .insert(conn);
}
/// Seed a `current_focus` parent + a single `current_focus_items` row
/// that points at `task_id` on `date`.
fn seed_current_focus_item(conn: &Connection, date: &str, task_id: &str) {
    conn.execute(
        "INSERT OR IGNORE INTO current_focus \
            (date, briefing, timezone, version, created_at, updated_at) \
         VALUES (?1, NULL, 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', ?2, ?2)",
        params![date, "2026-04-01T00:00:00Z"],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO current_focus_items (date, position, task_id) VALUES (?1, 0, ?2)",
        params![date, task_id],
    )
    .unwrap();
}
/// Seed a `focus_schedule` parent + a single `focus_schedule_blocks` row
/// of block_type='task' pointing at `task_id` on `schedule_date`.
fn seed_focus_schedule_block(conn: &Connection, schedule_date: &str, task_id: &str) {
    conn.execute(
        "INSERT OR IGNORE INTO focus_schedule \
            (date, rationale, timezone, version, created_at, updated_at) \
         VALUES (?1, NULL, 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', ?2, ?2)",
        params![schedule_date, "2026-04-01T00:00:00Z"],
    )
    .unwrap();
    conn.execute(
        "INSERT INTO focus_schedule_blocks \
            (schedule_date, position, block_type, start_time, end_time, task_id, event_id, title) \
         VALUES (?1, 0, 'task', 540, 600, ?2, NULL, 'Morning slot')",
        params![schedule_date, task_id],
    )
    .unwrap();
}
#[test]
fn spawn_recurrence_successor_rewires_current_focus_items() {
    let conn = test_conn();
    seed_daily_parent(
        &conn,
        "daily-rewire-a",
        "2026-04-04",
        "2026-04-01T00:00:00Z",
    );
    // Today's focus plan lists the parent task.
    seed_current_focus_item(&conn, "2026-04-04", "daily-rewire-a");
    let result = run_completion_in_tx(
        &conn,
        "daily-rewire-a",
        "2026-04-04T18:00:00Z",
        "0000000000000_0000_test2352a",
    )
    .unwrap();
    let succ_id = result
        .spawned_successor_id
        .as_deref()
        .expect("completion of recurring task should spawn successor");
    // The focus item that pointed at the completed parent should now
    // point at the freshly spawned successor.
    let rewired_task_id: String = conn
        .query_row(
            "SELECT task_id FROM current_focus_items WHERE date = '2026-04-04' AND position = 0",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(rewired_task_id, succ_id);
    // Workflow returns the rewire inventory; surface boundaries own audit rows.
    let changelog_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog \
             WHERE operation = 'recurrence_rewire'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(changelog_count, 0);
    let stale_changelog_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog \
             WHERE operation = 'recurrence_rewire' \
               AND entity_type = 'focus_schedule_block'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        stale_changelog_count, 0,
        "current_focus_items rewires must not masquerade as focus_schedule_block changes"
    );
    // the rewired-date inventory must surface the date so
    // callers can stamp a fresh HLC on the `current_focus` aggregate and
    // enqueue an upsert envelope. Without these fields, peer devices keep
    // pointing at the now-completed parent task.
    assert_eq!(
        result.rewired_current_focus_dates,
        vec!["2026-04-04".to_string()]
    );
    assert!(
        result.rewired_focus_schedule_dates.is_empty(),
        "no focus_schedule_blocks were seeded for this case"
    );
}
#[test]
fn spawn_recurrence_successor_rewires_focus_schedule_blocks_for_today_and_later() {
    let conn = test_conn();
    seed_daily_parent(
        &conn,
        "daily-rewire-b",
        "2026-04-04",
        "2026-04-01T00:00:00Z",
    );
    // Two forward-looking schedule blocks reference the parent: today and tomorrow.
    seed_focus_schedule_block(&conn, "2026-04-04", "daily-rewire-b");
    seed_focus_schedule_block(&conn, "2026-04-05", "daily-rewire-b");
    let result = run_completion_in_tx(
        &conn,
        "daily-rewire-b",
        "2026-04-04T18:00:00Z",
        "0000000000000_0000_test2352b",
    )
    .unwrap();
    let succ_id = result
        .spawned_successor_id
        .expect("completion of recurring task should spawn successor");
    // Today's block should be rewired.
    let today_task: String = conn
        .query_row(
            "SELECT task_id FROM focus_schedule_blocks \
             WHERE schedule_date = '2026-04-04' AND position = 0",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(today_task, succ_id);
    // Tomorrow's block should also be rewired.
    let tomorrow_task: String = conn
        .query_row(
            "SELECT task_id FROM focus_schedule_blocks \
             WHERE schedule_date = '2026-04-05' AND position = 0",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(tomorrow_task, succ_id);
    // both rewired dates must surface in the result so
    // callers enqueue an `ENTITY_FOCUS_SCHEDULE` envelope per date and
    // peers see today/tomorrow's plans now point at the successor.
    assert_eq!(
        result.rewired_focus_schedule_dates,
        vec!["2026-04-04".to_string(), "2026-04-05".to_string()]
    );
    let changelog_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog WHERE operation = 'recurrence_rewire'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(
        changelog_count, 0,
        "workflow should return rewired aggregate dates and leave recurrence_rewire audit rows to surface boundaries"
    );
}
#[test]
fn spawn_recurrence_successor_preserves_historical_focus_blocks() {
    let conn = test_conn();
    seed_daily_parent(
        &conn,
        "daily-rewire-c",
        "2026-04-04",
        "2026-04-01T00:00:00Z",
    );
    // A historical block from before "today" — must stay pinned to the parent
    // so the diagnostics / history views remain accurate.
    seed_focus_schedule_block(&conn, "2026-04-03", "daily-rewire-c");
    // And a historical current_focus_items row on a past date.
    seed_current_focus_item(&conn, "2026-04-02", "daily-rewire-c");
    // Plus a today row that SHOULD be rewired.
    seed_focus_schedule_block(&conn, "2026-04-04", "daily-rewire-c");
    let result = run_completion_in_tx(
        &conn,
        "daily-rewire-c",
        "2026-04-04T18:00:00Z",
        "0000000000000_0000_test2352c",
    )
    .unwrap();
    let succ_id = result
        .spawned_successor_id
        .expect("completion of recurring task should spawn successor");
    // Historical schedule block still references the parent.
    let hist_block_task: String = conn
        .query_row(
            "SELECT task_id FROM focus_schedule_blocks \
             WHERE schedule_date = '2026-04-03' AND position = 0",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(hist_block_task, "daily-rewire-c");
    // Historical current_focus_items row still references the parent.
    let hist_item_task: String = conn
        .query_row(
            "SELECT task_id FROM current_focus_items \
             WHERE date = '2026-04-02' AND position = 0",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(hist_item_task, "daily-rewire-c");
    // Today's block got rewired to the successor.
    let today_block_task: String = conn
        .query_row(
            "SELECT task_id FROM focus_schedule_blocks \
             WHERE schedule_date = '2026-04-04' AND position = 0",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(today_block_task, succ_id);
    // only today's date should appear in the rewired
    // inventory — the historical 2026-04-03 block was intentionally not
    // touched (forward-looking-only filter), so its parent
    // `focus_schedule` aggregate must NOT receive a sync envelope.
    assert_eq!(
        result.rewired_focus_schedule_dates,
        vec!["2026-04-04".to_string()]
    );
    assert!(
        result.rewired_current_focus_dates.is_empty(),
        "the seeded current_focus_items row was historical (2026-04-02), so no rewire should fire"
    );
}
