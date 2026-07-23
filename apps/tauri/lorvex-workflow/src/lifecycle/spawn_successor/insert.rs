//! Insert the successor task row. Inherits structural fields
//! (title, body, recurrence rule, scheduling fields) AND
//! content-shaped notes (`ai_notes`)
//! from the parent. Excluded by design:
//!
//! - `raw_input` — request-scoped to the original capture.
//! - `recurrence_exceptions` — EXDATEs belong to the parent series;
//!   the successor is the next occurrence, not a new series.
//! - `defer_count`, `last_defer_reason`, `last_deferred_at` — each
//!   occurrence has its own deferral history (`defer_count` reset
//!   to 0).
//! - `completed_at` — successor starts fresh.
//!
//! `ai_notes` are preserved so recurring-task context doesn't drop on
//! every spawn boundary.

use rusqlite::{params, Connection};

use lorvex_store::StoreError;

use super::super::snapshot::TaskSnapshot;

/// Compute the successor's `planned_date` so the offset from the
/// parent's `canonical_occurrence_date` is preserved. The cadence
/// anchor (rather than `due_date`) is the right reference because
/// it never moves under deferral. Example: `planned_date = Thursday`,
/// `canonical = Sunday` → offset = -3 days. Successor:
/// `next_due_date - 3 = next Thursday`.
pub(super) fn compute_successor_planned_date(
    snap: &TaskSnapshot,
    next_due_date: &str,
) -> Option<String> {
    let parent_planned = snap.planned_date?;
    let anchor = snap.canonical_occurrence_date?;
    let next_due_nd = lorvex_domain::time::parse_iso_date(next_due_date).ok()?;
    let offset_days = (parent_planned.as_naive_date() - anchor.as_naive_date()).num_days();
    let result = next_due_nd + chrono::Duration::days(offset_days);
    Some(result.format("%Y-%m-%d").to_string())
}

/// Compute the successor's `available_from` (defer-until) so the offset
/// from the parent's `canonical_occurrence_date` is preserved, exactly
/// as [`compute_successor_planned_date`] does for `planned_date`. Mirrors
/// the Apple app's `computeSuccessorAvailableFrom`: a parent whose
/// defer-until sits 2 days before its cadence anchor keeps a successor
/// whose defer-until sits 2 days before the next occurrence. `None` when
/// the parent has no `available_from` (or the dates don't parse).
pub(super) fn compute_successor_available_from(
    snap: &TaskSnapshot,
    next_due_date: &str,
) -> Option<String> {
    let parent_available_from = snap.available_from?;
    let anchor = snap.canonical_occurrence_date?;
    let next_due_nd = lorvex_domain::time::parse_iso_date(next_due_date).ok()?;
    let offset_days = (parent_available_from.as_naive_date() - anchor.as_naive_date()).num_days();
    let result = next_due_nd + chrono::Duration::days(offset_days);
    Some(result.format("%Y-%m-%d").to_string())
}

pub(super) struct InsertSuccessorParams<'a> {
    pub parent_id: &'a str,
    pub successor_id: &'a str,
    pub next_due_date: &'a str,
    pub spawned_recurrence: &'a str,
    pub spawned_group_id: Option<&'a str>,
    pub instance_key: Option<&'a str>,
    pub successor_planned_date: Option<&'a str>,
    pub successor_available_from: Option<&'a str>,
    pub version: &'a str,
    pub now: &'a str,
}

pub(super) fn insert_successor_row(
    conn: &Connection,
    params: InsertSuccessorParams<'_>,
) -> Result<(), StoreError> {
    conn.prepare_cached(
        "INSERT INTO tasks (
            id, title, body, ai_notes,
            status, list_id, priority,
            due_date, planned_date, available_from, canonical_occurrence_date, due_time,
            estimated_minutes, recurrence, recurrence_group_id,
            recurrence_instance_key, spawned_from,
            version, created_at, updated_at, defer_count
        ) SELECT
            ?1, title, body, ai_notes,
            'open', list_id, priority,
            ?2, ?10, ?11, ?2, due_time,
            estimated_minutes, ?3, ?9,
            ?4, ?5,
            ?6, ?7, ?7, 0
        FROM tasks WHERE id = ?8",
    )?
    .execute(params![
        params.successor_id,
        params.next_due_date,
        params.spawned_recurrence,
        params.instance_key,
        params.parent_id,
        params.version,
        params.now,
        params.parent_id,
        params.spawned_group_id,
        params.successor_planned_date,
        params.successor_available_from,
    ])?;
    Ok(())
}
