//! Shared operations for `current_focus` parent rows and `current_focus_items`
//! child materialization.
//!
//! Parent row operations enforce timezone immutability on the local write path:
//! the `timezone` column is set only on INSERT and never overwritten by UPDATE.
//!
//! The single canonical DELETE-then-INSERT loop with deduplication handles the
//! child sub-table. All callers (MCP, Tauri, sync-apply, import) should
//! delegate here instead of owning independent SQL.

use rusqlite::Connection;
use rusqlite::OptionalExtension;

use crate::error::StoreError;
use std::collections::HashSet;

// ---------------------------------------------------------------------------
// Parent row: current_focus
// ---------------------------------------------------------------------------

/// Outcome of a parent row upsert.
///
/// `LwwRejected` distinguishes the case where the row already exists but the
/// supplied `version` is not strictly greater than the current row's version,
/// so the UPDATE statement matched zero rows. Without this variant the
/// gate-rejected and gate-accepted paths both reported `Updated`, leaving
/// callers unable to tell whether their write actually landed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UpsertOutcome {
    Created,
    Updated,
    LwwRejected,
}

/// Create or update the `current_focus` parent row.
///
/// **Timezone immutability**: on UPDATE, the existing timezone is preserved.
/// The `timezone` parameter is only used on INSERT (row creation).
///
/// The UPDATE branch is gated on `?2 > current_focus.version` so a stale
/// local stamp racing an in-flight peer write cannot regress the row's HLC.
/// The outcome distinguishes the three cases:
///   * `Created` — no row existed, INSERT ran.
///   * `Updated` — row existed, UPDATE landed (version strictly greater).
///   * `LwwRejected` — row existed but the LWW gate rejected the write
///     (zero rows affected); the on-disk row is unchanged.
pub fn upsert_current_focus_header(
    conn: &Connection,
    date: &str,
    briefing: Option<&str>,
    timezone: &str,
    version: &str,
    now: &str,
) -> Result<UpsertOutcome, StoreError> {
    let exists: bool = conn
        .query_row(
            "SELECT 1 FROM current_focus WHERE date = ?1",
            [date],
            |_| Ok(true),
        )
        .optional()?
        .is_some();

    if exists {
        let rows_affected = conn
            .prepare_cached(
                "UPDATE current_focus SET briefing = ?1, version = ?2, updated_at = ?3 \
                 WHERE date = ?4 AND ?2 > version",
            )?
            .execute(rusqlite::params![briefing, version, now, date])?;
        if rows_affected == 0 {
            Ok(UpsertOutcome::LwwRejected)
        } else {
            Ok(UpsertOutcome::Updated)
        }
    } else {
        conn.prepare_cached(
            "INSERT INTO current_focus (date, briefing, timezone, version, created_at, updated_at) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?5)",
        )?
        .execute(rusqlite::params![date, briefing, timezone, version, now])?;
        Ok(UpsertOutcome::Created)
    }
}

/// Update only the version and timestamp of an existing `current_focus` row.
///
/// **Timezone immutability**: only `version` and `updated_at` are modified.
/// Useful when the parent row doesn't change (e.g., reorder, remove task).
///
/// the version-bumping branch is gated on
/// `?1 > current_focus.version` so a stale local stamp cannot regress the
/// row's HLC. The bare timestamp-only branch (no version supplied) is
/// untouched — that path is used for cosmetic touches that do not advance
/// the HLC and must remain a non-LWW write.
pub fn touch_current_focus_header(
    conn: &Connection,
    date: &str,
    version: Option<&str>,
    now: &str,
) -> Result<(), StoreError> {
    if let Some(version) = version {
        conn.prepare_cached(
            "UPDATE current_focus SET version = ?1, updated_at = ?2 \
             WHERE date = ?3 AND ?1 > version",
        )?
        .execute(rusqlite::params![version, now, date])?;
    } else {
        conn.prepare_cached("UPDATE current_focus SET updated_at = ?1 WHERE date = ?2")?
            .execute(rusqlite::params![now, date])?;
    }
    Ok(())
}

/// Sync-mode upsert: full-entity replacement from another device.
///
/// Unlike local writes, this **does** overwrite `timezone` and `created_at`
/// because the remote envelope is authoritative.
///
/// `version_cmp` should be `">"` for normal sync or `">="` when the
/// capability negotiation allows equal-version acceptance.
///
/// Returns `true` if a row was inserted or updated (i.e. the version check
/// passed), `false` if the existing row was newer.
#[allow(clippy::too_many_arguments)]
pub fn sync_upsert_current_focus(
    conn: &Connection,
    date: &str,
    briefing: Option<&str>,
    timezone: Option<&str>,
    version: &str,
    created_at: &str,
    updated_at: &str,
    version_cmp: &str,
) -> Result<bool, StoreError> {
    // The SQL takes one of two shapes (`>` or `>=`) keyed on the
    // runtime `version_cmp` argument. Cache both shapes so every
    // sync apply pays its `format!` cost exactly once.
    static SQL_GT: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    static SQL_GTE: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let render = |op: &str| {
        format!(
            "INSERT INTO current_focus (date, briefing, timezone, version, created_at, updated_at) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6) \
             ON CONFLICT(date) DO UPDATE SET \
                briefing=excluded.briefing, timezone=excluded.timezone, \
                created_at=excluded.created_at, updated_at=excluded.updated_at, \
                version=excluded.version \
             WHERE excluded.version {op} current_focus.version"
        )
    };
    let sql = match version_cmp {
        ">" => SQL_GT.get_or_init(|| render(">")),
        ">=" => SQL_GTE.get_or_init(|| render(">=")),
        other => {
            return Err(StoreError::Validation(format!(
                "sync_upsert_current_focus: version_cmp must be \">\" or \">=\", got {other:?}"
            )))
        }
    };
    let changes = conn.prepare_cached(sql)?.execute(rusqlite::params![
        date, briefing, timezone, version, created_at, updated_at
    ])?;
    Ok(changes > 0)
}

/// Delete the `current_focus` parent row.
///
/// CASCADE will automatically remove associated `current_focus_items`.
/// Returns `true` if a row was actually deleted.
pub fn delete_current_focus(conn: &Connection, date: &str) -> Result<bool, StoreError> {
    let changes = conn
        .prepare_cached("DELETE FROM current_focus WHERE date = ?1")?
        .execute([date])?;
    Ok(changes > 0)
}

// ---------------------------------------------------------------------------
// Child materialization: current_focus_items
// ---------------------------------------------------------------------------

/// Materialize focus items for a given date.
///
/// Deletes all existing items for `date`, then inserts `task_ids` with
/// sequential positions. Silently deduplicates task_ids to satisfy the
/// `UNIQUE(date, task_id)` constraint — the first occurrence wins.
///
/// **This helper is for SYNC-APPLY paths only.** Local writers must use
/// [`materialize_focus_items_with_header_bump`] to keep the parent row's
/// `(version, updated_at)` columns in lockstep with the rebuilt children.
/// Sync-apply callers already update the parent header via
/// [`sync_upsert_current_focus`] from the inbound envelope, so the bare
/// child-only rebuild is correct on that path.
pub fn materialize_focus_items(
    conn: &Connection,
    date: &str,
    task_ids: &[String],
) -> Result<(), StoreError> {
    conn.prepare_cached("DELETE FROM current_focus_items WHERE date = ?1")?
        .execute([date])?;

    let mut stmt = conn.prepare_cached(
        "INSERT INTO current_focus_items (date, position, task_id) VALUES (?1, ?2, ?3)",
    )?;
    let mut seen = HashSet::new();
    let mut position: i64 = 0;
    for task_id in task_ids {
        if seen.insert(task_id.as_str()) {
            stmt.execute(rusqlite::params![date, position, task_id])?;
            position += 1;
        }
    }
    Ok(())
}

/// Local-writer variant of [`materialize_focus_items`] that bumps the
/// parent `current_focus.{version, updated_at}` columns in the same
/// statement sequence so peers and local LWW gates always see the
/// rebuilt children paired with a strictly-newer parent version.
///
/// `materialize_focus_items` alone leaves the parent row
/// stale, which broke two contracts at once:
///
/// * The local LWW gate (`?1 > version`) silently rejects every peer
///   envelope whose HLC is older than the in-memory child rebuild.
/// * Aggregate enqueue stamps the parent via `version_stamp`, but
///   callers that forget to enqueue (or enqueue something else, e.g.
///   the focus_schedule aggregate) leave `current_focus` divergent
///   across devices.
///
/// Use this helper for every local-write path that rebuilds
/// `current_focus_items`. The `version` argument is the freshly-minted
/// HLC the caller will also embed in the outbox envelope; the same
/// string is written verbatim to the parent row so that the subsequent
/// outbox `version_stamp` (which re-stamps at the same HLC) is a
/// benign no-op.
///
/// Sync-apply paths must NOT call this helper — they already write
/// the parent header from the envelope payload via
/// [`sync_upsert_current_focus`], which carries the remote
/// `created_at` / `timezone` columns this helper deliberately does
/// not touch.
pub fn materialize_focus_items_with_header_bump(
    conn: &Connection,
    date: &str,
    task_ids: &[String],
    version: &str,
    now: &str,
) -> Result<(), StoreError> {
    // The parent UPDATE is gated on `?1 >= version` (LWW). The
    // sibling `upsert_current_focus_header` writes a strictly-newer
    // version, then this helper is called immediately after with the
    // SAME version to rebuild children — a benign re-stamp documented
    // by the doc-comment above. The strict `>` form rejected that
    // contracted re-stamp; `>=` accepts it (the UPDATE is a no-op for
    // `version` and a forward bump for `updated_at`) while still
    // rejecting any case where a peer envelope has advanced the row
    // past us between calls. The missing-row case still surfaces as
    // `StaleVersion` so callers don't rebuild orphaned children.
    let rows = conn
        .prepare_cached(
            "UPDATE current_focus SET version = ?1, updated_at = ?2 \
             WHERE date = ?3 AND ?1 >= version",
        )?
        .execute(rusqlite::params![version, now, date])?;
    if rows == 0 {
        return Err(StoreError::StaleVersion {
            entity: "current_focus",
            id: date.to_string(),
        });
    }
    materialize_focus_items(conn, date, task_ids)
}

/// Query task_ids from the current_focus_items sub-table for a given date,
/// returning them in position order.
pub fn query_focus_task_ids(conn: &Connection, date: &str) -> Result<Vec<String>, StoreError> {
    let mut stmt = conn.prepare_cached(
        "SELECT task_id FROM current_focus_items WHERE date = ?1 ORDER BY position ASC",
    )?;
    let rows = stmt.query_map([date], |row| row.get::<_, String>(0))?;
    Ok(rows.collect::<Result<_, rusqlite::Error>>()?)
}

#[cfg(test)]
mod tests;
