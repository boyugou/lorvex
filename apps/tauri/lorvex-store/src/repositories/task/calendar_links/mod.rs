//! Task-calendar-event link repository — shared CRUD operations for the
//! `task_calendar_event_links` table.
//!
//! Used by both the Tauri app and the MCP server. Callers own their own
//! side-effects (changelog logging, sync outbox enqueuing, event bus).

use crate::error::StoreError;
use lorvex_domain::time::SyncTimestamp;
use lorvex_domain::{EventId, TaskId};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};

use super::super::parse_sync_timestamp_column;

// ---------------------------------------------------------------------------
// Link struct
// ---------------------------------------------------------------------------

/// A row from `task_calendar_event_links`.
///
/// `created_at` and `updated_at` are now [`SyncTimestamp`]
/// rather than bare `String`. Same rationale as `MemoryEntry::updated_at`
/// — every consumer that ordered or compared link rows lex-
/// compare strings, which silently misorders when one device emits 3-
/// fractional-digit timestamps and another emits 6. JSON wire shape is
/// byte-stable because `SyncTimestamp` always emits the canonical
/// millisecond-Z form regardless of input precision; both `Serialize`
/// and `Deserialize` round-trip losslessly with that form.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TaskCalendarEventLink {
    pub task_id: String,
    pub calendar_event_id: String,
    pub version: String,
    pub created_at: SyncTimestamp,
    pub updated_at: SyncTimestamp,
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Column list used in SELECT queries. Must match field order in
/// [`link_from_row`].
pub const SELECT_COLS: &str = "task_id, calendar_event_id, version, created_at, updated_at";

// ---------------------------------------------------------------------------
// Row mapping
// ---------------------------------------------------------------------------

/// Map a `rusqlite::Row` (selected with [`SELECT_COLS`]) to a
/// [`TaskCalendarEventLink`].
fn link_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<TaskCalendarEventLink> {
    Ok(TaskCalendarEventLink {
        task_id: row.get(0)?,
        calendar_event_id: row.get(1)?,
        version: row.get(2)?,
        created_at: parse_sync_timestamp_column(row, 3, "task_calendar_event_links", "created_at")?,
        updated_at: parse_sync_timestamp_column(row, 4, "task_calendar_event_links", "updated_at")?,
    })
}

// ---------------------------------------------------------------------------
// Read operations
// ---------------------------------------------------------------------------

/// Read a single link by its composite primary key.
///
/// callers that need a pre-delete snapshot
/// before unlinking use this helper to capture the row in scope.
/// Returns `None` if the edge doesn't exist.
pub fn get_link(
    conn: &Connection,
    task_id: &TaskId,
    calendar_event_id: &EventId,
) -> Result<Option<TaskCalendarEventLink>, StoreError> {
    let query = format!(
        "SELECT {SELECT_COLS} FROM task_calendar_event_links \
         WHERE task_id = ?1 AND calendar_event_id = ?2"
    );
    Ok(conn
        .query_row(&query, params![task_id, calendar_event_id], link_from_row)
        .optional()?)
}

/// Return all links for a given task, ordered by `created_at`.
pub fn get_links_for_task(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<Vec<TaskCalendarEventLink>, StoreError> {
    let query = format!(
        "SELECT {SELECT_COLS} FROM task_calendar_event_links WHERE task_id = ?1 ORDER BY created_at, calendar_event_id"
    );
    let mut stmt = conn.prepare_cached(&query)?;
    let links = stmt
        .query_map(params![task_id], link_from_row)?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(links)
}

/// Return all links for a given calendar event, ordered by `created_at`.
pub fn get_links_for_event(
    conn: &Connection,
    event_id: &EventId,
) -> Result<Vec<TaskCalendarEventLink>, StoreError> {
    let query = format!(
        "SELECT {SELECT_COLS} FROM task_calendar_event_links WHERE calendar_event_id = ?1 ORDER BY created_at, task_id"
    );
    let mut stmt = conn.prepare_cached(&query)?;
    let links = stmt
        .query_map(params![event_id], link_from_row)?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(links)
}

// ---------------------------------------------------------------------------
// Write operations
// ---------------------------------------------------------------------------

/// Insert (or update on conflict) a link between a task and a calendar event.
///
/// Returns `(link, applied)`. `applied` is `true` when a row was inserted or
/// the LWW gate accepted the UPDATE; `false` when the existing row's version
/// was strictly newer than `version` and the UPSERT became a no-op. The
/// reloaded `TaskCalendarEventLink` always reflects the row currently in the
/// table — newer when applied, untouched when not.
///
/// gates the conflict UPDATE on
/// `excluded.version > task_calendar_event_links.version` so a stale local
/// stamp racing an in-flight peer write cannot regress the link's HLC. The
/// caller is responsible for verifying that both the task and event exist,
/// logging to `ai_changelog`, and enqueuing sync outbox entries — but should
/// short-circuit the changelog/outbox path when `applied` is `false`.
pub fn insert_link(
    conn: &Connection,
    task_id: &TaskId,
    event_id: &EventId,
    version: &str,
    now: &str,
) -> Result<(TaskCalendarEventLink, bool), StoreError> {
    let changes = conn.prepare_cached(
        "INSERT INTO task_calendar_event_links (task_id, calendar_event_id, version, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, ?4)
         ON CONFLICT(task_id, calendar_event_id) DO UPDATE SET
           version = excluded.version,
           updated_at = excluded.updated_at
         WHERE excluded.version > task_calendar_event_links.version",
    )?
    .execute(params![task_id, event_id, version, now])?;

    let query = format!(
        "SELECT {SELECT_COLS} FROM task_calendar_event_links WHERE task_id = ?1 AND calendar_event_id = ?2"
    );
    let link = conn
        .prepare_cached(&query)?
        .query_row(params![task_id, event_id], link_from_row)?;
    Ok((link, changes > 0))
}

/// Delete a link between a task and a calendar event.
///
/// Returns the number of rows actually deleted (0 or 1 — the composite
/// primary key guarantees at most one match). Aligned with
/// the `usize` shape now used by every other `delete_*` repo helper so
/// callers can branch on `deleted == 0` consistently. The caller is
/// responsible for changelog logging and sync outbox handling.
pub fn delete_link(
    conn: &Connection,
    task_id: &TaskId,
    event_id: &EventId,
) -> Result<usize, StoreError> {
    Ok(conn
        .prepare_cached(
            "DELETE FROM task_calendar_event_links WHERE task_id = ?1 AND calendar_event_id = ?2",
        )?
        .execute(params![task_id, event_id])?)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests;
