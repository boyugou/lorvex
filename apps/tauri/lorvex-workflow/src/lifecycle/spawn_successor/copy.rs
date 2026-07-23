//! Copy parent-task children onto the successor:
//!   * `task_tags` edges (idempotent INSERT OR IGNORE so a tag the
//!     parent shared with another task doesn't fail the copy).
//!   * `task_checklist_items` (new UUIDv7 per item, reset
//!     `completed_at` to NULL).
//!   * `task_reminders` (new UUIDv7, recomputed `reminder_at` based
//!     on `(parent_reminder_at - parent_due_date) + successor_due_date`;
//!     only future occurrences are copied).
//!
//! Each helper hoists its INSERT prepare out of the per-row loop so
//! a recurring task with N tags / M checklist items / R reminders
//! pays one prepare/parse total instead of N + M + R.

use rusqlite::{params, Connection};

use lorvex_store::StoreError;

use crate::reminder_anchor::resolve_task_reminder_local_anchor_for_utc;

use super::super::snapshot::TaskSnapshot;
use super::super::types::CopiedTagEdge;

pub(super) fn copy_task_tags(
    conn: &Connection,
    parent_id: &str,
    successor_id: &str,
    version: &str,
    now: &str,
) -> Result<Vec<CopiedTagEdge>, StoreError> {
    conn.prepare_cached(
        "INSERT OR IGNORE INTO task_tags (task_id, tag_id, version, created_at)
         SELECT ?1, tag_id, ?2, ?3 FROM task_tags WHERE task_id = ?4",
    )?
    .execute(params![successor_id, version, now, parent_id])?;
    let copied_tags: Vec<CopiedTagEdge> = conn
        .prepare_cached("SELECT tag_id FROM task_tags WHERE task_id = ?1")
        .and_then(|mut stmt| {
            let rows = stmt.query_map(params![successor_id], |row| row.get::<_, String>(0))?;
            rows.collect::<Result<Vec<_>, _>>()
        })?
        .into_iter()
        .map(|tag_id| CopiedTagEdge {
            task_id: successor_id.to_string(),
            tag_id,
            version: version.to_string(),
            created_at: now.to_string(),
        })
        .collect();
    Ok(copied_tags)
}

pub(super) fn copy_checklist_items(
    conn: &Connection,
    parent_id: &str,
    successor_id: &str,
    version: &str,
    now: &str,
) -> Result<Vec<String>, StoreError> {
    let parent_items: Vec<(i64, String)> = conn
        .prepare_cached(
            "SELECT position, text FROM task_checklist_items WHERE task_id = ?1 ORDER BY position ASC",
        )?
        .query_map(params![parent_id], |row| Ok((row.get(0)?, row.get(1)?)))?
        .collect::<Result<Vec<_>, _>>()?;
    // Lift the per-item INSERT prepare out of the loop.
    // every checklist item paid a fresh prepare/parse on every
    // recurrence rollover; the cached statement amortizes across
    // all items the parent had.
    let mut insert_item = conn.prepare_cached(
        "INSERT INTO task_checklist_items (id, task_id, position, text, completed_at, version, created_at, updated_at)
         VALUES (?1, ?2, ?3, ?4, NULL, ?5, ?6, ?6)",
    )?;
    let mut copied_checklist_item_ids: Vec<String> = Vec::with_capacity(parent_items.len());
    for (position, text) in parent_items {
        let item_id = lorvex_domain::new_entity_id_string();
        insert_item.execute(params![item_id, successor_id, position, text, version, now])?;
        copied_checklist_item_ids.push(item_id);
    }
    Ok(copied_checklist_item_ids)
}

/// Copy parent-active reminders onto the successor, preserving each
/// reminder's offset relative to the parent's `due_date`. Each copied
/// reminder gets a new UUIDv7, new version, and a recomputed
/// `reminder_at` based on
/// `(parent_reminder_at - parent_due_date) + successor_due_date`. Only
/// reminders whose recomputed time is in the future are copied.
///
/// Audit (silent-failure-hunter):
/// swallowed via `if let Ok(_)`, so a corrupt stored timestamp (or a
/// bug producing a malformed `next_due_date`) would silently spawn a
/// reminder-less successor with no signal to the user. Each parse now
/// surfaces as `StoreError::Validation`. The `parent_due_date` and
/// stored `reminder_at` rows came through validated write paths so
/// failure here implies on-disk corruption; `next_due_date` and `now`
/// are computed by sibling code so failure implies an upstream bug.
pub(super) fn copy_reminders(
    conn: &Connection,
    snap: &TaskSnapshot,
    successor_id: &str,
    next_due_date: &str,
    parent_active_reminder_times: &[String],
    version: &str,
    now: &str,
) -> Result<Vec<String>, StoreError> {
    let mut copied_reminder_ids: Vec<String> =
        Vec::with_capacity(parent_active_reminder_times.len());
    // Same loop-hoisting argument as the checklist-items INSERT
    // above: a recurring task with N reminders pays one
    // prepare/parse instead of N. The prepared statement is consumed
    // at the bottom of the function so it doesn't leak past the
    // local scope.
    let mut insert_reminder = conn.prepare_cached(
        "INSERT INTO task_reminders (
            id, task_id, reminder_at, original_local_time, original_tz,
            dismissed_at, cancelled_at, version, created_at
         )
         VALUES (?1, ?2, ?3, ?4, ?5, NULL, NULL, ?6, ?7)",
    )?;
    let Some(parent_due) = snap.due_date else {
        return Ok(copied_reminder_ids);
    };
    // Use the typed `Date`'s `NaiveDate` directly for offset
    // computation — no string round-trip needed.
    let parent_due_dt = parent_due
        .as_naive_date()
        .and_hms_opt(0, 0, 0)
        .expect("0:0:0 is always a valid time-of-day")
        .and_utc();
    let successor_due_dt = lorvex_domain::time::parse_iso_date(next_due_date)?
        .and_hms_opt(0, 0, 0)
        .expect("0:0:0 is always a valid time-of-day")
        .and_utc();

    let now_dt = chrono::DateTime::parse_from_rfc3339(now)
        .map(|dt| dt.with_timezone(&chrono::Utc))
        .map_err(|e| {
            StoreError::Validation(format!(
                "spawn_successor: corrupt `now` timestamp {now:?}: {e}"
            ))
        })?;

    for reminder_at_str in parent_active_reminder_times {
        let reminder_dt = chrono::DateTime::parse_from_rfc3339(reminder_at_str)
            .map_err(|e| {
                StoreError::Validation(format!(
                    "spawn_successor: corrupt parent reminder_at {reminder_at_str:?}: {e}"
                ))
            })?
            .with_timezone(&chrono::Utc);
        // Compute offset: how far before/after the parent's due_date start-of-day.
        let offset = reminder_dt.signed_duration_since(parent_due_dt);
        // Apply same offset to successor's due_date.
        let successor_reminder_dt = successor_due_dt + offset;

        // Only copy if the computed reminder time is in the future.
        if successor_reminder_dt <= now_dt {
            continue;
        }

        let reminder_id = lorvex_domain::new_entity_id_string();
        // Canonical millisecond `Z` form for lex-compat with the
        // polling query cutoffs (R12/R13). Previously
        // this used `SecondsFormat::Secs` so a row
        // stored at exactly `15:00:00Z` would briefly
        // fail to match a fractional cutoff.
        let successor_reminder_at = lorvex_domain::format_sync_timestamp(successor_reminder_dt);
        let (original_local_time, original_tz) =
            resolve_task_reminder_local_anchor_for_utc(conn, &successor_reminder_dt)?;
        insert_reminder.execute(params![
            reminder_id,
            successor_id,
            successor_reminder_at,
            original_local_time,
            original_tz,
            version,
            now
        ])?;
        copied_reminder_ids.push(reminder_id);
    }
    Ok(copied_reminder_ids)
}
