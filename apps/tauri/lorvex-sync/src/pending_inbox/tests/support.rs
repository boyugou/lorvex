use super::super::*;

pub(super) use crate::envelope::SyncOperation;
pub(super) use crate::test_db;
pub(super) use crate::tombstone::create_tombstone;
pub(super) use lorvex_domain::naming;
pub(super) use rusqlite::{params, Connection, Params};

pub(super) fn make_envelope(entity_type: &str, entity_id: &str) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::parse(entity_type)
            .expect("test entity_type must be a known EntityKind"),
        entity_id: entity_id.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: 1,
        payload: r#"{"title":"test"}"#.to_string(),
        device_id: "device-001".to_string(),
    }
}

pub(super) fn make_delete_envelope(entity_type: &str, entity_id: &str) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::parse(entity_type)
            .expect("test entity_type must be a known EntityKind"),
        entity_id: entity_id.to_string(),
        operation: SyncOperation::Delete,
        version: lorvex_domain::hlc::Hlc::parse("1711234569999_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: 1,
        payload: "{}".to_string(),
        device_id: "device-001".to_string(),
    }
}

/// inserts a raw row into `sync_pending_inbox` whose `envelope`
/// column is invalid JSON. `enqueue_pending` would normally reject
/// the payload at enqueue time (#3009-M6), but a row that landed in
/// the table from an earlier build, a corrupted row, or an
/// envelope persisted under an `entity_type` since retired (post-
/// #3004-H1 typed `EntityKind` parse fails for unrecognized
/// strings) can still appear. This helper lets the
/// unparseable-quarantine tests seed exactly that shape.
pub(super) fn insert_unparseable_pending_row(
    conn: &Connection,
    envelope_entity_type: &str,
    envelope_entity_id: &str,
    attempt_count: i64,
) {
    conn.execute(
        "INSERT INTO sync_pending_inbox (
            envelope, reason, missing_entity_type, missing_entity_id,
            envelope_entity_type, envelope_entity_id, envelope_version,
            first_attempted_at, last_attempted_at, attempt_count
         ) VALUES (
            ?1, ?2, ?3, ?4, ?5, ?6, ?7,
            '2026-03-27T09:00:00.000Z',
            '2026-03-27T09:00:00.000Z',
            ?8
         )",
        params![
            r#"{"entity_type":"task_reminder","entity_id":"broken""#,
            naming::RESOLUTION_FK_UNRESOLVED,
            naming::ENTITY_TASK,
            "01966a3f-7c8b-7d4e-8f3a-000000002189",
            envelope_entity_type,
            envelope_entity_id,
            "1711234567890_0000_a1b2c3d4a1b2c3d4",
            attempt_count,
        ],
    )
    .unwrap();
}

pub(super) fn explain_query_plan_details<P: Params>(
    conn: &Connection,
    sql: &str,
    params: P,
) -> Vec<String> {
    let mut stmt = conn.prepare(&format!("EXPLAIN QUERY PLAN {sql}")).unwrap();
    stmt.query_map(params, |row| row.get::<_, String>(3))
        .unwrap()
        .collect::<Result<Vec<_>, _>>()
        .unwrap()
}

pub(super) fn make_reminder_envelope_with_missing_task(
    reminder_id: &str,
    task_id: &str,
) -> SyncEnvelope {
    SyncEnvelope {
        entity_type: lorvex_domain::naming::EntityKind::TaskReminder,
        entity_id: reminder_id.to_string(),
        operation: SyncOperation::Upsert,
        version: lorvex_domain::hlc::Hlc::parse("1711234567890_0000_a1b2c3d4a1b2c3d4")
            .expect("test fixture version must be a canonical HLC"),
        payload_schema_version: 1,
        payload: format!(
            r#"{{"task_id":"{task_id}","reminder_at":"2026-01-01T09:00:00Z","created_at":"2026-01-01T09:00:00Z"}}"#
        ),
        device_id: "device-001".to_string(),
    }
}
