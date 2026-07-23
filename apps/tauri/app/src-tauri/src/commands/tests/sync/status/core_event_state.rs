use super::*;

fn create_sync_outbox_test_db() -> Connection {
    let conn = Connection::open_in_memory().expect("open in-memory db");
    conn.execute_batch(
        "CREATE TABLE sync_outbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            operation TEXT NOT NULL,
            version TEXT NOT NULL,
            payload_schema_version INTEGER NOT NULL,
            payload TEXT NOT NULL,
            device_id TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
            synced_at TEXT,
            retry_count INTEGER NOT NULL DEFAULT 0,
            last_retry_at TEXT,
            last_error TEXT
        ) STRICT;
        CREATE TABLE sync_checkpoints (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );",
    )
    .expect("create sync_outbox + sync_checkpoints");
    conn
}

#[test]
fn mark_sync_retry_keeps_original_created_at() {
    let conn = create_sync_outbox_test_db();

    let original_created_at = "2026-03-01T08:00:00Z";
    conn.execute(
        "INSERT INTO sync_outbox (
            entity_type, entity_id, operation, version, payload_schema_version, payload, device_id, created_at, synced_at, retry_count
         ) VALUES ('task', 'task-1', 'upsert', '0000000000000_0000_a0a0a0a0a0a0a0a0', 1, '{}', 'device-a', ?1, NULL, 0)",
        params![original_created_at],
    )
    .expect("insert pending outbox entry");

    // Get the auto-generated id as string.
    let entry_id: i64 = conn
        .query_row("SELECT id FROM sync_outbox LIMIT 1", [], |row| row.get(0))
        .expect("get entry id");
    let entry_id_str = entry_id.to_string();

    let now = "2026-03-02T09:30:00Z";
    mark_outbox_entry_retry_internal(&conn, &entry_id_str, "network timeout", now)
        .expect("mark retry");

    let (retry_count, created_at): (i64, String) = conn
        .query_row(
            "SELECT retry_count, created_at FROM sync_outbox WHERE id = ?1",
            params![entry_id],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .expect("read updated entry");
    assert_eq!(retry_count, 1);
    assert_eq!(created_at, original_created_at);

    let last_error: String = conn
        .query_row(
            "SELECT value FROM sync_checkpoints WHERE key = 'last_error'",
            [],
            |row| row.get(0),
        )
        .expect("read last_error");
    assert!(last_error.contains(now));
    assert!(last_error.contains("network timeout"));
}

#[test]
fn mark_outbox_entries_synced_is_idempotent_and_clears_last_error() {
    let conn = create_sync_outbox_test_db();

    conn.execute(
        "INSERT INTO sync_outbox (
            entity_type, entity_id, operation, version, payload_schema_version, payload, device_id, created_at, synced_at, retry_count
        ) VALUES (
            'task', 'task-1', 'upsert', '0000000000000_0000_a0a0a0a0a0a0a0a0', 1, '{}', 'device-a', '2026-03-02T08:00:00Z', NULL, 0
        )",
        [],
    )
    .expect("insert outbox entry");

    let entry_id: i64 = conn
        .query_row("SELECT id FROM sync_outbox LIMIT 1", [], |row| row.get(0))
        .expect("get entry id");
    let entry_id_str = entry_id.to_string();

    mark_outbox_entry_retry_internal(
        &conn,
        &entry_id_str,
        "network timeout",
        "2026-03-02T08:30:00Z",
    )
    .expect("mark retry");

    let changed = mark_outbox_entries_synced_internal(
        &conn,
        std::slice::from_ref(&entry_id_str),
        "2026-03-02T09:00:00Z",
    )
    .expect("mark synced");
    assert_eq!(changed, 1);

    let synced_at: Option<String> = conn
        .query_row(
            "SELECT synced_at FROM sync_outbox WHERE id = ?1",
            params![entry_id],
            |row| row.get(0),
        )
        .expect("read synced_at");
    assert_eq!(synced_at, Some("2026-03-02T09:00:00Z".to_string()));

    let row_last_error: Option<String> = conn
        .query_row(
            "SELECT last_error FROM sync_outbox WHERE id = ?1",
            params![entry_id],
            |row| row.get(0),
        )
        .expect("read row last_error");
    assert_eq!(row_last_error, None);

    let last_success: String = conn
        .query_row(
            "SELECT value FROM sync_checkpoints WHERE key = 'last_success_at'",
            [],
            |row| row.get(0),
        )
        .expect("read last_success_at");
    assert_eq!(last_success, "2026-03-02T09:00:00Z");

    let last_error: Option<String> = conn
        .query_row(
            "SELECT value FROM sync_checkpoints WHERE key = 'last_error'",
            [],
            |row| row.get(0),
        )
        .optional()
        .expect("query last_error");
    assert_eq!(last_error, None);

    let changed_again =
        mark_outbox_entries_synced_internal(&conn, &[entry_id_str], "2026-03-02T09:05:00Z")
            .expect("second mark synced");
    assert_eq!(changed_again, 0);
}

#[test]
fn mark_outbox_entries_synced_rejects_invalid_ids() {
    let conn = create_sync_outbox_test_db();

    let error = mark_outbox_entries_synced_internal(
        &conn,
        &["abc".to_string(), "42".to_string()],
        "2026-03-02T09:00:00Z",
    )
    .expect_err("invalid ids should be rejected");

    assert!(error
        .to_string()
        .contains("Invalid outbox entry id at index 0: abc"));
}
