//! Backend-agnostic flush sequencing for cross-surface mutation effects.
//!
//! Every cross-surface mutation that accumulates a typed sync-effects
//! bundle reaches a moment where the bundle must translate into outbox
//! enqueues + audit-changelog rows. The sequencing rules — what runs
//! before what, which categories share a snapshot pass, which audit
//! rows skip sync — are identical across surfaces. Only the underlying
//! enqueue/log primitives differ.
//!
//! Two layered traits split the contract:
//!
//! * [`MutationFlushBackend`] — the cross-effect base trait. Every
//!   per-surface backend implementing flush for any effects type
//!   declares its `Error` channel through this trait; the generic
//!   parameter `E` ties one impl to one effects type so a surface can
//!   layer multiple effects bundles onto one backend struct.
//! * Per-effect subtrait — [`TaskUpdateFlushBackend`] today; future
//!   batch-cancel / calendar-event / habit / memory / focus bundles
//!   layer the same way. The subtrait adds the per-category primitives
//!   the matching sequencer (e.g. [`flush_with_backend`]) calls in a
//!   fixed order.
//!
//! Layering `TaskUpdateFlushBackend` on top of `MutationFlushBackend`
//! makes the cross-surface contract uniform: backends carry one
//! associated `Error` type once, and the sequencer + the per-category
//! method signatures share that channel without re-declaring it.

use rusqlite::Connection;

use super::mutation::{
    TaskTagEdgeDelete, TaskUpdateSyncEffects, UpdateTaskCancelledSuccessor,
    UpdateTaskFocusRewireAudit, UpdateTaskSpawnedSuccessor,
};
use crate::lifecycle::{CopiedTagEdge, DeletedDependencyEdge};

/// Cross-effect base trait for per-surface flush backends.
///
/// `E` ties one impl to one sync-effects type. A surface that flushes
/// multiple bundle types (e.g. task updates plus batch cancels) layers
/// one impl per effects type onto the same backend struct; the shared
/// `Error` channel lets the surface keep one typed error throughout.
///
/// Per-effect subtraits add the category-specific primitives the
/// matching sequencer calls.
pub trait MutationFlushBackend<E: ?Sized> {
    /// Surface-specific error type the backend's primitives produce.
    /// Must absorb a `StoreError` so callers that bubble through
    /// store-layer failures can use the same error channel.
    type Error: From<lorvex_store::StoreError>;
}

/// Per-category primitives for flushing a [`TaskUpdateSyncEffects`]
/// bundle. The sequencer [`flush_with_backend`] calls these methods in
/// a fixed order; backends only own the per-category translation, not
/// the ordering.
pub trait TaskUpdateFlushBackend: MutationFlushBackend<TaskUpdateSyncEffects> {
    /// Tag entity upserts + task-tag edge upserts + task-tag edge
    /// deletes (with pre-delete payload snapshots).
    fn flush_tag_effects(
        &self,
        conn: &Connection,
        tag_upsert_ids: &[String],
        edge_upsert_ids: &[String],
        edge_deletes: &[TaskTagEdgeDelete],
    ) -> Result<(), Self::Error>;

    /// Dependency edge upserts + dependency edge tombstones.
    fn flush_dependency_edges(
        &self,
        conn: &Connection,
        edge_upsert_ids: &[String],
        edge_deletes: &[DeletedDependencyEdge],
    ) -> Result<(), Self::Error>;

    /// Reminder row upserts (cancellation + spawn + recurrence-rebase).
    fn flush_reminder_upserts(
        &self,
        conn: &Connection,
        reminder_ids: &[String],
    ) -> Result<(), Self::Error>;

    /// Primary task row upserts. Backends are responsible for
    /// filtering out any task ids the surrounding mutation executor
    /// already covered with its own snapshot enqueue.
    fn flush_task_upserts(&self, conn: &Connection, task_ids: &[String])
        -> Result<(), Self::Error>;

    /// Tasks whose dependency sets were touched as a side effect —
    /// each needs a sync envelope plus a "dependency-affected" audit row.
    fn flush_affected_dependents(
        &self,
        conn: &Connection,
        affected_ids: &[String],
    ) -> Result<(), Self::Error>;

    /// Spawned recurrence successors: per-successor `create` audit row
    /// plus inherited tag edges, checklist items, and reminders that
    /// need their own sync upserts.
    fn flush_spawned_successors(
        &self,
        conn: &Connection,
        successors: &[UpdateTaskSpawnedSuccessor],
        tag_edges: &[CopiedTagEdge],
        checklist_item_ids: &[String],
        reminder_ids: &[String],
    ) -> Result<(), Self::Error>;

    /// Successors cancelled by a recurrence-config change: per-successor
    /// `cancel` audit row.
    fn flush_cancelled_successors(
        &self,
        conn: &Connection,
        successors: &[UpdateTaskCancelledSuccessor],
    ) -> Result<(), Self::Error>;

    /// Focus rewires: bump every affected `focus_schedule` /
    /// `current_focus` aggregate, then emit the per-date audit rows
    /// that record which parent→successor rewire produced the bump.
    fn flush_focus_rewires(
        &self,
        conn: &Connection,
        rewired_focus_schedule_dates: &[String],
        rewired_current_focus_dates: &[String],
        audits: &[UpdateTaskFocusRewireAudit],
    ) -> Result<(), Self::Error>;
}

/// Helper that resolves `<B as MutationFlushBackend<TaskUpdateSyncEffects>>::Error`
/// in trait-method signatures without repeating the full path.
pub type TaskUpdateBackendError<B> = <B as MutationFlushBackend<TaskUpdateSyncEffects>>::Error;

/// Canonical sequencer for [`TaskUpdateSyncEffects`]: walk `effects` in
/// the order every surface must use and dispatch each category to
/// `backend`.
///
/// Ordering rationale:
///
/// 1. Tag mutations first — successor tag-edge upserts share the same
///    table and emitting parent edges before successor edges keeps
///    causal ordering on peers.
/// 2. Dependency edges before primary task upserts — the edge tables
///    are foreign-keyed to tasks, so emitting edges first matches the
///    apply-side ordering in `lorvex-sync`.
/// 3. Reminders before tasks — same FK reasoning.
/// 4. Primary task upserts.
/// 5. Affected-dependent dependency-cleanup audit batch.
/// 6. Spawned successors and their inherited children.
/// 7. Cancelled successors.
/// 8. Focus rewires last — they reference both the parent task and
///    the freshly created successor.
pub fn flush_with_backend<B: TaskUpdateFlushBackend>(
    conn: &Connection,
    effects: &TaskUpdateSyncEffects,
    backend: &B,
) -> Result<(), TaskUpdateBackendError<B>> {
    backend.flush_tag_effects(
        conn,
        &effects.tag_upsert_ids,
        &effects.task_tag_edge_upsert_ids,
        &effects.deleted_task_tag_edges,
    )?;
    backend.flush_dependency_edges(
        conn,
        &effects.dependency_edge_upsert_ids,
        &effects.deleted_dependency_edges,
    )?;
    backend.flush_reminder_upserts(conn, &effects.reminder_upsert_ids)?;
    backend.flush_task_upserts(conn, &effects.task_upsert_ids)?;
    backend.flush_affected_dependents(conn, &effects.affected_dependent_ids)?;
    backend.flush_spawned_successors(
        conn,
        &effects.spawned_successors,
        &effects.spawned_successor_tag_edges,
        &effects.spawned_successor_checklist_item_ids,
        &effects.spawned_successor_reminder_ids,
    )?;
    backend.flush_cancelled_successors(conn, &effects.cancelled_successors)?;
    backend.flush_focus_rewires(
        conn,
        &effects.rewired_focus_schedule_dates,
        &effects.rewired_current_focus_dates,
        &effects.focus_rewire_audits,
    )?;
    Ok(())
}
