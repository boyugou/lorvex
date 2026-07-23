//! Cross-verb effect-flush primitives shared by the four task-write
//! entry points (`task.create`, `task.batch_create`, `task.batch_update`,
//! `task.batch_cancel_in_list`).
//!
//! Each verb produces a typed `*SyncEffects` bundle whose categories
//! are a subset of the canonical task-write category set. Per-verb
//! sequencers in the sibling modules keep their original ordering, so
//! HLC version stamps the outbox emits remain bit-identical to the
//! pre-extraction code. What this module factors out is the **body** of
//! every per-category enqueue loop, removing the ~100 LOC of repeated
//! `for id in ids … enqueue_entity_upsert(…)` boilerplate that drifted
//! across the four flushers.

use lorvex_domain::hlc_state::HlcState;
use lorvex_domain::naming::{
    EDGE_TASK_TAG, ENTITY_CURRENT_FOCUS, ENTITY_FOCUS_SCHEDULE, ENTITY_TASK,
    ENTITY_TASK_CHECKLIST_ITEM, ENTITY_TASK_REMINDER,
};
use lorvex_sync::outbox_enqueue::{enqueue_entity_upsert, enqueue_payload_delete};
use lorvex_workflow::lifecycle::CopiedTagEdge;
use lorvex_workflow::task_batch_update::TaskTagEdgeDelete;
use rusqlite::Connection;
use serde_json::Value;

use crate::commands::shared::{log_cli_changelog_with_state, CliChangelogParams};
use crate::error::CliError;

/// Borrow view over a single spawned- or cancelled-successor record.
/// Unifies the three concrete successor shapes the workflow crate
/// returns (`CreateTaskSpawnedSuccessor`, `SpawnedSuccessorLog`,
/// `UpdateTaskSpawnedSuccessor` / `UpdateTaskCancelledSuccessor`) so
/// the shared flusher helpers can take one borrow type.
pub(crate) struct SuccessorView<'a> {
    pub successor_id: &'a str,
    pub summary: &'a str,
    pub after_task: &'a Value,
}

/// Enqueue an upsert envelope for every id in `ids` against the
/// supplied entity kind.
pub(crate) fn enqueue_upserts(
    conn: &Connection,
    device_id: &str,
    hlc_state: &mut HlcState,
    entity_kind: &'static str,
    ids: &[String],
) -> Result<(), CliError> {
    for id in ids {
        enqueue_entity_upsert(conn, entity_kind, id, hlc_state, device_id)?;
    }
    Ok(())
}

/// Enqueue payload-shaped tombstones for every task-tag edge in
/// `edges`. The `edges` slice carries pre-delete snapshots produced by
/// the workflow layer; the bare-outbox-ctx form is used so the
/// tombstone carries a fresh HLC version stamp.
pub(crate) fn enqueue_deleted_task_tag_edges(
    conn: &Connection,
    device_id: &str,
    hlc_state: &mut HlcState,
    edges: &[TaskTagEdgeDelete],
) -> Result<(), CliError> {
    for edge in edges {
        let task_id = lorvex_domain::TaskId::from_trusted(edge.task_id.clone());
        let tag_id = lorvex_domain::TagId::from_trusted(edge.tag_id.clone());
        let payload = lorvex_store::payload_loaders::task_tag_payload(
            &task_id,
            &tag_id,
            &edge.version,
            &edge.created_at,
        );
        let entity_id = format!("{}:{}", edge.task_id, edge.tag_id);
        let version = hlc_state.generate().to_string();
        enqueue_payload_delete(
            conn,
            EDGE_TASK_TAG,
            &entity_id,
            &payload,
            crate::commands::shared::bare_outbox_ctx(&version, device_id),
        )?;
    }
    Ok(())
}

/// Per-successor task upsert + audit changelog row (`operation`
/// distinguishes spawn from cancellation).
pub(crate) fn enqueue_successors<'a>(
    conn: &Connection,
    device_id: &str,
    hlc_state: &mut HlcState,
    operation: &'static str,
    successors: impl IntoIterator<Item = SuccessorView<'a>>,
) -> Result<(), CliError> {
    for successor in successors {
        enqueue_entity_upsert(
            conn,
            ENTITY_TASK,
            successor.successor_id,
            hlc_state,
            device_id,
        )?;
        log_cli_changelog_with_state(
            conn,
            hlc_state,
            CliChangelogParams {
                operation,
                entity_type: ENTITY_TASK,
                entity_id: successor.successor_id,
                summary: successor.summary,
                before_json: None,
                after_json: Some(successor.after_task.clone()),
            },
        )?;
    }
    Ok(())
}

/// Inherited children spawned alongside a recurrence successor: tag
/// edges (via the shared tag-effects helper), checklist items, and
/// reminders.
pub(crate) fn enqueue_spawned_children(
    conn: &Connection,
    device_id: &str,
    hlc_state: &mut HlcState,
    tag_edges: &[CopiedTagEdge],
    checklist_item_ids: &[String],
    reminder_ids: &[String],
) -> Result<(), CliError> {
    crate::commands::mutate::tags::effects::enqueue_copied_tag_edges(
        conn, hlc_state, device_id, tag_edges,
    )?;
    enqueue_upserts(
        conn,
        device_id,
        hlc_state,
        ENTITY_TASK_CHECKLIST_ITEM,
        checklist_item_ids,
    )?;
    enqueue_upserts(
        conn,
        device_id,
        hlc_state,
        ENTITY_TASK_REMINDER,
        reminder_ids,
    )?;
    Ok(())
}

/// Unified accessor trait over the create/batch_create/batch_update
/// task-write effect bundles (`CreateTaskSyncEffects`,
/// `BatchCreateSyncEffects`, `BatchUpdateSyncEffects`). Default-empty
/// getters let each `impl` declare only the categories its verb
/// actually emits; [`enqueue_task_lifecycle_effects`] drives every
/// per-verb flush through the same canonical sequence.
///
/// `task.batch_cancel_in_list` routes through the workflow's
/// `BatchCancelFlushBackend` (sibling `batch_cancel/flush.rs`)
/// instead, since the canonical ordering for that verb lives in
/// `lorvex_workflow::task_batch_cancel::flush_batch_cancel_with_backend`.
pub(crate) trait HasTaskWriteEffects {
    fn task_upsert_ids(&self) -> &[String] {
        &[]
    }
    fn tag_upsert_ids(&self) -> &[String] {
        &[]
    }
    fn task_tag_edge_upsert_ids(&self) -> &[String] {
        &[]
    }
    fn deleted_task_tag_edges(&self) -> &[TaskTagEdgeDelete] {
        &[]
    }
    fn dependency_edge_upsert_ids(&self) -> &[String] {
        &[]
    }
    fn deleted_dependency_edges(&self) -> &[lorvex_workflow::lifecycle::DeletedDependencyEdge] {
        &[]
    }
    fn reminder_upsert_ids(&self) -> &[String] {
        &[]
    }
    fn cancelled_reminder_ids(&self) -> &[String] {
        &[]
    }
    fn affected_dependent_ids(&self) -> &[String] {
        &[]
    }
    fn spawned_successors(&self) -> Vec<SuccessorView<'_>> {
        Vec::new()
    }
    fn spawned_successor_tag_edges(&self) -> &[CopiedTagEdge] {
        &[]
    }
    fn spawned_successor_checklist_item_ids(&self) -> &[String] {
        &[]
    }
    fn spawned_successor_reminder_ids(&self) -> &[String] {
        &[]
    }
    fn cancelled_successors(&self) -> Vec<SuccessorView<'_>> {
        Vec::new()
    }
    fn rewired_focus_schedule_dates(&self) -> &[String] {
        &[]
    }
    fn rewired_current_focus_dates(&self) -> &[String] {
        &[]
    }
}

impl HasTaskWriteEffects for lorvex_workflow::task_create::CreateTaskSyncEffects {
    fn task_upsert_ids(&self) -> &[String] {
        &self.task_upsert_ids
    }
    fn tag_upsert_ids(&self) -> &[String] {
        &self.tag_upsert_ids
    }
    fn task_tag_edge_upsert_ids(&self) -> &[String] {
        &self.task_tag_edge_upsert_ids
    }
    fn dependency_edge_upsert_ids(&self) -> &[String] {
        &self.dependency_edge_upsert_ids
    }
    fn reminder_upsert_ids(&self) -> &[String] {
        &self.reminder_upsert_ids
    }
    fn cancelled_reminder_ids(&self) -> &[String] {
        &self.cancelled_reminder_ids
    }
    fn spawned_successors(&self) -> Vec<SuccessorView<'_>> {
        self.spawned_successors
            .iter()
            .map(|s| SuccessorView {
                successor_id: s.successor_id.as_str(),
                summary: &s.summary,
                after_task: &s.after_task,
            })
            .collect()
    }
    fn spawned_successor_tag_edges(&self) -> &[CopiedTagEdge] {
        &self.spawned_successor_tag_edges
    }
    fn spawned_successor_checklist_item_ids(&self) -> &[String] {
        &self.spawned_successor_checklist_item_ids
    }
    fn spawned_successor_reminder_ids(&self) -> &[String] {
        &self.spawned_successor_reminder_ids
    }
    fn rewired_focus_schedule_dates(&self) -> &[String] {
        &self.rewired_focus_schedule_dates
    }
    fn rewired_current_focus_dates(&self) -> &[String] {
        &self.rewired_current_focus_dates
    }
}

impl HasTaskWriteEffects for lorvex_workflow::task_batch_create::BatchCreateSyncEffects {
    fn task_upsert_ids(&self) -> &[String] {
        &self.task_upsert_ids
    }
    fn tag_upsert_ids(&self) -> &[String] {
        &self.tag_upsert_ids
    }
    fn task_tag_edge_upsert_ids(&self) -> &[String] {
        &self.task_tag_edge_upsert_ids
    }
    fn dependency_edge_upsert_ids(&self) -> &[String] {
        &self.dependency_edge_upsert_ids
    }
    fn deleted_dependency_edges(&self) -> &[lorvex_workflow::lifecycle::DeletedDependencyEdge] {
        &self.deleted_dependency_edges
    }
    fn reminder_upsert_ids(&self) -> &[String] {
        &self.reminder_upsert_ids
    }
    fn cancelled_reminder_ids(&self) -> &[String] {
        &self.cancelled_reminder_ids
    }
    fn affected_dependent_ids(&self) -> &[String] {
        &self.affected_dependent_ids
    }
    fn spawned_successors(&self) -> Vec<SuccessorView<'_>> {
        self.spawned_successors
            .iter()
            .map(|s| SuccessorView {
                successor_id: s.successor_id.as_str(),
                summary: &s.summary,
                after_task: &s.after_task,
            })
            .collect()
    }
    fn spawned_successor_tag_edges(&self) -> &[CopiedTagEdge] {
        &self.spawned_successor_tag_edges
    }
    fn spawned_successor_checklist_item_ids(&self) -> &[String] {
        &self.spawned_successor_checklist_item_ids
    }
    fn spawned_successor_reminder_ids(&self) -> &[String] {
        &self.spawned_successor_reminder_ids
    }
    fn rewired_focus_schedule_dates(&self) -> &[String] {
        &self.rewired_focus_schedule_dates
    }
    fn rewired_current_focus_dates(&self) -> &[String] {
        &self.rewired_current_focus_dates
    }
}

impl HasTaskWriteEffects for lorvex_workflow::task_batch_update::BatchUpdateSyncEffects {
    fn task_upsert_ids(&self) -> &[String] {
        &self.task_upsert_ids
    }
    fn tag_upsert_ids(&self) -> &[String] {
        &self.tag_upsert_ids
    }
    fn task_tag_edge_upsert_ids(&self) -> &[String] {
        &self.task_tag_edge_upsert_ids
    }
    fn deleted_task_tag_edges(&self) -> &[TaskTagEdgeDelete] {
        &self.deleted_task_tag_edges
    }
    fn dependency_edge_upsert_ids(&self) -> &[String] {
        &self.dependency_edge_upsert_ids
    }
    fn deleted_dependency_edges(&self) -> &[lorvex_workflow::lifecycle::DeletedDependencyEdge] {
        &self.deleted_dependency_edges
    }
    fn reminder_upsert_ids(&self) -> &[String] {
        &self.reminder_upsert_ids
    }
    fn affected_dependent_ids(&self) -> &[String] {
        &self.affected_dependent_ids
    }
    fn spawned_successors(&self) -> Vec<SuccessorView<'_>> {
        self.spawned_successors
            .iter()
            .map(|s| SuccessorView {
                successor_id: &s.successor_id,
                summary: &s.summary,
                after_task: &s.after_task,
            })
            .collect()
    }
    fn spawned_successor_tag_edges(&self) -> &[CopiedTagEdge] {
        &self.spawned_successor_tag_edges
    }
    fn spawned_successor_checklist_item_ids(&self) -> &[String] {
        &self.spawned_successor_checklist_item_ids
    }
    fn spawned_successor_reminder_ids(&self) -> &[String] {
        &self.spawned_successor_reminder_ids
    }
    fn cancelled_successors(&self) -> Vec<SuccessorView<'_>> {
        self.cancelled_successors
            .iter()
            .map(|s| SuccessorView {
                successor_id: &s.successor_id,
                summary: &s.summary,
                after_task: &s.after_task,
            })
            .collect()
    }
    fn rewired_focus_schedule_dates(&self) -> &[String] {
        &self.rewired_focus_schedule_dates
    }
    fn rewired_current_focus_dates(&self) -> &[String] {
        &self.rewired_current_focus_dates
    }
}

/// Drive every category of a task-write effect bundle through the
/// canonical CLI outbox-enqueue sequence:
///
/// 1. task upserts
/// 2. tag upserts → task_tag edge upserts → task_tag edge tombstones
/// 3. dependency edge upserts → dependency edge tombstones
/// 4. reminder upserts → cancelled reminder upserts (still on
///    `ENTITY_TASK_REMINDER` — completion sets `cancelled_at` and the
///    row's own `version`, so the cancelled list is still an upsert
///    of the cancelled-state row).
/// 5. affected-dependent task upserts (re-emit `dependent` rows whose
///    blocker state changed downstream).
/// 6. spawned successor task upserts + audit changelog
/// 7. spawned successor child rows (tags, checklist items, reminders)
/// 8. cancelled successor task upserts + audit changelog
/// 9. focus_schedule / current_focus aggregate rewires
///
/// Per-verb flush wrappers shrink to ~10 LOC: build the effects
/// bundle, then `enqueue_task_lifecycle_effects(conn, device_id,
/// hlc, &effects)` runs every category the verb actually populated
/// (every other category resolves to an empty slice via the trait's
/// defaults). The order is single-sourced here so a future verb is
/// guaranteed to emit envelopes in the same canonical sequence.
pub(crate) fn enqueue_task_lifecycle_effects<E: HasTaskWriteEffects + ?Sized>(
    conn: &Connection,
    device_id: &str,
    hlc_state: &mut HlcState,
    effects: &E,
) -> Result<(), CliError> {
    enqueue_upserts(
        conn,
        device_id,
        hlc_state,
        ENTITY_TASK,
        effects.task_upsert_ids(),
    )?;
    enqueue_upserts(
        conn,
        device_id,
        hlc_state,
        lorvex_domain::naming::ENTITY_TAG,
        effects.tag_upsert_ids(),
    )?;
    enqueue_upserts(
        conn,
        device_id,
        hlc_state,
        EDGE_TASK_TAG,
        effects.task_tag_edge_upsert_ids(),
    )?;
    enqueue_deleted_task_tag_edges(conn, device_id, hlc_state, effects.deleted_task_tag_edges())?;
    enqueue_upserts(
        conn,
        device_id,
        hlc_state,
        lorvex_domain::naming::EDGE_TASK_DEPENDENCY,
        effects.dependency_edge_upsert_ids(),
    )?;
    crate::commands::mutate::tasks::dependencies::enqueue_deleted_dependency_edges(
        conn,
        hlc_state,
        device_id,
        effects.deleted_dependency_edges(),
    )?;
    enqueue_upserts(
        conn,
        device_id,
        hlc_state,
        ENTITY_TASK_REMINDER,
        effects.reminder_upsert_ids(),
    )?;
    enqueue_upserts(
        conn,
        device_id,
        hlc_state,
        ENTITY_TASK_REMINDER,
        effects.cancelled_reminder_ids(),
    )?;
    enqueue_upserts(
        conn,
        device_id,
        hlc_state,
        ENTITY_TASK,
        effects.affected_dependent_ids(),
    )?;
    enqueue_successors(
        conn,
        device_id,
        hlc_state,
        "create",
        effects.spawned_successors(),
    )?;
    enqueue_spawned_children(
        conn,
        device_id,
        hlc_state,
        effects.spawned_successor_tag_edges(),
        effects.spawned_successor_checklist_item_ids(),
        effects.spawned_successor_reminder_ids(),
    )?;
    enqueue_successors(
        conn,
        device_id,
        hlc_state,
        "cancel",
        effects.cancelled_successors(),
    )?;
    enqueue_focus_rewires(
        conn,
        device_id,
        hlc_state,
        effects.rewired_focus_schedule_dates(),
        effects.rewired_current_focus_dates(),
    )?;
    Ok(())
}

/// Bump every affected `focus_schedule` and `current_focus` aggregate.
pub(crate) fn enqueue_focus_rewires(
    conn: &Connection,
    device_id: &str,
    hlc_state: &mut HlcState,
    focus_schedule_dates: &[String],
    current_focus_dates: &[String],
) -> Result<(), CliError> {
    for date in focus_schedule_dates {
        crate::commands::shared::effects::enqueue_aggregate_root_upsert(
            conn,
            hlc_state,
            device_id,
            ENTITY_FOCUS_SCHEDULE,
            date,
        )?;
    }
    for date in current_focus_dates {
        crate::commands::shared::effects::enqueue_aggregate_root_upsert(
            conn,
            hlc_state,
            device_id,
            ENTITY_CURRENT_FOCUS,
            date,
        )?;
    }
    Ok(())
}
