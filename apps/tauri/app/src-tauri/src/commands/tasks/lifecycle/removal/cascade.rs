//! Side-effect helpers shared by every removal path
//! (`cancel_task_with_conn`, `permanent_delete_task_with_conn`,
//! `purge_cancelled_tasks_with_conn`, and the soft-delete
//! `archive_task_with_conn`).
//!
//!   * `cleanup_plan_refs_after_removal` — clears
//!     `current_focus_items` / `focus_schedule_blocks` rows that
//!     reference the task and re-enqueues a parent-aggregate
//!     upsert for every affected day so peers absorb the rewired
//!     plan rather than continuing to point at the deleted task.
//!   * `enqueue_cascaded_task_child_deletes` — pre-collects the
//!     pre-delete row snapshots for every independently-synced
//!     child entity (task_tags, task_checklist_items, task_reminders,
//!     task_calendar_event_links) and routes them through the typed
//!     `DeleteEnvelope` pipeline so peers see explicit tombstones
//!     instead of inferring deletes from a missing parent.

use rusqlite::{params, Connection};

use crate::error::AppError;

/// Clean up stale references to a deleted task in current_focus_items
/// and focus_schedule_blocks (both use soft-ref task_id, no FK CASCADE).
///
/// Pre-collect-and-enqueue lives here so every caller (the
/// soft-delete `archive_task_with_conn` plus the hard-delete sites
/// `permanent_delete_task_with_conn`, `purge_cancelled_tasks_with_conn`,
/// `empty_trash_with_conn`) re-points peers' parent-aggregate
/// envelopes in one place. A bare two-statement DELETE would leave
/// those envelopes pointing at the now-deleted task. The helper:
///
///   1. Collects affected `current_focus_items.date` and
///      `focus_schedule_blocks.schedule_date` rows BEFORE the DELETE
///      so the date list survives the cascade.
///   2. Runs the local DELETE so the widget / Today view stop
///      rendering the now-deleted task.
///   3. Re-enqueues parent-aggregate (`current_focus`,
///      `focus_schedule`) upserts for each affected day so peers
///      absorb the rewired plan and don't keep pointing at the
///      removed task.
///
/// returns `()` (#3022 M5). The previous signature
/// returned a `PlanRefCleanupSummary` carrying the affected focus and
/// schedule date lists with a doc-comment promising they would be
/// attached to `ai_changelog`, but every caller on the four
/// removal/archival paths simply dropped the value with `?;`. Either
/// the dates were structurally noise (the `enqueue_*_upsert_for_date`
/// loops below already publish each affected date through the sync
/// outbox so peers receive the truth — there's no second consumer to
/// feed) or the contract had drifted from intent. Surfacing them on
/// `ai_changelog` would require restructuring `finalize_task_mutation`
/// at every removal site for one consumer that has not materialized,
/// so the cleaner diff is to drop the struct now and let any future
/// caller that genuinely needs the lists re-derive them at the call
/// site (the SELECTs are cheap and indexed). The aggregate re-enqueue
/// invariant tested by the suite below still holds — it observes the
/// outbox, not the return value.
pub(in crate::commands::tasks::lifecycle) fn cleanup_plan_refs_after_removal(
    conn: &Connection,
    task_id: &str,
) -> Result<(), AppError> {
    let affected_focus_dates: Vec<String> = {
        let mut stmt = conn
            .prepare_cached("SELECT DISTINCT date FROM current_focus_items WHERE task_id = ?1")
            .map_err(AppError::from)?;
        let dates = stmt
            .query_map(params![task_id], |row| row.get::<_, String>(0))
            .map_err(AppError::from)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(AppError::from)?;
        dates
    };
    let affected_schedule_dates: Vec<String> = {
        let mut stmt = conn
            .prepare_cached(
                "SELECT DISTINCT schedule_date FROM focus_schedule_blocks WHERE task_id = ?1",
            )
            .map_err(AppError::from)?;
        let dates = stmt
            .query_map(params![task_id], |row| row.get::<_, String>(0))
            .map_err(AppError::from)?
            .collect::<Result<Vec<_>, _>>()
            .map_err(AppError::from)?;
        dates
    };

    conn.prepare_cached("DELETE FROM current_focus_items WHERE task_id = ?1")
        .map_err(AppError::from)?
        .execute(params![task_id])
        .map_err(AppError::from)?;
    conn.prepare_cached("DELETE FROM focus_schedule_blocks WHERE task_id = ?1")
        .map_err(AppError::from)?
        .execute(params![task_id])
        .map_err(AppError::from)?;

    for date in &affected_focus_dates {
        crate::commands::enqueue_current_focus_upsert_for_date(conn, date)?;
    }
    for date in &affected_schedule_dates {
        crate::commands::enqueue_focus_schedule_upsert_for_date(conn, date)?;
    }

    Ok(())
}

/// Enqueue DELETE envelopes for independently synced child entities before a
/// hard-delete cascades them away locally. SQLite FK CASCADE keeps the local
/// DB clean, but without these explicit deletes peers can retain stale child
/// rows indefinitely.
///
/// every child cascade now routes through the typed
/// `DeleteEnvelope` pipeline, so a `version` + `created_at` snapshot is
/// loaded from the live row BEFORE the FK CASCADE wipes it. The
/// `_updated_at` parameter is retained (and ignored) because callers in
/// `purge_cancelled_tasks_with_conn` and `empty_trash_with_conn` still
/// thread the post-mutation timestamp through for symmetry with the
/// non-cascade enqueue paths in the same loop body — converting the
/// signature would force a wave of unrelated argument churn for no
/// behavioral gain.
pub(in crate::commands::tasks) fn enqueue_cascaded_task_child_deletes(
    conn: &Connection,
    task_id: &str,
    _updated_at: &str,
) -> Result<(), AppError> {
    let mut tag_stmt = conn
        .prepare_cached("SELECT tag_id FROM task_tags WHERE task_id = ?1")
        .map_err(AppError::from)?;
    let tag_ids: Vec<String> = tag_stmt
        .query_map(params![task_id], |row| row.get(0))
        .map_err(AppError::from)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(AppError::from)?;
    drop(tag_stmt);

    let mut checklist_stmt = conn
        .prepare_cached("SELECT id FROM task_checklist_items WHERE task_id = ?1")
        .map_err(AppError::from)?;
    let checklist_item_ids: Vec<String> = checklist_stmt
        .query_map(params![task_id], |row| row.get(0))
        .map_err(AppError::from)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(AppError::from)?;
    drop(checklist_stmt);

    let mut reminder_stmt = conn
        .prepare_cached("SELECT id FROM task_reminders WHERE task_id = ?1")
        .map_err(AppError::from)?;
    let reminder_ids: Vec<String> = reminder_stmt
        .query_map(params![task_id], |row| row.get(0))
        .map_err(AppError::from)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(AppError::from)?;
    drop(reminder_stmt);

    let mut link_stmt = conn
        .prepare_cached(
            "SELECT calendar_event_id FROM task_calendar_event_links WHERE task_id = ?1",
        )
        .map_err(AppError::from)?;
    let calendar_event_ids: Vec<String> = link_stmt
        .query_map(params![task_id], |row| row.get(0))
        .map_err(AppError::from)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(AppError::from)?;
    drop(link_stmt);

    // route through `DeleteEnvelope` so the task_tag
    // tombstone payload carries `(task_id, tag_id, version, created_at)`
    // rather than the previous minimal `{task_id, tag_id, updated_at}`
    // shape (which dropped `version`, defeating peer LWW on the edge
    // tombstone path).
    // Batch the four per-id `SELECT … WHERE id = ?` pre-delete
    // snapshot loaders into one indexed scan each. For a task with
    // N tags / M checklist items / R reminders / E linked events
    // the previous shape ran N + M + R + E point-queries inside the
    // writer transaction; this collapses to four IN-list scans
    // regardless of task size.
    let typed_task_id = lorvex_domain::TaskId::from_trusted(task_id.to_string());
    let tag_snapshots =
        crate::commands::load_task_tag_pre_delete_snapshots(conn, &typed_task_id, &tag_ids)?;
    for tag_id in &tag_ids {
        let entity_id = lorvex_domain::TaskTagEdgeId::new(
            &typed_task_id,
            &lorvex_domain::TagId::from_trusted_str(tag_id),
        );
        let snapshot = tag_snapshots.get(tag_id).cloned().ok_or_else(|| {
            crate::error::AppError::NotFound(format!(
                "task_tag edge '{entity_id}' not found for sync snapshot"
            ))
        })?;
        crate::commands::enqueue_task_tag_delete(
            conn,
            crate::commands::DeleteEnvelope::new(entity_id.into_string(), snapshot),
        )?;
    }

    // load each child's pre-delete snapshot BEFORE the
    // SQLite FK CASCADE removes them, so the typed `DeleteEnvelope`
    // carries the full row state instead of `{id}`. Peers that GC'd
    // their local copy can reconstruct the deleted state from the
    // tombstone payload.
    let item_snapshots =
        crate::commands::load_task_checklist_item_pre_delete_snapshots(conn, &checklist_item_ids)?;
    for item_id in &checklist_item_ids {
        let snapshot = item_snapshots.get(item_id).cloned().ok_or_else(|| {
            crate::error::AppError::NotFound(format!(
                "task checklist item '{item_id}' not found for sync snapshot"
            ))
        })?;
        crate::commands::enqueue_task_checklist_item_delete(
            conn,
            crate::commands::DeleteEnvelope::new(item_id, snapshot),
        )?;
    }

    let reminder_snapshots =
        crate::commands::load_task_reminder_pre_delete_snapshots(conn, &reminder_ids)?;
    for reminder_id in &reminder_ids {
        let snapshot = reminder_snapshots
            .get(reminder_id)
            .cloned()
            .ok_or_else(|| {
                crate::error::AppError::NotFound(format!(
                    "task reminder '{reminder_id}' not found for sync snapshot"
                ))
            })?;
        crate::commands::enqueue_task_reminder_delete(
            conn,
            crate::commands::DeleteEnvelope::new(reminder_id, snapshot),
        )?;
    }

    // route through `DeleteEnvelope` so the
    // task_calendar_event_link tombstone payload carries
    // `(task_id, calendar_event_id, version, created_at, updated_at)`
    // rather than the previous minimal `{task_id, calendar_event_id, updated_at}`
    // shape (which dropped `version` + `created_at`, defeating peer
    // LWW on the edge tombstone path).
    let event_link_snapshots = crate::commands::load_task_calendar_event_link_pre_delete_snapshots(
        conn,
        &typed_task_id,
        &calendar_event_ids,
    )?;
    for calendar_event_id in &calendar_event_ids {
        let entity_id = format!("{task_id}:{calendar_event_id}");
        let snapshot = event_link_snapshots
            .get(calendar_event_id)
            .cloned()
            .ok_or_else(|| {
                crate::error::AppError::NotFound(format!(
                    "task_calendar_event_link edge '{task_id}:{calendar_event_id}' not found for sync snapshot"
                ))
            })?;
        crate::commands::enqueue_task_calendar_event_link_delete(
            conn,
            crate::commands::DeleteEnvelope::new(entity_id, snapshot),
        )?;
    }

    Ok(())
}
