//! `memory_revisions` retention GC.
//!
//! Without retention, `memory_revisions` would grow without bound:
//! every `write_memory` appends a row holding up to 100k characters,
//! and an agent that rewrites the same key every few minutes
//! (summary-style memory, evolving preference, running journal) would
//! inflate both the table and the local/remote sync footprint.
//!
//! Retention strategy balances two goals:
//!   1. **Time window**: entries older than `retention_days` are candidates
//!      for GC (matches the `ai_changelog` retention model).
//!   2. **Per-key keep-last-N safeguard**: every key retains at least
//!      `KEEP_LAST_N_PER_KEY` revisions so the "Restore previous value"
//!      feature keeps working even on heavily-churned keys. Without this,
//!      a key that's rewritten once a minute would retain zero history
//!      after a weekend regardless of the user's retention preference.
//!
//! The GC is a pure local-side operation — delete on one device does NOT
//! enqueue a sync envelope, so other devices keep their own history until
//! their next local sweep. This matches `audit_retention`'s per-device
//! semantics.

use rusqlite::Connection;

/// Minimum revisions retained per memory key regardless of age. Protects
/// the Restore feature against aggressively-churned keys. Keep aligned
/// with the UI's history pagination defaults so restoring a "recent"
/// revision always works.
pub const MEMORY_REVISION_KEEP_LAST_N_PER_KEY: u32 = 20;

/// Delete `memory_revisions` rows older than `retention_days` days,
/// subject to the [`MEMORY_REVISION_KEEP_LAST_N_PER_KEY`] per-key
/// safeguard. `None` retention = "forever" (noop). Returns the number
/// of deleted rows.
pub fn gc_memory_revisions_by_retention_days(
    conn: &Connection,
    retention_days: Option<u32>,
) -> Result<u64, rusqlite::Error> {
    let Some(days) = retention_days else {
        return Ok(0);
    };
    let offset = format!("-{days} days");
    let cutoff_iso: String = conn.query_row(
        "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now', ?1)",
        rusqlite::params![offset],
        |r| r.get(0),
    )?;

    gc_memory_revisions_before_cutoff_iso(conn, &cutoff_iso)
}

// Internal testable GC: delete revisions with `created_at < cutoff_iso`,
// subject to the per-key safeguard. Boundary tests pin `cutoff_iso` to
// avoid a moving-`now()` race between row insert and GC (#2805).
fn gc_memory_revisions_before_cutoff_iso(
    conn: &Connection,
    cutoff_iso: &str,
) -> Result<u64, rusqlite::Error> {
    let keep_per_key = MEMORY_REVISION_KEEP_LAST_N_PER_KEY;

    // Delete every revision whose created_at is past the window, EXCEPT
    // the N most-recent revisions per memory_key. The inner CTE numbers
    // revisions newest-first per key; the outer DELETE targets rows
    // whose rank > N AND whose age exceeds the retention window.
    let deleted = conn.execute(
        "DELETE FROM memory_revisions
         WHERE id IN (
             SELECT id FROM (
                 SELECT
                     id,
                     created_at,
                     ROW_NUMBER() OVER (
                         PARTITION BY memory_key
                         ORDER BY created_at DESC, id DESC
                     ) AS rank
                 FROM memory_revisions
             )
             WHERE rank > ?1
               AND created_at < ?2
         )",
        rusqlite::params![keep_per_key, cutoff_iso],
    )?;
    Ok(deleted as u64)
}

#[cfg(test)]
mod tests;
