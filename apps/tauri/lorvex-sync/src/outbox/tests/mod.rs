//! Tests for sync::outbox, split by outbox behavior family.

use super::query::decode_sync_operation;
use super::*;
use crate::envelope::{SyncEnvelope, SyncOperation};
use crate::test_db;
use rusqlite::params;

fn make_envelope(entity_type: &str, entity_id: &str, version: &str) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::parse(entity_type)
            .expect("test entity_type must be a known EntityKind"),
        entity_id: entity_id.to_string(),
        operation: SyncOperation::Upsert,
        // typed `version: Hlc` at the wire boundary. Test
        // fixtures must supply canonical HLC strings — non-canonical
        // inputs now fail at construction, mirroring how serde rejects
        // them on deserialize.
        version: lorvex_domain::hlc::Hlc::parse(version)
            .expect("test fixture version must parse as a canonical HLC"),
        payload_schema_version: 1,
        payload: r#"{"title":"test"}"#.to_string(),
        device_id: "device-001".to_string(),
    }
}

fn make_delete_envelope(entity_type: &str, entity_id: &str, version: &str) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::parse(entity_type)
            .expect("test entity_type must be a known EntityKind"),
        entity_id: entity_id.to_string(),
        operation: SyncOperation::Delete,
        version: lorvex_domain::hlc::Hlc::parse(version)
            .expect("test fixture version must parse as a canonical HLC"),
        payload_schema_version: 1,
        payload: "{}".to_string(),
        device_id: "device-001".to_string(),
    }
}

mod coalesce;
mod coalesce_undo_chain;
mod gc_and_undo;
mod hardening;
mod query_and_mutation;
mod query_deletes;
mod retry;
