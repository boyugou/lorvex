//! Child-row inserts that fan out after a task row is created:
//! reminders, dependency edges, tag edges. Each accumulates into
//! the orchestrator's [`super::effects::CreateTaskSyncEffects`].

use lorvex_domain::hlc_session::HlcSession;
use lorvex_domain::TaskId;
use lorvex_store::repositories::{tag_repo, task::dependencies};
use lorvex_store::StoreError;
use rusqlite::{params, Connection};

use super::effects::TaskTagSyncEffects;

pub fn insert_task_reminders(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    task_id: &str,
    reminders: Option<Vec<String>>,
) -> Result<Vec<String>, StoreError> {
    let Some(reminders) = reminders else {
        return Ok(Vec::new());
    };
    let timestamps: Vec<String> = reminders
        .iter()
        .map(|timestamp| canonicalize_reminder_timestamp(timestamp))
        .collect::<Result<_, _>>()?;
    let now = lorvex_domain::sync_timestamp_now();
    let mut created_ids = Vec::with_capacity(timestamps.len());
    for timestamp in timestamps {
        let reminder_id = lorvex_domain::new_entity_id_string();
        let version = hlc.next_version_string();
        let (original_local_time, original_tz) =
            crate::reminder_anchor::resolve_task_reminder_local_anchor(conn, &timestamp)?;
        conn.execute(
            "INSERT INTO task_reminders \
               (id, task_id, reminder_at, original_local_time, original_tz, version, created_at) \
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![
                reminder_id,
                task_id,
                timestamp,
                original_local_time,
                original_tz,
                version,
                now
            ],
        )?;
        created_ids.push(reminder_id);
    }
    Ok(created_ids)
}

pub fn insert_dependency_edges(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    task_id: &TaskId,
    depends_on: &[String],
) -> Result<Vec<String>, StoreError> {
    if depends_on.is_empty() {
        return Ok(Vec::new());
    }
    let version = hlc.next_version_string();
    let now = lorvex_domain::sync_timestamp_now();
    let depends_on_typed = depends_on
        .iter()
        .map(|id| TaskId::from_trusted(id.clone()))
        .collect::<Vec<_>>();
    dependencies::insert_dependency_edges_batch(conn, task_id, &depends_on_typed, &version, &now)?;
    Ok(depends_on
        .iter()
        .map(|dep_id| format!("{}:{dep_id}", task_id.as_str()))
        .collect())
}

pub fn insert_task_tags(
    conn: &Connection,
    hlc: &HlcSession<'_>,
    task_id: &TaskId,
    tags: &[String],
) -> Result<TaskTagSyncEffects, StoreError> {
    if tags.is_empty() {
        return Ok(TaskTagSyncEffects::default());
    }
    let now = lorvex_domain::sync_timestamp_now();
    let mut effects = TaskTagSyncEffects::default();
    let mut insert_stmt = conn.prepare_cached(
        "INSERT OR IGNORE INTO task_tags (task_id, tag_id, version, created_at) \
             VALUES (?1, ?2, ?3, ?4)",
    )?;
    for tag in tags {
        let tag_version = hlc.next_version_string();
        let (tag_id, created) = tag_repo::resolve_or_create_tag(conn, tag, &tag_version, &now)?;
        if created {
            effects.tag_upsert_ids.push(tag_id.clone());
        }
        let edge_version = hlc.next_version_string();
        insert_stmt.execute(params![task_id.as_str(), tag_id, edge_version, now])?;
        effects
            .task_tag_edge_upsert_ids
            .push(format!("{}:{}", task_id.as_str(), tag_id));
    }
    Ok(effects)
}

fn canonicalize_reminder_timestamp(raw: &str) -> Result<String, StoreError> {
    lorvex_domain::canonicalize_rfc3339_instant(raw).ok_or_else(|| {
        StoreError::Validation(format!(
            "Invalid reminder timestamp '{raw}'. Must be a valid RFC 3339 datetime (e.g. 2025-12-01T09:00:00Z)."
        ))
    })
}
