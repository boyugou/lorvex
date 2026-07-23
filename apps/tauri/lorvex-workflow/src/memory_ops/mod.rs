//! Shared memory mutation operations.
//!
//! These are the canonical implementations for memory entry mutations.
//! Both MCP and Tauri delegate to these instead of maintaining independent SQL.

use rusqlite::Connection;
use serde_json::Value;

use lorvex_store::payload_loaders::load_memory_delete_snapshot;
use lorvex_store::repositories::memory_revision_repo;
use lorvex_store::StoreError;

#[derive(Debug)]
pub struct MemoryMutationResult {
    pub revision_id: String,
    pub memory_key: String,
    pub pre_delete_payload: Option<Value>,
}

/// Upsert a memory entry + append revision. Canonical mutation owner.
///
/// the UPDATE arm of the upsert is gated by
/// `WHERE excluded.version > memories.version` so a stale local
/// stamp cannot clobber a freshly-applied peer envelope, mirroring
/// `repositories/preference_repo.rs::set_preference`. When the gate
/// rejects (zero rows changed AND a row exists for `key`), the
/// revision is NOT appended — appending one would leave the audit log
/// claiming a content change that never happened. Returns
/// `Ok(None)` for the stale-rejected case so callers can skip the
/// downstream sync enqueue / changelog.
///
/// Both `upsert_memory_entry` and [`delete_memory_entry`] use LWW gating
/// (`excluded.version > memories.version`) so peer writes are not silently
/// clobbered by stale local replays. The version envelope contract is
/// identical for both ops.
pub fn upsert_memory_entry(
    conn: &Connection,
    key: &str,
    content: &str,
    actor: &str,
    version: &str,
    now: &str,
) -> Result<Option<MemoryMutationResult>, StoreError> {
    // `id` is the schema's opaque row identity (UUIDv7). It is
    // insert-only: minted here for a brand-new key, and preserved
    // untouched by the `ON CONFLICT(key)` update arm, which reassigns
    // only the mutable columns. `key` remains the sync/MCP identity.
    let id = lorvex_domain::new_entity_id_string();
    let rows = conn
        .prepare_cached(
            "INSERT INTO memories (id, key, content, version, updated_at) VALUES (?1, ?2, ?3, ?4, ?5) \
             ON CONFLICT(key) DO UPDATE SET content = excluded.content, version = excluded.version, updated_at = excluded.updated_at \
             WHERE excluded.version > memories.version",
        )?
        .execute(rusqlite::params![id, key, content, version, now])?;

    if rows == 0 {
        // The key exists with a strictly-newer version — stale write
        // rejected. Skip the revision append so the audit log doesn't
        // record a phantom upsert.
        return Ok(None);
    }

    let rev_id = lorvex_domain::MemoryRevisionId::new();
    let typed_key = lorvex_domain::MemoryKey::from_trusted(key.to_string());
    memory_revision_repo::append_revision(
        conn,
        &rev_id,
        &typed_key,
        Some(content),
        "upsert",
        None,
        actor,
        version,
        now,
    )?;

    Ok(Some(MemoryMutationResult {
        revision_id: rev_id.into_string(),
        memory_key: key.to_string(),
        pre_delete_payload: None,
    }))
}

/// Delete a memory entry + append revision.
///
/// Returns `Ok(Some(result))` only when the row actually existed, the
/// delete passed the LWW gate, and the delete revision was appended.
/// Returns `Ok(None)` when the key is not present OR when the delete is
/// rejected because the stored row carries a strictly-newer version
/// (peer-applied write must not be clobbered by a stale local replay).
///
/// The version comparison mirrors [`upsert_memory_entry`]: the incoming
/// `version` must be `>` the stored row's `version` for the delete to
/// proceed. Both ops therefore share the same envelope contract.
pub fn delete_memory_entry(
    conn: &Connection,
    key: &str,
    actor: &str,
    version: &str,
    now: &str,
) -> Result<Option<MemoryMutationResult>, StoreError> {
    let pre_delete_payload = load_memory_delete_snapshot(conn, key)?;
    let changes = conn
        .prepare_cached("DELETE FROM memories WHERE key = ?1 AND version < ?2")?
        .execute(rusqlite::params![key, version])?;
    if changes == 0 {
        // Either the key is absent (true no-op) or it exists with a
        // version >= the incoming stamp (stale-write rejected). Both
        // cases skip the revision append — emitting one would record a
        // phantom delete in the audit log.
        return Ok(None);
    }

    let rev_id = lorvex_domain::MemoryRevisionId::new();
    let typed_key = lorvex_domain::MemoryKey::from_trusted(key.to_string());
    memory_revision_repo::append_revision(
        conn, &rev_id, &typed_key, None, "delete", None, actor, version, now,
    )?;
    Ok(Some(MemoryMutationResult {
        revision_id: rev_id.into_string(),
        memory_key: key.to_string(),
        pre_delete_payload,
    }))
}

/// Restore from a past revision + append restore revision.
///
/// same LWW gate as [`upsert_memory_entry`]. A stale
/// `version` stamp returns `Ok(None)` and skips the revision append.
pub fn restore_memory_revision(
    conn: &Connection,
    revision_id: &str,
    actor: &str,
    version: &str,
    now: &str,
) -> Result<Option<MemoryMutationResult>, StoreError> {
    let revision = memory_revision_repo::get_revision(conn, revision_id)?.ok_or_else(|| {
        StoreError::NotFound {
            entity: "memory_revision",
            id: revision_id.to_string(),
        }
    })?;

    let content = revision.content.ok_or_else(|| {
        StoreError::Validation("cannot restore from a delete revision".to_string())
    })?;

    // `id` is insert-only (see `upsert_memory_entry`): minted for a
    // brand-new key, preserved by the `ON CONFLICT(key)` update arm.
    let id = lorvex_domain::new_entity_id_string();
    let rows = conn
        .prepare_cached(
            "INSERT INTO memories (id, key, content, version, updated_at) VALUES (?1, ?2, ?3, ?4, ?5) \
             ON CONFLICT(key) DO UPDATE SET content = excluded.content, version = excluded.version, updated_at = excluded.updated_at \
             WHERE excluded.version > memories.version",
        )?
        .execute(rusqlite::params![
            id,
            revision.memory_key,
            content,
            version,
            now
        ])?;

    if rows == 0 {
        return Ok(None);
    }

    let rev_id = lorvex_domain::MemoryRevisionId::new();
    let typed_key = lorvex_domain::MemoryKey::from_trusted(revision.memory_key.clone());
    let typed_source = lorvex_domain::MemoryRevisionId::from_trusted(revision_id.to_string());
    memory_revision_repo::append_revision(
        conn,
        &rev_id,
        &typed_key,
        Some(&content),
        "restore",
        Some(&typed_source),
        actor,
        version,
        now,
    )?;

    Ok(Some(MemoryMutationResult {
        revision_id: rev_id.into_string(),
        memory_key: revision.memory_key,
        pre_delete_payload: None,
    }))
}

#[cfg(test)]
mod tests;
