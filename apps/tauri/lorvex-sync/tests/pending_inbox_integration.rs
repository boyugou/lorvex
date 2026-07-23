// trust: integration tests intentionally use unwrap() for assertion clarity —
// panics ARE the failure mode.
#![allow(clippy::unwrap_used)]

use rusqlite::Connection;

use lorvex_domain::naming;
use lorvex_store::open_db_in_memory;
use lorvex_sync::conflict_log::get_conflicts_by_type;
use lorvex_sync::envelope::{SyncEnvelope, SyncOperation};
use lorvex_sync::pending_inbox::{count_pending, drain_pending_inbox, enqueue_pending};
use lorvex_sync::tombstone::create_tombstone;

fn test_db() -> Connection {
    let conn = open_db_in_memory().expect("failed to open in-memory DB");
    // `apply_envelope` (and `drain_pending_inbox`,
    // which calls into it) debug_assert an outer transaction.
    conn.execute_batch("BEGIN IMMEDIATE")
        .expect("test_db: BEGIN IMMEDIATE must succeed on a fresh connection");
    conn
}

fn upsert_envelope(
    entity_type: &str,
    entity_id: &str,
    version: &str,
    payload: &str,
) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::parse(entity_type)
            .expect("test entity_type must be a known EntityKind"),
        entity_id: entity_id.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse(version)
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: 1,
        payload: payload.to_string(),
        device_id: "device-001".to_string(),
    }
}

fn seed_task(conn: &Connection, task_id: &str) {
    // delegate to the shared TaskBuilder so the
    // single source of truth for "minimal task row" lives in
    // `lorvex_store::test_support::fixtures` rather than 28+ inline
    // helpers across the workspace.
    lorvex_store::test_support::TaskBuilder::new(task_id).insert(conn);
}

fn seed_tag(conn: &Connection, tag_id: &str) {
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
         VALUES (?1, 'Tag', ?1, '0000000000000_0000_0000000000000000', '2026-03-20T00:00:00.000Z', '2026-03-20T00:00:00.000Z')",
        [tag_id],
    )
    .unwrap();
}

#[test]
fn pending_missing_dependency_replays_when_target_arrives() {
    let conn = test_db();
    let env = upsert_envelope(
        naming::ENTITY_TASK_REMINDER,
        "01966a3f-7c8b-7d4e-8f3a-000000004100",
        "1711234568000_0000_a1b2c3d4a1b2c3d4",
        r#"{
            "task_id":"01966a3f-7c8b-7d4e-8f3a-000000004108",
            "reminder_at":"2026-03-28T09:00:00Z",
            "created_at":"2026-03-27T09:00:00Z"
        }"#,
    );
    enqueue_pending(
        &conn,
        &env,
        naming::RESOLUTION_FK_UNRESOLVED,
        Some(naming::ENTITY_TASK),
        Some("01966a3f-7c8b-7d4e-8f3a-000000004108"),
    )
    .unwrap();

    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000004108");

    let summary = drain_pending_inbox(&conn).unwrap();
    assert_eq!(summary.replayed, 1);
    assert_eq!(count_pending(&conn).unwrap(), 0);

    let task_id: String = conn
        .query_row(
            "SELECT task_id FROM task_reminders WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000004100'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(task_id, "01966a3f-7c8b-7d4e-8f3a-000000004108");
}

#[test]
fn pending_missing_dependency_discards_when_target_tombstoned_without_redirect() {
    let conn = test_db();
    let env = upsert_envelope(
        naming::ENTITY_TASK_REMINDER,
        "01966a3f-7c8b-7d4e-8f3a-000000004101",
        "1711234568000_0000_a1b2c3d4a1b2c3d4",
        r#"{
            "task_id":"01966a3f-7c8b-7d4e-8f3a-000000004107",
            "reminder_at":"2026-03-28T09:00:00Z",
            "created_at":"2026-03-27T09:00:00Z"
        }"#,
    );
    enqueue_pending(
        &conn,
        &env,
        naming::RESOLUTION_FK_UNRESOLVED,
        Some(naming::ENTITY_TASK),
        Some("01966a3f-7c8b-7d4e-8f3a-000000004107"),
    )
    .unwrap();
    create_tombstone(
        &conn,
        naming::ENTITY_TASK,
        "01966a3f-7c8b-7d4e-8f3a-000000004107",
        "1711234569000_0000_deadbeefdeadbeef",
        "2026-03-27T10:00:00.000Z",
        None,
        None,
    )
    .unwrap();

    let summary = drain_pending_inbox(&conn).unwrap();
    assert_eq!(summary.discarded, 1);
    assert_eq!(count_pending(&conn).unwrap(), 0);
    assert_eq!(
        conn.query_row::<i64, _, _>(
            "SELECT COUNT(*) FROM task_reminders WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000004101'",
            [],
            |row| row.get(0),
        )
        .unwrap(),
        0
    );

    let unresolved = get_conflicts_by_type(&conn, naming::RESOLUTION_FK_UNRESOLVED, 10).unwrap();
    assert_eq!(unresolved.len(), 1);
    assert_eq!(unresolved[0].entity_type, naming::ENTITY_TASK_REMINDER);
    assert_eq!(
        unresolved[0].entity_id,
        "01966a3f-7c8b-7d4e-8f3a-000000004101"
    );
}

#[test]
fn pending_missing_dependency_redirect_remaps_and_applies() {
    let conn = test_db();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000004106");
    seed_tag(&conn, "01966a3f-7c8b-7d4e-8f3a-000000004105");

    let env = upsert_envelope(
        naming::EDGE_TASK_TAG,
        "01966a3f-7c8b-7d4e-8f3a-000000004106:01966a3f-7c8b-7d4e-8f3a-000000004104",
        "1711234568000_0000_a1b2c3d4a1b2c3d4",
        r#"{
            "task_id":"01966a3f-7c8b-7d4e-8f3a-000000004106",
            "tag_id":"01966a3f-7c8b-7d4e-8f3a-000000004104",
            "created_at":"2026-03-27T09:00:00Z"
        }"#,
    );
    enqueue_pending(
        &conn,
        &env,
        naming::RESOLUTION_FK_UNRESOLVED,
        Some(naming::ENTITY_TAG),
        Some("01966a3f-7c8b-7d4e-8f3a-000000004104"),
    )
    .unwrap();
    create_tombstone(
        &conn,
        naming::ENTITY_TAG,
        "01966a3f-7c8b-7d4e-8f3a-000000004104",
        "1711234569000_0000_deadbeefdeadbeef",
        "2026-03-27T10:00:00.000Z",
        Some("01966a3f-7c8b-7d4e-8f3a-000000004105"),
        Some(naming::ENTITY_TAG),
    )
    .unwrap();

    let summary = drain_pending_inbox(&conn).unwrap();
    assert_eq!(summary.remapped, 1);
    assert_eq!(summary.replayed, 1);
    assert_eq!(count_pending(&conn).unwrap(), 0);

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_tags WHERE task_id = '01966a3f-7c8b-7d4e-8f3a-000000004106' AND tag_id = '01966a3f-7c8b-7d4e-8f3a-000000004105'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(count, 1);
}

#[test]
fn pending_stalled_entries_log_once_after_one_hour_without_discarding() {
    let conn = test_db();
    let env = upsert_envelope(
        naming::ENTITY_TASK_REMINDER,
        "01966a3f-7c8b-7d4e-8f3a-000000004102",
        "1711234568000_0000_a1b2c3d4a1b2c3d4",
        r#"{
            "task_id":"01966a3f-7c8b-7d4e-8f3a-00000000410a",
            "reminder_at":"2026-03-28T09:00:00Z",
            "created_at":"2026-03-27T09:00:00Z"
        }"#,
    );
    enqueue_pending(
        &conn,
        &env,
        naming::RESOLUTION_FK_UNRESOLVED,
        Some(naming::ENTITY_TASK),
        Some("01966a3f-7c8b-7d4e-8f3a-00000000410a"),
    )
    .unwrap();
    conn.execute(
        "UPDATE sync_pending_inbox
         SET first_attempted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-2 hours'),
             last_attempted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now', '-2 hours')",
        [],
    )
    .unwrap();

    let first = drain_pending_inbox(&conn).unwrap();
    let second = drain_pending_inbox(&conn).unwrap();

    assert_eq!(count_pending(&conn).unwrap(), 1);
    assert_eq!(first.stalled_logged, 1);
    assert_eq!(second.stalled_logged, 0);

    let stalled = get_conflicts_by_type(&conn, naming::RESOLUTION_FK_STALLED, 10).unwrap();
    assert_eq!(stalled.len(), 1);
    assert_eq!(stalled[0].entity_type, naming::ENTITY_TASK_REMINDER);
    assert_eq!(stalled[0].entity_id, "01966a3f-7c8b-7d4e-8f3a-000000004102");
}

#[test]
fn pending_invalid_payload_surfaces_apply_failure_without_mutating_retry_state() {
    let conn = test_db();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000004109");

    let env = upsert_envelope(
        naming::ENTITY_TASK_REMINDER,
        "01966a3f-7c8b-7d4e-8f3a-000000004103",
        "1711234568000_0000_a1b2c3d4a1b2c3d4",
        r#"{
            "task_id":"01966a3f-7c8b-7d4e-8f3a-000000004109",
            "created_at":"2026-03-27T09:00:00Z"
        }"#,
    );
    enqueue_pending(
        &conn,
        &env,
        naming::RESOLUTION_FK_UNRESOLVED,
        Some(naming::ENTITY_TASK),
        Some("01966a3f-7c8b-7d4e-8f3a-000000004109"),
    )
    .unwrap();

    // R24 fix: drain no longer aborts on invalid payloads. Instead,
    // the error is logged and the entry remains in the inbox for a
    // future drain. This prevents a single poison-pill entry from
    // permanently blocking all other pending entries.
    let summary =
        drain_pending_inbox(&conn).expect("drain should succeed even with invalid entries");
    assert_eq!(
        summary.errors, 1,
        "invalid payload should be counted as an error, not abort the drain"
    );
    assert_eq!(summary.replayed, 0);

    assert_eq!(count_pending(&conn).unwrap(), 1);
    let attempt_count: i64 = conn
        .query_row(
            "SELECT attempt_count FROM sync_pending_inbox WHERE missing_entity_id = '01966a3f-7c8b-7d4e-8f3a-000000004109'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    // R26 fix: the error branch now increments attempt_count so
    // permanently-invalid entries don't produce unbounded stderr
    // output on every sync cycle for 90 days. The initial default
    // is 1, and the error branch calls `record_reattempt` once.
    assert_eq!(
        attempt_count, 2,
        "errored entry should bump attempt_count to prevent unbounded retries"
    );
}
