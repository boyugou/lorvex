//! Upserts for the memory aggregate: parent `memories` plus the append-only
//! `memory_revisions` log.

use rusqlite::Connection;

use super::super::helpers::{
    optional_string_field, required_string_field, required_sync_timestamp_field, VersionedJsonlLine,
};
use super::{should_replace_versioned, UpsertResult};
use crate::import::ImportError;

pub(in crate::import::apply::upserts) fn upsert_memory(
    conn: &Connection,
    entry: &VersionedJsonlLine,
) -> Result<UpsertResult, ImportError> {
    let p = &entry.payload;
    let key = required_string_field(p, "key", "memory payload")?;
    let version = entry.version.as_str();
    let content = required_string_field(p, "content", "memory payload")?;
    let updated_at = required_sync_timestamp_field(p, "updated_at", "memory payload")?;

    // A memory row is keyed for sync/LWW by its `key`; `id` is the
    // opaque schema PK, minted here on first insert and left untouched
    // by the update arm. The generic `import_lww_upsert` shares one
    // positional-param slice between INSERT and UPDATE, so the
    // insert-only `id` is spelled out here rather than folded into that
    // shared spec.
    match should_replace_versioned(conn, "memories", "key", &key, version)? {
        None => {
            let id = lorvex_domain::new_entity_id_string();
            conn.execute(
                "INSERT INTO memories (id, key, content, updated_at, version) VALUES (?1,?2,?3,?4,?5)",
                rusqlite::params![id, key, content, updated_at, version],
            )?;
            Ok(UpsertResult::Created)
        }
        Some(true) => {
            conn.execute(
                "UPDATE memories SET content=?2, updated_at=?3, version=?4 WHERE key=?1",
                rusqlite::params![key, content, updated_at, version],
            )?;
            Ok(UpsertResult::Updated)
        }
        Some(false) => Ok(UpsertResult::Skipped),
    }
}

pub(in crate::import::apply::upserts) fn upsert_memory_revision(
    conn: &Connection,
    entry: &VersionedJsonlLine,
) -> Result<UpsertResult, ImportError> {
    let p = &entry.payload;
    let id = required_string_field(p, "id", "memory_revision payload")?;
    let memory_key = required_string_field(p, "memory_key", "memory_revision payload")?;
    let operation = required_string_field(p, "operation", "memory_revision payload")?;
    let actor = required_string_field(p, "actor", "memory_revision payload")?;
    let created_at = required_sync_timestamp_field(p, "created_at", "memory_revision payload")?;
    let content = optional_string_field(p, "content", "memory_revision payload")?;
    let source_revision_id =
        optional_string_field(p, "source_revision_id", "memory_revision payload")?;

    // Memory revisions are append-only: INSERT OR IGNORE for idempotent import.
    let changes = conn.execute(
        "INSERT OR IGNORE INTO memory_revisions
             (id, memory_key, content, operation, source_revision_id, actor, version, created_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
        rusqlite::params![
            id,
            memory_key,
            content.as_deref(),
            operation,
            source_revision_id.as_deref(),
            actor,
            entry.version.as_str(),
            created_at,
        ],
    )?;

    if changes > 0 {
        Ok(UpsertResult::Created)
    } else {
        Ok(UpsertResult::Skipped)
    }
}
