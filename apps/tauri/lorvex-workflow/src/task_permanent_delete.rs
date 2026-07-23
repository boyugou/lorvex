use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::naming::{
    EDGE_TASK_CALENDAR_EVENT_LINK, EDGE_TASK_DEPENDENCY, EDGE_TASK_TAG, ENTITY_TASK,
    ENTITY_TASK_CHECKLIST_ITEM, ENTITY_TASK_REMINDER,
};
use lorvex_domain::TaskId;
use lorvex_store::repositories::task::read;
use lorvex_store::StoreError;
use rusqlite::Connection;
use serde_json::{json, Value};

#[derive(Debug, Clone)]
pub struct PermanentDeleteTaskInput {
    pub task_id: TaskId,
}

#[derive(Debug, Clone)]
pub struct SyncPayloadChange {
    pub entity_type: &'static str,
    pub entity_id: String,
    pub payload: Value,
}

#[derive(Debug, Clone, Default)]
pub struct FocusParentDates {
    pub current_focus: Vec<String>,
    pub focus_schedule: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct PermanentDeleteTaskResult {
    pub task_id: String,
    pub title: String,
    pub deleted: bool,
    pub payload: Value,
    pub before_task: Value,
    pub delete_syncs: Vec<SyncPayloadChange>,
    pub focus_parent_dates: FocusParentDates,
    pub summary: String,
}

fn collect_focus_parent_dates_for_task(
    conn: &Connection,
    task_id: &str,
) -> Result<FocusParentDates, StoreError> {
    let current_focus = {
        let mut stmt = conn
            .prepare_cached("SELECT DISTINCT date FROM current_focus_items WHERE task_id = ?1")?;
        let rows = stmt
            .query_map([task_id], |row| row.get::<_, String>(0))?
            .collect::<Result<Vec<_>, _>>()?;
        rows
    };
    let focus_schedule = {
        let mut stmt = conn.prepare_cached(
            "SELECT DISTINCT schedule_date FROM focus_schedule_blocks WHERE task_id = ?1",
        )?;
        let rows = stmt
            .query_map([task_id], |row| row.get::<_, String>(0))?
            .collect::<Result<Vec<_>, _>>()?;
        rows
    };
    Ok(FocusParentDates {
        current_focus,
        focus_schedule,
    })
}

fn tagged_changes(entity_type: &'static str, rows: Vec<(String, Value)>) -> Vec<SyncPayloadChange> {
    rows.into_iter()
        .map(|(entity_id, payload)| SyncPayloadChange {
            entity_type,
            entity_id,
            payload,
        })
        .collect()
}

pub fn permanent_delete_task(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    input: PermanentDeleteTaskInput,
) -> Result<PermanentDeleteTaskResult, StoreError> {
    let task_id = input.task_id;
    let task_id_str = task_id.to_string();
    let before = read::get_task(conn, &task_id)?.ok_or_else(|| StoreError::NotFound {
        entity: ENTITY_TASK,
        id: task_id_str.clone(),
    })?;
    if before.lifecycle().archived_at().is_none() {
        return Err(StoreError::Validation(
            "task must be archived via archive_task before permanent_delete_task can remove it; \
             the two-step Trash flow prevents a single MCP call from destroying live data \
             (issue #2363)"
                .to_string(),
        ));
    }

    let title = before.core().title().to_string();
    let before_task = serde_json::to_value(&before)?;

    let mut delete_syncs = Vec::new();
    delete_syncs.extend(tagged_changes(
        EDGE_TASK_TAG,
        lorvex_store::payload_loaders::load_task_tags_for_task(conn, &task_id)?,
    ));
    delete_syncs.extend(tagged_changes(
        ENTITY_TASK_CHECKLIST_ITEM,
        lorvex_store::payload_loaders::load_task_checklist_items_for_task(conn, &task_id)?,
    ));
    delete_syncs.extend(tagged_changes(
        ENTITY_TASK_REMINDER,
        lorvex_store::payload_loaders::load_task_reminders_for_task(conn, &task_id)?,
    ));
    delete_syncs.extend(tagged_changes(
        EDGE_TASK_CALENDAR_EVENT_LINK,
        lorvex_store::payload_loaders::load_task_calendar_event_links_for_task(conn, &task_id)?,
    ));
    delete_syncs.extend(tagged_changes(
        EDGE_TASK_DEPENDENCY,
        lorvex_store::payload_loaders::load_task_dependencies_for_task(conn, &task_id)?,
    ));

    let focus_parent_dates = collect_focus_parent_dates_for_task(conn, &task_id_str)?;

    conn.prepare_cached("DELETE FROM current_focus_items WHERE task_id = ?1")?
        .execute([task_id_str.as_str()])?;
    conn.prepare_cached("DELETE FROM focus_schedule_blocks WHERE task_id = ?1")?
        .execute([task_id_str.as_str()])?;
    conn.prepare_cached("DELETE FROM task_dependencies WHERE task_id = ?1")?
        .execute([task_id_str.as_str()])?;
    conn.prepare_cached("DELETE FROM task_dependencies WHERE depends_on_task_id = ?1")?
        .execute([task_id_str.as_str()])?;

    let delete_version = hlc.next_version_string();
    let deleted = lorvex_store::repositories::task::write::hard_delete_task_lww(
        conn,
        &task_id,
        &delete_version,
    )? > 0;
    if deleted {
        delete_syncs.push(SyncPayloadChange {
            entity_type: ENTITY_TASK,
            entity_id: task_id_str.clone(),
            payload: before_task.clone(),
        });
    }

    let summary = format!("Permanently deleted task '{title}'");
    Ok(PermanentDeleteTaskResult {
        task_id: task_id_str.clone(),
        title,
        deleted,
        payload: json!({
            "id": task_id_str,
            "deleted": deleted,
            "previous": before_task,
        }),
        before_task,
        delete_syncs,
        focus_parent_dates,
        summary,
    })
}
