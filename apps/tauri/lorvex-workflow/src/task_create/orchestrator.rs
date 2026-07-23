//! The canonical task-create orchestrator.
//!
//! Runs the validation → INSERT → child-row fan-out → optional
//! completion pipeline, accumulating every emitted row into
//! [`super::effects::CreateTaskSyncEffects`] so each consumer surface
//! (mcp-server, CLI, Tauri commands) can drive the same outbox enqueue
//! path. The sequence:
//!
//! 1. Optionally drop `raw_input` when the user preference disables capture.
//! 2. [`super::prepared::prepare_task_insert`] validates + normalizes
//!    every field and produces a [`super::prepared::PreparedTaskInsert`].
//! 3. The row + its tag / reminder / dependency-edge children are
//!    written and their IDs accumulated.
//! 4. When `completed: true`, [`crate::lifecycle::effects::run_completion`]
//!    runs immediately and any spawned successor / focus rewire / cancelled
//!    reminder is folded into the same effects envelope.
//! 5. Final payload is the enriched task JSON + optional next-occurrence +
//!    newly-unblocked dependents + optional intake advice.

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::{Patch, TaskId};
use lorvex_store::StoreError;
use rusqlite::Connection;
use serde_json::{json, Value};

use super::advice::build_task_intake_advice;
use super::child_inserts::{insert_dependency_edges, insert_task_reminders, insert_task_tags};
use super::effects::CreateTaskSyncEffects;
use super::input::{
    CreateTaskFocusRewireAudit, CreateTaskInput, CreateTaskResult, CreateTaskSpawnedSuccessor,
};
use super::prepared::{build_create_summary, prepare_task_insert};

pub fn create_task(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    input: CreateTaskInput,
) -> Result<CreateTaskResult, StoreError> {
    let CreateTaskInput {
        id,
        task: mut input,
        include_advice,
    } = input;
    let should_complete = input.completed.unwrap_or(false);
    if !input.raw_input.is_unset() && !should_store_raw_input(conn)? {
        // Preference disables raw-input capture: collapse any
        // incoming `Set` / `Clear` back to `Unset` so the writer
        // skips the column entirely.
        input.raw_input = Patch::Unset;
    }
    let reminders = input.reminders.clone();
    let now = lorvex_domain::sync_timestamp_now();
    let task_id = id.unwrap_or_else(lorvex_domain::new_entity_id_string);
    let typed_task_id = TaskId::from_trusted(task_id.clone());
    let prepared = prepare_task_insert(conn, hlc, task_id.clone(), now.clone(), input)?;
    prepared.execute_insert(conn)?;

    let mut sync_effects = CreateTaskSyncEffects::default();
    let tag_effects = insert_task_tags(conn, hlc, &typed_task_id, &prepared.tags)?;
    sync_effects
        .tag_upsert_ids
        .extend(tag_effects.tag_upsert_ids);
    sync_effects
        .task_tag_edge_upsert_ids
        .extend(tag_effects.task_tag_edge_upsert_ids);
    sync_effects
        .reminder_upsert_ids
        .extend(insert_task_reminders(conn, hlc, &task_id, reminders)?);
    sync_effects
        .dependency_edge_upsert_ids
        .extend(insert_dependency_edges(
            conn,
            hlc,
            &typed_task_id,
            &prepared.depends_on,
        )?);
    sync_effects.task_upsert_ids.push(task_id);

    let mut next_occurrence = Value::Null;
    let newly_unblocked_ids = if should_complete {
        let completion =
            crate::lifecycle::effects::run_completion(conn, &typed_task_id, &now, hlc)?;
        sync_effects
            .cancelled_reminder_ids
            .extend(completion.cancelled_reminder_ids);
        if let Some(successor_id) = completion.spawned_successor_id {
            let typed_successor_id = TaskId::from_trusted(successor_id);
            sync_effects
                .focus_rewire_audits
                .push(CreateTaskFocusRewireAudit {
                    parent_task_id: typed_task_id.clone(),
                    successor_id: typed_successor_id.clone(),
                    focus_schedule_dates: completion.rewired_focus_schedule_dates.clone(),
                    current_focus_dates: completion.rewired_current_focus_dates.clone(),
                });
            let successor =
                crate::task_response::load_enriched_task_json(conn, &typed_successor_id)?;
            next_occurrence = successor.clone();
            sync_effects
                .spawned_successors
                .push(CreateTaskSpawnedSuccessor {
                    successor_id: typed_successor_id,
                    summary: "Spawned recurrence successor from pre-completed create".to_string(),
                    after_task: successor,
                });
        }
        sync_effects
            .spawned_successor_tag_edges
            .extend(completion.spawned_successor_tag_edges);
        sync_effects
            .spawned_successor_checklist_item_ids
            .extend(completion.spawned_successor_checklist_item_ids);
        sync_effects
            .spawned_successor_reminder_ids
            .extend(completion.spawned_successor_reminder_ids);
        sync_effects
            .rewired_focus_schedule_dates
            .extend(completion.rewired_focus_schedule_dates);
        sync_effects
            .rewired_current_focus_dates
            .extend(completion.rewired_current_focus_dates);
        find_active_tasks_depending_on(conn, &typed_task_id)?
    } else {
        Vec::new()
    };

    let task = crate::task_response::load_enriched_task_json(conn, &typed_task_id)?;
    let newly_unblocked =
        crate::task_response::load_enriched_tasks_json(conn, &newly_unblocked_ids)?;
    let advice = if include_advice {
        build_task_intake_advice(conn, &task)?
    } else {
        Vec::new()
    };
    let summary = build_create_summary(conn, &prepared, should_complete)?;
    let payload = json!({
        "task": task,
        "next_occurrence": next_occurrence,
        "newly_unblocked": newly_unblocked,
        "advice": advice,
    });

    Ok(CreateTaskResult {
        task_id: typed_task_id,
        task: payload["task"].clone(),
        next_occurrence: payload["next_occurrence"].clone(),
        newly_unblocked: payload["newly_unblocked"]
            .as_array()
            .cloned()
            .unwrap_or_default(),
        advice: payload["advice"].as_array().cloned().unwrap_or_default(),
        payload,
        summary,
        sync_effects,
    })
}

fn find_active_tasks_depending_on(
    conn: &Connection,
    task_id: &TaskId,
) -> Result<Vec<String>, StoreError> {
    static SQL: std::sync::OnceLock<String> = std::sync::OnceLock::new();
    let mut stmt = conn.prepare_cached(SQL.get_or_init(|| {
        format!(
            "SELECT td.task_id FROM task_dependencies td
                 JOIN tasks t ON t.id = td.task_id
                 WHERE td.depends_on_task_id = ?1
                   AND t.status IN ({active_list})
                   AND t.archived_at IS NULL",
            active_list = lorvex_domain::naming::status::ACTIVE_STATUS_SQL_LIST,
        )
    }))?;
    let ids = stmt
        .query_map([task_id.as_str()], |row| row.get::<_, String>(0))?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(ids)
}

pub fn should_store_raw_input(conn: &Connection) -> Result<bool, StoreError> {
    let raw = match conn.query_row(
        "SELECT value FROM preferences WHERE key = ?1",
        [lorvex_domain::preference_keys::PREF_RECORD_RAW_INPUT],
        |row| row.get::<_, String>(0),
    ) {
        Ok(value) => value,
        Err(rusqlite::Error::QueryReturnedNoRows) => return Ok(true),
        Err(error) => return Err(StoreError::from(error)),
    };

    lorvex_domain::parse_json_bool_preference(Some(&raw)).ok_or_else(|| {
        StoreError::Validation(format!(
            "{} preference must be a JSON boolean",
            lorvex_domain::preference_keys::PREF_RECORD_RAW_INPUT
        ))
    })
}
