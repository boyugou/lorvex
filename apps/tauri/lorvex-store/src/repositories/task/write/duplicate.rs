//! DUPLICATE — clone an existing task into a fresh row.
//!
//! Owns the [`duplicate_task`] INSERT-from-source. Differs from
//! [`super::create_task`] in that the column values come from a
//! [`TaskRow`] rather than a [`super::TaskCreateParams`], and several
//! lifecycle columns are intentionally reset (status -> `open`,
//! `raw_input` / `completed_at` / `last_deferred_at`
//! cleared, `defer_count` zeroed) — see the function doc.

use lorvex_domain::naming::STATUS_OPEN;
use rusqlite::{params, Connection};

use crate::error::StoreError;
use crate::repositories::task::read::{task_from_row, TaskRow, TASK_COLUMNS};

/// Duplicate a task from a source `TaskRow`. Copies most fields from the source
/// but resets: raw_input = NULL, status = 'open', completed_at = NULL,
/// last_deferred_at = NULL, defer_count = 0.
///
/// `recurrence_exceptions` is intentionally NOT copied: exceptions
/// (EXDATEs the user has skipped) belong to the original recurrence
/// series. A duplicate represents a freshly-decided new task that
/// happens to share the source's structure — the user has not
/// skipped any of its occurrences yet.
///
/// Tags and dependency copying are handled by the caller after this function.
///
/// Returns the inserted [`TaskRow`] for parity with [`super::create_task`]
/// so callers don't need to re-fetch with `get_task` to surface the
/// canonical row.
#[allow(clippy::too_many_arguments)]
pub fn duplicate_task(
    conn: &Connection,
    source: &TaskRow,
    new_id: &str,
    new_title: &str,
    recurrence_group_id: Option<&str>,
    canonical_occurrence_date: Option<&str>,
    version: &str,
    now: &str,
) -> Result<TaskRow, StoreError> {
    // RETURNING the inserted row in a single round-trip avoids the
    // separate `get_task()` SELECT this function pay.
    let sql = format!(
        "INSERT INTO tasks \
         (id, title, body, raw_input, ai_notes, status, list_id, priority, \
          due_date, due_time, estimated_minutes, \
          recurrence, recurrence_group_id, canonical_occurrence_date, \
          planned_date, version, created_at, updated_at, \
          completed_at, last_deferred_at, defer_count) \
         VALUES (?1, ?2, ?3, NULL, ?4, ?5, ?6, ?7, ?8, ?9, ?10, \
                 ?11, ?12, ?13, NULL, ?14, ?15, ?15, NULL, NULL, 0) \
         RETURNING {TASK_COLUMNS}"
    );
    let row = conn.prepare_cached(&sql)?.query_row(
        params![
            new_id,
            new_title,
            source.core.body.as_deref(),
            source.core.ai_notes.as_deref(),
            STATUS_OPEN,
            &source.core.list_id,
            source.core.priority,
            source.scheduling.due.date(),
            source.scheduling.due.time(),
            source.scheduling.estimated_minutes,
            source.recurrence.recurrence.as_deref(),
            recurrence_group_id,
            canonical_occurrence_date,
            version,
            now,
        ],
        task_from_row,
    )?;
    Ok(row)
}
