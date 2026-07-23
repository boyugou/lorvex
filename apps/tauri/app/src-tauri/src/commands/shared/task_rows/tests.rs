use super::*;
use lorvex_domain::naming::{EDGE_TASK_TAG, ENTITY_TAG, STATUS_OPEN};
use lorvex_store::repositories::task::write::{self, TaskCreateParams};

use crate::test_support::test_conn;

#[test]
fn resolve_or_create_tag_entry_creates_tag_without_enqueuing_sync_side_effects() {
    let conn = test_conn();
    // Audit: `resolve_or_create_tag_entry` now generates the
    // initial HLC internally (the version stamper overwrites it
    // during outbox enqueue) and accepts `now` as the canonical
    // timestamp the caller staged for the surrounding logical
    // write — so the test verifies BOTH columns persist
    // independently.
    let now = "2026-01-01T00:00:00.000Z";

    let (tag_id, created) = resolve_or_create_tag_entry(&conn, "Work", now).expect("create tag");
    assert!(created);

    let (display_name, lookup_key, updated_at): (String, String, String) = conn
        .query_row(
            "SELECT display_name, lookup_key, updated_at FROM tags WHERE id = ?1",
            rusqlite::params![tag_id],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("persisted tag row");
    assert_eq!(display_name, "Work");
    assert_eq!(lookup_key, "work");
    assert_eq!(updated_at, now, "caller-supplied now must persist");
    let row_version: String = conn
        .query_row(
            "SELECT version FROM tags WHERE id = ?1",
            rusqlite::params![tag_id],
            |row| row.get(0),
        )
        .expect("tag version");
    assert!(!row_version.is_empty(), "tag must carry a real HLC version");

    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1",
            rusqlite::params![ENTITY_TAG],
            |row| row.get(0),
        )
        .expect("count tag outbox entries");
    assert_eq!(outbox_count, 0);
}

#[test]
fn resolve_or_create_tag_entry_does_not_enqueue_for_existing_tag() {
    let conn = test_conn();
    // `tags.created_at` / `tags.updated_at` are
    // canonical sync-timestamp columns, not HLC version strings.
    // Pre-fix this test seeded the rows with raw HLCs from
    // `generate_version()`, which the SyncTimestamp from-SQL
    // validator now rejects with a typed conversion error. Use
    // `sync_timestamp_now()` so the fixture matches the production
    // contract (callers stage canonical ms-Z timestamps for `now`).
    let first = crate::commands::sync_timestamp_now();
    let second = crate::commands::sync_timestamp_now();

    let (tag_id, created) =
        resolve_or_create_tag_entry(&conn, "Work", &first).expect("create initial tag");
    assert!(created);
    conn.execute("DELETE FROM sync_outbox", [])
        .expect("clear initial outbox");

    let (resolved, created) =
        resolve_or_create_tag_entry(&conn, "work", &second).expect("resolve existing tag");

    assert_eq!(resolved, tag_id);
    assert!(!created);

    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1",
            rusqlite::params![ENTITY_TAG],
            |row| row.get(0),
        )
        .expect("count tag outbox entries");
    assert_eq!(outbox_count, 0);
}

fn insert_open_task(conn: &rusqlite::Connection, task_id: &str) {
    // `version` is an HLC string but `now` lands in
    // `tasks.created_at`/`updated_at` — canonical sync timestamps,
    // not HLCs. Pre-fix this fixture reused the same HLC for both,
    // which the SyncTimestamp from-SQL validator now rejects. Stage
    // the two fields independently so the contract is honored.
    let version = crate::hlc::generate_version();
    let now = crate::commands::sync_timestamp_now();
    write::create_task(
        conn,
        &TaskCreateParams::builder(task_id, "Test task", STATUS_OPEN, &version, &now)
            .build()
            .expect("build TaskCreateParams"),
    )
    .expect("insert task");
}

#[test]
fn with_immediate_transaction_preserves_original_error_when_rollback_succeeds() {
    let conn = test_conn();

    let error = with_immediate_transaction(&conn, |_conn| {
        Err::<(), AppError>(AppError::Validation("boom".to_string()))
    })
    .expect_err("transaction should fail");

    match error {
        AppError::Validation(message) => assert_eq!(message, "boom"),
        other => panic!("expected validation error, got {other:?}"),
    }
}

#[test]
fn with_immediate_transaction_surfaces_rollback_failures() {
    let conn = test_conn();

    let error = with_immediate_transaction(&conn, |txn| {
        txn.execute(
            "INSERT INTO lists (id, name, created_at, updated_at, version) VALUES (?1, ?2, ?3, ?3, ?4)",
            rusqlite::params!["list-1", "Test", "2026-03-29T00:00:00Z", "v1"],
        )
        .expect("insert inside transaction");
        txn.execute_batch("ROLLBACK")
            .expect("manually rollback active transaction");
        Err::<(), AppError>(AppError::Validation("boom".to_string()))
    })
    .expect_err("transaction should fail");

    // rollback-failure synthesis now lands in the
    // typed `AppError::TransactionRollbackFailed` carrier (issue
    // #2991-H1) rather than the generic `Internal` envelope. The
    // surface-level invariants — original error preserved, failure
    // pointer to the rollback engine — still apply.
    match error {
        AppError::TransactionRollbackFailed(message) => {
            assert!(message.contains("boom"), "unexpected message: {message}");
            assert!(
                message.contains("rollback failed"),
                "unexpected message: {message}"
            );
            assert!(
                message.contains("no transaction is active"),
                "unexpected message: {message}"
            );
        }
        other => panic!("expected typed rollback-failure error, got {other:?}"),
    }

    // After the failed transaction, only the schema-seeded Inbox list should remain.
    // The "list-1" that was inserted inside the rolled-back transaction should not exist.
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM lists", [], |row| row.get(0))
        .expect("count lists after failed transaction");
    assert_eq!(count, 1); // Only the schema-seeded Inbox
    let has_test_list: bool = conn
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM lists WHERE id = 'list-1')",
            [],
            |row| row.get(0),
        )
        .expect("check for test list");
    assert!(!has_test_list, "rolled-back list-1 should not persist");
}

#[test]
fn with_immediate_transaction_bumps_local_change_seq_on_success() {
    let conn = test_conn();

    with_immediate_transaction(&conn, |txn| {
        txn.execute(
            "INSERT INTO lists (id, name, created_at, updated_at, version) VALUES (?1, ?2, ?3, ?3, ?4)",
            rusqlite::params!["list-seq", "Seq", "2026-03-29T00:00:00Z", "v1"],
        )?;
        Ok::<_, AppError>(())
    })
    .expect("transaction should succeed");

    // `local_change_seq` now lives in the typed
    // `local_counters` table with an INTEGER value column.
    let seq: i64 = conn
        .query_row(
            "SELECT value FROM local_counters WHERE name = 'local_change_seq'",
            [],
            |row| row.get(0),
        )
        .expect("load local change seq");
    assert_eq!(seq, 1);
}

#[test]
fn link_tag_to_task_enqueues_single_tag_snapshot_and_edge_for_new_tag() {
    let conn = test_conn();
    insert_open_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000a201");
    // `now` flows into `tags.created_at` /
    // `tags.updated_at`, which the SyncTimestamp validator now
    // rejects when populated with HLC strings.
    let now = crate::commands::sync_timestamp_now();

    link_tag_to_task(
        &conn,
        &lorvex_domain::TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000a201".to_string()),
        "Work",
        &now,
    )
    .expect("link new tag");

    let tag_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1",
            rusqlite::params![ENTITY_TAG],
            |row| row.get(0),
        )
        .expect("count tag outbox entries");
    let edge_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1",
            rusqlite::params![EDGE_TASK_TAG],
            |row| row.get(0),
        )
        .expect("count task_tag outbox entries");

    assert_eq!(tag_count, 1);
    assert_eq!(edge_count, 1);
}

#[test]
fn link_tag_to_task_skips_tag_entity_enqueue_for_existing_tag() {
    let conn = test_conn();
    insert_open_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000a201");
    // `now` lands in `tags.created_at` /
    // `tags.updated_at` (canonical sync-timestamp columns), not in
    // a version slot. The pre-fix fixture passed HLC strings here,
    // which the SyncTimestamp from-SQL validator now rejects.
    let now = crate::commands::sync_timestamp_now();
    resolve_or_create_tag_entry(&conn, "Work", &now).expect("seed existing tag");
    conn.execute("DELETE FROM sync_outbox", [])
        .expect("clear initial outbox");

    link_tag_to_task(
        &conn,
        &lorvex_domain::TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-00000000a201".to_string()),
        "work",
        &crate::commands::sync_timestamp_now(),
    )
    .expect("link existing tag");

    let tag_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1",
            rusqlite::params![ENTITY_TAG],
            |row| row.get(0),
        )
        .expect("count tag outbox entries");
    let edge_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1",
            rusqlite::params![EDGE_TASK_TAG],
            |row| row.get(0),
        )
        .expect("count task_tag outbox entries");

    assert_eq!(tag_count, 0);
    assert_eq!(edge_count, 1);
}

#[test]
fn task_from_task_row_preserves_required_version() {
    let task = task_from_task_row(lorvex_store::repositories::task::read::TaskRow::from_parts(
        lorvex_store::repositories::task::read::TaskCore::new(
            lorvex_store::repositories::task::read::TaskCoreFields {
                id: "01966a3f-7c8b-7d4e-8f3a-00000000a201".to_string(),
                title: "Task".to_string(),
                body: None,
                raw_input: None,
                ai_notes: None,
                status: "open".to_string(),
                list_id: "inbox".to_string(),
                priority: None,
                version: "v-test".to_string(),
                created_at: "2026-03-29T00:00:00Z".to_string(),
                updated_at: "2026-03-29T00:00:00Z".to_string(),
            },
        ),
        lorvex_store::repositories::task::read::TaskScheduling::new(
            lorvex_store::repositories::task::read::TaskSchedulingFields::default(),
        ),
        lorvex_store::repositories::task::read::TaskRecurrenceState::new(
            lorvex_store::repositories::task::read::TaskRecurrenceStateFields::default(),
        ),
        lorvex_store::repositories::task::read::TaskLifecycleTimestamps::new(
            lorvex_store::repositories::task::read::TaskLifecycleTimestampsFields::default(),
        ),
    ));

    assert_eq!(task.version, "v-test");
}
