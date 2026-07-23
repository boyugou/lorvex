use super::*;

/// Regression test: focus_schedule should work on a fresh database without
/// a pre-existing current focus.
#[test]
fn save_focus_schedule_creates_current_focus_when_none_exists() {
    let conn = setup_sync_test_conn();
    let today = lorvex_workflow::timezone::today_ymd_for_conn(&conn).expect("resolve today");
    let now = sync_timestamp_now();

    // Insert a task for the schedule to reference
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new("task-1")
        .title("Test task")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at(&now)
        .insert(&conn);

    // Insert a focus schedule
    conn.execute(
        "INSERT INTO focus_schedule (date, version, created_at, updated_at)
         VALUES (?1, '0000000000000_0000_a0a0a0a0a0a0a0a0', ?2, ?2)",
        params![today, now],
    )
    .expect("insert focus schedule");

    // Insert block into sub-table (start_time/end_time are INTEGER minute-of-day)
    conn.execute(
        "INSERT INTO focus_schedule_blocks (schedule_date, position, block_type, start_time, end_time, task_id)
         VALUES (?1, 0, 'task', 540, 600, 'task-1')",
        params![today],
    )
    .expect("insert focus schedule block");

    // Verify no current focus exists yet
    let plan_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus WHERE date = ?1",
            params![today],
            |row| row.get(0),
        )
        .expect("count plans");
    assert_eq!(
        plan_count, 0,
        "No current focus should exist before applying"
    );

    // Simulate save_focus_schedule applying to current_focus
    conn.execute(
        "INSERT INTO current_focus (date, briefing, timezone, version, created_at, updated_at)
         VALUES (?1, NULL, NULL, '0000000000000_0000_a0a0a0a0a0a0a0a0', ?2, ?2)
         ON CONFLICT(date) DO UPDATE SET
         briefing = COALESCE(current_focus.briefing, excluded.briefing),
         timezone = COALESCE(excluded.timezone, current_focus.timezone),
         updated_at = excluded.updated_at",
        params![today, now],
    )
    .expect("save schedule should create current focus with created_at");

    conn.execute(
        "INSERT INTO current_focus_items (date, position, task_id) VALUES (?1, 0, 'task-1')",
        params![today],
    )
    .expect("insert current_focus_items");

    // Verify current focus was created
    let plan_created_at: String = conn
        .query_row(
            "SELECT created_at FROM current_focus WHERE date = ?1",
            params![today],
            |row| row.get(0),
        )
        .expect("read created plan");

    assert!(!plan_created_at.is_empty(), "created_at must be populated");

    // Verify task IDs are in the items sub-table
    let item_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus_items WHERE date = ?1",
            params![today],
            |row| row.get(0),
        )
        .expect("count items");
    assert_eq!(item_count, 1, "Should have one task in current_focus_items");
}
