use crate::contract::PermanentDeleteTaskArgs;
use crate::contract_validate::ContractValidate;
use crate::error::McpError;
use crate::json_row::query_all_as_json;
use crate::runtime::change_tracking::{
    execute_mcp_mutation_with_tombstone_audit_finalizer, log_change, LogChangeParams,
};
use crate::system::handler_support::fetch_task_json;
use crate::tasks::dependencies::{
    cleanup_plan_refs_after_removal, remove_task_from_all_deps, sync_dep_affected_tasks,
};
use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{
    EDGE_TASK_CALENDAR_EVENT_LINK, EDGE_TASK_TAG, ENTITY_TASK, ENTITY_TASK_CHECKLIST_ITEM,
    ENTITY_TASK_REMINDER, OP_DELETE,
};
use lorvex_domain::TaskId;
use lorvex_store::StoreError;
use lorvex_workflow::mutation::{Mutation, MutationOutput};
use rusqlite::Connection;
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashMap};

/// pre-delete row snapshots for every child + edge
/// table that `permanent_delete_task` will lose to the
/// `ON DELETE CASCADE` chain.
/// degenerate `{id, task_id}` (or composite-key) envelopes from just
/// the foreign-key columns, so a peer that had already GC'd its copy
/// could not reconstruct `before_json` from the tombstone. Sibling
/// delete paths (#2818, #2928-H1) load
/// the full pre-delete row JSON; this struct mirrors that pattern.
///
/// Each map is keyed by the outbox `entity_id`:
/// - `task_tags`, `task_calendar_event_links` → `"task_id:other_id"`
/// - `task_checklist_items`, `task_reminders` → row PK `id`
struct TaskCascadeDeleteSnapshots {
    /// `task_tags` rows, keyed by `"task_id:tag_id"`.
    tag_edges: BTreeMap<String, Value>,
    /// `task_checklist_items` rows, keyed by row id.
    checklist_items: BTreeMap<String, Value>,
    /// `task_reminders` rows, keyed by row id.
    reminders: BTreeMap<String, Value>,
    /// `task_calendar_event_links` rows, keyed by
    /// `"task_id:calendar_event_id"`.
    calendar_link_edges: BTreeMap<String, Value>,
}

/// Snapshot every child + edge row joined on `task_id = ?` BEFORE the
/// parent `DELETE FROM tasks` fires the FK cascade, so each
/// per-entity tombstone payload can carry the full pre-delete row.
///
/// Only enumerates the **synced** child + edge tables. Parent-owned
/// soft refs (`current_focus_items`, `focus_schedule_blocks`) are
/// scrubbed by `cleanup_plan_refs_after_removal` and never independently
/// synced. Local-only edges (`task_provider_event_links`) and
/// reminder-scoped delivery state (`task_reminder_delivery_state`,
/// which cascades through `task_reminders`) are not in
/// `ALL_SYNCABLE_TYPES`, so emitting tombstones for them would be a
/// no-op at the outbox boundary. `task_dependencies` is handled
/// upstream by `remove_task_from_all_deps`, which already loads its
/// own composite-key snapshots and enqueues per-edge tombstones —
/// re-snapshotting here would either duplicate or, worse, see an
/// already-deleted row.
fn collect_cascaded_task_snapshots(
    conn: &Connection,
    task_id: &str,
) -> Result<TaskCascadeDeleteSnapshots, McpError> {
    let mut tag_edges: BTreeMap<String, Value> = BTreeMap::new();
    for row in query_all_as_json(
        conn,
        "SELECT * FROM task_tags WHERE task_id = ?1",
        [task_id],
    )? {
        let tag_id = row
            .get("tag_id")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                McpError::Internal(
                    "task_tags row missing `tag_id` while snapshotting cascade".to_string(),
                )
            })?
            .to_string();
        tag_edges.insert(format!("{task_id}:{tag_id}"), row);
    }

    let mut checklist_items: BTreeMap<String, Value> = BTreeMap::new();
    for row in query_all_as_json(
        conn,
        "SELECT * FROM task_checklist_items WHERE task_id = ?1",
        [task_id],
    )? {
        let id = row
            .get("id")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                McpError::Internal(
                    "task_checklist_items row missing `id` while snapshotting cascade".to_string(),
                )
            })?
            .to_string();
        checklist_items.insert(id, row);
    }

    let mut reminders: BTreeMap<String, Value> = BTreeMap::new();
    for row in query_all_as_json(
        conn,
        "SELECT * FROM task_reminders WHERE task_id = ?1",
        [task_id],
    )? {
        let id = row
            .get("id")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                McpError::Internal(
                    "task_reminders row missing `id` while snapshotting cascade".to_string(),
                )
            })?
            .to_string();
        reminders.insert(id, row);
    }

    let mut calendar_link_edges: BTreeMap<String, Value> = BTreeMap::new();
    for row in query_all_as_json(
        conn,
        "SELECT * FROM task_calendar_event_links WHERE task_id = ?1",
        [task_id],
    )? {
        let event_id = row
            .get("calendar_event_id")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                McpError::Internal(
                    "task_calendar_event_links row missing `calendar_event_id` while snapshotting cascade"
                        .to_string(),
                )
            })?
            .to_string();
        calendar_link_edges.insert(format!("{task_id}:{event_id}"), row);
    }

    Ok(TaskCascadeDeleteSnapshots {
        tag_edges,
        checklist_items,
        reminders,
        calendar_link_edges,
    })
}

struct PermanentDeleteTaskMutation {
    id: TaskId,
    before: Value,
    title: String,
}

impl Mutation for PermanentDeleteTaskMutation {
    fn entity_kind(&self) -> &'static str {
        ENTITY_TASK
    }

    fn operation(&self) -> &'static str {
        "permanent_delete"
    }

    fn pre_snapshot(&self, _conn: &Connection) -> Result<Option<Value>, StoreError> {
        Ok(Some(self.before.clone()))
    }

    fn apply(&self, conn: &Connection, hlc: &HlcSession<'_>) -> Result<MutationOutput, StoreError> {
        let delete_version = hlc.next_version_string();
        let deleted = lorvex_store::repositories::task::write::hard_delete_task_lww(
            conn,
            &self.id,
            &delete_version,
        )? > 0;
        Ok(MutationOutput::new(
            json!({
                "id": self.id.as_str(),
                "deleted": deleted,
                "previous": self.before,
            }),
            format!("Permanently deleted task '{}'", self.title),
        ))
    }
}

fn log_cascaded_child_tombstones(
    conn: &Connection,
    cascaded_children: &TaskCascadeDeleteSnapshots,
    title: &str,
) -> Result<(), McpError> {
    // thread the
    // pre-delete row JSON for every cascaded child + edge through
    // both the changelog `before_json` slot and the outbox
    // tombstone payload.
    // from just the composite-key fields ({id, task_id} / {task_id,
    // tag_id}, etc.), which peers that had GC'd their copies
    // could not reconstruct from. The full row carries text,
    // version, created_at, completed_at, dismissed_at, and so on
    // — everything `read_current_entity_snapshot` would have
    // returned had the row still existed at outbox time.
    for (edge_id, snapshot) in &cascaded_children.tag_edges {
        let mut tombstones: HashMap<String, Value> = HashMap::with_capacity(1);
        tombstones.insert(edge_id.clone(), snapshot.clone());
        log_change(
            conn,
            LogChangeParams::new(
                OP_DELETE,
                EDGE_TASK_TAG,
                "permanent_delete_task",
                format!("Removed tag link '{edge_id}' while deleting task '{title}'"),
            )
            .with_entity_id(edge_id.clone())
            .with_before(snapshot.clone()),
            Some(&tombstones),
        )?;
    }

    for (checklist_item_id, snapshot) in &cascaded_children.checklist_items {
        let mut tombstones: HashMap<String, Value> = HashMap::with_capacity(1);
        tombstones.insert(checklist_item_id.clone(), snapshot.clone());
        log_change(
            conn,
            LogChangeParams::new(
                OP_DELETE,
                ENTITY_TASK_CHECKLIST_ITEM,
                "permanent_delete_task",
                format!(
                    "Removed checklist item '{checklist_item_id}' while deleting task '{title}'"
                ),
            )
            .with_entity_id(checklist_item_id.clone())
            .with_before(snapshot.clone()),
            Some(&tombstones),
        )?;
    }

    for (reminder_id, snapshot) in &cascaded_children.reminders {
        let mut tombstones: HashMap<String, Value> = HashMap::with_capacity(1);
        tombstones.insert(reminder_id.clone(), snapshot.clone());
        log_change(
            conn,
            LogChangeParams::new(
                OP_DELETE,
                ENTITY_TASK_REMINDER,
                "permanent_delete_task",
                format!("Removed reminder '{reminder_id}' while deleting task '{title}'"),
            )
            .with_entity_id(reminder_id.clone())
            .with_before(snapshot.clone()),
            Some(&tombstones),
        )?;
    }

    for (edge_id, snapshot) in &cascaded_children.calendar_link_edges {
        let mut tombstones: HashMap<String, Value> = HashMap::with_capacity(1);
        tombstones.insert(edge_id.clone(), snapshot.clone());
        log_change(
            conn,
            LogChangeParams::new(
                OP_DELETE,
                EDGE_TASK_CALENDAR_EVENT_LINK,
                "permanent_delete_task",
                format!("Removed calendar link '{edge_id}' while deleting task '{title}'"),
            )
            .with_entity_id(edge_id.clone())
            .with_before(snapshot.clone()),
            Some(&tombstones),
        )?;
    }
    Ok(())
}

pub(crate) fn permanent_delete_task(
    conn: &Connection,
    args: PermanentDeleteTaskArgs,
) -> Result<String, McpError> {
    let request_repr = crate::runtime::idempotency::canonical_request_repr(&args)?;
    args.validate_shape()?;
    let PermanentDeleteTaskArgs {
        id,
        // `dry_run` is consumed at the router layer (#2370).
        dry_run: _,
        idempotency_key,
    } = args;
    if let Some(cached) = crate::runtime::idempotency::lookup_cached(
        conn,
        "permanent_delete_task",
        idempotency_key.as_deref(),
        &request_repr,
    )? {
        return Ok(cached);
    }

    // see `complete_task` — derive enforced UUID format; trim
    // defensively to match the prior `validate_uuid_arg` return shape.
    let id = id.trim().to_string();
    let before = fetch_task_json(conn, &id)?;

    // the Tauri `permanent_delete_task` command
    // already requires `archived_at IS NOT NULL` so the UI delete flow
    // is two-step (Trash → Permanently delete). Mirror that gate here
    // so the MCP tool cannot bypass Trash and destroy a live task in a
    // single call — every hard-delete now has a prior `archive_task`
    // mutation the user can see and undo during the 30-day retention
    // window.
    let archived_at = before
        .get("archived_at")
        .and_then(serde_json::Value::as_str);
    if archived_at.is_none() {
        return Err(McpError::Validation(
            "task must be archived via archive_task before permanent_delete_task can remove it; \
             the two-step Trash flow prevents a single MCP call from destroying live data \
             (issue #2363)"
                .to_string(),
        ));
    }

    let id_typed = lorvex_domain::TaskId::from_trusted(id.clone());
    let dep_affected = remove_task_from_all_deps(conn, &id_typed)?;
    // snapshot every child + edge BEFORE the parent
    // `DELETE FROM tasks` fires the FK cascade, otherwise the rows
    // are gone and the tombstone payload degrades to the composite
    // key. Order matters: this must run AFTER
    // `remove_task_from_all_deps` (which deletes dependency edges and
    // emits its own per-edge snapshots) but BEFORE the parent delete
    // below.
    let cascaded_children = collect_cascaded_task_snapshots(conn, &id)?;

    // Sync updated dependency arrays before deleting the main task.
    // (dep-affected rows are already updated by remove_task_from_all_deps.)
    let title = before
        .get("title")
        .and_then(serde_json::Value::as_str)
        .unwrap_or("task")
        .to_string();
    sync_dep_affected_tasks(conn, &dep_affected, &title, "permanent_delete_task")?;

    // Clean orphaned references from current_focus and focus_schedule.
    cleanup_plan_refs_after_removal(conn, &id_typed)?;

    let mutation = PermanentDeleteTaskMutation {
        id: id_typed,
        before: before.clone(),
        title: title.clone(),
    };
    let mut parent_tombstones: HashMap<String, Value> = HashMap::with_capacity(1);
    parent_tombstones.insert(id.clone(), before);
    let output = execute_mcp_mutation_with_tombstone_audit_finalizer(
        conn,
        &mutation,
        "permanent_delete_task",
        id,
        parent_tombstones,
        McpError::from,
        move |conn, execution| {
            if execution
                .output
                .after
                .get("deleted")
                .and_then(Value::as_bool)
                == Some(true)
            {
                log_cascaded_child_tombstones(conn, &cascaded_children, &title)?;
            }
            Ok(())
        },
    )?;

    // CLAUDE.md rule 5 — include the pre-delete snapshot
    // so the assistant can narrate what was removed ("deleted 'X',
    // which was due tomorrow and tagged #work") and potentially drive
    // a human-facing undo/confirm flow. The snapshot is NOT an actual
    // undo path — permanent_delete is destructive by design — but the
    // caller can print the fields that disappeared.
    let response = serde_json::to_string(&output.after)?;
    crate::runtime::idempotency::record_if_keyed(
        conn,
        idempotency_key.as_deref(),
        "permanent_delete_task",
        &request_repr,
        &response,
    )?;
    Ok(response)
}
