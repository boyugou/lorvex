use rusqlite::Connection;

pub(super) fn setup_sync_status_test_conn() -> Connection {
    let conn = Connection::open_in_memory().expect("open in-memory db");
    conn.execute_batch(
        "
        CREATE TABLE sync_outbox (
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
            value TEXT
        );
        CREATE TABLE sync_pending_inbox (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            envelope TEXT NOT NULL,
            reason TEXT NOT NULL,
            missing_entity_type TEXT NOT NULL,
            missing_entity_id TEXT NOT NULL,
            first_attempted_at TEXT NOT NULL,
            last_attempted_at TEXT NOT NULL,
            attempt_count INTEGER NOT NULL
        ) STRICT;
        CREATE TABLE sync_tombstones (
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            version TEXT NOT NULL,
            deleted_at TEXT NOT NULL,
            redirect_entity_id TEXT,
            redirect_entity_type TEXT
        ) STRICT;
        CREATE TABLE sync_conflict_log (
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            winner_version TEXT NOT NULL,
            loser_version TEXT NOT NULL,
            loser_device_id TEXT NOT NULL,
            loser_payload TEXT,
            resolved_at TEXT NOT NULL,
            resolution_type TEXT NOT NULL
        ) STRICT;
        CREATE TABLE calendar_subscriptions (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            url TEXT NOT NULL,
            color TEXT,
            enabled INTEGER NOT NULL DEFAULT 1,
            version TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        ) STRICT;
        CREATE TABLE provider_scope_runtime_state (
            provider_kind TEXT NOT NULL,
            provider_scope TEXT NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1,
            availability_state TEXT NOT NULL DEFAULT 'enabled',
            last_refresh_attempt_at TEXT,
            last_refresh_success_at TEXT,
            last_refresh_result TEXT,
            last_error TEXT,
            next_attempt_at TEXT,
            PRIMARY KEY (provider_kind, provider_scope)
        ) STRICT;
        CREATE TABLE preferences (
            key TEXT PRIMARY KEY,
            value TEXT
        );
        ",
    )
    .expect("create minimal sync schema");
    conn
}
