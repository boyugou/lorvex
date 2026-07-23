//! Primary `tasks` row UPDATE for a single-row task update.
//!
//! [`apply_primary_row_patch`] runs the SQL UPDATE on the `tasks` row
//! itself — title / body / list_id / priority / minutes / planned_date
//! / etc. — and is a no-op when the prepared patch carries no row-level
//! field. Status changes flow through the lifecycle owner in
//! [`super::status`] and never land here.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::Patch;
use lorvex_store::repositories::task::write::{self, TaskUpdatePatch};
use lorvex_store::StoreError;
use rusqlite::Connection;

use super::preparation::PreparedTaskUpdate;

pub(in crate::task_update) const fn has_primary_row_patch(prepared: &PreparedTaskUpdate) -> bool {
    prepared.title.is_some()
        || prepared.body.is_set_or_clear()
        || prepared.raw_input.is_set_or_clear()
        || prepared.ai_notes.is_set_or_clear()
        || prepared.list_id.is_set_or_clear()
        || prepared.priority.is_set_or_clear()
        || prepared.estimated_minutes.is_set_or_clear()
        || prepared.planned_date.is_set_or_clear()
}

pub(in crate::task_update) fn apply_primary_row_patch(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    task_id: &str,
    prepared: &PreparedTaskUpdate,
    now: &str,
) -> Result<(), StoreError> {
    if !has_primary_row_patch(prepared) {
        return Ok(());
    }
    let version = hlc.next_version_string();
    let patch = TaskUpdatePatch {
        task_id,
        title: prepared.title.as_deref(),
        body: prepared.body.as_deref(),
        raw_input: prepared.raw_input.as_deref(),
        ai_notes: prepared.ai_notes.as_deref(),
        status: None,
        list_id: prepared.list_id.as_deref(),
        priority: prepared.priority.clone(),
        due_time: Patch::Unset,
        estimated_minutes: prepared.estimated_minutes.clone(),
        planned_date: prepared.planned_date.as_deref(),
        archived_at: Patch::Unset,
        version: &version,
        now,
        before_status: Some(prepared.before_status),
    };
    write::apply_task_update(conn, &patch)
}
