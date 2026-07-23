//! Restore path for a deleted list row (#3420).
//!
//! INSERT OR REPLACE writes a fresh HLC-minted version so peers running
//! LWW prefer the restored row over the delete tombstone, then enqueues
//! a single upsert envelope. `delete_list` already rejects deletion of
//! any list still holding assigned tasks, so there are no edge rows to
//! replay.

use rusqlite::params;

use crate::commands::{enqueue_list_upsert, fetch_list_by_id, TaskList};
use crate::error::{AppError, AppResult};

/// Restore a list from its pre-delete snapshot. Mints a fresh HLC and
/// emits the upsert envelope inside the caller's transaction.
pub(super) fn restore_list(
    conn: &rusqlite::Connection,
    list: &TaskList,
    now: &str,
) -> AppResult<TaskList> {
    let version = crate::hlc::generate_version_result()?;
    insert_or_replace_list(conn, list, &version, now)?;
    let restored = fetch_list_by_id(conn, &list.id)?
        .ok_or_else(|| AppError::Internal(format!("list {} disappeared after restore", list.id)))?;
    enqueue_list_upsert(conn, &restored)?;
    Ok(restored)
}

fn insert_or_replace_list(
    conn: &rusqlite::Connection,
    list: &TaskList,
    version: &str,
    now: &str,
) -> AppResult<()> {
    // `created_at` comes from the snapshot's original value (#3434).
    // `updated_at` is bound to `now` so the restored row's
    // last-touched moment reflects the undo.
    conn.prepare_cached(
        "INSERT OR REPLACE INTO lists \
         (id, name, color, icon, description, ai_notes, created_at, updated_at, version) \
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
    )
    .map_err(AppError::from)?
    .execute(params![
        list.id,
        list.name,
        list.color,
        list.icon,
        list.description,
        list.ai_notes,
        list.created_at,
        now,
        version,
    ])
    .map_err(AppError::from)?;
    Ok(())
}
