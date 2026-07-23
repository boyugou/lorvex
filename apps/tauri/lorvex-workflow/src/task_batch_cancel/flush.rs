//! Backend-agnostic flush sequencing for [`BatchCancelSyncEffects`].
//!
//! Mirrors the [`task_update::flush`] module's two-layer split: the
//! cross-effect base trait [`MutationFlushBackend`] carries the per-effects
//! `Error` channel, and the per-effect subtrait
//! [`BatchCancelFlushBackend`] adds the category-specific primitives.
//! Each consumer surface (MCP, CLI) implements both for its backend
//! struct and routes through [`flush_batch_cancel_with_backend`] so the
//! ordering rules — which categories share a snapshot pass, which audit
//! rows skip sync — live in one place.
//!
//! The category set is a subset of the task-update set: there is no
//! tag-effect category (batch cancel cannot add tags), no
//! cancelled-successor category (a single cancel can spawn one
//! successor; a list-level batch never cancels its own successor), and
//! no focus-rewire audit category (the canonical aggregate-root bump is
//! the surface-uniform contract; MCP's `recurrence_rewire` per-date
//! audit rows live on `task_update` because that's the only surface
//! consuming the parent→successor mapping today).

use rusqlite::Connection;

use super::{BatchCancelSyncEffects, SpawnedSuccessorLog};
use crate::lifecycle::{CopiedTagEdge, DeletedDependencyEdge};
use crate::task_update::MutationFlushBackend;

/// Per-category primitives for flushing a [`BatchCancelSyncEffects`]
/// bundle. The sequencer [`flush_batch_cancel_with_backend`] calls these
/// methods in a fixed order; backends only own the per-category
/// translation, not the ordering.
pub trait BatchCancelFlushBackend: MutationFlushBackend<BatchCancelSyncEffects> {
    /// Primary task rows of the cancelled tasks. Backends that already
    /// covered these ids via a surrounding executor's own snapshot
    /// enqueue (e.g. MCP's per-row `log_change` path) may no-op.
    fn flush_cancelled_task_upserts(
        &self,
        conn: &Connection,
        task_ids: &[String],
    ) -> Result<(), Self::Error>;

    /// Reminders cancelled as a side effect of cancelling each task.
    fn flush_cancelled_reminders(
        &self,
        conn: &Connection,
        reminder_ids: &[String],
    ) -> Result<(), Self::Error>;

    /// Dependency edges deleted because one of the cancelled tasks
    /// participated in them. Backends consume the pre-delete snapshot
    /// to emit the tombstone payload.
    fn flush_deleted_dependency_edges(
        &self,
        conn: &Connection,
        edges: &[DeletedDependencyEdge],
    ) -> Result<(), Self::Error>;

    /// Tasks whose dependency sets were touched by a cascade — each
    /// needs its own sync envelope plus an audit row recording the
    /// dependency-affected side effect.
    fn flush_affected_dependents(
        &self,
        conn: &Connection,
        affected_ids: &[String],
    ) -> Result<(), Self::Error>;

    /// Spawned recurrence successors (one per cancelled recurring task
    /// when `cancel_series=false`): per-successor `create` audit row,
    /// plus the inherited tag edges / checklist items / reminders.
    fn flush_spawned_successors(
        &self,
        conn: &Connection,
        successors: &[SpawnedSuccessorLog],
        tag_edges: &[CopiedTagEdge],
        checklist_item_ids: &[String],
        reminder_ids: &[String],
    ) -> Result<(), Self::Error>;

    /// Focus rewires: bump every affected `focus_schedule` /
    /// `current_focus` aggregate root.
    fn flush_focus_rewires(
        &self,
        conn: &Connection,
        focus_schedule_dates: &[String],
        current_focus_dates: &[String],
    ) -> Result<(), Self::Error>;
}

/// Helper that resolves `<B as MutationFlushBackend<BatchCancelSyncEffects>>::Error`
/// in trait-method signatures without repeating the full path.
pub type BatchCancelBackendError<B> = <B as MutationFlushBackend<BatchCancelSyncEffects>>::Error;

/// Canonical sequencer for [`BatchCancelSyncEffects`]. Walks `effects`
/// in the order every surface must use and dispatches each category to
/// `backend`.
///
/// Ordering rationale:
///
/// 1. Cancelled task rows first — the side-effect categories below
///    (reminders, dep edges, affected dependents) reference these via
///    FK; emitting parents before children matches the apply-side
///    ordering in `lorvex-sync`.
/// 2. Cancelled reminders next, then deleted dep edges, then affected
///    dependents — the dep-edge tombstone must land between the parent
///    row sync and the dependents' own sync so an out-of-order apply
///    can't observe a dependent that still references a deleted edge.
/// 3. Spawned successors and their inherited children before focus
///    rewires — focus aggregates reference the successor row after a
///    rewire, so the successor must already be enqueued.
/// 4. Focus rewires last.
///
/// The whole-operation `batch_cancel` audit row (with `before_states`
/// / `after_states` and the cancelled task ids) is intentionally NOT
/// part of this sequencer — surfaces own that audit because the
/// before/after snapshot shape lives on the result struct, not on the
/// sync-effects bundle.
pub fn flush_batch_cancel_with_backend<B: BatchCancelFlushBackend>(
    conn: &Connection,
    effects: &BatchCancelSyncEffects,
    backend: &B,
) -> Result<(), BatchCancelBackendError<B>> {
    backend.flush_cancelled_task_upserts(conn, &effects.task_upsert_ids)?;
    backend.flush_cancelled_reminders(conn, &effects.cancelled_reminder_ids)?;
    backend.flush_deleted_dependency_edges(conn, &effects.deleted_dependency_edges)?;
    backend.flush_affected_dependents(conn, &effects.affected_dependent_ids)?;
    backend.flush_spawned_successors(
        conn,
        &effects.spawned_successors,
        &effects.spawned_successor_tag_edges,
        &effects.spawned_successor_checklist_item_ids,
        &effects.spawned_successor_reminder_ids,
    )?;
    backend.flush_focus_rewires(
        conn,
        &effects.rewired_focus_schedule_dates,
        &effects.rewired_current_focus_dates,
    )?;
    Ok(())
}
