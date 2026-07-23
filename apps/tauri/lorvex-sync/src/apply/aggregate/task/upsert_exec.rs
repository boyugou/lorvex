//! SQL binding for the task upsert path.
//!
//! Once the row builder has produced a fully-typed [`TaskRow`], the
//! only work left at the binding edge is naming each column in a
//! `named_params!` block. Splitting that into UPDATE vs INSERT
//! variants keeps the dispatch in [`super`] focused on row-existence
//! routing and the recurrence-instance-key dedup hook.

use rusqlite::{named_params, Connection};

use super::super::super::LwwTieBreak;
use super::super::ApplyError;
use super::row_build::TaskRow;
use super::update_sql::{task_update_sql, TASK_INSERT_SQL};

/// Run the partial-update UPDATE against an existing row. Every
/// nullable column is gated with its `:col_present` flag so absence
/// preserves the existing value instead of clobbering it.
///
/// The SQL takes exactly one of two shapes: the trailing
/// `WHERE id = :id AND :version > version` (RejectEqual) or
/// `WHERE id = :id AND :version >= version` (AllowEqual). Both
/// shapes are render-once via `OnceLock` and reused across every
/// task upsert;
/// `format!` allocation against this 44-line UPDATE even though the
/// resulting bytes were identical to the prior call.
///
/// `prepare_cached(sql)` keys on the SQL text; both shapes hit the
/// connection's cache after the first envelope of each tie-break
/// flavor.
pub(super) fn execute_task_update(
    conn: &Connection,
    row: &TaskRow,
    allow_equal_versions: LwwTieBreak,
) -> Result<(), ApplyError> {
    let sql = task_update_sql(allow_equal_versions);
    conn.prepare_cached(sql)?.execute(named_params! {
        // bind the typed `TaskId` directly via the rusqlite ToSql
        // impl on the newtype — no `.as_str()` allocation, and the
        // typed id is the only path that reaches the SQL layer.
        ":id": &row.entity_id,
        ":title": row.title,
        ":body": row.body,
        ":body_present": row.body_present,
        ":raw_input": row.raw_input,
        ":raw_input_present": row.raw_input_present,
        ":ai_notes": row.ai_notes,
        ":ai_notes_present": row.ai_notes_present,
        ":status": row.status,
        ":list_id": row.list_id,
        ":priority": row.priority,
        ":priority_present": row.priority_present,
        ":due_date": row.due_date,
        ":due_date_present": row.due_date_present,
        ":due_time": row.due_time,
        ":due_time_present": row.due_time_present,
        ":estimated_minutes": row.estimated_minutes,
        ":estimated_minutes_present": row.estimated_minutes_present,
        ":recurrence": row.recurrence,
        ":recurrence_present": row.recurrence_present,
        ":spawned_from": row.spawned_from,
        ":spawned_from_present": row.spawned_from_present,
        ":recurrence_group_id": row.recurrence_group_id,
        ":recurrence_group_id_present": row.recurrence_group_id_present,
        ":canonical_occurrence_date": row.canonical_occurrence_date,
        ":canonical_occurrence_date_present": row.canonical_occurrence_date_present,
        ":created_at": row.created_at,
        ":updated_at": row.updated_at,
        ":completed_at": row.completed_at,
        ":completed_at_present": row.completed_at_present,
        ":last_deferred_at": row.last_deferred_at,
        ":last_deferred_at_present": row.last_deferred_at_present,
        ":last_defer_reason": row.last_defer_reason,
        ":last_defer_reason_present": row.last_defer_reason_present,
        ":planned_date": row.planned_date,
        ":planned_date_present": row.planned_date_present,
        ":available_from": row.available_from,
        ":available_from_present": row.available_from_present,
        ":defer_count": row.defer_count,
        ":defer_count_present": row.defer_count_present,
        ":recurrence_instance_key": row.recurrence_instance_key,
        ":recurrence_instance_key_present": row.recurrence_instance_key_present,
        ":version": row.version,
        ":archived_at": row.archived_at,
        ":archived_at_present": row.archived_at_present,
    })?;
    Ok(())
}

/// Run the fresh-row INSERT. Bind values directly; absent /
/// explicit-clear fields land as SQL NULL (or the schema default
/// for `defer_count`). The "absent on a fresh INSERT" case can
/// theoretically still trip a multi-column CHECK if the peer's
/// payload is itself inconsistent (e.g. `recurrence` set but
/// `due_date` absent), but that case is the peer's bug — surfacing
/// it as a typed SQL error here is the correct shape: the
/// inconsistent payload is rejected at apply rather than persisted
/// in a partially-stored state.
pub(super) fn execute_task_insert(conn: &Connection, row: &TaskRow) -> Result<(), ApplyError> {
    conn.prepare_cached(TASK_INSERT_SQL)?
        .execute(named_params! {
            ":id": &row.entity_id,
            ":title": row.title,
            ":body": row.body,
            ":raw_input": row.raw_input,
            ":ai_notes": row.ai_notes,
            ":status": row.status,
            ":list_id": row.list_id,
            ":priority": row.priority,
            ":due_date": row.due_date,
            ":due_time": row.due_time,
            ":estimated_minutes": row.estimated_minutes,
            ":recurrence": row.recurrence,
            ":spawned_from": row.spawned_from,
            ":recurrence_group_id": row.recurrence_group_id,
            ":canonical_occurrence_date": row.canonical_occurrence_date,
            ":created_at": row.created_at,
            ":updated_at": row.updated_at,
            ":completed_at": row.completed_at,
            ":last_deferred_at": row.last_deferred_at,
            ":last_defer_reason": row.last_defer_reason,
            ":planned_date": row.planned_date,
            ":available_from": row.available_from,
            ":defer_count": row.defer_count,
            ":recurrence_instance_key": row.recurrence_instance_key,
            ":version": row.version,
            ":archived_at": row.archived_at,
        })?;
    Ok(())
}
