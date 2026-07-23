//! Tests for `memory`. Extracted from the parent file
//! to keep the production module focused.

use super::crud::{
    create_memory_entry_with_conn, delete_ai_memory_entry_with_conn, delete_notes_for_ai_with_conn,
    restore_memory_revision_with_conn, set_notes_for_ai_with_conn, MAX_HUMAN_MEMORY_KEY_LENGTH,
};
use crate::test_support::test_conn;
use lorvex_domain::memory::MEMORY_KEY_NOTES_FOR_AI;
use lorvex_domain::naming::{ENTITY_MEMORY, ENTITY_MEMORY_REVISION, OP_DELETE, OP_UPSERT};

fn setup() -> rusqlite::Connection {
    test_conn()
}

fn load_outbox_payloads(conn: &rusqlite::Connection) -> Vec<(String, String, serde_json::Value)> {
    let mut stmt = conn
        .prepare(
            "SELECT entity_type, operation, payload
             FROM sync_outbox
             ORDER BY id",
        )
        .expect("prepare sync_outbox payload query");

    stmt.query_map([], |row| {
        let payload: String = row.get(2)?;
        let parsed = serde_json::from_str::<serde_json::Value>(&payload)
            .expect("sync_outbox payload should be valid json");
        Ok((row.get(0)?, row.get(1)?, parsed))
    })
    .expect("query sync_outbox payload rows")
    .collect::<Result<Vec<_>, _>>()
    .expect("collect sync_outbox payload rows")
}

#[test]
fn set_notes_for_ai_with_conn_enqueues_memory_and_revision_snapshots() {
    let conn = setup();

    set_notes_for_ai_with_conn(&conn, "remember this forever").expect("set notes_for_ai");

    let payloads = load_outbox_payloads(&conn);
    assert_eq!(payloads.len(), 2);

    let memory_payload = payloads
        .iter()
        .find(|(entity_type, _, _)| entity_type == ENTITY_MEMORY)
        .expect("memory entity payload should exist");
    assert_eq!(memory_payload.1, OP_UPSERT);
    assert_eq!(memory_payload.2["key"], MEMORY_KEY_NOTES_FOR_AI);
    assert_eq!(memory_payload.2["content"], "remember this forever");

    let revision_payload = payloads
        .iter()
        .find(|(entity_type, _, _)| entity_type == ENTITY_MEMORY_REVISION)
        .expect("memory revision payload should exist");
    assert_eq!(revision_payload.1, OP_UPSERT);
    assert_eq!(revision_payload.2["memory_key"], MEMORY_KEY_NOTES_FOR_AI);
    assert_eq!(revision_payload.2["operation"], "upsert");
    assert_eq!(revision_payload.2["actor"], "human");
    assert_eq!(revision_payload.2["content"], "remember this forever");
}

#[test]
fn delete_ai_memory_entry_with_conn_rejects_human_owned_key() {
    let conn = setup();

    let error = delete_ai_memory_entry_with_conn(&conn, MEMORY_KEY_NOTES_FOR_AI)
        .expect_err("human-owned notes key should be rejected");

    let message = error.to_string();
    assert!(
        message.contains("delete_notes_for_ai"),
        "unexpected error: {message}"
    );
}

#[test]
fn delete_ai_memory_entry_with_conn_enqueues_full_pre_delete_payload() {
    let conn = setup();
    lorvex_workflow::memory_ops::upsert_memory_entry(
        &conn,
        "behavioral_patterns",
        "prefers quiet focus blocks",
        "ai",
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
        "2026-03-29T10:00:00Z",
    )
    .expect("seed memory")
    .expect("seed upsert must report Some");

    let result = delete_ai_memory_entry_with_conn(&conn, "behavioral_patterns")
        .expect("delete seeded AI memory");
    assert!(result.deleted);

    let payloads = load_outbox_payloads(&conn);
    let memory_delete = payloads
        .iter()
        .find(|(entity_type, operation, _)| entity_type == ENTITY_MEMORY && operation == OP_DELETE)
        .expect("memory delete tombstone should exist");
    assert_eq!(memory_delete.2["key"], "behavioral_patterns");
    assert_eq!(memory_delete.2["content"], "prefers quiet focus blocks");
    assert_eq!(
        memory_delete.2["version"],
        "0000000000000_0000_a0a0a0a0a0a0a0a0"
    );
    assert_eq!(memory_delete.2["updated_at"], "2026-03-29T10:00:00Z");
}

#[test]
fn delete_notes_for_ai_with_conn_enqueues_full_pre_delete_payload() {
    let conn = setup();
    lorvex_workflow::memory_ops::upsert_memory_entry(
        &conn,
        MEMORY_KEY_NOTES_FOR_AI,
        "human note before delete",
        "human",
        "0000000000000_0000_a0a0a0a0a0a0a0a0",
        "2026-03-29T10:00:00Z",
    )
    .expect("seed notes_for_ai")
    .expect("seed upsert must report Some");

    let result = delete_notes_for_ai_with_conn(&conn).expect("delete notes_for_ai");
    assert!(result.deleted);

    let payloads = load_outbox_payloads(&conn);
    let memory_delete = payloads
        .iter()
        .find(|(entity_type, operation, _)| entity_type == ENTITY_MEMORY && operation == OP_DELETE)
        .expect("notes_for_ai delete tombstone should exist");
    assert_eq!(memory_delete.2["key"], MEMORY_KEY_NOTES_FOR_AI);
    assert_eq!(memory_delete.2["content"], "human note before delete");
    assert_eq!(
        memory_delete.2["version"],
        "0000000000000_0000_a0a0a0a0a0a0a0a0"
    );
    assert_eq!(memory_delete.2["updated_at"], "2026-03-29T10:00:00Z");
}

#[test]
fn restore_memory_revision_with_conn_enqueues_restored_snapshots() {
    let conn = setup();
    let created = lorvex_workflow::memory_ops::upsert_memory_entry(
        &conn,
        "behavioral_patterns",
        "original",
        "ai",
        "v1",
        "2026-03-29T10:00:00Z",
    )
    .expect("seed memory revision")
    .expect("seed upsert must report Some");
    lorvex_workflow::memory_ops::delete_memory_entry(
        &conn,
        "behavioral_patterns",
        "ai",
        "v2",
        "2026-03-29T10:05:00Z",
    )
    .expect("delete seeded memory")
    .expect("delete revision should be returned");

    restore_memory_revision_with_conn(&conn, &created.revision_id)
        .expect("restore seeded memory revision");

    let payloads = load_outbox_payloads(&conn);
    assert_eq!(payloads.len(), 2);

    let memory_payload = payloads
        .iter()
        .find(|(entity_type, _, _)| entity_type == ENTITY_MEMORY)
        .expect("memory restore payload should exist");
    assert_eq!(memory_payload.2["key"], "behavioral_patterns");
    assert_eq!(memory_payload.2["content"], "original");

    let revision_payload = payloads
        .iter()
        .find(|(entity_type, _, _)| entity_type == ENTITY_MEMORY_REVISION)
        .expect("revision restore payload should exist");
    assert_eq!(revision_payload.2["memory_key"], "behavioral_patterns");
    assert_eq!(revision_payload.2["operation"], "restore");
    assert_eq!(
        revision_payload.2["source_revision_id"],
        created.revision_id
    );
    assert_eq!(revision_payload.2["actor"], "human");
}

// ── create_memory_entry_with_conn (#2415) ──────────────────────

#[test]
fn create_memory_entry_with_conn_writes_human_owned_row_and_snapshots() {
    let conn = setup();

    create_memory_entry_with_conn(&conn, "work_hours", "9-5 Pacific")
        .expect("create user-seeded memory entry");

    // Row exists with the requested content.
    let (content, _version, _updated_at): (String, String, String) = conn
        .query_row(
            "SELECT content, version, updated_at FROM memories WHERE key = 'work_hours'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("row must be present after create");
    assert_eq!(content, "9-5 Pacific");

    // Revision is attributed to the human.
    let actor: String = conn
        .query_row(
            "SELECT actor FROM memory_revisions WHERE memory_key = 'work_hours' \
             ORDER BY created_at DESC LIMIT 1",
            [],
            |row| row.get(0),
        )
        .expect("revision must be present");
    assert_eq!(actor, "human");

    // Outbox holds memory upsert + revision snapshot.
    let payloads = load_outbox_payloads(&conn);
    assert_eq!(payloads.len(), 2);
    assert!(payloads
        .iter()
        .any(|(entity, op, _)| entity == ENTITY_MEMORY && op == OP_UPSERT));
    assert!(payloads
        .iter()
        .any(|(entity, op, _)| entity == ENTITY_MEMORY_REVISION && op == OP_UPSERT));
}

#[test]
fn create_memory_entry_with_conn_roundtrips_through_get_ai_memory_query() {
    let conn = setup();

    create_memory_entry_with_conn(&conn, "dislikes", "morning meetings").expect("seed user memory");

    // Same shape as the get_ai_memory Tauri command, including the
    // ownership derivation via the latest revision's actor.
    let (key, content, latest_actor): (String, String, Option<String>) = conn
        .query_row(
            "SELECT m.key, m.content, ( \
                SELECT r.actor FROM memory_revisions r \
                WHERE r.memory_key = m.key AND r.operation != 'delete' \
                ORDER BY r.created_at DESC, r.id DESC LIMIT 1 \
             ) FROM memories m WHERE m.key = 'dislikes'",
            [],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
        )
        .expect("round-trip read");
    assert_eq!(key, "dislikes");
    assert_eq!(content, "morning meetings");
    assert_eq!(latest_actor.as_deref(), Some("human"));
}

#[test]
fn create_memory_entry_with_conn_rejects_duplicate_key() {
    let conn = setup();

    create_memory_entry_with_conn(&conn, "pets", "two cats").expect("initial create");
    let err = create_memory_entry_with_conn(&conn, "pets", "also a dog")
        .expect_err("duplicate create must fail");
    assert!(
        err.to_string().contains("already exists"),
        "unexpected error: {err}"
    );
}

#[test]
fn create_memory_entry_with_conn_rejects_reserved_human_key() {
    let conn = setup();

    let err = create_memory_entry_with_conn(&conn, MEMORY_KEY_NOTES_FOR_AI, "hi")
        .expect_err("reserved notes_for_ai key must be rejected");
    assert!(
        err.to_string().contains("set_notes_for_ai"),
        "unexpected error: {err}"
    );
}

#[test]
fn create_memory_entry_with_conn_rejects_invalid_keys() {
    let conn = setup();

    for bad in [
        "",
        " leading_space",
        "trailing_space ",
        "bad key with spaces",
        "slash/key",
        "weird$char",
    ] {
        let err = create_memory_entry_with_conn(&conn, bad, "content")
            .expect_err("invalid key must be rejected");
        let msg = err.to_string();
        assert!(
            msg.contains("Memory key"),
            "unexpected error for {bad:?}: {msg}"
        );
    }

    // Length cap at MAX_HUMAN_MEMORY_KEY_LENGTH chars.
    let long = "a".repeat(MAX_HUMAN_MEMORY_KEY_LENGTH + 1);
    let err = create_memory_entry_with_conn(&conn, &long, "content")
        .expect_err("oversize key must be rejected");
    assert!(err.to_string().contains("maximum length"));
}
