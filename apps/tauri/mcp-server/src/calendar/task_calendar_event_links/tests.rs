use super::*;
use crate::contract::BatchLinkTasksToEventArgs;
use crate::db::open_database_for_path;
use rusqlite::Connection;
use tempfile::tempdir;

const EVENT_BATCH: &str = "01966a3f-7c8b-7d4e-8f3a-000000000111";
const EVENT_EDGE: &str = "01966a3f-7c8b-7d4e-8f3a-000000000112";
const TASK_EDGE: &str = "01966a3f-7c8b-7d4e-8f3a-000000000113";

fn open_temp_db() -> Connection {
    let dir = tempdir().expect("create temp dir");
    let db_path = dir.path().join("db.sqlite");
    let conn = open_database_for_path(&db_path).expect("open temp db");
    // Leak the tempdir so it outlives the connection (same pattern used by
    // other unit tests in this crate).
    let _leaked = Box::leak(Box::new(dir));
    conn
}

fn seed_task(conn: &Connection, id: &str) {
    // lift to canonical TaskBuilder.
    let title = format!("task {id}");
    lorvex_store::test_support::TaskBuilder::new(id)
        .title(&title)
        .created_at("2026-03-01T00:00:00Z")
        .insert(conn);
}

fn seed_event(conn: &Connection, id: &str) {
    let now = "2026-03-01T00:00:00Z";
    conn.execute(
        "INSERT INTO calendar_events (id, title, start_date, version, created_at, updated_at) \
         VALUES (?1, 'Team sync', '2026-03-02', '0000000000000_0000_0000000000000000', ?2, ?2)",
        (id, now),
    )
    .expect("insert calendar event");
}

#[test]
#[serial_test::serial(hlc)]
fn link_task_to_event_rejects_malformed_task_id_before_lookup() {
    let conn = open_temp_db();
    seed_event(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000101");

    let err = link_task_to_event(
        &conn,
        LinkTaskToEventArgs {
            task_id: "task-1".to_string(),
            event_id: "01966a3f-7c8b-7d4e-8f3a-000000000101".to_string(),
            idempotency_key: None,
            dry_run: false,
        },
    )
    .expect_err("malformed task id should fail before DB membership lookup");

    let msg = err.to_string();
    assert!(
        msg.contains("task_id") && msg.contains("UUID"),
        "expected UUID validation error, got: {msg}"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn batch_link_tasks_to_event_rejects_malformed_event_id_before_lookup() {
    let conn = open_temp_db();

    let err = batch_link_tasks_to_event(
        &conn,
        BatchLinkTasksToEventArgs {
            task_ids: vec!["01966a3f-7c8b-7d4e-8f3a-000000000201".to_string()],
            event_id: "event-1".to_string(),
            idempotency_key: None,
        },
    )
    .expect_err("malformed event id should fail before event lookup");

    let msg = err.to_string();
    assert!(
        msg.contains("event_id") && msg.contains("UUID"),
        "expected UUID validation error, got: {msg}"
    );
}

/// Regression test for #2751: batch_link_tasks_to_event validates every
/// supplied task id via a single IN query instead of one SELECT per id.
/// We can't easily spy on statement counts, so this exercises the happy
/// path with a batch of ids to confirm the IN query returns all of them
/// and links are created end-to-end.
#[test]
#[serial_test::serial(hlc)]
fn link_tasks_to_event_validates_all_task_ids_via_single_in_query() {
    let conn = open_temp_db();
    for i in 1..=5 {
        seed_task(&conn, &format!("01966a3f-7c8b-7d4e-8f3a-00000000010{i}"));
    }
    seed_event(&conn, EVENT_BATCH);

    let response = batch_link_tasks_to_event(
        &conn,
        BatchLinkTasksToEventArgs {
            task_ids: (1..=5)
                .map(|i| format!("01966a3f-7c8b-7d4e-8f3a-00000000010{i}"))
                .collect(),
            event_id: EVENT_BATCH.to_string(),
            idempotency_key: None,
        },
    )
    .expect("batch link should succeed when every task id exists");

    let payload: serde_json::Value = serde_json::from_str(&response).expect("valid json response");
    assert_eq!(
        payload
            .get("linked_count")
            .and_then(serde_json::Value::as_u64),
        Some(5)
    );
    assert_eq!(
        payload
            .get("links")
            .and_then(|v| v.as_array())
            .map(Vec::len),
        Some(5)
    );

    // Sanity check: every task id really has a link row in the DB.
    let stored: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_calendar_event_links WHERE calendar_event_id = ?1",
            [EVENT_BATCH],
            |row| row.get(0),
        )
        .expect("count link rows");
    assert_eq!(stored, 5);
}

#[test]
#[serial_test::serial(hlc)]
fn link_tasks_to_event_rejects_if_any_task_id_missing_with_clear_message() {
    let conn = open_temp_db();
    let task_1 = "01966a3f-7c8b-7d4e-8f3a-000000000121";
    let task_2 = "01966a3f-7c8b-7d4e-8f3a-000000000122";
    let missing_task = "01966a3f-7c8b-7d4e-8f3a-000000000123";
    seed_task(&conn, task_1);
    seed_task(&conn, task_2);
    // task-3 intentionally missing
    seed_event(&conn, EVENT_BATCH);

    let err = batch_link_tasks_to_event(
        &conn,
        BatchLinkTasksToEventArgs {
            task_ids: vec![
                task_1.to_string(),
                missing_task.to_string(),
                task_2.to_string(),
            ],
            event_id: EVENT_BATCH.to_string(),
            idempotency_key: None,
        },
    )
    .expect_err("missing task id should surface as NotFound");

    let msg = err.to_string();
    assert!(
        msg.contains(missing_task),
        "error should name the missing task id, got: {msg}"
    );

    // Verify no partial link rows were created for the existing ids.
    let stored: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM task_calendar_event_links WHERE calendar_event_id = ?1",
            [EVENT_BATCH],
            |row| row.get(0),
        )
        .expect("count link rows");
    assert_eq!(
        stored, 0,
        "validation failure must short-circuit before any inserts"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn unlink_task_from_event_preserves_full_pre_delete_snapshot() {
    let conn = open_temp_db();
    seed_task(&conn, TASK_EDGE);
    seed_event(&conn, EVENT_EDGE);
    conn.execute(
        "INSERT INTO task_calendar_event_links
         (task_id, calendar_event_id, version, created_at, updated_at)
         VALUES (?1, ?2,
                 '0000000000000_0000_edgeedgeedgeedge',
                 '2026-04-02T08:00:00Z',
                 '2026-04-02T09:00:00Z')",
        (TASK_EDGE, EVENT_EDGE),
    )
    .expect("insert link");

    let response = unlink_task_from_event(
        &conn,
        UnlinkTaskFromEventArgs {
            task_id: TASK_EDGE.to_string(),
            event_id: EVENT_EDGE.to_string(),
            idempotency_key: None,
            dry_run: false,
        },
    )
    .expect("unlink succeeds");
    let payload: serde_json::Value = serde_json::from_str(&response).expect("valid response");
    assert_eq!(payload["deleted"], true);

    for (table, column) in [("sync_outbox", "payload"), ("ai_changelog", "before_json")] {
        let raw: String = conn
            .query_row(
                &format!(
                    "SELECT {column} FROM {table}
                     WHERE entity_type = 'task_calendar_event_link'
                       AND entity_id = ?1
                     ORDER BY id DESC LIMIT 1"
                ),
                [format!("{TASK_EDGE}:{EVENT_EDGE}")],
                |row| row.get(0),
            )
            .expect("load persisted snapshot");
        let snapshot: serde_json::Value =
            serde_json::from_str(&raw).expect("snapshot is valid json");
        assert_eq!(snapshot["task_id"], TASK_EDGE);
        assert_eq!(snapshot["calendar_event_id"], EVENT_EDGE);
        assert_eq!(snapshot["version"], "0000000000000_0000_edgeedgeedgeedge");
        assert_eq!(snapshot["created_at"], "2026-04-02T08:00:00.000Z");
        assert_eq!(snapshot["updated_at"], "2026-04-02T09:00:00.000Z");
    }
}
