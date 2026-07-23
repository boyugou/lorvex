use super::support::*;

#[test]
fn test_focus_schedule_blocks_roundtrip() {
    let dirs = setup_dirs();

    let source = open_db_in_memory().unwrap();
    source
        .execute(
            "INSERT INTO lists (id, name, version, created_at, updated_at)
             VALUES ('list-schedule', 'Schedule', '1711234567890_0000_11571157deadbeef', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
            [],
        )
        .unwrap();

    // Need a task for the block's FK reference.
    source
        .execute(
            "INSERT INTO tasks (id, title, status, list_id, created_at, updated_at, version)
             VALUES ('task-s1', 'Deep work', 'open', 'list-schedule', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '1711234567890_0001_deadbeefdeadbeef')",
            [],
        )
        .unwrap();

    source
        .execute(
            "INSERT INTO focus_schedule (date, rationale, timezone, created_at, updated_at, version)
             VALUES ('2026-03-25', 'Morning deep work', 'America/New_York',
                     '2026-03-25T07:00:00Z', '2026-03-25T07:00:00Z', '1711234567890_0090_a1b2c3d4a1b2c3d4')",
            [],
        )
        .unwrap();
    source
        .execute(
            "INSERT INTO focus_schedule_blocks (schedule_date, position, block_type, start_time, end_time, task_id, title)
             VALUES ('2026-03-25', 0, 'task', 540, 660, 'task-s1', 'Deep work session')",
            [],
        )
        .unwrap();
    source
        .execute(
            "INSERT INTO focus_schedule_blocks (schedule_date, position, block_type, start_time, end_time, title)
             VALUES ('2026-03-25', 1, 'buffer', 660, 690, 'Break')",
            [],
        )
        .unwrap();

    export_to_zip(&source, &dirs.zip_path, "dev-1").unwrap();

    let target = open_db_in_memory().unwrap();
    target
        .execute(
            "INSERT INTO lists (id, name, version, created_at, updated_at)
             VALUES ('list-schedule', 'Schedule', '1711234567890_0000_11571157deadbeef', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')",
            [],
        )
        .unwrap();
    // Insert the task in the target so FK constraints are satisfied.
    target
        .execute(
            "INSERT INTO tasks (id, title, status, list_id, created_at, updated_at, version)
             VALUES ('task-s1', 'Deep work', 'open', 'list-schedule', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '1711234567890_0001_deadbeefdeadbeef')",
            [],
        )
        .unwrap();
    import_from_zip(&target, &dirs.zip_path).unwrap();

    let rationale: Option<String> = target
        .query_row(
            "SELECT rationale FROM focus_schedule WHERE date = '2026-03-25'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(rationale, Some("Morning deep work".to_string()));

    let block_count: i64 = target
        .query_row(
            "SELECT COUNT(*) FROM focus_schedule_blocks WHERE schedule_date = '2026-03-25'",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(block_count, 2, "focus_schedule_blocks should round-trip");

    let first_block_type: String = target
        .query_row(
            "SELECT block_type FROM focus_schedule_blocks WHERE schedule_date = '2026-03-25' AND position = 0",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(first_block_type, "task");

    let first_task_id: Option<String> = target
        .query_row(
            "SELECT task_id FROM focus_schedule_blocks WHERE schedule_date = '2026-03-25' AND position = 0",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_eq!(first_task_id, Some("task-s1".to_string()));
}
