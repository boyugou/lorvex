use super::*;
use crate::open_db_in_memory;

fn insert_schedule_header(conn: &Connection, date: &str) {
    conn.execute(
        "INSERT INTO focus_schedule (date, timezone, version, created_at, updated_at) \
         VALUES (?1, 'UTC', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-03-27T00:00:00Z', '2026-03-27T00:00:00Z')",
        [date],
    )
    .unwrap();
}

#[test]
fn materialize_inserts_blocks_in_order() {
    let conn = open_db_in_memory().unwrap();
    insert_schedule_header(&conn, "2026-03-27");

    let blocks = vec![
        ScheduleBlockEntry {
            block_type: "task".into(),
            start_minutes: 540,
            end_minutes: 600,
            task_id: Some("t1".into()),
            event_id: None,
            title: Some("Work on feature".into()),
        },
        ScheduleBlockEntry {
            block_type: "buffer".into(),
            start_minutes: 600,
            end_minutes: 630,
            task_id: None,
            event_id: None,
            title: Some("Break".into()),
        },
    ];

    materialize_schedule_blocks(&conn, "2026-03-27", &blocks).unwrap();

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM focus_schedule_blocks WHERE schedule_date = '2026-03-27'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count, 2);

    // Verify ordering
    let first_type: String = conn
        .query_row(
            "SELECT block_type FROM focus_schedule_blocks \
             WHERE schedule_date = '2026-03-27' ORDER BY position ASC LIMIT 1",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(first_type, "task");
}

#[test]
fn materialize_replaces_existing_blocks() {
    let conn = open_db_in_memory().unwrap();
    insert_schedule_header(&conn, "2026-03-27");

    let blocks1 = vec![ScheduleBlockEntry {
        block_type: "task".into(),
        start_minutes: 0,
        end_minutes: 60,
        task_id: Some("t-initial".into()),
        event_id: None,
        title: None,
    }];
    materialize_schedule_blocks(&conn, "2026-03-27", &blocks1).unwrap();

    let blocks2 = vec![
        ScheduleBlockEntry {
            block_type: "event".into(),
            start_minutes: 120,
            end_minutes: 180,
            task_id: None,
            event_id: Some("e1".into()),
            title: Some("Meeting".into()),
        },
        ScheduleBlockEntry {
            block_type: "task".into(),
            start_minutes: 180,
            end_minutes: 240,
            task_id: Some("t2".into()),
            event_id: None,
            title: None,
        },
    ];
    materialize_schedule_blocks(&conn, "2026-03-27", &blocks2).unwrap();

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM focus_schedule_blocks WHERE schedule_date = '2026-03-27'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count, 2);
}

#[test]
fn materialize_empty_clears_all() {
    let conn = open_db_in_memory().unwrap();
    insert_schedule_header(&conn, "2026-03-27");

    let blocks = vec![ScheduleBlockEntry {
        block_type: "task".into(),
        start_minutes: 0,
        end_minutes: 60,
        task_id: Some("t-clear-me".into()),
        event_id: None,
        title: None,
    }];
    materialize_schedule_blocks(&conn, "2026-03-27", &blocks).unwrap();
    materialize_schedule_blocks(&conn, "2026-03-27", &[]).unwrap();

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM focus_schedule_blocks WHERE schedule_date = '2026-03-27'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count, 0);
}

#[test]
fn upsert_header_sets_timezone_on_create() {
    let conn = open_db_in_memory().unwrap();

    upsert_focus_schedule_header(
        &conn,
        "2026-03-27",
        Some("Morning plan"),
        "America/New_York",
        "v1",
        "2026-03-27T08:00:00Z",
    )
    .unwrap();

    let (tz, rationale): (String, Option<String>) = conn
        .query_row(
            "SELECT timezone, rationale FROM focus_schedule WHERE date = '2026-03-27'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    assert_eq!(tz, "America/New_York");
    assert_eq!(rationale.as_deref(), Some("Morning plan"));
}

#[test]
fn upsert_header_preserves_timezone_on_update() {
    let conn = open_db_in_memory().unwrap();

    // Create with America/New_York
    upsert_focus_schedule_header(
        &conn,
        "2026-03-27",
        Some("First"),
        "America/New_York",
        "v1",
        "2026-03-27T08:00:00Z",
    )
    .unwrap();

    // Update with a different timezone — should be ignored
    upsert_focus_schedule_header(
        &conn,
        "2026-03-27",
        Some("Updated rationale"),
        "Asia/Tokyo",
        "v2",
        "2026-03-27T12:00:00Z",
    )
    .unwrap();

    let (tz, rationale, version): (String, Option<String>, String) = conn
        .query_row(
            "SELECT timezone, rationale, version FROM focus_schedule WHERE date = '2026-03-27'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    // Timezone must remain the original value
    assert_eq!(tz, "America/New_York");
    // But rationale and version should be updated
    assert_eq!(rationale.as_deref(), Some("Updated rationale"));
    assert_eq!(version, "v2");
}

/// a local-write
/// `upsert_focus_schedule_header` with a version that doesn't
/// strictly exceed the row's current version MUST be a no-op.
/// Pre-fix the conflict UPDATE blindly overwrote the row's
/// rationale + version, regressing the cluster's HLC.
#[test]
fn upsert_focus_schedule_header_lww_gate_rejects_stale_version() {
    let conn = open_db_in_memory().unwrap();

    let applied1 = upsert_focus_schedule_header(
        &conn,
        "2026-04-26",
        Some("winning rationale"),
        "America/New_York",
        "0002000000000_0001_winnerwinnerwi",
        "2026-04-26T08:00:00Z",
    )
    .unwrap();
    assert!(applied1, "initial insert must apply");

    // Stale write at v1 must NOT regress version, rationale, or updated_at.
    let applied2 = upsert_focus_schedule_header(
        &conn,
        "2026-04-26",
        Some("stale rationale"),
        "America/New_York",
        "0001000000000_0001_loseroloseroloser",
        "2026-04-26T09:00:00Z",
    )
    .unwrap();
    assert!(!applied2, "stale stamp under LWW gate must be a no-op");

    let (rationale, version, updated_at): (Option<String>, String, String) = conn
        .query_row(
            "SELECT rationale, version, updated_at FROM focus_schedule WHERE date = '2026-04-26'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .unwrap();
    assert_eq!(rationale.as_deref(), Some("winning rationale"));
    assert_eq!(version, "0002000000000_0001_winnerwinnerwi");
    assert_eq!(updated_at, "2026-04-26T08:00:00Z");
}

/// `SyncVersionCmp::Greater`
/// must reject equal-version replays so a re-delivered envelope at
/// the same HLC is a no-op (the LWW invariant). `GreaterOrEqual`
/// must accept the same replay so shadow-promote / replay paths
/// can rehydrate without bumping HLC.
fn seed_baseline(conn: &Connection, date: &str, version: &str) {
    conn.execute(
        "INSERT INTO focus_schedule (date, rationale, timezone, version, created_at, updated_at) \
         VALUES (?1, 'baseline', 'UTC', ?2, '2026-04-19T08:00:00Z', '2026-04-19T08:00:00Z')",
        rusqlite::params![date, version],
    )
    .unwrap();
}

fn read_state(conn: &Connection, date: &str) -> (Option<String>, String) {
    conn.query_row(
        "SELECT rationale, version FROM focus_schedule WHERE date = ?1",
        [date],
        |row| Ok((row.get(0)?, row.get(1)?)),
    )
    .unwrap()
}

#[test]
fn sync_version_cmp_greater_rejects_equal_and_lower_versions() {
    let conn = open_db_in_memory().unwrap();
    seed_baseline(&conn, "2026-04-19", "0001000000000_0001_devicea0000000");

    // Equal-version replay: Greater says no, the row is unchanged.
    let written = sync_upsert_focus_schedule(
        &conn,
        "2026-04-19",
        Some("attempted-equal"),
        Some("UTC"),
        "0001000000000_0001_devicea0000000",
        "2026-04-19T09:00:00Z",
        "2026-04-19T09:00:00Z",
        SyncVersionCmp::Greater,
    )
    .unwrap();
    assert!(!written, "equal version under Greater must be a no-op");
    let (rationale, version) = read_state(&conn, "2026-04-19");
    assert_eq!(rationale.as_deref(), Some("baseline"));
    assert_eq!(version, "0001000000000_0001_devicea0000000");

    // Older-version replay: Greater rejects.
    let written = sync_upsert_focus_schedule(
        &conn,
        "2026-04-19",
        Some("attempted-older"),
        Some("UTC"),
        "0000999999999_0001_devicea0000000",
        "2026-04-19T09:00:00Z",
        "2026-04-19T09:00:00Z",
        SyncVersionCmp::Greater,
    )
    .unwrap();
    assert!(!written, "older version under Greater must be a no-op");

    // Newer-version replay: Greater accepts.
    let written = sync_upsert_focus_schedule(
        &conn,
        "2026-04-19",
        Some("newer-wins"),
        Some("UTC"),
        "0001000000001_0001_devicea0000000",
        "2026-04-19T09:00:00Z",
        "2026-04-19T09:00:00Z",
        SyncVersionCmp::Greater,
    )
    .unwrap();
    assert!(written, "strictly-newer version under Greater must apply");
    let (rationale, version) = read_state(&conn, "2026-04-19");
    assert_eq!(rationale.as_deref(), Some("newer-wins"));
    assert_eq!(version, "0001000000001_0001_devicea0000000");
}

#[test]
fn sync_version_cmp_greater_or_equal_accepts_equal_version_replay() {
    let conn = open_db_in_memory().unwrap();
    seed_baseline(&conn, "2026-04-20", "0001000000000_0001_devicea0000000");

    // Equal-version replay under GreaterOrEqual: the row is
    // rehydrated to match the new payload, but version stays
    // equal (idempotent re-emit semantics).
    let written = sync_upsert_focus_schedule(
        &conn,
        "2026-04-20",
        Some("rehydrated"),
        Some("UTC"),
        "0001000000000_0001_devicea0000000",
        "2026-04-19T09:00:00Z",
        "2026-04-19T09:00:00Z",
        SyncVersionCmp::GreaterOrEqual,
    )
    .unwrap();
    assert!(
        written,
        "equal version under GreaterOrEqual must apply (rehydrate path)"
    );
    let (rationale, version) = read_state(&conn, "2026-04-20");
    assert_eq!(rationale.as_deref(), Some("rehydrated"));
    assert_eq!(version, "0001000000000_0001_devicea0000000");

    // Older-version replay still rejected even under GreaterOrEqual.
    let written = sync_upsert_focus_schedule(
        &conn,
        "2026-04-20",
        Some("attempted-older"),
        Some("UTC"),
        "0000999999999_0001_devicea0000000",
        "2026-04-19T09:00:00Z",
        "2026-04-19T09:00:00Z",
        SyncVersionCmp::GreaterOrEqual,
    )
    .unwrap();
    assert!(
        !written,
        "older version under GreaterOrEqual must still be a no-op"
    );
}

#[test]
fn sync_version_cmp_as_sql_emits_static_safe_operators() {
    // the enum must only ever produce these two
    // SQL operators. A regression that added a user-supplied
    // string back into the operator slot is the SQL-injection
    // class the enum was introduced to close.
    assert_eq!(SyncVersionCmp::Greater.as_sql(), ">");
    assert_eq!(SyncVersionCmp::GreaterOrEqual.as_sql(), ">=");
}
