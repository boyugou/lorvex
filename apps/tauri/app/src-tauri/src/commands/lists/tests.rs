//! IPC test coverage for `shelve_list`. Previously
//! untested — a user hitting "Shelve all" on a list held the writer
//! for N tasks with no unit-level guard on the skip semantics
//! (completed/cancelled tasks must stay put). These tests exercise
//! the `_with_conn` entry point against an in-memory DB.

use super::shelve::shelve_list_with_conn;
use crate::error::AppError;
use crate::test_support::test_conn;
use rusqlite::params;

fn seed_list(conn: &rusqlite::Connection, id: &str, name: &str) {
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES (?1, ?2, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z', '2026-04-01T08:00:00Z')",
        params![id, name],
    )
    .expect("seed list");
}

fn seed_task(conn: &rusqlite::Connection, id: &str, title: &str, list_id: &str, status: &str) {
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title(title)
        .status(status)
        .list_id(Some(list_id))
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-04-01T08:00:00Z")
        .insert(conn);
}

#[test]
fn shelve_list_with_conn_rejects_missing_list() {
    let conn = test_conn();

    let error = shelve_list_with_conn(
        &conn,
        &lorvex_domain::ListId::from_trusted("does-not-exist".to_string()),
    )
    .expect_err("missing list should be rejected");

    match error {
        AppError::NotFound(message) => assert!(message.contains("does-not-exist")),
        other => panic!("expected NotFound, got {other:?}"),
    }
}

#[test]
fn shelve_list_with_conn_returns_empty_result_for_list_without_open_tasks() {
    let conn = test_conn();
    seed_list(&conn, "01966a3f-7c8b-7d4e-8f3a-000000001301", "Empty");
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001401",
        "Done",
        "01966a3f-7c8b-7d4e-8f3a-000000001301",
        "completed",
    );

    let result = shelve_list_with_conn(
        &conn,
        &lorvex_domain::ListId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000001301".to_string()),
    )
    .expect("shelve on empty-open-list should succeed");
    assert_eq!(result.shelved_count, 0);
    assert!(result.shelved_task_ids.is_empty());
    assert!(result.skipped_task_ids.is_empty());

    // The completed task must stay as completed.
    let status: String = conn
        .query_row(
            "SELECT status FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000001401'",
            [],
            |row| row.get(0),
        )
        .expect("load status");
    assert_eq!(status, "completed");
}

#[test]
fn shelve_list_with_conn_moves_only_open_tasks_to_someday() {
    let conn = test_conn();
    seed_list(&conn, "01966a3f-7c8b-7d4e-8f3a-000000001302", "Mixed");
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001402",
        "Open 1",
        "01966a3f-7c8b-7d4e-8f3a-000000001302",
        "open",
    );
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001403",
        "Open 2",
        "01966a3f-7c8b-7d4e-8f3a-000000001302",
        "open",
    );
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001404",
        "Done",
        "01966a3f-7c8b-7d4e-8f3a-000000001302",
        "completed",
    );
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001405",
        "Cancelled",
        "01966a3f-7c8b-7d4e-8f3a-000000001302",
        "cancelled",
    );
    // Seed a task in a different list; it must stay untouched.
    seed_list(&conn, "01966a3f-7c8b-7d4e-8f3a-000000001303", "Other");
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001406",
        "Other",
        "01966a3f-7c8b-7d4e-8f3a-000000001303",
        "open",
    );

    let result = shelve_list_with_conn(
        &conn,
        &lorvex_domain::ListId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000001302".to_string()),
    )
    .expect("shelve should succeed");

    assert_eq!(result.shelved_count, 2);
    assert!(result
        .shelved_task_ids
        .contains(&"01966a3f-7c8b-7d4e-8f3a-000000001402".to_string()));
    assert!(result
        .shelved_task_ids
        .contains(&"01966a3f-7c8b-7d4e-8f3a-000000001403".to_string()));
    // Tasks that were never `open` (completed / cancelled) are
    // filtered out of `open_ids` upstream — they should never be
    // reported as skipped, only as untouched.
    assert!(result.skipped_task_ids.is_empty());

    // Only the open tasks in this list changed to someday.
    let statuses: std::collections::HashMap<String, String> = conn
        .prepare("SELECT id, status FROM tasks ORDER BY id")
        .expect("prepare")
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))
        .expect("run")
        .collect::<rusqlite::Result<Vec<_>>>()
        .expect("collect")
        .into_iter()
        .collect();

    assert_eq!(
        statuses.get("01966a3f-7c8b-7d4e-8f3a-000000001402"),
        Some(&"someday".to_string())
    );
    assert_eq!(
        statuses.get("01966a3f-7c8b-7d4e-8f3a-000000001403"),
        Some(&"someday".to_string())
    );
    assert_eq!(
        statuses.get("01966a3f-7c8b-7d4e-8f3a-000000001404"),
        Some(&"completed".to_string())
    );
    assert_eq!(
        statuses.get("01966a3f-7c8b-7d4e-8f3a-000000001405"),
        Some(&"cancelled".to_string())
    );
    assert_eq!(
        statuses.get("01966a3f-7c8b-7d4e-8f3a-000000001406"),
        Some(&"open".to_string())
    );
}

/// the canonical
/// `apply_task_update` LWW gate (`new_version > existing_version`)
/// must reject a shelve whose freshly-minted HLC is not strictly
/// newer than the row's current version. Pre-fix, `shelve_list`
/// issued a raw UPDATE with no LWW guard and would silently
/// clobber a freshly-applied newer remote status.
#[test]
fn shelve_list_with_conn_lww_gate_rejects_stale_shelve() {
    let conn = test_conn();
    seed_list(&conn, "01966a3f-7c8b-7d4e-8f3a-000000001304", "Stale gate");

    // Seed a task with a version that lex-compares NEWER than any
    // freshly-minted HLC the test produces. HLC versions render as
    // `{13-digit ms}_{counter}_{device}` where the leading 13 chars
    // are zero-padded UTC milliseconds. A row stamped with all-9s
    // is therefore strictly newer than any 2026-era write.
    let stale_proof_version = "9999999999999_9999_zzzzzzzzzzzzzzzz";
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new("01966a3f-7c8b-7d4e-8f3a-000000001407")
        .title("Newer remote")
        .version(stale_proof_version)
        .created_at("2026-04-01T08:00:00Z")
        .list_id(Some("01966a3f-7c8b-7d4e-8f3a-000000001304"))
        .insert(&conn);

    let result = shelve_list_with_conn(
        &conn,
        &lorvex_domain::ListId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000001304".to_string()),
    )
    .expect("shelve should succeed");

    // The canonical patch's LWW gate rejected the UPDATE because
    // the freshly-minted local version is older than the stamped
    // remote version. The result must report zero rows shelved
    // and the row must remain `open` with the original version.
    assert_eq!(
        result.shelved_count, 0,
        "stale shelve must be rejected by LWW gate"
    );
    assert!(result.shelved_task_ids.is_empty());
    // Audit hotfix: the LWW-rejected row must surface in
    // `skipped_task_ids` so the caller can render a "couldn't
    // shelve N tasks" message rather than silently dropping the
    // signal that work didn't land.
    assert_eq!(
        result.skipped_task_ids,
        vec!["01966a3f-7c8b-7d4e-8f3a-000000001407".to_string()]
    );

    let (status, version): (String, String) = conn
        .query_row(
            "SELECT status, version FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000001407'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read post-shelve state");
    assert_eq!(status, "open", "stale shelve must not flip status");
    assert_eq!(
        version, stale_proof_version,
        "stale shelve must not bump version"
    );

    // No outbox row for the stale task — `apply_task_update`
    // returning 0 rows short-circuits the enqueue.
    let outbox_for_stale: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = '01966a3f-7c8b-7d4e-8f3a-000000001407'",
            [],
            |row| row.get(0),
        )
        .expect("count outbox rows");
    assert_eq!(
        outbox_for_stale, 0,
        "stale shelve must not enqueue an envelope"
    );
}

#[test]
fn shelve_list_with_conn_enqueues_sync_outbox_per_shelved_task() {
    let conn = test_conn();
    seed_list(&conn, "01966a3f-7c8b-7d4e-8f3a-000000001305", "Sync list");
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001408",
        "A",
        "01966a3f-7c8b-7d4e-8f3a-000000001305",
        "open",
    );
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000001409",
        "B",
        "01966a3f-7c8b-7d4e-8f3a-000000001305",
        "open",
    );

    shelve_list_with_conn(
        &conn,
        &lorvex_domain::ListId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000001305".to_string()),
    )
    .expect("shelve should succeed");

    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(DISTINCT entity_id) FROM sync_outbox
             WHERE entity_id IN ('01966a3f-7c8b-7d4e-8f3a-000000001408', '01966a3f-7c8b-7d4e-8f3a-000000001409')",
            [],
            |row| row.get(0),
        )
        .expect("count outbox rows");
    assert_eq!(outbox_count, 2);
}
