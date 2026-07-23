//! Delete + cascade-tombstone path for the task aggregate.
//!
//! Lives in its own module so [`super`] can stay focused on upsert
//! dispatch. The cascade helper pre-tombstones every child / edge
//! row before SQLite's `ON DELETE CASCADE` removes them; without
//! that, a later upsert that revives the parent task would leave
//! every edge permanently lost on the deleting device.

use rusqlite::Connection;

use lorvex_domain::ids::TaskId;

use super::super::super::LwwTieBreak;
use super::super::helpers::{
    gate_then_cascade_into_outcome, tombstone_child_rows, tombstone_composite_edges,
};
use super::super::ApplyError;

/// Returns the shared [`super::super::LwwGatedDeleteOutcome`] so
/// the in-handler LWW gate's `Reject` arm surfaces as a typed
/// outcome rather than collapsing into `Ok(())`. A silent SQL
/// DELETE suppression that still let the dispatcher report
/// `Applied` would let `apply_envelope` mint a tombstone at the
/// loser's HLC over the surviving local row. Sharing the outcome
/// enum across task / habit / calendar_event keeps three byte-
/// isomorphic definitions on one declaration.
pub(crate) fn apply_task_delete(
    conn: &Connection,
    entity_id: &str,
    version: &str,
    apply_ts: &str,
) -> Result<super::super::LwwGatedDeleteOutcome, ApplyError> {
    // Issue #3285 phase 3: parse to the typed `TaskId` once at the
    // handler entry. Every SQL bind, helper call, and conflict-log
    // write below threads the typed id; the `&str` parameter is
    // preserved only because the dispatch table's fn-pointer type
    // is shared across aggregate handlers — migrating the
    // dispatcher signatures is a separate batch.
    let task_id = TaskId::from_trusted(entity_id.to_string());
    // Route through the shared `gate_then_cascade` helper so the
    // LWW gate fires BEFORE the cascade closure can run. The
    // skipped on either-side parse failure), then the cascade,
    // then `evaluate_delete_lww`'s byte-compare fallback — a
    // tainted local `version` (`'v1'`, `'seed'`, a legacy fixture)
    // plus a canonical-HLC envelope therefore landed cascade
    // tombstones over child / edge rows of a parent the gate then
    // refused to delete. Peers' subsequent edge upserts compared
    // against those orphan tombstones (cascade HLC ≥ edge HLC) and
    // stayed rejected forever.
    //
    // The helper:
    //   1. Calls `evaluate_delete_lww` first — parse-then-compare
    //      with a byte-compare fallback that still refuses
    //      strictly-stale envelopes against tainted local rows.
    //   2. Runs the cascade closure ONLY when the gate says Apply.
    //   3. Runs the parent DELETE in the same outer transaction.
    //
    // `apply_task_delete` is reachable from
    // `apply_entity_with_version_mode(_, true)` via shadow
    // promotion (`>=` semantics); `allow_equal_versions = true`
    // keeps that replay idempotent.
    gate_then_cascade_into_outcome(
        conn,
        "SELECT version FROM tasks WHERE id = ?1",
        "DELETE FROM tasks WHERE id = :id",
        task_id.as_str(),
        version,
        LwwTieBreak::AllowEqual,
        |conn| {
            // Tombstone every cascading child / edge row BEFORE
            // SQLite's `ON DELETE CASCADE` silently removes them.
            // Without this, a later upsert that revives the task
            // left every edge permanently lost on the deleting
            // device.
            //
            // The `FnOnce` closure bound on
            // `gate_then_cascade_into_outcome` imposes no
            // `'static` requirement, so the cascade helper can
            // borrow `task_id`, `version`, and `apply_ts`
            // straight from the surrounding scope without
            // allocating three `String`s per delete envelope to
            // widen those borrows.
            tombstone_cascading_children_for_task(conn, &task_id, version, apply_ts)
        },
    )
}

fn tombstone_cascading_children_for_task(
    conn: &Connection,
    task_id: &TaskId,
    version: &str,
    deleted_at: &str,
) -> Result<(), ApplyError> {
    // The cascade helpers still take `&str` for the parent id and
    // for the composite-key formatter; we feed `task_id.as_str()`
    // (zero-copy via the newtype's `as_str`) so the typed seam
    // covers every SQL bind site that originates from this scope.
    let task_id_str = task_id.as_str();
    // task_tags — composite `{task_id}:{tag_id}`. SELECT the row's
    // `version` alongside the identity column so the helper can
    // stamp the tombstone at `max(parent_version, row_version)`
    // and a concurrent edge edit at `Vx > Vp` is not silently lost
    // when the cascade runs at the parent's lower `Vp`.
    tombstone_composite_edges(
        conn,
        "SELECT tag_id, version FROM task_tags WHERE task_id = ?1",
        task_id_str,
        lorvex_domain::naming::EDGE_TASK_TAG,
        |other| format!("{task_id_str}:{other}"),
        version,
        deleted_at,
    )?;
    // task_dependencies — composite `{task_id}:{depends_on_task_id}`.
    // The delete affects the task in BOTH directions: edges where
    // this task is the source AND edges where it's the target.
    tombstone_composite_edges(
        conn,
        "SELECT depends_on_task_id, version FROM task_dependencies WHERE task_id = ?1",
        task_id_str,
        lorvex_domain::naming::EDGE_TASK_DEPENDENCY,
        |other| format!("{task_id_str}:{other}"),
        version,
        deleted_at,
    )?;
    tombstone_composite_edges(
        conn,
        "SELECT task_id, version FROM task_dependencies WHERE depends_on_task_id = ?1",
        task_id_str,
        lorvex_domain::naming::EDGE_TASK_DEPENDENCY,
        |other| format!("{other}:{task_id_str}"),
        version,
        deleted_at,
    )?;
    // task_calendar_event_links — composite `{task_id}:{calendar_event_id}`.
    tombstone_composite_edges(
        conn,
        "SELECT calendar_event_id, version FROM task_calendar_event_links WHERE task_id = ?1",
        task_id_str,
        lorvex_domain::naming::EDGE_TASK_CALENDAR_EVENT_LINK,
        |other| format!("{task_id_str}:{other}"),
        version,
        deleted_at,
    )?;
    // Children with single-column PK — tombstone by the child's
    // own id.
    tombstone_child_rows(
        conn,
        "SELECT id, version FROM task_reminders WHERE task_id = ?1",
        task_id_str,
        lorvex_domain::naming::ENTITY_TASK_REMINDER,
        version,
        deleted_at,
    )?;
    tombstone_child_rows(
        conn,
        "SELECT id, version FROM task_checklist_items WHERE task_id = ?1",
        task_id_str,
        lorvex_domain::naming::ENTITY_TASK_CHECKLIST_ITEM,
        version,
        deleted_at,
    )?;
    // task_provider_event_links is a device-local projection, not
    // a synced entity — no tombstone needed. The CASCADE is fine
    // for it.
    Ok(())
}
