//! Shared reminder query repository — due and upcoming task reminders.
//!
//! Canonical query owner for both MCP and Tauri. Joins
//! `task_reminder_delivery_state` to filter by `delivery_state = 'pending'`
//! (the authoritative device-local delivery gate).

use lorvex_domain::time::{Date, SyncTimestamp};
use lorvex_domain::TaskId;
use rusqlite::{params, Connection};

use crate::error::StoreError;

#[cfg(test)]
mod tests;

/// A single reminder row joined with its parent task's key fields
/// and device-local delivery state.
///
/// `reminder_at` / `dismissed_at` /
/// `cancelled_at` / `created_at` are typed `SyncTimestamp` (so the
/// sync-timestamp invariant is type-system enforced; see
/// [`SyncTimestamp`]'s docs), and `task_due_date` is a typed
/// [`Date`] (`YYYY-MM-DD` format invariant enforced at construction).
/// Wire format is unchanged — both newtypes serialize as the same
/// canonical string the column was always written with, so JSON / sync
/// envelopes / SQLite columns stay byte-identical.
#[derive(Debug, Clone, serde::Serialize)]
pub struct ReminderRow {
    pub id: String,
    pub task_id: String,
    pub reminder_at: SyncTimestamp,
    pub dismissed_at: Option<SyncTimestamp>,
    pub cancelled_at: Option<SyncTimestamp>,
    pub created_at: SyncTimestamp,
    pub delivery_state: String,
    pub task_title: String,
    pub task_status: String,
    pub task_due_date: Option<Date>,
    pub task_priority: Option<i64>,
}

/// Result envelope for reminder queries, including pagination metadata.
#[derive(Debug, Clone, serde::Serialize)]
pub struct ReminderQueryResult {
    pub rows: Vec<ReminderRow>,
    pub total_matching: i64,
}

fn reminder_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<ReminderRow> {
    Ok(ReminderRow {
        id: row.get(0)?,
        task_id: row.get(1)?,
        reminder_at: row.get(2)?,
        dismissed_at: row.get(3)?,
        cancelled_at: row.get(4)?,
        created_at: row.get(5)?,
        delivery_state: row.get(6)?,
        task_title: row.get(7)?,
        task_status: row.get(8)?,
        task_due_date: row.get(9)?,
        task_priority: row.get(10)?,
    })
}

/// Get reminders that are currently due (`reminder_at <= now`).
///
/// Only includes reminders for open tasks where:
/// - `cancelled_at IS NULL` (not cancelled by lifecycle transition)
/// - `dismissed_at IS NULL` (not dismissed by user)
/// - `delivery_state = 'pending'` (not yet fired/snoozed)
pub fn get_due_task_reminders(
    conn: &Connection,
    now: &str,
    limit: u32,
) -> Result<ReminderQueryResult, StoreError> {
    // the adaptive reminder poller fires every few
    // seconds; the earlier separate COUNT doubled the scan cost.
    // Query `LIMIT+1` rows instead — if we got back more than the
    // caller asked for, the result is truncated. `total_matching`
    // becomes "at least the rows we returned" in the non-truncated
    // case and is a sentinel -1 in the truncated case so callers
    // can distinguish "exactly N" from "≥ limit". MCP toolchain
    // handles the -1 branch explicitly.
    let fetch_limit = limit.saturating_add(1);
    let mut stmt = conn.prepare_cached(
        "SELECT tr.id, tr.task_id, tr.reminder_at, tr.dismissed_at, tr.cancelled_at, \
                tr.created_at, \
                COALESCE(ds.delivery_state, 'pending') AS delivery_state, \
                t.title, t.status, t.due_date, t.priority \
         FROM task_reminders tr \
         JOIN tasks t ON tr.task_id = t.id \
         LEFT JOIN task_reminder_delivery_state ds ON ds.reminder_id = tr.id \
         WHERE t.status = 'open' \
           AND t.archived_at IS NULL \
           AND tr.cancelled_at IS NULL \
           AND tr.dismissed_at IS NULL \
           AND COALESCE(ds.delivery_state, 'pending') = 'pending' \
           AND tr.reminder_at <= ?1 \
         ORDER BY tr.reminder_at ASC, tr.id ASC \
         LIMIT ?2",
    )?;
    let mut rows: Vec<_> = stmt
        .query_map(params![now, fetch_limit], reminder_from_row)?
        .collect::<Result<_, _>>()?;

    // compare in `usize` rather than casting `rows.len()`
    // down to `u32`. On 64-bit platforms `rows.len()` is `usize` and
    // `as u32` truncates silently when the SELECT returns more than
    // `u32::MAX` rows; comparing `len > limit as usize` is exact for
    // any limit and matches clippy's `cast-possible-truncation` lint.
    let truncated = rows.len() > limit as usize;
    if truncated {
        rows.truncate(limit as usize);
    }
    let total_matching = if truncated { -1 } else { rows.len() as i64 };

    Ok(ReminderQueryResult {
        rows,
        total_matching,
    })
}

/// Shared owner of "all reminders for a task" reads. Joins `tasks`
/// so trashed (`archived_at IS NOT NULL`) parents are excluded from
/// the result. MCP and Tauri share this single helper so the filter
/// applies uniformly; a bare `task_reminders` query on either
/// surface would return reminders for trashed tasks while the
/// notification poller (`get_due_task_reminders` /
/// `get_upcoming_task_reminders_until`) correctly skips them, and
/// the drift would surface as the task-detail view rendering
/// reminders for a task that no longer existed in the user's lists.
///
/// Ordered by `reminder_at ASC, id ASC` for stable pagination /
/// rendering across re-fetches.
pub fn get_reminders_for_task(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<Vec<ReminderRow>, StoreError> {
    let mut stmt = conn.prepare_cached(
        "SELECT tr.id, tr.task_id, tr.reminder_at, tr.dismissed_at, tr.cancelled_at, \
                tr.created_at, \
                COALESCE(ds.delivery_state, 'pending') AS delivery_state, \
                t.title, t.status, t.due_date, t.priority \
         FROM task_reminders tr \
         JOIN tasks t ON tr.task_id = t.id \
         LEFT JOIN task_reminder_delivery_state ds ON ds.reminder_id = tr.id \
         WHERE tr.task_id = ?1 \
           AND t.archived_at IS NULL \
         ORDER BY tr.reminder_at ASC, tr.id ASC",
    )?;
    let rows: Vec<_> = stmt
        .query_map(params![task_id], reminder_from_row)?
        .collect::<Result<_, _>>()?;
    Ok(rows)
}

/// Get reminders due within an exact timestamp window (`now < reminder_at <= horizon`).
///
/// This is the canonical shared owner for upcoming reminder queries.
/// Both MCP (hours-based) and Tauri (seconds-based) adapters compute
/// their own `horizon` timestamp and call this function.
pub fn get_upcoming_task_reminders_until(
    conn: &Connection,
    now: &str,
    horizon: &str,
    limit: u32,
) -> Result<ReminderQueryResult, StoreError> {
    // same LIMIT+1 truncation-detection pattern as the
    // due-reminders query above. Drops a full scan on every
    // adaptive-poller tick.
    let fetch_limit = limit.saturating_add(1);
    let mut stmt = conn.prepare_cached(
        "SELECT tr.id, tr.task_id, tr.reminder_at, tr.dismissed_at, tr.cancelled_at, \
                tr.created_at, \
                COALESCE(ds.delivery_state, 'pending') AS delivery_state, \
                t.title, t.status, t.due_date, t.priority \
         FROM task_reminders tr \
         JOIN tasks t ON tr.task_id = t.id \
         LEFT JOIN task_reminder_delivery_state ds ON ds.reminder_id = tr.id \
         WHERE t.status = 'open' \
           AND t.archived_at IS NULL \
           AND tr.cancelled_at IS NULL \
           AND tr.dismissed_at IS NULL \
           AND COALESCE(ds.delivery_state, 'pending') = 'pending' \
           AND tr.reminder_at > ?1 \
           AND tr.reminder_at <= ?2 \
         ORDER BY tr.reminder_at ASC, tr.id ASC \
         LIMIT ?3",
    )?;
    let mut rows: Vec<_> = stmt
        .query_map(params![now, horizon, fetch_limit], reminder_from_row)?
        .collect::<Result<_, _>>()?;

    // compare in `usize` rather than casting `rows.len()`
    // down to `u32`. On 64-bit platforms `rows.len()` is `usize` and
    // `as u32` truncates silently when the SELECT returns more than
    // `u32::MAX` rows; comparing `len > limit as usize` is exact for
    // any limit and matches clippy's `cast-possible-truncation` lint.
    let truncated = rows.len() > limit as usize;
    if truncated {
        rows.truncate(limit as usize);
    }
    let total_matching = if truncated { -1 } else { rows.len() as i64 };

    Ok(ReminderQueryResult {
        rows,
        total_matching,
    })
}
