//! Typed `sync_checkpoints` accessors. Replaces ~20 ad-hoc raw-SQL
//! upsert sites across `app/src-tauri` and tests with a single
//! API.
//!
//! `sync_checkpoints` is a key-value table that stores per-device
//! sync runtime state — `device_id`, last error, last success at,
//! reseed flags, etc. The table is local-only (NOT in
//! `ALL_SYNCABLE_TYPES`) and rows are updated on every sync cycle,
//! so the upsert path is hot. The previous shape duplicated
//! `INSERT ... ON CONFLICT DO UPDATE` boilerplate at each site;
//! centralizing eliminates the chance of one site doing the upsert
//! in a non-busy-retry path while another site does it inside a
//! transaction.
//!
//! All helpers take `&Connection` so they compose freely inside
//! `with_immediate_transaction` / `with_savepoint` blocks. Sites
//! that need busy-retry should wrap the call exactly as they did
//! around the previous raw SQL.

use rusqlite::{Connection, OptionalExtension};

use crate::error::RuntimeResult;

// ── Well-known checkpoint keys ──────────────────────────────────────
//
// These are the keys that have explicit constants today across the
// app. Centralizing them here means a future rename touches one site
// instead of fan-out grepping. Per-key meaning lives next to each
// constant rather than in one table — the comments stay closer to
// the call sites that read them.

/// The stable, per-install device identity. Seeded by
/// [`crate::device_identity::get_or_create_device_id`] and never
/// rewritten thereafter; HLC suffixes are derived from this value.
pub const KEY_DEVICE_ID: &str = "device_id";

/// Wall-clock timestamp of the last *successful* sync round-trip.
/// Used by the UI to render "synced N minutes ago" copy.
pub const KEY_LAST_SUCCESS_AT: &str = "last_success_at";

/// Most recent sync error message, with a `[timestamp]` prefix. The
/// row is deleted on the next successful sync so the UI surfaces a
/// cleared error rather than a stale one.
pub const KEY_LAST_ERROR: &str = "last_error";

/// Set to the literal string `"1"` once `seed_full_sync` has run.
/// Guards against re-seeding into a populated outbox.
pub const KEY_FULL_SYNC_SEEDED: &str = "full_sync_seeded";

/// Set to `"true"` when the local device must drop and re-seed its
/// data from the cloud (e.g. tombstone watermark expired before this
/// device pulled). Honored by `lorvex_workflow::reseed`.
pub const KEY_RESEED_REQUIRED: &str = "reseed_required";

// ── CRUD helpers ────────────────────────────────────────────────────

/// Read a checkpoint value. `Ok(None)` for missing keys.
pub fn get(conn: &Connection, key: &str) -> RuntimeResult<Option<String>> {
    let value = conn
        .query_row(
            "SELECT value FROM sync_checkpoints WHERE key = ?1",
            [key],
            |row| row.get::<_, String>(0),
        )
        .optional()?;
    Ok(value)
}

/// Upsert a checkpoint value. Atomically inserts or updates so two
/// concurrent writers can't race between an `INSERT` and a separate
/// `UPDATE` — `ON CONFLICT(key) DO UPDATE` collapses both shapes
/// into a single statement.
pub fn set(conn: &Connection, key: &str, value: &str) -> RuntimeResult<()> {
    conn.execute(
        "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2) \
         ON CONFLICT(key) DO UPDATE SET value = excluded.value",
        [key, value],
    )?;
    Ok(())
}

/// Delete a checkpoint key. Returns `true` if a row was deleted,
/// `false` if the key was already absent.
pub fn clear(conn: &Connection, key: &str) -> RuntimeResult<bool> {
    let changed = conn.execute("DELETE FROM sync_checkpoints WHERE key = ?1", [key])?;
    Ok(changed > 0)
}

/// Set only if the key is currently absent (atomic claim).
/// Returns `true` if the value was newly inserted, `false` if the
/// key already existed (in which case `value` is unchanged).
///
/// Backed by `INSERT ... ON CONFLICT DO NOTHING RETURNING value`,
/// which collapses the conditional insert + readback into a single
/// busy-retry-eligible statement (#2925-M9 pattern).
pub fn set_if_absent(conn: &Connection, key: &str, value: &str) -> RuntimeResult<bool> {
    let inserted: Option<String> = conn
        .query_row(
            "INSERT INTO sync_checkpoints (key, value) VALUES (?1, ?2) \
             ON CONFLICT(key) DO NOTHING \
             RETURNING value",
            [key, value],
            |row| row.get::<_, String>(0),
        )
        .optional()?;
    Ok(inserted.is_some())
}

#[cfg(test)]
mod tests;
