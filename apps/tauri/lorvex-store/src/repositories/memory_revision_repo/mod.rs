use crate::error::StoreError;
use lorvex_domain::time::SyncTimestamp;
use rusqlite::Connection;

use super::parse_sync_timestamp_column;

#[cfg(test)]
mod tests;

/// A row from the `memory_revisions` table.
///
/// `created_at` is a [`SyncTimestamp`] rather than a bare `String` so
/// ordering and comparison stay correct across devices that emit
/// different fractional-digit precisions (lex-comparing the raw
/// strings would silently misorder). JSON wire shape is byte-stable
/// because `SyncTimestamp` always emits the canonical millisecond-Z
/// form regardless of input precision.
#[derive(Debug, Clone, serde::Serialize)]
pub struct MemoryRevision {
    pub id: String,
    pub memory_key: String,
    pub content: Option<String>,
    pub operation: String,
    pub source_revision_id: Option<String>,
    pub actor: String,
    pub version: String,
    pub created_at: SyncTimestamp,
}

/// Append a revision entry.
#[allow(clippy::too_many_arguments)]
pub fn append_revision(
    conn: &Connection,
    id: &lorvex_domain::MemoryRevisionId,
    memory_key: &lorvex_domain::MemoryKey,
    content: Option<&str>,
    operation: &str,
    source_revision_id: Option<&lorvex_domain::MemoryRevisionId>,
    actor: &str,
    version: &str,
    now: &str,
) -> Result<(), StoreError> {
    conn.prepare_cached(
        "INSERT INTO memory_revisions (id, memory_key, content, operation, source_revision_id, actor, version, created_at) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
    )?
    .execute(rusqlite::params![id, memory_key, content, operation, source_revision_id, actor, version, now])?;
    Ok(())
}

/// Get revision history for a key, most recent first.
///
/// the `ORDER BY` carries an `id ASC` tiebreaker
/// so two revisions captured in the same microsecond — e.g. a batch
/// import that stamps multiple appends with the same `now` — sort
/// deterministically. Without it, OFFSET-paged iteration over the
/// history surface produced a non-stable order between pages, which
/// is the same hazard `TASK_ORDER_BY` exists to defeat (CLAUDE.md
/// rule #4). UUIDv7 ids are monotonic over time, so `id ASC`
/// approximates "first append wins" within a tied microsecond
/// window without needing an additional column.
pub fn get_revisions_for_key(
    conn: &Connection,
    memory_key: &lorvex_domain::MemoryKey,
    limit: u32,
) -> Result<Vec<MemoryRevision>, StoreError> {
    let mut stmt = conn.prepare_cached(
        "SELECT id, memory_key, content, operation, source_revision_id, actor, version, created_at \
         FROM memory_revisions WHERE memory_key = ?1 \
         ORDER BY created_at DESC, id ASC LIMIT ?2",
    )?;
    let rows = stmt.query_map(rusqlite::params![memory_key, limit], row_to_memory_revision)?;
    Ok(rows.collect::<Result<Vec<_>, _>>()?)
}

/// Get a specific revision by ID.
pub fn get_revision(
    conn: &Connection,
    revision_id: &str,
) -> Result<Option<MemoryRevision>, StoreError> {
    use rusqlite::OptionalExtension;
    Ok(conn
        .prepare_cached(
            "SELECT id, memory_key, content, operation, source_revision_id, actor, version, created_at \
             FROM memory_revisions WHERE id = ?1",
        )?
        .query_row([revision_id], row_to_memory_revision)
        .optional()?)
}

/// Map a `rusqlite::Row` (columns ordered as `id, memory_key, content,
/// operation, source_revision_id, actor, version, created_at`) into a
/// typed [`MemoryRevision`]. Centralizing the parser keeps the column-
/// index / `SyncTimestamp::parse` invariant in one place (Audit
/// #3004-M3).
fn row_to_memory_revision(row: &rusqlite::Row<'_>) -> rusqlite::Result<MemoryRevision> {
    Ok(MemoryRevision {
        id: row.get(0)?,
        memory_key: row.get(1)?,
        content: row.get(2)?,
        operation: row.get(3)?,
        source_revision_id: row.get(4)?,
        actor: row.get(5)?,
        version: row.get(6)?,
        created_at: parse_sync_timestamp_column(row, 7, "memory_revisions", "created_at")?,
    })
}
