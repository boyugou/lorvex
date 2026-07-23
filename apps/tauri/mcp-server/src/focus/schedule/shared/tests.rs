use super::*;

#[test]
#[serial_test::serial(hlc)]
fn materialize_blocks_accepts_integer_sync_minutes() {
    let conn = lorvex_store::open_db_in_memory().expect("open db");
    conn.execute(
        "INSERT INTO focus_schedule (date, timezone, version, created_at, updated_at) \
         VALUES (?1, 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T00:00:00Z', '2026-03-29T00:00:00Z')",
        ["2026-03-29"],
    )
    .expect("insert focus schedule header");

    materialize_blocks(
        &conn,
        "2026-03-29",
        &[json!({
            "block_type": "buffer",
            "start_time": 540,
            "end_time": 600,
        })],
    )
    .expect("materialize integer-minute blocks");

    let (start_minutes, end_minutes): (i64, i64) = conn
        .query_row(
            "SELECT start_time, end_time FROM focus_schedule_blocks WHERE schedule_date = ?1",
            ["2026-03-29"],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load stored block");

    assert_eq!((start_minutes, end_minutes), (540, 600));
}

#[test]
#[serial_test::serial(hlc)]
fn materialize_blocks_rejects_malformed_time_instead_of_defaulting() {
    let conn = lorvex_store::open_db_in_memory().expect("open db");
    conn.execute(
        "INSERT INTO focus_schedule (date, timezone, version, created_at, updated_at) \
         VALUES (?1, 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T00:00:00Z', '2026-03-29T00:00:00Z')",
        ["2026-03-29"],
    )
    .expect("insert focus schedule header");

    let error = materialize_blocks(
        &conn,
        "2026-03-29",
        &[json!({
            "block_type": "task",
            "task_id": "task-1",
            "start_time": "bogus",
            "end_time": "10:00",
        })],
    )
    .expect_err("invalid block time should fail")
    .to_string();

    assert!(error.contains("start_time"), "unexpected error: {error}");
}

#[test]
#[serial_test::serial(hlc)]
fn query_blocks_preserves_null_task_id_for_non_task_blocks() {
    let conn = lorvex_store::open_db_in_memory().expect("open db");
    conn.execute(
        "INSERT INTO focus_schedule (date, timezone, version, created_at, updated_at) \
         VALUES (?1, 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-29T00:00:00Z', '2026-03-29T00:00:00Z')",
        ["2026-03-29"],
    )
    .expect("insert focus schedule header");
    conn.execute(
        "INSERT INTO focus_schedule_blocks (schedule_date, position, block_type, start_time, end_time, title) \
         VALUES (?1, 0, 'buffer', 540, 600, 'Buffer')",
        ["2026-03-29"],
    )
    .expect("insert focus schedule block");

    let blocks = query_blocks_for_schedule(&conn, "2026-03-29").expect("query blocks");
    assert_eq!(blocks.len(), 1);
    assert!(blocks[0]["task_id"].is_null());
}

#[test]
#[serial_test::serial(hlc)]
fn normalize_focus_schedule_row_rejects_missing_date() {
    let conn = lorvex_store::open_db_in_memory().expect("open db");
    let error =
        normalize_focus_schedule_row(&conn, json!({})).expect_err("missing date should fail");
    assert!(
        error.to_string().contains("missing date"),
        "unexpected error: {error}"
    );
}
