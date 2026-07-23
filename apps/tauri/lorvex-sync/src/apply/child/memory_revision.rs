use lorvex_domain::ids::{MemoryKey, MemoryRevisionId};

use super::helpers::{optional_str, required_str};
use super::*;

/// Apply an inbound `memory_revision` envelope.
///
/// Memory revisions are an append-only audit stream keyed by UUIDv7.
/// Each revision is a unique write — different peers writing different
/// content always mint different `id`s, so the `id` collision case can
/// only happen on a peer replay of the same exact revision. The
/// envelope-level `version` and `allow_equal_versions` parameters are
/// part of the dispatch contract (see
/// the `EntityHandler::standard` row factor in `apply::dispatch`) but
/// intentionally ignored here: any LWW-style "let the newer envelope
/// rewrite the existing row" semantics would let a misbehaving peer
/// edit history. INSERT OR IGNORE keeps the first-seen content,
/// matching the immutability the audit-stream contract requires.
pub(crate) fn apply_memory_revision_upsert(
    conn: &Connection,
    entity_id: &str,
    payload: &str,
    _version: &str,
    _allow_equal_versions: LwwTieBreak,
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    // Issue #3285: parse the PK and the memory-key FK into typed
    // newtypes at handler entry. SQL bind sites use the rusqlite
    // ToSql impl on the newtype directly (zero-copy); dispatcher-
    // validated upstream so `from_trusted` skips a redundant parse.
    let id = MemoryRevisionId::from_trusted(entity_id.to_string());
    let val: serde_json::Value = serde_json::from_str(payload)?;

    let memory_key_str = required_str(&val, "memory_key", "memory_revision")?;
    let memory_key = MemoryKey::from_trusted(memory_key_str.to_string());
    // Unicode hygiene (#2427): memory revision content mirrors memory content.
    let content_owned =
        optional_str(&val, "content", "memory_revision")?.map(lorvex_domain::sanitize_user_text);
    let content: Option<&str> = content_owned.as_deref();
    let operation_raw = required_str(&val, "operation", "memory_revision")?;
    // the closed set lived in three
    // parallel declarations — a `VALID_MEMORY_REVISION_OPS` allowlist
    // here, the `memory_revisions.operation` text column, and a SQL
    // CHECK constraint. We now parse once via the typed
    // `MemoryRevisionOperation` enum at the trust boundary; the SQL
    // CHECK is the byte-level last gate but the closed set lives in
    // exactly one Rust source file.
    let operation_kind = lorvex_domain::memory::MemoryRevisionOperation::parse(operation_raw)
        .ok_or_else(|| {
            let allowed: Vec<&'static str> = lorvex_domain::memory::MemoryRevisionOperation::all()
                .iter()
                .map(lorvex_domain::memory::MemoryRevisionOperation::as_str)
                .collect();
            ApplyError::InvalidPayload(format!(
                "memory_revision payload: operation '{operation_raw}' is not one of {allowed:?}"
            ))
        })?;
    // Re-bind to the canonical wire string. The DB column carries
    // text; this guarantees we round-trip exactly the canonical form
    // produced by the enum's `as_str()` even if a caller typed-fooled
    // a near-canonical input through a tolerant peer.
    let operation = operation_kind.as_str();
    let source_revision_id = optional_str(&val, "source_revision_id", "memory_revision")?;
    let actor_raw = required_str(&val, "actor", "memory_revision")?;
    // same shape as `operation` — the closed set is
    // the typed `MemoryRevisionActor` enum, the SQL CHECK is the last
    // byte-level gate.
    let actor_kind =
        lorvex_domain::memory::MemoryRevisionActor::parse(actor_raw).ok_or_else(|| {
            ApplyError::InvalidPayload(format!(
                "memory_revision payload: actor '{actor_raw}' is not one of [\"ai\", \"human\"]"
            ))
        })?;
    let actor = actor_kind.as_str();
    let version = required_str(&val, "version", "memory_revision")?;
    let created_at = required_str(&val, "created_at", "memory_revision")?;

    // Append-only: INSERT OR IGNORE ensures idempotent sync.
    conn.prepare_cached(
        "INSERT OR IGNORE INTO memory_revisions
             (id, memory_key, content, operation, source_revision_id, actor, version, created_at)
         VALUES (:id, :memory_key, :content, :operation, :source_revision_id, :actor, :version, :created_at)",
    )?
    .execute(named_params! {
        ":id": &id,
        ":memory_key": &memory_key,
        ":content": content,
        ":operation": operation,
        ":source_revision_id": source_revision_id,
        ":actor": actor,
        ":version": version,
        ":created_at": created_at,
    })?;
    Ok(())
}

pub(crate) fn apply_memory_revision_delete(
    conn: &Connection,
    entity_id: &str,
    version: &str,
    _apply_ts: &str,
) -> Result<(), ApplyError> {
    // Issue #3285: parse the PK into a typed `MemoryRevisionId` once
    // at handler entry. The shared `lww_gated_delete` helper takes a
    // `&[&str]` slice for PK values, so we feed `id.as_str()` — the
    // typed seam still covers every read of the id in this handler
    // scope, with a single zero-copy borrow at the boundary of the
    // cross-aggregate helper.
    let id = MemoryRevisionId::from_trusted(entity_id.to_string());
    // defense-in-depth in-row LWW guard. Memory
    // revisions are append-only on the producer side, so the writer
    // never authors deletes. A peer (legitimately or otherwise)
    // crafting a delete envelope still flows through this handler;
    // the LWW gate prevents a stale-delete from removing a row that
    // a different peer has just refreshed. Routes through
    // `lww_gated_delete` (NA3) so every edge/child delete shares one
    // typed comparator.
    crate::apply::lww_gated_delete(conn, "memory_revisions", &["id"], &[id.as_str()], version)?;
    Ok(())
}
