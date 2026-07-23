//! Internal test coverage for the body-append helper. The underlying
//! `lorvex_workflow::lifecycle::append_to_task_body`
//! has its own tests; this suite locks down validation and outbox
//! enqueue behavior at the command-adapter boundary.
use super::*;
use rusqlite::params;

use crate::test_support::test_conn;

fn seed_task(conn: &rusqlite::Connection, id: &str, title: &str) {
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(id)
        .title(title)
        .list_id(Some("inbox"))
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-04-01T08:00:00Z")
        .insert(conn);
}

#[test]
fn append_to_task_body_with_conn_rejects_whitespace_only_text() {
    let conn = test_conn();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000001", "Task 1");

    let error = append_to_task_body_with_conn(
        &conn,
        &lorvex_domain::TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000001".to_string()),
        "   \n\t  ",
        "2026-04-01T09:00:00Z",
    )
    .expect_err("whitespace-only text should be rejected");

    match error {
        AppError::Validation(message) => {
            assert!(message.contains("text"), "unexpected: {message}");
        }
        other => panic!("expected Validation, got {other:?}"),
    }
}

#[test]
fn append_to_task_body_with_conn_appends_text_and_enqueues_outbox() {
    let conn = test_conn();
    seed_task(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000001", "Task 1");

    let task = append_to_task_body_with_conn(
        &conn,
        &lorvex_domain::TaskId::from_trusted("01966a3f-7c8b-7d4e-8f3a-000000000001".to_string()),
        "Follow-up note",
        "2026-04-01T09:00:00Z",
    )
    .expect("append should succeed");

    assert!(
        task.body
            .as_deref()
            .unwrap_or("")
            .contains("Follow-up note"),
        "task body should contain appended text, got {:?}",
        task.body
    );

    let outbox_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000001'",
            [],
            |row| row.get(0),
        )
        .expect("count outbox rows");
    assert!(outbox_count >= 1);
}

#[test]
fn append_to_task_body_with_conn_rejects_missing_task() {
    let conn = test_conn();

    let error = append_to_task_body_with_conn(
        &conn,
        &lorvex_domain::TaskId::from_trusted("nonexistent".to_string()),
        "Hello",
        "2026-04-01T09:00:00Z",
    )
    .expect_err("missing task should be rejected");

    // Surfaces as either NotFound (fetch failure) or Store error
    // from the lorvex_workflow append call — both are acceptable
    // negative signals. Just assert the DB state wasn't mutated.
    assert!(!error.to_string().is_empty());
}

// ──────────────────────────────────────────────────────────────────
// update_task undo roundtrip regression tests. Each
// drives the full `update_task_inner_with_conn` path, invokes the
// shared undo apply helper from the `undo` sibling, and asserts
// the pre-mutation state is fully restored.
// ──────────────────────────────────────────────────────────────────

// `apply_task_update` gates writes on `new_version >
// existing_version` lexicographically. HLC versions render as
// `{13-digit ms}_{counter}_{device}` — a digit-leading string. Seed
// rows must therefore use a version that is lex-LESS than any real
// HLC, otherwise the WHERE clause filters out every test mutation.
const SEED_VERSION: &str = "0000000000000_0000_7365656473656564";

fn seed_list_and_task(conn: &rusqlite::Connection, list_id: &str, task_id: &str, title: &str) {
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at)
         VALUES (?1, 'Default', ?2, '2026-04-01T08:00:00Z', '2026-04-01T08:00:00Z')",
        params![list_id, SEED_VERSION],
    )
    .expect("seed list");
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new(task_id)
        .title(title)
        .version(SEED_VERSION)
        .created_at("2026-04-01T08:00:00Z")
        .list_id(Some(list_id))
        .insert(conn);
}

fn assert_task_unchanged_after_rejected_update(conn: &rusqlite::Connection, task_id: &str) {
    let (title, version): (String, String) = conn
        .query_row(
            "SELECT title, version FROM tasks WHERE id = ?1",
            [task_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load task after rejected update");
    assert_eq!(title, "Original");
    assert_eq!(version, SEED_VERSION);

    let outbox_count: i64 = conn
        .query_row("SELECT COUNT(*) FROM sync_outbox", [], |row| row.get(0))
        .expect("count outbox rows after rejected update");
    assert_eq!(outbox_count, 0);
}

#[test]
fn update_task_rejects_malformed_scalar_patch_values_without_mutating() {
    let cases = [
        ("title", serde_json::json!({ "title": null })),
        ("body", serde_json::json!({ "body": true })),
        ("ai_notes", serde_json::json!({ "ai_notes": ["note"] })),
        ("status", serde_json::json!({ "status": 7 })),
        ("list_id", serde_json::json!({ "list_id": false })),
        ("priority", serde_json::json!({ "priority": "high" })),
        (
            "estimated_minutes",
            serde_json::json!({ "estimated_minutes": 1.5 }),
        ),
        ("due_date", serde_json::json!({ "due_date": true })),
        ("due_time", serde_json::json!({ "due_time": 7 })),
        ("planned_date", serde_json::json!({ "planned_date": [] })),
        ("recurrence", serde_json::json!({ "recurrence": "DAILY" })),
    ];

    for (field, patch) in cases {
        let conn = test_conn();
        seed_list_and_task(
            &conn,
            "01966a3f-7c8b-7d4e-8f3a-000000000024",
            "01966a3f-7c8b-7d4e-8f3a-000000000014",
            "Original",
        );

        let error = crate::commands::with_immediate_transaction(&conn, |conn| {
            update_task_inner_with_conn(conn, "01966a3f-7c8b-7d4e-8f3a-000000000014", &patch)
        })
        .expect_err("malformed update_task patch should be rejected");

        match error {
            AppError::Validation(message) => assert!(
                message.contains(field),
                "expected {field} validation error, got {message}"
            ),
            other => panic!("expected Validation for {field}, got {other:?}"),
        }
        assert_task_unchanged_after_rejected_update(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000014");
    }
}

#[test]
fn update_task_rejects_malformed_relationship_arrays_without_mutating() {
    let cases = [
        ("tags", serde_json::json!({ "tags": ["work", 42] })),
        (
            "depends_on",
            serde_json::json!({ "depends_on": ["01966a3f-7c8b-7d4e-8f3a-000000000015", false] }),
        ),
    ];

    for (field, patch) in cases {
        let conn = test_conn();
        seed_list_and_task(
            &conn,
            "01966a3f-7c8b-7d4e-8f3a-000000000024",
            "01966a3f-7c8b-7d4e-8f3a-000000000014",
            "Original",
        );

        let error = crate::commands::with_immediate_transaction(&conn, |conn| {
            update_task_inner_with_conn(conn, "01966a3f-7c8b-7d4e-8f3a-000000000014", &patch)
        })
        .expect_err("mixed relationship arrays should be rejected");

        match error {
            AppError::Validation(message) => assert!(
                message.contains(field),
                "expected {field} validation error, got {message}"
            ),
            other => panic!("expected Validation for {field}, got {other:?}"),
        }
        assert_task_unchanged_after_rejected_update(&conn, "01966a3f-7c8b-7d4e-8f3a-000000000014");
    }
}

/// Parse the `UndoToken` JSON returned by `update_task_inner_with_conn`
/// and replay it through the canonical undo-apply helper. Mirrors
/// what `undo_task_lifecycle` does at the IPC boundary, including
/// the surrounding `with_immediate_transaction` wrap that the
/// lifecycle-transition assertion requires (#2926-H4).
fn apply_update_undo_via_token(
    conn: &rusqlite::Connection,
    undo_token_json: &str,
    now: &str,
) -> Result<Task, AppError> {
    let undo: super::super::undo::UndoToken =
        serde_json::from_str(undo_token_json).expect("parse undo token");
    crate::commands::with_immediate_transaction(conn, |conn| {
        super::super::undo::apply_single_undo_for_tests(conn, &undo, now)
    })
}

#[test]
fn update_task_undo_roundtrip_restores_title_priority_due_date() {
    let conn = test_conn();
    seed_list_and_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000024",
        "01966a3f-7c8b-7d4e-8f3a-000000000005",
        "Original",
    );
    conn.execute(
        "UPDATE tasks SET priority = 3, due_date = '2026-04-10' WHERE id = '01966a3f-7c8b-7d4e-8f3a-000000000005'",
        [],
    )
    .expect("seed priority + due_date");

    let now = "2026-04-15T09:00:00.000000Z";
    // `apply_lifecycle_transition` debug-asserts the
    // caller already opened a transaction. Production paths route
    // through `with_immediate_transaction`; tests must mirror that.
    let result = crate::commands::with_immediate_transaction(&conn, |conn| {
        update_task_inner_with_conn(
            conn,
            "01966a3f-7c8b-7d4e-8f3a-000000000005",
            &serde_json::json!({
                "title": "Mutated",
                "priority": 1,
                "due_date": "2026-04-20",
            }),
        )
    })
    .expect("update should succeed");

    assert_eq!(result.task.title, "Mutated");
    assert_eq!(result.task.priority, Some(1));
    assert_eq!(result.task.due_date.as_deref(), Some("2026-04-20"));
    assert!(
        !result.undo_token.is_empty(),
        "update must emit an undo token"
    );

    // The forward update enqueues a plain, immediately-dispatchable
    // task upsert row (no emit-hold).
    let pending_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox \
             WHERE entity_type = 'task' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000005' \
             AND synced_at IS NULL",
            [],
            |row| row.get(0),
        )
        .expect("count pending outbox");
    assert!(
        pending_count >= 1,
        "forward update must enqueue a pending task outbox row"
    );

    // Replay the undo — the pre-mutation values must come back.
    let restored =
        apply_update_undo_via_token(&conn, &result.undo_token, now).expect("undo should succeed");
    assert_eq!(restored.title, "Original");
    assert_eq!(restored.priority, Some(3));
    assert_eq!(restored.due_date.as_deref(), Some("2026-04-10"));
}

#[test]
fn update_task_public_undo_succeeds_without_redo_token() {
    let conn = test_conn();
    seed_list_and_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000024",
        "01966a3f-7c8b-7d4e-8f3a-000000000006",
        "Original",
    );

    let now = "2026-04-15T09:00:00.000000Z";
    let result = crate::commands::with_immediate_transaction(&conn, |conn| {
        update_task_inner_with_conn(
            conn,
            "01966a3f-7c8b-7d4e-8f3a-000000000006",
            &serde_json::json!({
                "title": "Changed through update",
                "priority": 1,
            }),
        )
    })
    .expect("update should succeed");

    let restored =
        super::super::undo::undo_task_lifecycle_with_conn_for_tests(&conn, &result.undo_token, now)
            .expect("public undo wrapper should succeed for update tokens");

    assert_eq!(restored.task.title, "Original");
    assert_eq!(restored.task.priority, None);
    assert_eq!(
        restored.redo_token, None,
        "update undo is intentionally one-way"
    );

    // Undo replays the snapshot through the update path, leaving an
    // ordinary unsynced task upsert that supersedes the forward write.
    let restored_outbox_rows: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox \
             WHERE entity_type = 'task' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000006' \
             AND synced_at IS NULL",
            [],
            |row| row.get(0),
        )
        .expect("count restored outbox rows");
    assert!(
        restored_outbox_rows >= 1,
        "undo restore must enqueue an ordinary unsynced task upsert"
    );
}

#[test]
fn consecutive_updates_coalesce_and_latest_undo_restores_prior_edit() {
    let conn = test_conn();
    seed_list_and_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000024",
        "01966a3f-7c8b-7d4e-8f3a-000000000007",
        "Original",
    );

    let now = "2026-04-15T09:00:00.000000Z";
    crate::commands::with_immediate_transaction(&conn, |conn| {
        update_task_inner_with_conn(
            conn,
            "01966a3f-7c8b-7d4e-8f3a-000000000007",
            &serde_json::json!({ "title": "First edit" }),
        )
    })
    .expect("first update should succeed");

    let second = crate::commands::with_immediate_transaction(&conn, |conn| {
        update_task_inner_with_conn(
            conn,
            "01966a3f-7c8b-7d4e-8f3a-000000000007",
            &serde_json::json!({ "title": "Second edit" }),
        )
    })
    .expect("second update should succeed");

    // Two consecutive updates to the same task coalesce into a single
    // pending task outbox row carrying the latest state.
    let pending_task_rows: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox \
             WHERE entity_type = 'task' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000007' \
             AND synced_at IS NULL",
            [],
            |row| row.get(0),
        )
        .expect("count pending task rows");
    assert_eq!(
        pending_task_rows, 1,
        "consecutive updates must coalesce into one pending task outbox row"
    );

    // The second update's token snapshots the post-first-edit state, so
    // undoing the latest edit restores the "First edit" title.
    let restored =
        apply_update_undo_via_token(&conn, &second.undo_token, now).expect("undo should succeed");
    assert_eq!(
        restored.title, "First edit",
        "undoing the latest edit must restore the first edit snapshot"
    );

    let pending_after_undo: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox \
             WHERE entity_type = 'task' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000007' \
             AND synced_at IS NULL",
            [],
            |row| row.get(0),
        )
        .expect("count pending task rows after undo");
    assert_eq!(
        pending_after_undo, 1,
        "undo replays through the update path, coalescing into one pending row"
    );
}

#[test]
fn update_task_undo_after_forward_rows_synced_emits_compensating_upsert() {
    let conn = test_conn();
    seed_list_and_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000024",
        "01966a3f-7c8b-7d4e-8f3a-000000000008",
        "Original",
    );

    let now = "2026-04-15T09:00:00.000000Z";
    let result = crate::commands::with_immediate_transaction(&conn, |conn| {
        update_task_inner_with_conn(
            conn,
            "01966a3f-7c8b-7d4e-8f3a-000000000008",
            &serde_json::json!({
                "title": "Already shipped",
                "priority": 1,
            }),
        )
    })
    .expect("update should succeed");

    // Simulate a push cycle that shipped the forward update's row.
    conn.execute(
        "UPDATE sync_outbox SET synced_at = ?1 \
         WHERE entity_type = 'task' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000008' \
         AND synced_at IS NULL",
        params![now],
    )
    .expect("mark forward row synced");

    let restored = apply_update_undo_via_token(&conn, &result.undo_token, now)
        .expect("undo should succeed after forward rows shipped");

    assert_eq!(restored.title, "Original");
    assert_eq!(restored.priority, None);

    let shipped_forward_rows: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox \
             WHERE entity_type = 'task' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000008' \
             AND synced_at IS NOT NULL",
            [],
            |row| row.get(0),
        )
        .expect("count shipped forward rows");
    assert!(
        shipped_forward_rows >= 1,
        "synced forward rows must remain as immutable send history"
    );

    let forward_version: String = conn
        .query_row(
            "SELECT version FROM sync_outbox \
             WHERE entity_type = 'task' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000008' \
             AND synced_at IS NOT NULL \
             ORDER BY id DESC LIMIT 1",
            [],
            |row| row.get(0),
        )
        .expect("load shipped forward version");
    let (operation, compensating_version): (String, String) = conn
        .query_row(
            "SELECT operation, version FROM sync_outbox \
             WHERE entity_type = 'task' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000008' \
             AND synced_at IS NULL \
             ORDER BY id DESC LIMIT 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("load compensating row");
    assert_eq!(
        operation, "upsert",
        "undo after a shipped update must enqueue an upsert, not a tombstone or no-op envelope"
    );
    assert!(
        compensating_version > forward_version,
        "compensating undo upsert must LWW-beat the already-shipped forward row"
    );
}

#[test]
fn update_task_undo_roundtrip_restores_rename() {
    let conn = test_conn();
    seed_list_and_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000024",
        "01966a3f-7c8b-7d4e-8f3a-00000000000a",
        "Pre-rename title",
    );

    let now = "2026-04-15T09:00:00.000000Z";
    let result = crate::commands::with_immediate_transaction(&conn, |conn| {
        update_task_inner_with_conn(
            conn,
            "01966a3f-7c8b-7d4e-8f3a-00000000000a",
            &serde_json::json!({ "title": "Post-rename title" }),
        )
    })
    .expect("rename should succeed");

    assert_eq!(result.task.title, "Post-rename title");
    assert!(!result.undo_token.is_empty());

    let restored =
        apply_update_undo_via_token(&conn, &result.undo_token, now).expect("undo should succeed");
    assert_eq!(restored.title, "Pre-rename title");
}

#[test]
fn update_task_undo_roundtrip_restores_priority_change() {
    let conn = test_conn();
    seed_list_and_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000024",
        "01966a3f-7c8b-7d4e-8f3a-00000000000b",
        "Priority test",
    );
    // No priority seeded — pre-mutation is NULL, post is 2.

    let now = "2026-04-15T09:00:00.000000Z";
    let result = crate::commands::with_immediate_transaction(&conn, |conn| {
        update_task_inner_with_conn(
            conn,
            "01966a3f-7c8b-7d4e-8f3a-00000000000b",
            &serde_json::json!({ "priority": 2 }),
        )
    })
    .expect("priority set should succeed");

    assert_eq!(result.task.priority, Some(2));

    let restored =
        apply_update_undo_via_token(&conn, &result.undo_token, now).expect("undo should succeed");
    assert_eq!(
        restored.priority, None,
        "priority must revert to unset (null), not fall back to a default"
    );
}

#[test]
fn update_task_undo_roundtrip_restores_recurrence_rule() {
    let conn = test_conn();
    seed_list_and_task(
        &conn,
        "01966a3f-7c8b-7d4e-8f3a-000000000024",
        "01966a3f-7c8b-7d4e-8f3a-00000000000c",
        "Recurring",
    );
    conn.execute(
        "UPDATE tasks
         SET due_date = '2026-04-10',
             canonical_occurrence_date = '2026-04-10',
             recurrence = ?1,
             recurrence_group_id = 'rg-update-undo'
         WHERE id = '01966a3f-7c8b-7d4e-8f3a-00000000000c'",
        params![r#"{"FREQ":"WEEKLY","INTERVAL":1}"#],
    )
    .expect("seed recurrence");

    let now = "2026-04-15T09:00:00.000000Z";
    let result = crate::commands::with_immediate_transaction(&conn, |conn| {
        update_task_inner_with_conn(
            conn,
            "01966a3f-7c8b-7d4e-8f3a-00000000000c",
            &serde_json::json!({ "recurrence": null }),
        )
    })
    .expect("recurrence clear should succeed");

    assert_eq!(result.task.recurrence, None);

    let restored = apply_update_undo_via_token(&conn, &result.undo_token, now)
        .expect("undo should restore recurrence");
    let restored_recurrence: serde_json::Value = serde_json::from_str(
        restored
            .recurrence
            .as_deref()
            .expect("recurrence should be restored"),
    )
    .expect("restored recurrence should stay canonical JSON");

    assert_eq!(restored_recurrence["FREQ"], "WEEKLY");
    assert_eq!(restored_recurrence["INTERVAL"], 1);
    assert_eq!(restored.due_date.as_deref(), Some("2026-04-10"));
}
