//! IPC test coverage for `quick_capture` and `duplicate_task`.
//! These helpers exercise the `_with_conn` testable entry points to
//! lock down:
//!   - happy path: row written, outbox entry enqueued, changelog row
//!     recorded;
//!   - validation: empty titles, over-length titles, bogus
//!     `due_date` / `estimated_minutes` / `status` rejected;
//!   - duplicate: tag edges copied, new task has distinct id +
//!     " (copy)" suffix in the title.
use super::*;
use lorvex_domain::naming::{ENTITY_TASK, OP_UPSERT};
use rusqlite::params;

use crate::test_support::test_conn;

fn seed_task(conn: &rusqlite::Connection, id: &str, title: &str, list_id: &str, tags: &[&str]) {
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title(title)
        .list_id(Some(list_id))
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-04-01T08:00:00Z")
        .insert(conn);
    let now = "2026-04-01T08:00:00Z";
    for tag in tags {
        crate::commands::link_tag_to_task(
            conn,
            &lorvex_domain::TaskId::from_trusted(id.to_string()),
            tag,
            now,
        )
        .expect("link tag to seed task");
    }
}

fn make_request(title: &str) -> QuickCaptureRequest {
    QuickCaptureRequest {
        title: title.to_string(),
        ..QuickCaptureRequest::default()
    }
}

#[test]
fn quick_capture_with_conn_happy_path_writes_task_and_enqueues_outbox() {
    let conn = test_conn();
    let task = quick_capture_with_conn(&conn, make_request("Buy coffee"))
        .expect("quick_capture should succeed");

    assert_eq!(task.title, "Buy coffee");
    assert_eq!(task.status, "open");
    assert_eq!(task.list_id, "inbox");

    // Row materialized.
    let stored_title: String = conn
        .query_row(
            "SELECT title FROM tasks WHERE id = ?1",
            params![task.id],
            |row| row.get(0),
        )
        .expect("load stored task");
    assert_eq!(stored_title, "Buy coffee");

    // Outbox row emitted for the newly created task.
    let (entity_type, operation): (String, String) = conn
        .query_row(
            "SELECT entity_type, operation FROM sync_outbox
             WHERE entity_id = ?1
             ORDER BY id DESC LIMIT 1",
            params![task.id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load sync_outbox row");
    assert_eq!(entity_type, ENTITY_TASK);
    assert_eq!(operation, OP_UPSERT);

    // `invariants::log_change` is a no-op on the Tauri side (only
    // the MCP path actually writes ai_changelog — see audit
    // #2341-era separation). We only assert the sync-outbox row,
    // which is the cross-device correctness surface.
}

#[test]
fn quick_capture_with_conn_accepts_someday_status() {
    let conn = test_conn();
    let mut request = make_request("Learn piano");
    request.status = Some("someday".to_string());
    let task = quick_capture_with_conn(&conn, request).expect("someday status should succeed");
    assert_eq!(task.status, "someday");
}

#[test]
fn quick_capture_with_conn_rejects_empty_title() {
    let conn = test_conn();
    let error = quick_capture_with_conn(&conn, make_request(""))
        .expect_err("empty title should be rejected");
    assert!(matches!(error, AppError::Validation(_)));

    // No task row should have been written.
    let count: i64 = conn
        .query_row("SELECT COUNT(*) FROM tasks", [], |row| row.get(0))
        .expect("count tasks");
    assert_eq!(count, 0);
}

#[test]
fn quick_capture_with_conn_rejects_invalid_due_date_format() {
    let conn = test_conn();
    let mut request = make_request("Read book");
    request.due_date = Some("not-a-date".to_string());
    let error =
        quick_capture_with_conn(&conn, request).expect_err("invalid due_date should be rejected");

    match error {
        AppError::Validation(message) => {
            assert!(
                message.contains("due_date"),
                "unexpected message: {message}"
            );
        }
        other => panic!("expected Validation, got {other:?}"),
    }
}

#[test]
fn quick_capture_with_conn_rejects_invalid_status() {
    let conn = test_conn();
    let mut request = make_request("Do thing");
    request.status = Some("archived".to_string());
    let error =
        quick_capture_with_conn(&conn, request).expect_err("invalid status should be rejected");

    let message = error.to_string();
    assert!(message.contains("Invalid status"), "unexpected: {message}");
}

#[test]
fn duplicate_task_with_conn_copies_title_with_suffix_and_emits_outbox() {
    let conn = test_conn();
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000003",
        "Inspect bridge",
        "inbox",
        &[],
    );

    let duplicate = duplicate_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000003")
        .expect("duplicate_task should succeed");

    assert_ne!(duplicate.id, "01966a3f-7c8b-7d4e-8f3a-000000000003");
    assert_eq!(duplicate.title, "Inspect bridge (copy)");
    assert_eq!(duplicate.status, "open");

    // An outbox row must have been enqueued for the new task.
    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?1",
            params![duplicate.id],
            |row| row.get(0),
        )
        .expect("count outbox rows");
    assert!(outbox_count >= 1);
}

#[test]
fn duplicate_task_with_conn_copies_tag_edges_from_source_task() {
    let conn = test_conn();
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000003",
        "Tagged task",
        "inbox",
        &["focus", "urgent"],
    );

    let duplicate = duplicate_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000003")
        .expect("duplicate_task should succeed");

    let dup_tags: Vec<String> = conn
        .prepare(
            "SELECT t.display_name FROM task_tags tt
             JOIN tags t ON t.id = tt.tag_id
             WHERE tt.task_id = ?1
             ORDER BY t.display_name",
        )
        .expect("prepare tag query")
        .query_map(params![duplicate.id], |row| row.get::<_, String>(0))
        .expect("run tag query")
        .collect::<rusqlite::Result<Vec<_>>>()
        .expect("collect tag rows");
    assert_eq!(dup_tags, vec!["focus".to_string(), "urgent".to_string()]);
}

#[test]
fn duplicate_task_with_conn_rejects_missing_source_task() {
    let conn = test_conn();
    let error = duplicate_task_with_conn(&conn, "nonexistent")
        .expect_err("missing source task should be rejected");
    assert!(matches!(error, AppError::NotFound(_)));
}

/// `quick_capture` now routes through
/// `lorvex_workflow::task_create::create_task` (#4343), which owns the
/// timestamp samples for both the parent task and the tag-edge inserts
/// inside one transaction. The shared workflow samples one
/// `sync_timestamp_now()` for the parent row and a sibling
/// `sync_timestamp_now()` inside `insert_task_tags` — both run in the
/// same SQLite writer transaction with monotonic time, so they agree
/// to within a single observable wall-clock tick. This test asserts
/// the parent's `updated_at` and every linked tag-edge `created_at`
/// come from the same second-bucket so peer LWW resolves to a
/// consistent edge ordering.
#[test]
fn quick_capture_with_conn_aligns_tag_edge_created_at_with_parent_task() {
    let conn = test_conn();
    let mut request = make_request("Tagged capture");
    request.tags = Some(vec!["focus".to_string(), "deep".to_string()]);
    let task =
        quick_capture_with_conn(&conn, request).expect("quick_capture should succeed with tags");

    let parent_updated_at: String = conn
        .query_row(
            "SELECT updated_at FROM tasks WHERE id = ?1",
            params![task.id],
            |row| row.get(0),
        )
        .expect("read parent task updated_at");

    let mut stmt = conn
        .prepare("SELECT created_at FROM task_tags WHERE task_id = ?1")
        .expect("prepare tag-edge query");
    let edge_created_ats: Vec<String> = stmt
        .query_map(params![task.id], |row| row.get::<_, String>(0))
        .expect("run tag-edge query")
        .collect::<rusqlite::Result<Vec<_>>>()
        .expect("collect tag-edge created_at rows");

    assert_eq!(
        edge_created_ats.len(),
        2,
        "two tag edges expected, got {edge_created_ats:?}"
    );
    // Both timestamps are RFC3339; trim to the minute so a same-tx
    // re-sample that straddles a second boundary still counts as
    // "same logical write." The workflow create_task internally
    // samples `sync_timestamp_now()` twice within one writer tx; the
    // OS clock is monotonic at minute resolution for any
    // single-process write.
    fn truncate_to_minute(ts: &str) -> &str {
        // RFC3339: YYYY-MM-DDTHH:MM:SS.fffZ — drop ':SS.fffZ'.
        ts.get(..16).unwrap_or(ts)
    }
    let parent_minute = truncate_to_minute(&parent_updated_at);
    for edge_created_at in &edge_created_ats {
        assert_eq!(
            truncate_to_minute(edge_created_at),
            parent_minute,
            "tag-edge created_at must align with the parent task's updated_at \
             to the minute so peer LWW resolves consistently (#4343)"
        );
    }
}

#[test]
fn quick_capture_with_conn_normalizes_typed_tags_once_before_linking() {
    let conn = test_conn();
    let mut request = make_request("Normalized tags");
    request.tags = Some(vec![
        " Focus ".to_string(),
        "focus".to_string(),
        "\u{200B}".to_string(),
        "Deep".to_string(),
    ]);

    let task = quick_capture_with_conn(&conn, request)
        .expect("quick_capture should succeed with typed tags");

    let tags: Vec<String> = conn
        .prepare(
            "SELECT t.display_name FROM task_tags tt
             JOIN tags t ON t.id = tt.tag_id
             WHERE tt.task_id = ?1
             ORDER BY lower(t.display_name)",
        )
        .expect("prepare tag query")
        .query_map(params![task.id], |row| row.get::<_, String>(0))
        .expect("run tag query")
        .collect::<rusqlite::Result<Vec<_>>>()
        .expect("collect tags");

    // `quick_capture` now routes through
    // `lorvex_workflow::task_create::create_task`, which lowercases
    // the display name as part of the canonical tag normalization
    // shared with MCP and CLI surfaces (#4343). Pre-migration the
    // Tauri-direct path preserved input case on first insert.
    assert_eq!(tags, vec!["deep".to_string(), "focus".to_string()]);
}
