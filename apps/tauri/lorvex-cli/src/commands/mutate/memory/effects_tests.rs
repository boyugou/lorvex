use super::effects::*;
use lorvex_domain::naming::{ENTITY_MEMORY, ENTITY_MEMORY_REVISION, OP_DELETE};
use rusqlite::OptionalExtension;

#[test]
fn write_delete_and_restore_memory_syncs_revisions_and_changelog() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");

    let written = write_memory_with_conn(&mut conn, "preferences.tone", "cafe\u{202E} calm")
        .expect("write memory");
    assert_eq!(written.key, "preferences.tone");
    assert_eq!(written.content, "cafe calm");
    assert_eq!(written.operation, "create");

    let stored: String = conn
        .query_row(
            "SELECT content FROM memories WHERE key = 'preferences.tone'",
            [],
            |row| row.get(0),
        )
        .expect("load memory");
    assert_eq!(stored, "cafe calm");

    let memory_outbox: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1 AND entity_id = ?2",
            [ENTITY_MEMORY, "preferences.tone"],
            |row| row.get(0),
        )
        .expect("count memory outbox");
    assert_eq!(memory_outbox, 1);

    let revision_outbox: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM sync_outbox WHERE entity_type = ?1",
            [ENTITY_MEMORY_REVISION],
            |row| row.get(0),
        )
        .expect("count revision outbox");
    assert_eq!(revision_outbox, 1);

    let deleted = delete_memory_with_conn(&mut conn, "preferences.tone").expect("delete memory");
    assert!(deleted.deleted);
    assert!(deleted.revision_id.is_some());
    assert_eq!(deleted.before_content.as_deref(), Some("cafe calm"));

    let delete_payload_raw: String = conn
        .query_row(
            "SELECT payload FROM sync_outbox
             WHERE entity_type = ?1
               AND entity_id = ?2
               AND operation = ?3
             ORDER BY id DESC LIMIT 1",
            rusqlite::params![ENTITY_MEMORY, "preferences.tone", OP_DELETE],
            |row| row.get(0),
        )
        .expect("memory delete outbox payload");
    let delete_payload: serde_json::Value =
        serde_json::from_str(&delete_payload_raw).expect("parse memory delete outbox payload");
    assert_eq!(delete_payload["key"], "preferences.tone");
    assert_eq!(delete_payload["content"], "cafe calm");
    assert_eq!(delete_payload["version"], written.version);
    assert_eq!(delete_payload["updated_at"], written.updated_at);

    let missing_after_delete: Option<String> = conn
        .query_row(
            "SELECT content FROM memories WHERE key = 'preferences.tone'",
            [],
            |row| row.get(0),
        )
        .optional()
        .expect("load deleted memory");
    assert!(missing_after_delete.is_none());

    let restored =
        restore_memory_with_conn(&mut conn, &written.revision_id).expect("restore memory");
    assert_eq!(restored.key, "preferences.tone");
    assert_eq!(restored.from_revision_id, written.revision_id);

    let restored_content: String = conn
        .query_row(
            "SELECT content FROM memories WHERE key = 'preferences.tone'",
            [],
            |row| row.get(0),
        )
        .expect("load restored memory");
    assert_eq!(restored_content, "cafe calm");

    // create + delete + restore (update) = 3 user ops; the delete's outbox row
    // is coalesced away when restore re-asserts the memory in the same
    // transaction, which logs an additional `sync.outbox.coalesced_delete_dropped`
    // diagnostic entry — 4 rows total.
    let user_op_count: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM ai_changelog
             WHERE entity_type = ?1 AND entity_id = ?2
               AND operation IN ('create', 'update', 'delete')",
            [ENTITY_MEMORY, "preferences.tone"],
            |row| row.get(0),
        )
        .expect("count user-op changelog");
    assert_eq!(user_op_count, 3);
}

#[test]
fn memory_mutations_reject_human_owned_key() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");

    let error = write_memory_with_conn(&mut conn, "notes_for_ai", "do not write")
        .expect_err("human-owned key should fail");
    assert!(error.to_string().contains("human-owned"));
}

/// `enqueue_memory_revision_upsert` must
/// mint a fresh HLC for the outbox envelope's transport version
/// rather than reusing the revision row's stored `version`.
/// (payload `version` field) and the outbox coalescing axis
/// (`OutboxWriteContext.version`), so a CLI invocation that
/// re-enqueued the same revision_id (after a partial transport
/// failure) collided on version and the outbox dropped the
/// retry as a duplicate.
#[test]
fn memory_revision_outbox_version_advances_on_repeated_enqueue() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    // each call to
    // `enqueue_memory_revision_upsert` must mint a FRESH HLC
    // for the outbox envelope rather than reusing the revision
    // row's stored version.
    // reused for every retry, so a second enqueue would land
    // at the SAME outbox version and coalesce-by-version
    // silently dropped the retry as a duplicate. Post-fix
    // the second enqueue produces a strictly-greater envelope
    // version and correctly replaces the prior row.
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    let written =
        write_memory_with_conn(&mut conn, "preferences.style", "concise").expect("write memory");
    let device_id = lorvex_runtime::get_or_create_device_id(&conn).expect("device id");

    let outbox_version_first: String = conn
        .query_row(
            "SELECT version FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2
             ORDER BY id DESC LIMIT 1",
            rusqlite::params![ENTITY_MEMORY_REVISION, &written.revision_id],
            |row| row.get(0),
        )
        .expect("read first envelope version");

    // Re-enqueue the same revision id (simulating a retry after
    // a partial transport failure). With CL-H12 the second
    // enqueue mints a strictly-newer envelope version.
    let mut hlc_guard = crate::hlc_guard::lock_shared(&conn).expect("lock HLC for retry enqueue");
    super::effects::enqueue_memory_revision_upsert(
        &conn,
        &mut hlc_guard,
        &device_id,
        &written.revision_id,
    )
    .expect("re-enqueue revision");
    drop(hlc_guard);
    let outbox_version_second: String = conn
        .query_row(
            "SELECT version FROM sync_outbox
             WHERE entity_type = ?1 AND entity_id = ?2
             ORDER BY id DESC LIMIT 1",
            rusqlite::params![ENTITY_MEMORY_REVISION, &written.revision_id],
            |row| row.get(0),
        )
        .expect("read second envelope version");
    assert!(
        outbox_version_second > outbox_version_first,
        "second enqueue must produce a strictly-newer envelope version; \
         first={outbox_version_first}, second={outbox_version_second}"
    );
}

/// `validate_memory_key` must
/// sanitize-then-trim before length / human-owned checks. A key
/// containing bidi overrides, ZWSP, or surrounding whitespace
/// must persist as the cleaned form so the DB row matches what
/// consumers see in the assistant UI.
/// checked emptiness/length on the raw input, so visually-similar
/// keys (e.g. `preferences.tone` vs `preferences.tone\u{200b}`)
/// reached the DB as distinct rows.
#[test]
fn write_memory_persists_sanitized_key_not_raw_input() {
    let _hlc = crate::commands::shared::test_support::acquire_hlc_test_state();
    let mut conn = lorvex_store::open_db_in_memory().expect("open in-memory db");
    // Bidi override + ZWSP + surrounding whitespace.
    let raw_key = "  preferences.\u{202E}\u{200B}tone  ";
    let result =
        write_memory_with_conn(&mut conn, raw_key, "calm").expect("write with tainted key");
    // The persisted key must be the cleaned form, not the raw
    // input — otherwise the DB row drifts from the consumer view.
    assert_eq!(result.key, "preferences.tone");
    let exists: bool = conn
        .query_row(
            "SELECT 1 FROM memories WHERE key = 'preferences.tone'",
            [],
            |_row| Ok(true),
        )
        .unwrap_or(false);
    assert!(
        exists,
        "sanitized key must land in DB; got result={result:?}"
    );
    let raw_exists: bool = conn
        .query_row(
            "SELECT 1 FROM memories WHERE key = ?1",
            rusqlite::params![raw_key],
            |_row| Ok(true),
        )
        .unwrap_or(false);
    assert!(!raw_exists, "raw bidi-tainted key must NOT land in DB");
}
