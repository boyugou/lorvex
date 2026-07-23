//! Internal helpers shared by every checklist `*_with_conn` core:
//! the row-mapper, the bounded list query, the positional UPDATE
//! gated by an LWW comparison, and the parent-task touch that
//! routes through the canonical `apply_task_update` patch wrapped
//! in a [`Mutation`] descriptor so the parent bump shares the
//! per-mutation `HlcSession` and runs the executor's
//! `local_change_seq++` / event_bus broadcast finalizer.

use std::cell::RefCell;

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{ENTITY_TASK, OP_UPSERT};
use lorvex_domain::TaskId;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::{params, Connection};
use serde_json::Value;

use crate::commands::fetch_task_by_id;
use crate::commands::shared::effects::execute_ipc_entity_mutation;
use crate::commands::TaskChecklistItem;
use crate::commands::{enqueue_task_checklist_item_upsert, enqueue_task_upsert};
use crate::error::{AppError, AppResult};

pub(super) fn checklist_item_from_row(
    row: &rusqlite::Row<'_>,
) -> rusqlite::Result<TaskChecklistItem> {
    Ok(TaskChecklistItem {
        id: row.get(0)?,
        task_id: row.get(1)?,
        position: row.get(2)?,
        text: row.get(3)?,
        completed_at: row.get(4)?,
        version: row.get(5)?,
        created_at: row.get(6)?,
        updated_at: row.get(7)?,
    })
}

pub(super) fn list_items_with_conn(
    conn: &rusqlite::Connection,
    task_id: &TaskId,
) -> AppResult<Vec<TaskChecklistItem>> {
    let mut stmt = conn.prepare_cached(
        "SELECT id, task_id, position, text, completed_at, version, created_at, updated_at
         FROM task_checklist_items
         WHERE task_id = ?1
         ORDER BY position ASC, created_at ASC, id ASC",
    )?;
    let rows = stmt.query_map(params![task_id.as_str()], checklist_item_from_row)?;
    rows.collect::<Result<Vec<_>, _>>().map_err(Into::into)
}

/// Apply a positional re-write to every checklist item in `ordered_ids`,
/// gated on a strict `?version > task_checklist_items.version` LWW
/// comparison so a stale local reorder cannot regress an item whose
/// version was advanced by an in-flight peer write (rename, completion
/// flip) racing the same transaction.
///
/// Without the LWW guard, two peers re-ordering the same checklist
/// simultaneously could each clobber the other's `version` even when
/// the inbound HLC was older. Mirrors the gate used by
/// `apply_task_update`, `update_list_patched`, `set_preference`, and
/// `insert_link`. When the gate rejects a row (`changes == 0`) the
/// outbox enqueue is skipped for that row: any envelope built from
/// the older stamp would lose the same LWW race at the peer.
pub(super) fn update_item_positions(
    conn: &rusqlite::Connection,
    task_id: &TaskId,
    ordered_ids: &[String],
    now: &str,
) -> AppResult<()> {
    // Lift the prepare out of the per-item loop so reordering N
    // checklist items pays one prepare instead of N.
    let mut stmt = conn.prepare_cached(
        "UPDATE task_checklist_items
         SET position = ?2, updated_at = ?3, version = ?4
         WHERE id = ?1 AND task_id = ?5 AND ?4 > version",
    )?;
    for (position, id) in ordered_ids.iter().enumerate() {
        let version = crate::hlc::generate_version_result()?;
        let changes = stmt.execute(params![id, position as i64, now, version, task_id.as_str()])?;
        if changes > 0 {
            enqueue_task_checklist_item_upsert(conn, id)?;
        }
    }
    Ok(())
}

/// A checklist mutation must advance the parent task's
/// `(version, updated_at)` AND enqueue a sync envelope for the
/// post-touch row. Bumping only `updated_at` would leave `version`
/// stale, with two consequences:
///   1. The local LWW gate (`?1 > version`) and the sync-apply LWW gate
///      (`excluded.version > tasks.version`) would reject peer envelopes
///      that legitimately advanced the parent task — peer wins would
///      be silently dropped because the local row's `version` had not
///      moved.
///   2. No outbox row would be emitted for the parent, so the
///      post-touch `(version, updated_at)` would never propagate to
///      peers; remote devices would keep seeing the pre-checklist
///      parent state even after a successful local checklist
///      round-trip.
///
/// Routing the touch through `write::apply_task_update` rather than a
/// raw `UPDATE` runs the canonical patch with the same strict-`?version
/// \> tasks.version` LWW gate every other task write uses, so a stale
/// local checklist edit racing a newer remote upsert cannot regress
/// the parent's HLC. A raw UPDATE without the gate would clobber
/// `version`/`updated_at`, silently take the older HLC, and the next
/// inbound peer envelope would then lose the LWW race against its own
/// (now-newer) version. The empty-fields patch still emits the
/// canonical `version = ?` + `updated_at = ?` SET clauses so the row is
/// bumped on every call.
pub(super) fn touch_parent_task_timestamp(
    conn: &rusqlite::Connection,
    task_id: &TaskId,
    now: &str,
) -> AppResult<()> {
    let mutation = TouchParentTaskMutation {
        task_id,
        now,
        rejected_by_lww: RefCell::new(false),
    };
    execute_ipc_entity_mutation(conn, &mutation, |conn, _execution| {
        if *mutation.rejected_by_lww.borrow() {
            // LWW rejected the local stamp — a peer's freshly
            // applied state already supplied a newer stamp. Skip
            // the upsert enqueue so we don't ship an envelope the
            // peer would also reject under its own LWW.
            return Ok(());
        }
        let task = fetch_task_by_id(conn, task_id.as_str())?;
        enqueue_task_upsert(conn, &task)?;
        Ok(())
    })?;
    Ok(())
}

/// `Mutation` descriptor for the parent-task touch issued by every
/// checklist-item mutation. The empty-fields patch still emits the
/// canonical `version = ?` + `updated_at = ?` SET clauses so the row
/// is bumped exactly as before, and the LWW gate inside
/// `apply_task_update` still applies — a stale local checklist edit
/// racing a newer remote upsert is recorded in `rejected_by_lww` and
/// the surface finalizer skips the upsert enqueue.
struct TouchParentTaskMutation<'a> {
    task_id: &'a TaskId,
    now: &'a str,
    rejected_by_lww: RefCell<bool>,
}

impl<'a> Mutation for TouchParentTaskMutation<'a> {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        OP_UPSERT
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        // No audit funnel on the Tauri surface — skip the snapshot.
        Ok(None)
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let before = fetch_task_by_id(conn, self.task_id.as_str()).map_err(|err| match err {
            AppError::Store(s) => *s,
            other => StoreError::Invariant(other.to_string()),
        })?;
        let version = hlc.next_version_string();
        let patch = lorvex_store::repositories::task::write::TaskUpdatePatch {
            task_id: self.task_id.as_str(),
            version: &version,
            now: self.now,
            before_status: Some(
                lorvex_store::repositories::task::write::parse_task_status_for_update(
                    self.task_id.as_str(),
                    &before.status,
                )?,
            ),
            ..Default::default()
        };
        match lorvex_store::repositories::task::write::apply_task_update(conn, &patch) {
            Ok(()) => {}
            Err(StoreError::StaleVersion { .. }) => {
                *self.rejected_by_lww.borrow_mut() = true;
            }
            Err(e) => return Err(e),
        }
        let summary = format!("Touched parent task '{}'", self.task_id.as_str());
        let after = serde_json::json!({ "id": self.task_id.as_str() });
        Ok(MutationOutput::new(after, summary))
    }
}
