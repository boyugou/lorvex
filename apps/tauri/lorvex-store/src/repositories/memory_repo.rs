use crate::error::StoreError;
use lorvex_domain::time::SyncTimestamp;
use rusqlite::Connection;

use super::parse_sync_timestamp_column;

/// A row from the `memories` table.
///
/// `updated_at` is now [`SyncTimestamp`] rather than a
/// bare `String`. The rationale matches
/// `lorvex_store::repositories::ai_changelog_query::AiChangelogEntry::timestamp`:
/// every consumer that ordered or compared memory rows lex-
/// compare strings, which silently misorders when one device emits
/// 3-fractional-digit timestamps and another emits 6. `SyncTimestamp`
/// flips ordering onto the underlying `DateTime<Utc>` while keeping the
/// JSON wire shape byte-identical (custom `Serialize` round-trips through
/// the canonical millisecond-Z form). SQL bind sites stay unchanged
/// because writes flow through `format_sync_timestamp` already; the
/// SELECT path needs an explicit `parse` because `lorvex-domain` is
/// IO-free and does not implement `rusqlite::types::FromSql`.
#[derive(Debug, Clone, serde::Serialize)]
pub struct MemoryEntry {
    pub key: String,
    pub content: String,
    pub version: String,
    pub updated_at: SyncTimestamp,
}

pub fn get_memory_entry(conn: &Connection, key: &str) -> Result<Option<MemoryEntry>, StoreError> {
    use rusqlite::OptionalExtension;
    Ok(conn
        .query_row(
            "SELECT key, content, version, updated_at FROM memories WHERE key = ?1",
            [key],
            row_to_memory_entry,
        )
        .optional()?)
}

/// Map a `rusqlite::Row` (columns ordered as `key, content, version,
/// updated_at`) into a typed [`MemoryEntry`]. Exposed for callers that
/// build the row through `query_map` against custom `SELECT … FROM
/// memories` shapes (see `lorvex-cli`); centralizing the parser here
/// keeps the column-index / `SyncTimestamp::parse` invariant in one
/// place.
pub fn row_to_memory_entry(row: &rusqlite::Row<'_>) -> rusqlite::Result<MemoryEntry> {
    Ok(MemoryEntry {
        key: row.get(0)?,
        content: row.get(1)?,
        version: row.get(2)?,
        updated_at: parse_sync_timestamp_column(row, 3, "memories", "updated_at")?,
    })
}
