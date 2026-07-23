use super::{add_to_current_focus, clear_current_focus, get_current_focus, set_current_focus};
use crate::contract::{
    AddToCurrentFocusArgs, ClearCurrentFocusArgs, GetCurrentFocusArgs, SetCurrentFocusArgs,
};
use crate::db::open_database_for_path;
use rusqlite::Connection;
use serde_json::Value;
use tempfile::tempdir;

fn open_temp_db() -> Connection {
    let dir = tempdir().expect("create temp dir");
    let db_path = dir.path().join("db.sqlite");
    let conn = open_database_for_path(&db_path).expect("open temp db");
    let _leaked = Box::leak(Box::new(dir));
    conn
}

fn seed_timezone_preference(conn: &Connection, timezone: &str) {
    conn.execute(
        "INSERT INTO preferences (key, value, version, updated_at) VALUES ('timezone', ?1, '0000000000000_0000_0000000000000000', '2026-03-01T00:00:00Z')",
        [serde_json::to_string(timezone).expect("serialize timezone")],
    )
    .expect("insert timezone preference");
}

fn seed_stub_tasks(conn: &Connection, ids: &[&str]) {
    for id in ids {
        conn.execute(
            "INSERT OR IGNORE INTO tasks (id, title, status, version, created_at, updated_at) VALUES (?1, ?1, 'open', '0000000000000_0000_0000000000000000', '2026-03-01T00:00:00Z', '2026-03-01T00:00:00Z')",
            [id],
        )
        .expect("insert stub task");
    }
}

#[test]
#[serial_test::serial(hlc)]
fn set_current_focus_response_parses_task_ids_array() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    // validator requires UUID-shaped task IDs at the
    // MCP boundary, so seed real UUIDs.
    let task_a = uuid::Uuid::now_v7().to_string();
    let task_b = uuid::Uuid::now_v7().to_string();
    seed_stub_tasks(&conn, &[task_a.as_str(), task_b.as_str()]);

    let response = set_current_focus(
        &conn,
        SetCurrentFocusArgs {
            task_ids: vec![task_a.clone(), task_b.clone()],
            briefing: Some("Focus on the real work".to_string()),
            date: Some("2026-03-02".to_string()),
            idempotency_key: None,
        },
    )
    .expect("set current focus response");

    let payload: Value = serde_json::from_str(&response).expect("parse set current focus response");
    assert_eq!(
        payload.get("task_ids"),
        Some(&serde_json::json!([task_a, task_b])),
    );
    assert_eq!(
        payload.get("timezone"),
        Some(&serde_json::json!("America/Los_Angeles")),
    );

    // Verify items are in the sub-table
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus_items WHERE date = '2026-03-02'",
            [],
            |row| row.get(0),
        )
        .expect("count items");
    assert_eq!(count, 2);
}

#[test]
#[serial_test::serial(hlc)]
fn get_current_focus_response_parses_task_ids_array() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    let task_a = uuid::Uuid::now_v7().to_string();
    let task_b = uuid::Uuid::now_v7().to_string();
    seed_stub_tasks(&conn, &[task_a.as_str(), task_b.as_str()]);

    set_current_focus(
        &conn,
        SetCurrentFocusArgs {
            task_ids: vec![task_a.clone(), task_b.clone()],
            briefing: Some("Focus on the real work".to_string()),
            date: Some("2026-03-02".to_string()),
            idempotency_key: None,
        },
    )
    .expect("seed current focus");

    let response = get_current_focus(
        &conn,
        GetCurrentFocusArgs {
            date: Some("2026-03-02".to_string()),
        },
    )
    .expect("get current focus response");

    let payload: Value = serde_json::from_str(&response).expect("parse get current focus response");
    assert_eq!(
        payload.get("task_ids"),
        Some(&serde_json::json!([task_a, task_b])),
    );
    assert_eq!(
        payload.get("tasks").and_then(Value::as_array).map(Vec::len),
        Some(2),
    );
    assert_eq!(
        payload.get("timezone"),
        Some(&serde_json::json!("America/Los_Angeles")),
    );
}

/// the MCP entry points (`set_current_focus`,
/// `add_to_current_focus`) validate task_ids against the local
/// task table at the trust boundary. The store-layer
/// `materialize_focus_items` preserves soft references for the
/// sync-apply path (where a peer's focus may arrive before its
/// tasks); that contract is exercised in apply-pipeline tests, not
/// here.
#[test]
#[serial_test::serial(hlc)]
fn mcp_set_current_focus_rejects_phantom_task_ids() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");

    let err = set_current_focus(
        &conn,
        SetCurrentFocusArgs {
            task_ids: vec!["nonexistent-task".to_string()],
            briefing: None,
            date: Some("2026-03-02".to_string()),
            idempotency_key: None,
        },
    )
    .expect_err("MCP path must reject phantom task_ids (#2888)");
    let message = err.to_string().to_lowercase();
    assert!(
        message.contains("task_ids")
            || message.contains("not found")
            || message.contains("does not exist"),
        "unexpected error message: {message}",
    );

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus_items WHERE date = '2026-03-02'",
            [],
            |row| row.get(0),
        )
        .expect("count");
    assert_eq!(count, 0, "no rows should be inserted on validation failure");
}

/// archived (soft-deleted) tasks must be rejected at the
/// trust boundary. Every task read path filters `archived_at IS NULL`,
/// so an archived ID in the focus would render as a ghost row.
#[test]
#[serial_test::serial(hlc)]
fn mcp_set_current_focus_rejects_archived_task_ids() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");

    let live = uuid::Uuid::now_v7().to_string();
    let trashed = uuid::Uuid::now_v7().to_string();
    seed_stub_tasks(&conn, &[live.as_str(), trashed.as_str()]);
    conn.execute(
        "UPDATE tasks SET archived_at = '2026-04-26T00:00:00.000Z' WHERE id = ?1",
        [trashed.as_str()],
    )
    .expect("soft-delete trashed task");

    let err = set_current_focus(
        &conn,
        SetCurrentFocusArgs {
            task_ids: vec![live, trashed.clone()],
            briefing: None,
            date: Some("2026-03-02".to_string()),
            idempotency_key: None,
        },
    )
    .expect_err("MCP path must reject archived task_ids (#2888)");
    let message = err.to_string();
    assert!(
        message.contains("archived"),
        "unexpected error message: {message}",
    );
    assert!(
        message.contains(&trashed),
        "expected the trashed id in the error: {message}",
    );

    // No partial write — the live id must not have been materialized
    // alongside the rejected archived id.
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus_items WHERE date = '2026-03-02'",
            [],
            |row| row.get(0),
        )
        .expect("count");
    assert_eq!(count, 0, "no rows should be inserted on validation failure");
}

#[test]
#[serial_test::serial(hlc)]
fn mcp_set_current_focus_accepts_only_live_tasks() {
    // Sanity check that the new validator does not regress the happy
    // path — a fully-live batch must still succeed end to end.
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    let task_a = uuid::Uuid::now_v7().to_string();
    let task_b = uuid::Uuid::now_v7().to_string();
    seed_stub_tasks(&conn, &[task_a.as_str(), task_b.as_str()]);

    let response = set_current_focus(
        &conn,
        SetCurrentFocusArgs {
            task_ids: vec![task_a.clone(), task_b.clone()],
            briefing: None,
            date: Some("2026-03-02".to_string()),
            idempotency_key: None,
        },
    )
    .expect("set current focus with two live tasks");
    let payload: Value = serde_json::from_str(&response).expect("parse response");
    assert_eq!(
        payload.get("task_ids"),
        Some(&serde_json::json!([task_a, task_b])),
    );
}

#[test]
#[serial_test::serial(hlc)]
fn mcp_add_to_current_focus_rejects_phantom_task_ids() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    let live = uuid::Uuid::now_v7().to_string();
    seed_stub_tasks(&conn, &[live.as_str()]);

    // Seed an existing focus row first so we exercise the additive
    // path rather than the create branch.
    set_current_focus(
        &conn,
        SetCurrentFocusArgs {
            task_ids: vec![live],
            briefing: None,
            date: Some("2026-03-02".to_string()),
            idempotency_key: None,
        },
    )
    .expect("seed focus");

    let err = add_to_current_focus(
        &conn,
        AddToCurrentFocusArgs {
            task_ids: vec![uuid::Uuid::now_v7().to_string()],
            briefing: None,
            date: Some("2026-03-02".to_string()),
            idempotency_key: None,
        },
    )
    .expect_err("MCP path must reject phantom task_ids on add (#2888)");
    let message = err.to_string().to_lowercase();
    assert!(
        message.contains("non-existent") || message.contains("does not exist"),
        "unexpected error message: {message}",
    );

    // The pre-existing row must be untouched.
    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus_items WHERE date = '2026-03-02'",
            [],
            |row| row.get(0),
        )
        .expect("count");
    assert_eq!(count, 1, "additive path must not partially apply");
}

#[test]
#[serial_test::serial(hlc)]
fn mcp_add_to_current_focus_rejects_archived_task_ids() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    let live = uuid::Uuid::now_v7().to_string();
    let trashed = uuid::Uuid::now_v7().to_string();
    seed_stub_tasks(&conn, &[live.as_str(), trashed.as_str()]);

    set_current_focus(
        &conn,
        SetCurrentFocusArgs {
            task_ids: vec![live],
            briefing: None,
            date: Some("2026-03-02".to_string()),
            idempotency_key: None,
        },
    )
    .expect("seed focus");

    conn.execute(
        "UPDATE tasks SET archived_at = '2026-04-26T00:00:00.000Z' WHERE id = ?1",
        [trashed.as_str()],
    )
    .expect("soft-delete");

    let err = add_to_current_focus(
        &conn,
        AddToCurrentFocusArgs {
            task_ids: vec![trashed.clone()],
            briefing: None,
            date: Some("2026-03-02".to_string()),
            idempotency_key: None,
        },
    )
    .expect_err("MCP path must reject archived task_ids on add (#2888)");
    let message = err.to_string();
    assert!(message.contains("archived"), "unexpected error: {message}");
    assert!(
        message.contains(&trashed),
        "expected id in error: {message}"
    );

    let count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus_items WHERE date = '2026-03-02'",
            [],
            |row| row.get(0),
        )
        .expect("count");
    assert_eq!(count, 1, "additive path must not partially apply");
}

/// defense-in-depth read-side gate.
///
/// Even with the #2888 / #2971-H1 write-side validators in place, an
/// active task that was added to current focus can be archived AFTER
/// the focus was written (e.g. the user trashes the task in the UI
/// later). Pre-fix the read would silently surface the archived row in
/// `tasks[]` as a ghost. The new `fetch_existing_active_tasks_json`
/// helper filters `archived_at IS NULL` at read time, so the ghost
/// disappears from the rendered focus surface; the link table row is
/// preserved so the pin re-emerges automatically if the task is
/// restored.
#[test]
#[serial_test::serial(hlc)]
fn get_current_focus_omits_post_write_archived_tasks() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    let live = uuid::Uuid::now_v7().to_string();
    let later_archived = uuid::Uuid::now_v7().to_string();
    seed_stub_tasks(&conn, &[live.as_str(), later_archived.as_str()]);

    set_current_focus(
        &conn,
        SetCurrentFocusArgs {
            task_ids: vec![live.clone(), later_archived.clone()],
            briefing: None,
            date: Some("2026-03-02".to_string()),
            idempotency_key: None,
        },
    )
    .expect("seed current focus with two live tasks");

    // Archive one of the pinned tasks AFTER it landed in focus —
    // simulates the user trashing the task in the UI later.
    conn.execute(
        "UPDATE tasks SET archived_at = '2026-04-26T00:00:00.000Z' WHERE id = ?1",
        [later_archived.as_str()],
    )
    .expect("soft-delete pinned task post-write");

    let response = get_current_focus(
        &conn,
        GetCurrentFocusArgs {
            date: Some("2026-03-02".to_string()),
        },
    )
    .expect("get current focus after post-write archive");
    let payload: Value = serde_json::from_str(&response).expect("parse get response");

    // task_ids array reflects the underlying link table — both ids
    // remain so a future restore re-surfaces the row automatically.
    assert_eq!(
        payload.get("task_ids"),
        Some(&serde_json::json!([live, later_archived])),
        "task_ids must preserve the pin even after archive: {payload}",
    );

    // The rendered tasks[] array, however, must omit the archived
    // row — every other read path filters `archived_at IS NULL`,
    // so the focus surface stays internally consistent.
    let tasks = payload
        .get("tasks")
        .and_then(Value::as_array)
        .expect("tasks array");
    assert_eq!(
        tasks.len(),
        1,
        "archived task must be filtered out: {tasks:?}"
    );
    assert_eq!(
        tasks[0].get("id").and_then(Value::as_str),
        Some(live.as_str()),
        "only the still-live task should render: {tasks:?}",
    );
}

/// #4600 F4: `clear_current_focus` on a date with no plan must
/// be a complete no-op — no changelog row, no outbox envelope.
/// A peer that LWWs an empty `delete` envelope over its real
/// focus plan loses user data.
#[test]
#[serial_test::serial(hlc)]
fn mcp_clear_current_focus_on_empty_day_writes_no_changelog_or_outbox() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");

    let before_changelog: i64 = conn
        .query_row("SELECT COUNT(*) FROM ai_changelog", [], |row| row.get(0))
        .expect("count changelog");
    let before_outbox: i64 = conn
        .query_row("SELECT COUNT(*) FROM sync_outbox", [], |row| row.get(0))
        .expect("count outbox");

    clear_current_focus(
        &conn,
        ClearCurrentFocusArgs {
            date: Some("2026-03-02".to_string()),
        },
    )
    .expect("clear on empty day succeeds");

    let after_changelog: i64 = conn
        .query_row("SELECT COUNT(*) FROM ai_changelog", [], |row| row.get(0))
        .expect("count changelog");
    let after_outbox: i64 = conn
        .query_row("SELECT COUNT(*) FROM sync_outbox", [], |row| row.get(0))
        .expect("count outbox");

    assert_eq!(
        after_changelog, before_changelog,
        "no-op clear must not write a changelog row",
    );
    assert_eq!(
        after_outbox, before_outbox,
        "no-op clear must not enqueue a sync envelope",
    );
}

#[test]
#[serial_test::serial(hlc)]
fn mcp_set_current_focus_mixed_batch_reports_first_offender_in_caller_order() {
    let conn = open_temp_db();
    seed_timezone_preference(&conn, "America/Los_Angeles");
    let live = uuid::Uuid::now_v7().to_string();
    let trashed = uuid::Uuid::now_v7().to_string();
    let phantom = uuid::Uuid::now_v7().to_string();
    seed_stub_tasks(&conn, &[live.as_str(), trashed.as_str()]);
    conn.execute(
        "UPDATE tasks SET archived_at = '2026-04-26T00:00:00.000Z' WHERE id = ?1",
        [trashed.as_str()],
    )
    .expect("soft-delete");

    // Caller order: live → archived → phantom. The validator must
    // surface the archived one first (it appears before the phantom).
    let err = set_current_focus(
        &conn,
        SetCurrentFocusArgs {
            task_ids: vec![live, trashed.clone(), phantom.clone()],
            briefing: None,
            date: Some("2026-03-02".to_string()),
            idempotency_key: None,
        },
    )
    .expect_err("mixed batch must be rejected");
    let message = err.to_string();
    assert!(message.contains("archived"), "expected archived: {message}");
    assert!(message.contains(&trashed), "expected trashed id: {message}");
    assert!(
        !message.contains(&phantom),
        "phantom is later in caller order; validator should stop at archived: {message}",
    );
}
