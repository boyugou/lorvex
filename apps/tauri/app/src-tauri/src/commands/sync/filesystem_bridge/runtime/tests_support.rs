//! Shared fixtures for the runtime test siblings.
//!
//! `commands/` depth is held at ≤3 by collapsing the runtime tests
//! into flat `tests_*` siblings under `runtime/`. Shared helpers
//! live here as `pub(super)` items so the `tests_*.rs` siblings can
//! pull them in via `use super::tests_support::*`.

pub(super) use super::*;
pub(super) use crate::test_support::test_conn;
pub(super) use lorvex_sync::envelope::{SyncEnvelope, SyncOperation};

pub(super) fn setup_runtime_test_conn() -> rusqlite::Connection {
    test_conn()
}

pub(super) fn outbox_entry_fixture(
    retry_count: i64,
    last_retry_at: Option<&str>,
) -> outbox::OutboxEntry {
    outbox::OutboxEntry {
        id: 1,
        envelope: SyncEnvelope {
            entity_type: lorvex_domain::naming::EntityKind::Task,
            entity_id: "task-backoff".to_string(),
            operation: SyncOperation::Upsert,
            version: lorvex_domain::hlc::Hlc::parse("1774807200000_0000_6465766963656162")
                .expect("test fixture HLC"),
            payload_schema_version: 1,
            payload: "{}".to_string(),
            device_id: "device-backoff".to_string(),
        },
        created_at: "2026-03-29T18:00:00Z".to_string(),
        synced_at: None,
        retry_count,
        last_retry_at: last_retry_at.map(str::to_string),
    }
}
