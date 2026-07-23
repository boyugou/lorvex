//! Final-delete a trashed task plus its child cascade (tag edges,
//! checklist items, reminders, calendar-event links, dependency edges,
//! and affected focus parent aggregates.

use lorvex_domain::naming::{
    EDGE_TASK_CALENDAR_EVENT_LINK, EDGE_TASK_DEPENDENCY, EDGE_TASK_TAG, ENTITY_TASK,
    ENTITY_TASK_CHECKLIST_ITEM, ENTITY_TASK_REMINDER, OP_DELETE,
};
use lorvex_domain::TaskId;
use lorvex_domain::{hlc_session::HlcSession, hlc_state::HlcState};
use lorvex_runtime::{bump_local_change_seq, get_or_create_device_id};
use lorvex_store::repositories::task::read;
use lorvex_store::StoreError;
use lorvex_sync::outbox_enqueue::{enqueue_payload_delete, enqueue_payload_upsert};
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde::Serialize;
use serde_json::Value;
use std::cell::RefCell;

use crate::commands::shared::{
    execute_cli_mutation_with_finalizer, log_cli_changelog_with_state, CliChangelogParams,
};
use crate::hlc_guard::lock_shared;

use super::focus_dates::{collect_focus_parent_dates_for_task, FocusParentDates};

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub(crate) struct PermanentDeleteTaskResult {
    pub(crate) task_id: String,
    pub(crate) title: Option<String>,
    pub(crate) archived_at: Option<String>,
    pub(crate) deleted: bool,
    pub(crate) dry_run: bool,
}

struct PermanentDeleteCliTaskMutation {
    task_id: TaskId,
    before: read::TaskRow,
    before_json: Value,
    device_id: String,
    dry_run: bool,
    tag_edges: Vec<(String, Value)>,
    checklist_items: Vec<(String, Value)>,
    reminder_rows: Vec<(String, Value)>,
    calendar_link_edges: Vec<(String, Value)>,
    dependency_edges: Vec<(String, Value)>,
    affected_focus_parents: FocusParentDates,
    result: RefCell<Option<PermanentDeleteTaskResult>>,
}

impl PermanentDeleteCliTaskMutation {
    fn base_result(&self, deleted: bool) -> PermanentDeleteTaskResult {
        PermanentDeleteTaskResult {
            task_id: self.task_id.to_string(),
            title: Some(self.before.core().title().to_string()),
            archived_at: self.before.lifecycle().archived_at().map(str::to_string),
            deleted,
            dry_run: self.dry_run,
        }
    }

    fn summary(&self) -> String {
        format!("Permanently deleted task '{}'", self.before.core().title())
    }
}

impl Mutation for PermanentDeleteCliTaskMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        OP_DELETE
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before_json.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        conn.prepare_cached("DELETE FROM current_focus_items WHERE task_id = ?1")?
            .execute([self.task_id.as_str()])?;
        conn.prepare_cached("DELETE FROM focus_schedule_blocks WHERE task_id = ?1")?
            .execute([self.task_id.as_str()])?;
        conn.prepare_cached("DELETE FROM task_dependencies WHERE task_id = ?1")?
            .execute([self.task_id.as_str()])?;
        conn.prepare_cached("DELETE FROM task_dependencies WHERE depends_on_task_id = ?1")?
            .execute([self.task_id.as_str()])?;

        for (entity_id, payload) in &self.tag_edges {
            enqueue_cascade_delete(
                conn,
                hlc,
                &self.device_id,
                EDGE_TASK_TAG,
                entity_id,
                payload,
            )?;
        }
        for (item_id, payload) in &self.checklist_items {
            enqueue_cascade_delete(
                conn,
                hlc,
                &self.device_id,
                ENTITY_TASK_CHECKLIST_ITEM,
                item_id,
                payload,
            )?;
        }
        for (reminder_id, payload) in &self.reminder_rows {
            enqueue_cascade_delete(
                conn,
                hlc,
                &self.device_id,
                ENTITY_TASK_REMINDER,
                reminder_id,
                payload,
            )?;
        }
        for (entity_id, payload) in &self.calendar_link_edges {
            enqueue_cascade_delete(
                conn,
                hlc,
                &self.device_id,
                EDGE_TASK_CALENDAR_EVENT_LINK,
                entity_id,
                payload,
            )?;
        }
        for (entity_id, payload) in &self.dependency_edges {
            enqueue_cascade_delete(
                conn,
                hlc,
                &self.device_id,
                EDGE_TASK_DEPENDENCY,
                entity_id,
                payload,
            )?;
        }

        let delete_version = hlc.next_version_string();
        let deleted = lorvex_store::repositories::task::write::hard_delete_task_lww(
            conn,
            &self.task_id,
            &delete_version,
        )?;
        let result = self.base_result(deleted > 0);
        if result.deleted {
            enqueue_payload_delete(
                conn,
                ENTITY_TASK,
                self.task_id.as_str(),
                &self.before_json,
                crate::commands::shared::bare_outbox_ctx(&delete_version, &self.device_id),
            )
            .map_err(|error| StoreError::Invariant(error.to_string()))?;
        }
        self.result.replace(Some(result.clone()));
        Ok(MutationOutput::new(
            serde_json::to_value(&result)?,
            self.summary(),
        ))
    }
}

/// Owned-tx wrapper. See `complete_task_with_conn` for the rationale.
/// dry-run rolls back the entire owned transaction so sentinel reads
/// don't persist; the real-delete path commits when `result.deleted`.
#[cfg(test)]
pub(crate) fn permanent_delete_task_with_conn(
    conn: &mut Connection,
    task_id: &TaskId,
    dry_run: bool,
) -> Result<PermanentDeleteTaskResult, crate::error::CliError> {
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let result = permanent_delete_task_in_tx(&tx, task_id, dry_run)?;
    if dry_run || !result.deleted {
        // dry-run path or "row was already gone" no-op:
        // discard any sentinel reads. For real deletes the inner body
        // populates `result.deleted=true` and we commit below.
        tx.rollback()?;
    } else {
        tx.commit()?;
    }
    Ok(result)
}

/// Inside-transaction body for `permanent_delete_task_with_conn` (#3019-H3).
///
/// The caller owns the transaction or savepoint; this function only
/// performs the cascade reads, child detaches, outbox enqueues, and
/// the final `DELETE FROM tasks` row. When `dry_run=true` it stops
/// before any mutation runs and returns `result.deleted = false` so
/// the caller can roll back its scope to discard the transient reads.
pub(crate) fn permanent_delete_task_in_tx(
    conn: &Connection,
    task_id: &TaskId,
    dry_run: bool,
) -> Result<PermanentDeleteTaskResult, crate::error::CliError> {
    let task_id_str = task_id.as_str();
    let before = read::get_task(conn, task_id)?;
    if let Some(task) = before.as_ref() {
        if task.lifecycle().archived_at().is_none() {
            return Err(crate::error::CliError::Conflict(format!(
                "task '{task_id_str}' is not in the Trash; move it to Trash before permanent delete"
            )));
        }
    }

    let mut result = PermanentDeleteTaskResult {
        task_id: task_id_str.to_string(),
        title: before.as_ref().map(|task| task.core().title().to_string()),
        archived_at: before
            .as_ref()
            .and_then(|task| task.lifecycle().archived_at().map(str::to_string)),
        deleted: false,
        dry_run,
    };
    if dry_run || before.is_none() {
        return Ok(result);
    }

    let device_id = get_or_create_device_id(conn)?;
    // load FULL pre-delete child rows so each cascade
    // tombstone ships its row as the sync envelope payload (matches
    // the MCP `permanent_delete_task` shape in
    // mcp-server/src/tasks/lifecycle/writes/permanent_delete.rs).
    // The previous shape used `enqueue_entity_delete` which writes an
    // empty `{}` payload — peers that missed the upsert can't
    // reconstruct the row from a tombstone. Same loss class as
    // #2818 / #2903 / #2928-H1.
    // Route through the spb cascade scanners so the snapshot shape
    // matches the row-mapper byte-for-byte;
    // its own SELECT + `json!` for each of the four child shapes.
    let tag_edges = lorvex_store::payload_loaders::load_task_tags_for_task(conn, task_id)?;
    let checklist_items =
        lorvex_store::payload_loaders::load_task_checklist_items_for_task(conn, task_id)?;
    let reminder_rows = lorvex_store::payload_loaders::load_task_reminders_for_task(conn, task_id)?;
    let calendar_link_edges =
        lorvex_store::payload_loaders::load_task_calendar_event_links_for_task(conn, task_id)?;
    let dependency_edges: Vec<(String, serde_json::Value)> = {
        // Two single-index SELECTs UNIONed instead of an OR-scan: the
        // PK index on task_id and the secondary index on
        // depends_on_task_id can each serve their own predicate, but
        // SQLite cannot combine them under a single OR. Two prepared
        // statements wrapped in a closure keep the row→payload mapping
        // identical to the previous shape (entity_id, version, etc.).
        let row_to_edge =
            |row: &rusqlite::Row<'_>| -> rusqlite::Result<(String, serde_json::Value)> {
                let task_id: lorvex_domain::TaskId = row.get(0)?;
                let depends_on: lorvex_domain::TaskId = row.get(1)?;
                let created_at: String = row.get(2)?;
                let version: String = row.get(3)?;
                let entity_id = format!("{task_id}:{depends_on}");
                let payload = lorvex_store::payload_loaders::task_dependency_payload(
                    &task_id,
                    &depends_on,
                    &version,
                    &created_at,
                );
                Ok((entity_id, payload))
            };
        let mut edges = {
            let mut stmt = conn.prepare_cached(
                "SELECT task_id, depends_on_task_id, created_at, version
                 FROM task_dependencies WHERE task_id = ?1",
            )?;
            let rows: Vec<_> = stmt
                .query_map([task_id_str], row_to_edge)?
                .collect::<Result<Vec<_>, _>>()?;
            rows
        };
        let incoming: Vec<_> = {
            let mut stmt = conn.prepare_cached(
                "SELECT task_id, depends_on_task_id, created_at, version
                 FROM task_dependencies WHERE depends_on_task_id = ?1",
            )?;
            let rows: Vec<_> = stmt
                .query_map([task_id_str], row_to_edge)?
                .collect::<Result<Vec<_>, _>>()?;
            rows
        };
        edges.extend(incoming);
        edges
    };
    let affected_focus_parents = collect_focus_parent_dates_for_task(conn, task_id_str)?;

    let mutation = PermanentDeleteCliTaskMutation {
        task_id: task_id.clone(),
        before: before
            .as_ref()
            .expect("checked before exists for real delete")
            .clone(),
        before_json: serde_json::to_value(before.as_ref().expect("checked before exists"))?,
        device_id: device_id.clone(),
        dry_run,
        tag_edges,
        checklist_items,
        reminder_rows,
        calendar_link_edges,
        dependency_edges,
        affected_focus_parents,
        result: RefCell::new(None),
    };
    let mut hlc_guard = lock_shared(conn)?;
    execute_cli_mutation_with_finalizer(
        conn,
        &mut hlc_guard,
        &mutation,
        crate::error::CliError::from,
        |execution, hlc_state| {
            for date in &mutation.affected_focus_parents.current_focus {
                enqueue_aggregate_root_upsert_if_present(
                    conn,
                    hlc_state,
                    &device_id,
                    lorvex_domain::naming::ENTITY_CURRENT_FOCUS,
                    date,
                )?;
            }
            for date in &mutation.affected_focus_parents.focus_schedule {
                enqueue_aggregate_root_upsert_if_present(
                    conn,
                    hlc_state,
                    &device_id,
                    lorvex_domain::naming::ENTITY_FOCUS_SCHEDULE,
                    date,
                )?;
            }
            let result_ref = mutation.result.borrow();
            let result = result_ref
                .as_ref()
                .expect("Mutation contract: permanent delete result staged by apply");
            if result.deleted {
                log_cli_changelog_with_state(
                    conn,
                    hlc_state,
                    CliChangelogParams {
                        operation: execution.operation,
                        entity_type: execution.entity_kind,
                        entity_id: task_id_str,
                        summary: &execution.output.summary,
                        before_json: execution.before,
                        after_json: None,
                    },
                )?;
                bump_local_change_seq(conn)?;
            }
            Ok(())
        },
    )?;
    drop(hlc_guard);
    result = mutation
        .result
        .take()
        .expect("Mutation contract: permanent delete result staged by apply");
    Ok(result)
}

fn enqueue_cascade_delete(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    device_id: &str,
    entity_type: &'static str,
    entity_id: &str,
    payload: &Value,
) -> Result<(), StoreError> {
    let version = hlc.next_version_string();
    enqueue_payload_delete(
        conn,
        entity_type,
        entity_id,
        payload,
        crate::commands::shared::bare_outbox_ctx(&version, device_id),
    )
    .map_err(|error| StoreError::Invariant(error.to_string()))
}

fn enqueue_aggregate_root_upsert_if_present(
    conn: &Connection,
    hlc_state: &mut HlcState,
    device_id: &str,
    entity_type: &'static str,
    entity_id: &str,
) -> Result<(), crate::error::CliError> {
    let Some(payload) = lorvex_sync::payload_build::aggregate::build_aggregate_payload(
        conn,
        entity_type,
        entity_id,
    )?
    else {
        return Ok(());
    };
    let version = hlc_state.generate().to_string();
    enqueue_payload_upsert(
        conn,
        entity_type,
        entity_id,
        &payload,
        crate::commands::shared::bare_outbox_ctx(&version, device_id),
    )?;
    Ok(())
}
