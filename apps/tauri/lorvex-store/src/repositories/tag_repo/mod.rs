//! Tag repository — shared CRUD operations for the `tags` and
//! `tags` and `task_tags` tables.
//!
//! Used by both the Tauri app and the MCP server. All tag name matching flows
//! through `normalize_lookup_key` from `lorvex-domain`; no ad-hoc lowercasing.

use crate::error::StoreError;
use lorvex_domain::entity_id::new_entity_id_string;
use lorvex_domain::naming::ENTITY_TAG;
use lorvex_domain::tag::normalize_lookup_key;
use lorvex_domain::time::SyncTimestamp;
use rusqlite::{params, Connection, OptionalExtension};

use super::parse_sync_timestamp_column;

// ---------------------------------------------------------------------------
// Tag struct
// ---------------------------------------------------------------------------

/// A tag row as stored in SQLite.
///
/// Fields mirror the `tags` table columns:
/// - `display_name`: original-case display name.
/// - `lookup_key`: case-folded key for merge detection.
///
/// `created_at` and `updated_at` are now [`SyncTimestamp`]
/// rather than bare `String`. Same rationale as `MemoryEntry::updated_at`
/// — every consumer that ordered or compared tag rows lex-
/// compare strings, which silently misorders when one device emits 3-
/// fractional-digit timestamps and another emits 6. JSON wire shape is
/// byte-stable because `SyncTimestamp` always emits the canonical
/// millisecond-Z form regardless of input precision.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Tag {
    pub id: String,
    pub display_name: String,
    pub lookup_key: String,
    pub color: Option<String>,
    pub created_at: SyncTimestamp,
    pub updated_at: SyncTimestamp,
    pub version: String,
}

// ---------------------------------------------------------------------------
// Read operations
// ---------------------------------------------------------------------------

/// Look up a tag by its current `lookup_key` (exact match). Returns
/// `Ok(None)` when no row matches.
///
/// `tags.lookup_key` has no UNIQUE index (the sync
/// merge in `apply::tag::merge_duplicate_tags` holds two rows
/// mid-convergence so a constraint here would break the merger).
/// In the narrow race window between two-devices-emit-same-key and
/// the merge sweep, duplicates are observable. `ORDER BY id ASC
/// LIMIT 1` gives this read a deterministic winner that matches
/// the merger's "min id wins" tiebreak, so a pre-merge sample
/// still agrees with the eventually-converged state.
fn get_tag_by_lookup_key(conn: &Connection, lookup_key: &str) -> Result<Option<Tag>, StoreError> {
    // route through `prepare_cached` so the per-tag
    // resolution loop in `add_tags` (and every task-write tag-resolve
    // path) reuses one parsed plan across the per-call N —
    // a 50-tag bulk import re-parsed this SELECT 50 times. The SQL
    // shape is stable so the cache key collapses to one entry.
    Ok(conn
        .prepare_cached(
            "SELECT id, display_name, lookup_key, color, created_at, updated_at, version \
             FROM tags WHERE lookup_key = ?1 ORDER BY id ASC LIMIT 1",
        )?
        .query_row([lookup_key], tag_from_row)
        .optional()?)
}

/// Look up a tag by display name. Normalizes the input to a `lookup_key`
/// first, then queries the current `lookup_key` column. Returns
/// `Ok(None)` when no row matches.
///
/// renamed from `find_tag_by_name` to `get_tag_by_name`
/// so every repository read converges on the `get_*` prefix the
/// `repositories/mod.rs` convention codifies for `Result<Option<_>, _>`
/// shape lookups.
pub fn get_tag_by_name(conn: &Connection, name: &str) -> Result<Option<Tag>, StoreError> {
    let key = normalize_lookup_key(name);
    get_tag_by_lookup_key(conn, &key)
}

// ---------------------------------------------------------------------------
// Write operations
// ---------------------------------------------------------------------------

/// Resolve a tag by display name, or create it if it does not exist.
///
/// Returns `(tag_id, was_created)`. The `version` parameter is the HLC string
/// to stamp on a newly created tag. `now` is the canonical sync timestamp
/// (millisecond `Z` form per `sync_timestamp_now()`, see
/// `lorvex-domain/src/time/sync_timestamp.rs`); accepting it as an
/// argument keeps the timestamp deterministic across the entire logical
/// write so tests and replays can pin a clock and so the value stays in
/// lockstep with whatever HLC the caller passed in `version`.
pub fn resolve_or_create_tag(
    conn: &Connection,
    display_name: &str,
    version: &str,
    now: &str,
) -> Result<(String, bool), StoreError> {
    let lookup_key = normalize_lookup_key(display_name);

    if let Some(existing) = get_tag_by_lookup_key(conn, &lookup_key)? {
        return Ok((existing.id, false));
    }

    let id = new_entity_id_string();
    conn.prepare_cached(
        "INSERT INTO tags (id, display_name, lookup_key, created_at, updated_at, version) \
         VALUES (?1, ?2, ?3, ?4, ?4, ?5)",
    )?
    .execute(params![id, display_name, lookup_key, now, version])?;

    Ok((id, true))
}

/// Rename an existing tag. Updates `display_name` and `lookup_key`.
/// `now` follows the same contract as `resolve_or_create_tag` — the
/// caller staged the timestamp upstream so this function does not
/// drift it via a fresh `sync_timestamp_now()` call mid-transaction.
///
/// gated by `version > tags.version` so a stale local
/// rename cannot clobber a newer remote rename in the sync-apply
/// path. Returns `StoreError::NotFound` when the tag id doesn't
/// exist, and `StoreError::StaleVersion` when the row exists but
/// the caller's `version` is not strictly greater. The cluster's
/// already-converged state is preserved either way; callers surface
/// the StaleVersion error so the response payload reflects the
/// cluster's truth instead of silently pretending the rename
/// succeeded.
pub fn rename_tag(
    conn: &Connection,
    tag_id: &lorvex_domain::TagId,
    new_display_name: &str,
    version: &str,
    now: &str,
) -> Result<(), StoreError> {
    let new_lookup_key = normalize_lookup_key(new_display_name);

    let affected = conn
        .prepare_cached(
            "UPDATE tags SET display_name = ?1, lookup_key = ?2, updated_at = ?3, version = ?4 \
             WHERE id = ?5 AND ?4 > version",
        )?
        .execute(params![
            new_display_name,
            new_lookup_key,
            now,
            version,
            tag_id
        ])?;
    if affected == 0 {
        // Distinguish "row missing" from "stale-version no-op".
        let exists: bool = conn
            .prepare_cached("SELECT 1 FROM tags WHERE id = ?1")?
            .query_row([tag_id], |_| Ok(true))
            .optional()?
            .unwrap_or(false);
        if !exists {
            return Err(StoreError::NotFound {
                entity: "tag",
                id: tag_id.to_string(),
            });
        }
        // Stale-version write: cluster's already-converged state is
        // preserved by the LWW gate. Surface as `StaleVersion` so
        // callers can render the canonical row instead of returning
        // Ok with stale local data.
        return Err(StoreError::StaleVersion {
            entity: ENTITY_TAG,
            id: tag_id.to_string(),
        });
    }

    Ok(())
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn tag_from_row(row: &rusqlite::Row<'_>) -> Result<Tag, rusqlite::Error> {
    Ok(Tag {
        id: row.get(0)?,
        display_name: row.get(1)?,
        lookup_key: row.get(2)?,
        color: row.get(3)?,
        created_at: parse_sync_timestamp_column(row, 4, "tags", "created_at")?,
        updated_at: parse_sync_timestamp_column(row, 5, "tags", "updated_at")?,
        version: row.get(6)?,
    })
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests;
