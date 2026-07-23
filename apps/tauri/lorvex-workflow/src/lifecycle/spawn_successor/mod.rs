//! Spawn the next recurrence successor when a parent task is completed
//! or cancelled (skip-cancel).
//!
//! Uses the same recurrence semantics as the adapter-local spawn
//! functions: `inject_bymonthday` for MONTHLY/YEARLY rules,
//! `decrement_recurrence_count` for COUNT-based rules,
//! timezone-aware "today" from the user's preference (see
//! [`timezone::today_ymd_in_user_timezone`]), and
//! `next_occurrence_strictly_after` for cadence-preserving date
//! computation.
//!
//! The orchestrator is split across five sibling modules so a future
//! change to the EXDATE walk doesn't share a file with the focus-plan
//! rewire and the per-phase prepare-cached discipline reads
//! top-to-bottom:
//!
//!   * `next_due` — `compute_next_due_date` walks the cadence anchor
//!     past EXDATE entries, decrements `COUNT` if applicable, and
//!     dedupes against the cross-device instance-key index.
//!   * `insert` — `insert_successor_row` runs the canonical
//!     `INSERT ... SELECT FROM tasks WHERE id = ?` that inherits
//!     structural fields (title/body/recurrence) and content notes
//!     (`ai_notes`); plus
//!     `compute_successor_planned_date` preserves the
//!     planned-vs-anchor offset.
//!   * `rewire` — `rewire_focus_plan` collects affected
//!     `focus_schedule_blocks` / `current_focus_items` dates and
//!     UPDATEs them onto the successor. The dates travel to surface
//!     boundaries for sync/audit projection.
//!   * `copy` — `copy_task_tags`, `copy_checklist_items`,
//!     `copy_reminders` lift each child cascade out of the orchestrator.
//!   * `timezone` — `today_ymd_in_user_timezone` resolves the
//!     `timezone` preference, falling back to system-local when
//!     missing, in lockstep with
//!     `lorvex_domain::today_ymd_for_timezone_name`.

use rusqlite::Connection;

use lorvex_domain::TaskId;

use lorvex_store::StoreError;

use super::snapshot::TaskSnapshot;
use super::types::CopiedTagEdge;

mod copy;
mod insert;
mod next_due;
mod rewire;
mod timezone;

/// Spawn result returned to the lifecycle orchestrator.
///
/// The store layer never enqueues sync envelopes itself — it collects the
/// inventory of side effects so each surface (MCP / Tauri / CLI) can stamp
/// its own HLC version and enqueue the correct envelopes inside the same
/// transaction. The `rewired_*_dates` lists cover the focus-plan rewire —
/// which mutates `focus_schedule_blocks` and `current_focus_items` rows
/// under their parent aggregate roots — so callers can emit sync envelopes
/// for the parents whose children now point at the freshly spawned successor.
pub(super) struct SpawnResult {
    pub(super) successor_id: String,
    pub(super) copied_tag_edges: Vec<CopiedTagEdge>,
    pub(super) copied_checklist_item_ids: Vec<String>,
    pub(super) copied_reminder_ids: Vec<String>,
    /// Dates whose `focus_schedule_blocks` rows were rewired from the
    /// completed parent task to the successor. Callers must enqueue an
    /// `ENTITY_FOCUS_SCHEDULE` upsert envelope for each so peers see
    /// today's plan now references the open successor instead of the
    /// completed parent.
    pub(super) rewired_focus_schedule_dates: Vec<String>,
    /// Dates whose `current_focus_items` rows were rewired from the
    /// completed parent task to the successor. Callers must enqueue an
    /// `ENTITY_CURRENT_FOCUS` upsert envelope for each.
    pub(super) rewired_current_focus_dates: Vec<String>,
}

pub(super) fn spawn_recurrence_successor(
    conn: &Connection,
    parent_id: &TaskId,
    snap: &TaskSnapshot,
    parent_active_reminder_times: &[String],
    now: &str,
    version: &str,
) -> Result<Option<SpawnResult>, StoreError> {
    let Some(decision) = next_due::compute_next_due_date(conn, snap, now)? else {
        return Ok(None);
    };
    let next_due_date = decision.next_due_date;
    let spawned_recurrence = decision.spawned_recurrence;
    let today_ymd = decision.today_ymd;

    let group_id = snap.recurrence_group_id.as_deref();
    let instance_key = group_id
        .and_then(|gid| lorvex_domain::recurrence::generate_instance_key(gid, &next_due_date));
    let successor_planned_date = insert::compute_successor_planned_date(snap, &next_due_date);
    let successor_available_from = insert::compute_successor_available_from(snap, &next_due_date);
    let successor_id = lorvex_domain::new_entity_id_string();

    insert::insert_successor_row(
        conn,
        insert::InsertSuccessorParams {
            parent_id: parent_id.as_str(),
            successor_id: &successor_id,
            next_due_date: &next_due_date,
            spawned_recurrence: &spawned_recurrence,
            spawned_group_id: group_id,
            instance_key: instance_key.as_deref(),
            successor_planned_date: successor_planned_date.as_deref(),
            successor_available_from: successor_available_from.as_deref(),
            version,
            now,
        },
    )?;

    let rewire::FocusRewireResult {
        rewired_focus_schedule_dates,
        rewired_current_focus_dates,
    } = rewire::rewire_focus_plan(conn, parent_id.as_str(), &successor_id, &today_ymd)?;

    let copied_tag_edges =
        copy::copy_task_tags(conn, parent_id.as_str(), &successor_id, version, now)?;
    let copied_checklist_item_ids =
        copy::copy_checklist_items(conn, parent_id.as_str(), &successor_id, version, now)?;
    let copied_reminder_ids = copy::copy_reminders(
        conn,
        snap,
        &successor_id,
        &next_due_date,
        parent_active_reminder_times,
        version,
        now,
    )?;

    Ok(Some(SpawnResult {
        successor_id,
        copied_tag_edges,
        copied_checklist_item_ids,
        copied_reminder_ids,
        rewired_focus_schedule_dates,
        rewired_current_focus_dates,
    }))
}
