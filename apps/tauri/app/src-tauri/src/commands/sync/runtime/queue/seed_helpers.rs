//! Generic seed primitives shared by every entity class:
//!
//!   * `seed_simple_sync_payloads` — adapter that asks
//!     `lorvex_store::payload_loaders` to stream canonical
//!     simple-entity payloads without exposing SELECT projections or
//!     row mappers to Tauri.
//!   * `seed_ids_and_delegate` — variant that delegates payload
//!     construction to an entity-specific `enqueue_*_upsert` helper
//!     (used for entities whose Tauri-side enricher pulls
//!     extra-table data, e.g. task reminders / checklist items).
//!   * `seed_aggregate_root_by_date` / `seed_aggregate_ids` — route
//!     date-keyed aggregate roots (current_focus, focus_schedule,
//!     daily_review) through the canonical aggregate builder.

use lorvex_domain::naming::OP_UPSERT;
use lorvex_store::payload_loaders::{
    for_each_simple_sync_payload, SimpleSyncPayloadSeedError, SimpleSyncSeedKind,
};

use super::enqueue::enqueue_to_outbox;
use crate::error::{AppError, AppResult};

/// Stream canonical simple-entity payloads from `lorvex-store` and
/// enqueue them as upserts. Store owns the SQL projection, ordering,
/// row mapping, and entity-id extraction; Tauri owns outbox policy.
pub(super) fn seed_simple_sync_payloads(
    conn: &rusqlite::Connection,
    entity_type: &str,
    kind: SimpleSyncSeedKind,
) -> AppResult<i64> {
    for_each_simple_sync_payload(conn, kind, |entity_id, payload| {
        enqueue_to_outbox(conn, entity_type, &entity_id, OP_UPSERT, &payload).map_err(|error| {
            AppError::Internal(format!(
                "Failed to enqueue {entity_type} '{entity_id}': {error}"
            ))
        })
    })
    .map_err(|error| match error {
        SimpleSyncPayloadSeedError::Store(error) => AppError::from(error),
        SimpleSyncPayloadSeedError::Callback(error) => error,
    })
}

/// Seed IDs from a table and delegate to an existing enqueue helper.
pub(super) fn seed_ids_and_delegate<F>(
    conn: &rusqlite::Connection,
    entity_type: &str,
    sql: &str,
    enqueue_fn: F,
) -> AppResult<i64>
where
    F: Fn(&rusqlite::Connection, &str) -> AppResult<()>,
{
    let mut stmt = conn.prepare_cached(sql).map_err(AppError::from)?;
    let ids: Vec<String> = stmt
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(AppError::from)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| AppError::Internal(format!("Failed to read {entity_type} row: {e}")))?;
    let count = ids.len() as i64;
    for id in &ids {
        enqueue_fn(conn, id).map_err(|e| {
            AppError::Internal(format!("Failed to enqueue {entity_type} '{id}': {e}"))
        })?;
    }
    Ok(count)
}

/// shared seed helper for date-keyed aggregate roots
/// (`current_focus`, `focus_schedule`, `daily_review`). Routes through
/// the canonical aggregate builder so the seeded outbound envelope
/// matches the apply-side expectation byte-for-byte.
pub(super) fn seed_aggregate_root_by_date(
    conn: &rusqlite::Connection,
    entity_type: &'static str,
    sql: &str,
) -> AppResult<i64> {
    seed_aggregate_ids(conn, entity_type, sql)
}

pub(super) fn seed_aggregate_ids(
    conn: &rusqlite::Connection,
    entity_type: &'static str,
    sql: &str,
) -> AppResult<i64> {
    debug_assert!(
        lorvex_domain::naming::EntityKind::parse(entity_type).is_some_and(
            lorvex_sync::payload_build::aggregate::kind_is_aggregate_root_with_embedded_children
        ),
        "seed_aggregate_ids called for non-aggregate type {entity_type:?}"
    );
    let mut stmt = conn.prepare_cached(sql).map_err(AppError::from)?;
    let ids: Vec<String> = stmt
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(AppError::from)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| AppError::Internal(format!("Failed to read {entity_type} row: {e}")))?;
    let count = ids.len() as i64;
    for id in &ids {
        let Some(payload) =
            lorvex_sync::payload_build::aggregate::build_aggregate_payload(conn, entity_type, id)
                .map_err(AppError::from)?
        else {
            return Err(AppError::Internal(format!(
                "{entity_type} '{id}' selected by seed query but canonical builder returned None",
            )));
        };
        enqueue_to_outbox(conn, entity_type, id, OP_UPSERT, &payload).map_err(|e| {
            AppError::Internal(format!("Failed to enqueue {entity_type} '{id}': {e}"))
        })?;
    }
    Ok(count)
}
