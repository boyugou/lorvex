pub(super) use rusqlite::{params, Connection};
pub(super) use std::sync::{Arc, Barrier};
pub(super) use std::thread;

pub(super) use lorvex_domain::naming;
pub(super) use lorvex_store::{open_db_at_path, open_db_in_memory};
pub(super) use lorvex_sync::apply::{apply_envelope, ApplyResult};
pub(super) use lorvex_sync::envelope::{SyncEnvelope, SyncOperation};
pub(super) use lorvex_sync::tombstone::{create_tombstone, get_tombstone};

pub(super) fn test_db() -> Connection {
    // the merge sites in apply::aggregate::recurrence
    // and apply::tag debug_assert! that a production observer is
    // installed (forgotten wire-up should fail loudly in dev). Unit
    // tests inside the lib crate are cfg(test)-gated past the assert
    // and route through the TEST_OBSERVER slot, but integration test
    // crates compile the lib WITHOUT cfg(test), so we wire a no-op
    // observer once at the first test_db() construction. The
    // OnceLock makes the call idempotent across every test in the
    // file.
    let _ = lorvex_sync::hlc::install_noop_observer_for_tests();
    let conn = open_db_in_memory().expect("failed to open in-memory test DB");
    // `apply_envelope` debug_asserts that it runs
    // inside an outer transaction (the `with_immediate_transaction`
    // wrapper holds the line in production). Mirror the unit-test
    // helper in `lorvex-sync::test_db` and open a transaction at
    // construction time so integration tests don't trip the assert.
    conn.execute_batch("BEGIN IMMEDIATE")
        .expect("test_db: BEGIN IMMEDIATE must succeed on a fresh connection");
    conn
}

/// Build an upsert envelope.
pub(super) fn upsert_envelope(
    entity_type: &str,
    entity_id: &str,
    version: &str,
    payload: &str,
) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::parse(entity_type)
            .expect("test entity_type must be a known EntityKind"),
        entity_id: entity_id.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse(version)
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: 1,
        payload: payload.to_string(),
        device_id: "device-001".to_string(),
    }
}

/// Build a delete envelope.
pub(super) fn delete_envelope(entity_type: &str, entity_id: &str, version: &str) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::parse(entity_type)
            .expect("test entity_type must be a known EntityKind"),
        entity_id: entity_id.to_string(),
        operation: SyncOperation::Delete,
        version: lorvex_domain::hlc::Hlc::parse(version)
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: 1,
        payload: "{}".to_string(),
        device_id: "device-001".to_string(),
    }
}

/// Insert a prerequisite list row so tasks can reference it.
pub(super) fn seed_list(conn: &Connection, list_id: &str) {
    lorvex_store::test_support::ListBuilder::new(list_id)
        .name("Test List")
        .insert(conn);
}

/// Insert a prerequisite task row so edges/children can reference it.
///
/// delegates to the shared
/// [`lorvex_store::test_support::TaskBuilder`] so a column added to the
/// `tasks` table doesn't ripple through every integration test that
/// reused this helper. The `version` / timestamp defaults match the
/// pre-existing inline literal byte-for-byte.
pub(super) fn seed_task(conn: &Connection, task_id: &str) {
    lorvex_store::test_support::TaskBuilder::new(task_id).insert(conn);
}

/// Insert a prerequisite tag row.
pub(super) fn seed_tag(conn: &Connection, tag_id: &str, name: &str, lookup_key: &str) {
    conn.execute(
        "INSERT INTO tags (id, display_name, lookup_key, version, created_at, updated_at)
         VALUES (?1, ?2, ?3, '0000000000000_0000_0000000000000000', '2026-03-20T00:00:00.000Z', '2026-03-20T00:00:00.000Z')",
        params![tag_id, name, lookup_key],
    )
    .unwrap();
}

/// Count rows matching a simple condition.
pub(super) fn count_rows(conn: &Connection, table: &str, where_clause: &str) -> i64 {
    let sql = if where_clause.is_empty() {
        format!("SELECT COUNT(*) FROM {table}")
    } else {
        format!("SELECT COUNT(*) FROM {table} WHERE {where_clause}")
    };
    conn.query_row(&sql, [], |row| row.get(0)).unwrap()
}

// HLC versions used across tests. Higher physical_ms = newer.
pub(super) const V1: &str = "1711234567000_0000_a1b2c3d4a1b2c3d4"; // oldest
pub(super) const V2: &str = "1711234568000_0000_a1b2c3d4a1b2c3d4"; // middle
pub(super) const V3: &str = "1711234569000_0000_a1b2c3d4a1b2c3d4"; // newest

pub(super) fn mk_task_envelope(
    entity_id: &str,
    title: &str,
    version: &str,
    device_id: &str,
) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::Task,
        entity_id: entity_id.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse(version)
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: 1,
        payload: serde_json::json!({
            "title": title,
            "status": "open",
            "defer_count": 0,
            "list_id": lorvex_store::INBOX_LIST_ID,
            "created_at": "2026-04-19T00:00:00.000Z",
            "updated_at": "2026-04-19T00:00:00.000Z",
        })
        .to_string(),
        device_id: device_id.to_string(),
    }
}
