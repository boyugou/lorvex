//! IPC test coverage for the lifecycle removal
//! commands. These exercise the `_with_conn` shims — which mirror
//! the production transaction body but run against an in-memory
//! SQLite connection without the Spotlight / event-bus post-commit
//! dispatch that requires a live Tauri runtime.
use super::*;
use lorvex_domain::naming::{EDGE_TASK_CALENDAR_EVENT_LINK, EDGE_TASK_TAG, ENTITY_TASK};
use rusqlite::params;

use crate::commands::tasks::UndoToken;
use crate::error::AppError;
use crate::test_support::{fixture_uuid, test_conn};

struct SeededChildIds {
    tag_edge_id: String,
    checklist_item_id: String,
    reminder_id: String,
    calendar_link_edge_id: String,
    outgoing_dep_edge_id: String,
    incoming_dep_edge_id: String,
}

fn seed_task(conn: &rusqlite::Connection, id: &str, status: &str, archived_at: Option<&str>) {
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title("Removal target")
        .status(status)
        .list_id(Some("inbox"))
        .archived_at(archived_at)
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-04-01T08:00:00Z")
        .insert(conn);
}

fn seed_task_delete_children(
    conn: &rusqlite::Connection,
    task_id: &str,
    incoming_dep_task_id: &str,
    outgoing_dep_task_id: &str,
) -> SeededChildIds {
    let tag_id = fixture_uuid(&format!("tag-{task_id}"));
    let checklist_item_id = fixture_uuid(&format!("check-{task_id}"));
    let reminder_id = fixture_uuid(&format!("reminder-{task_id}"));
    let event_id = fixture_uuid(&format!("event-{task_id}"));

    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
         VALUES (?1, 'Delete tag', ?2, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z', '2026-04-01T08:00:00Z')",
        params![tag_id, format!("delete-tag-{task_id}")],
    )
    .expect("seed tag");
    conn.execute(
        "INSERT INTO task_tags (task_id, tag_id, version, created_at)
         VALUES (?1, ?2, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z')",
        params![task_id, &tag_id],
    )
    .expect("seed task tag");

    conn.execute(
        "INSERT INTO task_checklist_items
            (id, task_id, position, text, version, created_at, updated_at)
         VALUES (?1, ?2, 0, 'Checklist', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z', '2026-04-01T08:00:00Z')",
        params![&checklist_item_id, task_id],
    )
    .expect("seed checklist item");

    conn.execute(
        "INSERT INTO task_reminders (id, task_id, reminder_at, version, created_at)
         VALUES (?1, ?2, '2026-04-20T09:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z')",
        params![&reminder_id, task_id],
    )
    .expect("seed reminder");

    conn.execute(
        "INSERT INTO calendar_events
            (id, title, start_date, all_day, version, created_at, updated_at)
         VALUES (?1, 'Delete event', '2026-04-20', 1, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z', '2026-04-01T08:00:00Z')",
        params![&event_id],
    )
    .expect("seed calendar event");
    conn.execute(
        "INSERT INTO task_calendar_event_links
            (task_id, calendar_event_id, created_at, updated_at, version)
         VALUES (?1, ?2, '2026-04-01T08:00:00Z', '2026-04-01T08:00:00Z', '0000000000000_0000_a0a0a0a0a0a0a0a0')",
        params![task_id, &event_id],
    )
    .expect("seed calendar link");

    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at)
         VALUES (?1, ?2, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z')",
        params![task_id, outgoing_dep_task_id],
    )
    .expect("seed outgoing dependency");
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at)
         VALUES (?1, ?2, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z')",
        params![incoming_dep_task_id, task_id],
    )
    .expect("seed incoming dependency");

    SeededChildIds {
        tag_edge_id: format!("{task_id}:{tag_id}"),
        checklist_item_id,
        reminder_id,
        calendar_link_edge_id: format!("{task_id}:{event_id}"),
        outgoing_dep_edge_id: format!("{task_id}:{outgoing_dep_task_id}"),
        incoming_dep_edge_id: format!("{incoming_dep_task_id}:{task_id}"),
    }
}

fn count_delete_outbox(conn: &rusqlite::Connection, entity_type: &str, entity_id: &str) -> i64 {
    conn.query_row(
        "SELECT COUNT(*) FROM sync_outbox
         WHERE entity_type = ?1 AND entity_id = ?2 AND operation = 'delete'",
        params![entity_type, entity_id],
        |row| row.get(0),
    )
    .expect("count delete outbox rows")
}

fn count_tombstones(conn: &rusqlite::Connection, entity_type: &str, entity_id: &str) -> i64 {
    conn.query_row(
        "SELECT COUNT(*) FROM sync_tombstones
         WHERE entity_type = ?1 AND entity_id = ?2",
        params![entity_type, entity_id],
        |row| row.get(0),
    )
    .expect("count tombstones")
}

// ──────────────────────────────────────────────────────────────────
// cancel_task
// ──────────────────────────────────────────────────────────────────

#[test]
fn cancel_task_with_conn_rejects_missing_task() {
    let conn = test_conn();
    let error = cancel_task_with_conn(&conn, "does-not-exist", false)
        .expect_err("missing task should be rejected");
    assert!(matches!(error, AppError::NotFound(_)));
}

#[test]
fn cancel_task_with_conn_rejects_already_cancelled() {
    let conn = test_conn();
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000005f",
        "cancelled",
        None,
    );

    let error = cancel_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000005f", false)
        .expect_err("double-cancel should be rejected");
    match error {
        AppError::Validation(msg) => {
            assert!(msg.contains("already cancelled"), "unexpected: {msg}");
        }
        other => panic!("expected Validation, got {other:?}"),
    }
}

#[test]
fn cancel_task_with_conn_rejects_completed_task() {
    let conn = test_conn();
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000004c",
        "completed",
        None,
    );

    let error = cancel_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000004c", false)
        .expect_err("completed task must be reopened before cancellation");
    match error {
        AppError::Validation(msg) => {
            assert!(
                msg.contains("completed") && msg.contains("cancelled"),
                "unexpected: {msg}"
            );
        }
        other => panic!("expected Validation, got {other:?}"),
    }
}

#[test]
fn cancel_task_with_conn_cancels_open_task_and_emits_outbox_row() {
    let conn = test_conn();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000064", "open", None);

    let result = cancel_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000064", false)
        .expect("cancel should succeed");
    assert_eq!(result.task.status, "cancelled");
    assert!(
        !result.undo_token.is_empty(),
        "undo token must be populated for a successful cancel"
    );

    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000064'",
            [],
            |row| row.get(0),
        )
        .expect("count outbox rows");
    assert!(outbox_count >= 1, "cancel must enqueue a sync envelope");
}

#[test]
fn cancel_task_with_conn_preserves_series_flag_in_undo_token() {
    let conn = test_conn();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000077", "open", None);

    let result = cancel_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000077", true)
        .expect("cancel should succeed");
    let undo: UndoToken = serde_json::from_str(&result.undo_token).expect("parse undo token");

    assert!(
        undo.cancel_series,
        "redo must know the original cancel was a series stop"
    );
}

// ──────────────────────────────────────────────────────────────────
// permanent_delete_task — archive-gate cases are covered in #2490,
// so here we check the core hard-delete path once the gate is open.
// ──────────────────────────────────────────────────────────────────

#[test]
fn permanent_delete_task_with_conn_is_noop_on_missing_row() {
    let conn = test_conn();
    let deleted = permanent_delete_task_with_conn(&conn, "does-not-exist")
        .expect("missing row should succeed as no-op");
    assert!(!deleted, "no-op delete must report `deleted = false`");
}

#[test]
fn permanent_delete_task_with_conn_removes_archived_task() {
    let conn = test_conn();
    // Archived tasks are eligible for hard-delete (they're already
    // in the Trash).
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000003e",
        "cancelled",
        Some("2026-04-01T09:00:00Z"),
    );

    let deleted = permanent_delete_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000003e")
        .expect("archived task should hard-delete");
    assert!(deleted);

    let remaining: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-00000000003e'",
            [],
            |row| row.get(0),
        )
        .expect("count tasks");
    assert_eq!(remaining, 0, "task row must be gone after hard-delete");

    // A delete envelope must be enqueued for peer propagation.
    let delete_envelope_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = '01966a3f-7c8b-7d4e-8f3a-00000000003e' AND operation = 'delete'",
            [],
            |row| row.get(0),
        )
        .expect("count delete envelopes");
    assert!(
        delete_envelope_count >= 1,
        "hard-delete must enqueue a delete envelope"
    );
}

#[test]
fn permanent_delete_task_with_conn_emits_child_delete_envelopes_and_tombstones() {
    let conn = test_conn();
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000003f",
        "cancelled",
        Some("2026-04-01T09:00:00Z"),
    );
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000049", "open", None);
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000004a", "open", None);
    let child_ids = seed_task_delete_children(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000003f",
        "01966a3f-7c8b-7d4e-8f3a-000000000049",
        "01966a3f-7c8b-7d4e-8f3a-00000000004a",
    );

    let deleted = permanent_delete_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000003f")
        .expect("archived task should hard-delete with child sync");
    assert!(deleted);

    let expected = [
        (EDGE_TASK_TAG, child_ids.tag_edge_id.as_str()),
        (
            lorvex_domain::naming::ENTITY_TASK_CHECKLIST_ITEM,
            child_ids.checklist_item_id.as_str(),
        ),
        (
            lorvex_domain::naming::ENTITY_TASK_REMINDER,
            child_ids.reminder_id.as_str(),
        ),
        (
            EDGE_TASK_CALENDAR_EVENT_LINK,
            child_ids.calendar_link_edge_id.as_str(),
        ),
        (
            lorvex_domain::naming::EDGE_TASK_DEPENDENCY,
            child_ids.outgoing_dep_edge_id.as_str(),
        ),
        (
            lorvex_domain::naming::EDGE_TASK_DEPENDENCY,
            child_ids.incoming_dep_edge_id.as_str(),
        ),
    ];

    for (entity_type, entity_id) in expected {
        assert!(
            count_delete_outbox(&conn, entity_type, entity_id) >= 1,
            "expected delete outbox row for {entity_type}/{entity_id}"
        );
        assert_eq!(
            count_tombstones(&conn, entity_type, entity_id),
            1,
            "expected tombstone for {entity_type}/{entity_id}"
        );
    }
}

// ──────────────────────────────────────────────────────────────────
// purge_cancelled_tasks
// ──────────────────────────────────────────────────────────────────

#[test]
fn purge_cancelled_tasks_with_conn_is_noop_when_none_cancelled() {
    let conn = test_conn();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000064", "open", None);

    let result =
        purge_cancelled_tasks_with_conn(&conn).expect("purge should succeed on empty-trash DB");

    assert_eq!(result.purged_count, 0);
    assert!(result.purged_task_ids.is_empty());
}

#[test]
fn purge_cancelled_tasks_with_conn_deletes_only_cancelled_and_emits_tombstones() {
    let conn = test_conn();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000064", "open", None);
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000040",
        "cancelled",
        None,
    );
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000041",
        "cancelled",
        None,
    );

    let result = purge_cancelled_tasks_with_conn(&conn).expect("purge should succeed");

    assert_eq!(result.purged_count, 2);
    assert_eq!(result.purged_task_ids.len(), 2);
    assert!(result
        .purged_task_ids
        .contains(&"01966a3f-7c8b-7d4e-8f3a-000000000040".to_string()));
    assert!(result
        .purged_task_ids
        .contains(&"01966a3f-7c8b-7d4e-8f3a-000000000041".to_string()));

    let surviving: i64 = conn
        .query_row("SELECT COUNT(*) FROM tasks", [], |row| row.get(0))
        .expect("count surviving tasks");
    assert_eq!(surviving, 1, "only the open task should remain");

    // Each cancelled task must have enqueued a delete envelope so
    // peers can apply the tombstone.
    for id in &result.purged_task_ids {
        let count: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = ?1 AND operation = 'delete'",
                params![id],
                |row| row.get(0),
            )
            .expect("count delete envelopes");
        assert!(count >= 1, "purge must enqueue a delete envelope for {id}");
    }
}

#[test]
fn purge_cancelled_tasks_with_conn_skips_lww_newer_cancelled_rows() {
    let conn = test_conn();
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000061",
        "cancelled",
        None,
    );
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000051",
        "cancelled",
        None,
    );
    conn.execute(
        "UPDATE tasks
         SET version = '9999999999999_9999_ffffffffffffffff'
         WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000051'",
        [],
    )
    .expect("force future version");

    let result = purge_cancelled_tasks_with_conn(&conn).expect("purge should succeed");

    assert_eq!(
        result.purged_task_ids,
        vec!["01966a3f-7c8b-7d4e-8f3a-000000000061".to_string()]
    );
    assert_eq!(result.purged_count, 1);

    let stale_status: String = conn
        .query_row(
            "SELECT status FROM tasks WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000051'",
            [],
            |row| row.get(0),
        )
        .expect("future-version task should remain");
    assert_eq!(stale_status, "cancelled");
    assert_eq!(
        count_delete_outbox(&conn, ENTITY_TASK, "01966a3f-7c8b-7d4e-8f3a-000000000051"),
        0,
        "LWW-skipped task must not emit a delete envelope"
    );
}

#[test]
fn purge_cancelled_tasks_with_conn_emits_child_delete_envelopes_and_tombstones() {
    let conn = test_conn();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000068", "open", None);
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000065",
        "cancelled",
        None,
    );
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000066", "open", None);
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000067", "open", None);
    let child_ids = seed_task_delete_children(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000065",
        "01966a3f-7c8b-7d4e-8f3a-000000000066",
        "01966a3f-7c8b-7d4e-8f3a-000000000067",
    );

    let result = purge_cancelled_tasks_with_conn(&conn).expect("purge should succeed");
    assert_eq!(result.purged_count, 1);
    assert_eq!(
        result.purged_task_ids,
        vec!["01966a3f-7c8b-7d4e-8f3a-000000000065".to_string()]
    );

    let expected = [
        (EDGE_TASK_TAG, child_ids.tag_edge_id.as_str()),
        (
            lorvex_domain::naming::ENTITY_TASK_CHECKLIST_ITEM,
            child_ids.checklist_item_id.as_str(),
        ),
        (
            lorvex_domain::naming::ENTITY_TASK_REMINDER,
            child_ids.reminder_id.as_str(),
        ),
        (
            EDGE_TASK_CALENDAR_EVENT_LINK,
            child_ids.calendar_link_edge_id.as_str(),
        ),
        (
            lorvex_domain::naming::EDGE_TASK_DEPENDENCY,
            child_ids.outgoing_dep_edge_id.as_str(),
        ),
        (
            lorvex_domain::naming::EDGE_TASK_DEPENDENCY,
            child_ids.incoming_dep_edge_id.as_str(),
        ),
    ];

    for (entity_type, entity_id) in expected {
        assert!(
            count_delete_outbox(&conn, entity_type, entity_id) >= 1,
            "expected delete outbox row for {entity_type}/{entity_id}"
        );
        assert_eq!(
            count_tombstones(&conn, entity_type, entity_id),
            1,
            "expected tombstone for {entity_type}/{entity_id}"
        );
    }
}

/// every hard-delete site that flows
/// through `cleanup_plan_refs_after_removal` MUST re-enqueue
/// parent-aggregate upserts for the dates whose `current_focus` /
/// `focus_schedule` rows pointed at the doomed task. Pre-fix the
/// helper did a bare two-statement DELETE and peers' plan
/// aggregates kept pointing at the removed task. This exercises
/// `permanent_delete_task_with_conn`; the same helper is shared
/// with `purge_cancelled_tasks_with_conn` and `empty_trash_with_conn`,
/// which are covered by sibling regressions in their own modules.
#[test]
fn permanent_delete_reenqueues_parent_aggregate_upserts_for_focus_and_schedule_days() {
    let conn = test_conn();
    // Archive-gate: permanent_delete_task_with_conn refuses live tasks.
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000058",
        "open",
        Some("2026-04-01T09:00:00Z"),
    );

    conn.execute(
        "INSERT OR IGNORE INTO current_focus (date, briefing, version, created_at, updated_at) \
         VALUES ('2026-04-22', NULL, '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-22T00:00:00Z', '2026-04-22T00:00:00Z')",
        [],
    )
    .expect("seed current_focus row");
    conn.execute(
        "INSERT INTO current_focus_items (date, task_id, position) \
         VALUES ('2026-04-22', '01966a3f-7c8b-7d4e-8f3a-000000000058', 0)",
        [],
    )
    .expect("seed focus item");
    conn.execute(
        "INSERT OR IGNORE INTO focus_schedule (date, version, created_at, updated_at) \
         VALUES ('2026-04-23', '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-23T00:00:00Z', '2026-04-23T00:00:00Z')",
        [],
    )
    .expect("seed focus_schedule row");
    conn.execute(
        "INSERT INTO focus_schedule_blocks
            (schedule_date, position, block_type, start_time, end_time, task_id)
         VALUES ('2026-04-23', 0, 'task', 540, 600, '01966a3f-7c8b-7d4e-8f3a-000000000058')",
        [],
    )
    .expect("seed focus_schedule block");

    let deleted = permanent_delete_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000058")
        .expect("archived task should hard-delete with plan-ref re-enqueue");
    assert!(deleted);

    // Post-fix expectation: at least one parent-aggregate upsert
    // envelope per affected day must have been enqueued. The
    // `entity_id` for date-keyed aggregates is the date string.
    let current_focus_envelopes: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox \
             WHERE entity_type = 'current_focus' AND operation = 'upsert' \
               AND entity_id = '2026-04-22'",
            [],
            |row| row.get(0),
        )
        .expect("count current_focus envelopes for affected day");
    assert!(
        current_focus_envelopes >= 1,
        "permanent_delete must enqueue a current_focus parent-aggregate upsert for 2026-04-22"
    );
    let focus_schedule_envelopes: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox \
             WHERE entity_type = 'focus_schedule' AND operation = 'upsert' \
               AND entity_id = '2026-04-23'",
            [],
            |row| row.get(0),
        )
        .expect("count focus_schedule envelopes for affected day");
    assert!(
        focus_schedule_envelopes >= 1,
        "permanent_delete must enqueue a focus_schedule parent-aggregate upsert for 2026-04-23"
    );

    // Sanity: the local rows are gone.
    let live_items: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM current_focus_items WHERE task_id = '01966a3f-7c8b-7d4e-8f3a-000000000058'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(live_items, 0);
    let live_blocks: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM focus_schedule_blocks WHERE task_id = '01966a3f-7c8b-7d4e-8f3a-000000000058'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(live_blocks, 0);
}

#[test]
fn permanent_delete_reenqueues_dependent_task_aggregate_after_dependency_cleanup() {
    let conn = test_conn();
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-00000000005e",
        "open",
        Some("2026-04-01T09:00:00Z"),
    );
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000004b", "open", None);
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-00000000004b', '01966a3f-7c8b-7d4e-8f3a-00000000005e',
                 '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z')",
        [],
    )
    .expect("seed dependency");

    let deleted = permanent_delete_task_with_conn(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000005e")
        .expect("archived task should hard-delete");
    assert!(deleted);

    let dependent_upserts: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = 'task' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-00000000004b'
               AND operation = 'upsert'",
            [],
            |row| row.get(0),
        )
        .expect("count dependent task upserts");
    assert_eq!(
        dependent_upserts, 1,
        "hard-delete dependency cleanup must sync the dependent task aggregate"
    );
}

#[test]
fn purge_cancelled_reenqueues_dependent_task_aggregate_after_dependency_cleanup() {
    let conn = test_conn();
    seed_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000043",
        "cancelled",
        None,
    );
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-00000000004b", "open", None);
    conn.execute(
        "INSERT INTO task_dependencies (task_id, depends_on_task_id, version, created_at)
         VALUES ('01966a3f-7c8b-7d4e-8f3a-00000000004b', '01966a3f-7c8b-7d4e-8f3a-000000000043',
                 '0000000000000_0000_a0a0a0a0a0a0a0a0', '2026-04-01T08:00:00Z')",
        [],
    )
    .expect("seed dependency");

    let result = purge_cancelled_tasks_with_conn(&conn).expect("purge should succeed");
    assert_eq!(
        result.purged_task_ids,
        vec!["01966a3f-7c8b-7d4e-8f3a-000000000043".to_string()]
    );

    let dependent_upserts: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox
             WHERE entity_type = 'task' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-00000000004b'
               AND operation = 'upsert'",
            [],
            |row| row.get(0),
        )
        .expect("count dependent task upserts");
    assert_eq!(
        dependent_upserts, 1,
        "purge dependency cleanup must sync the dependent task aggregate"
    );
}
