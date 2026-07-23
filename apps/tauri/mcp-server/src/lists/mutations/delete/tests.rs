use super::*;
use crate::contract::DeleteListArgs;
use crate::db::open_database_for_path;
use rusqlite::params;
use tempfile::tempdir;

/// Open a fresh DB (schema already seeds the canonical `inbox` list)
/// and add one additional list so delete_list's "last list" guard
/// does not trip when removing `01966a3f-7c8b-7d4e-8f3a-000000000301`.
fn open_temp_db_with_two_lists() -> Connection {
    let dir = tempdir().expect("create temp dir");
    let db_path = dir.path().join("db.sqlite");
    let conn = open_database_for_path(&db_path).expect("open temp db");
    let _leaked = Box::leak(Box::new(dir));
    let now = "2026-04-18T09:00:00.000000Z";
    let ver = "0000000000000_0000_a0a0a0a0a0a0a0a0";
    conn.execute(
        "INSERT INTO lists (id, name, version, created_at, updated_at) \
         VALUES ('01966a3f-7c8b-7d4e-8f3a-000000000301', 'Drop', ?1, ?2, ?2)",
        params![ver, now],
    )
    .unwrap();
    conn
}

// delete_list returns an undo_token whose JSON contains the
// pre-delete list row so a reverse write can re-insert it.
#[test]
#[serial_test::serial(hlc)]
fn delete_list_returns_undo_token_with_pre_snapshot() {
    let conn = open_temp_db_with_two_lists();

    let payload = delete_list(
        &conn,
        DeleteListArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-000000000301".to_string(),
            dry_run: false,
            idempotency_key: None,
        },
    )
    .expect("delete_list should succeed");
    let value: serde_json::Value = serde_json::from_str(&payload).unwrap();

    let undo_raw = value["undo_token"].as_str().expect("undo_token present");
    let token: crate::runtime::undo::McpUndoToken =
        serde_json::from_str(undo_raw).expect("token parses");
    assert_eq!(token.kind, crate::runtime::undo::McpUndoKind::DeleteList);
    assert_eq!(
        token.entity_id.as_deref(),
        Some("01966a3f-7c8b-7d4e-8f3a-000000000301")
    );
    assert_eq!(
        token.pre_entity_json.as_ref().and_then(|v| v.get("name")),
        Some(&serde_json::json!("Drop"))
    );
}

// The outbox DELETE envelope for the list is enqueued plain
// (immediately dispatchable), and `ai_changelog.undo_token` persists
// the serialized token for a restart-safe reverse-write lookup.
#[test]
#[serial_test::serial(hlc)]
fn delete_list_enqueues_plain_envelope_and_persists_undo_token() {
    let conn = open_temp_db_with_two_lists();

    let payload = delete_list(
        &conn,
        DeleteListArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-000000000301".to_string(),
            dry_run: false,
            idempotency_key: None,
        },
    )
    .expect("delete_list should succeed");
    let value: serde_json::Value = serde_json::from_str(&payload).unwrap();
    assert!(
        value["undo_token"].as_str().is_some(),
        "response must carry undo_token"
    );

    let envelope_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox \
             WHERE entity_type = 'list' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000301' AND operation = 'delete'",
            [],
            |row| row.get(0),
        )
        .expect("list delete envelope must exist");
    assert_eq!(
        envelope_count, 1,
        "list delete must enqueue exactly one outbox envelope"
    );

    // ai_changelog row also persists the token so a restart-safe
    // lookup from the Tauri side (via get_changelog) can surface it.
    let persisted: Option<String> = conn
        .query_row(
            "SELECT undo_token FROM ai_changelog WHERE entity_type = 'list' AND entity_id = '01966a3f-7c8b-7d4e-8f3a-000000000301'",
            [],
            |row| row.get(0),
        )
        .expect("ai_changelog row must exist");
    assert!(
        persisted.is_some(),
        "ai_changelog.undo_token must be populated"
    );
}

#[test]
#[serial_test::serial(hlc)]
fn delete_list_rejects_cancelled_tasks_still_assigned() {
    let conn = open_temp_db_with_two_lists();
    // lift to canonical TaskBuilder.
    lorvex_store::test_support::fixtures::TaskBuilder::new("task-cancelled")
        .title("Cancelled task")
        .status("cancelled")
        .version("0000000000000_0000_a0a0a0a0a0a0a0a0")
        .created_at("2026-04-18T09:00:00.000000Z")
        .list_id(Some("01966a3f-7c8b-7d4e-8f3a-000000000301"))
        .insert(&conn);

    let err = delete_list(
        &conn,
        DeleteListArgs {
            id: "01966a3f-7c8b-7d4e-8f3a-000000000301".to_string(),
            dry_run: false,
            idempotency_key: None,
        },
    )
    .expect_err("cancelled tasks should still block delete_list");

    match err {
        McpError::Validation(message) => {
            assert!(message.contains("1 task(s) are still assigned"));
        }
        other => panic!("expected validation error, got {other:?}"),
    }
}
