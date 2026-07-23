use super::*;
use lorvex_domain::ids::{TagId, TaskId};

#[derive(Debug, Default)]
pub(super) struct CascadedTaskSnapshots {
    pub(super) tag_edges: Vec<(String, Value)>,
    pub(super) checklist_items: Vec<(String, Value)>,
    pub(super) reminders: Vec<(String, Value)>,
    pub(super) calendar_links: Vec<(String, Value)>,
}

pub(super) fn collect_cascaded_task_snapshots(
    conn: &Connection,
    task_id: &TaskId,
) -> StartupTrashPurgeResult<CascadedTaskSnapshots> {
    let mut snapshots = CascadedTaskSnapshots::default();

    {
        let mut stmt = conn.prepare_cached(
            "SELECT tag_id, created_at, version
             FROM task_tags
             WHERE task_id = ?1
             ORDER BY tag_id ASC",
        )?;
        let rows = stmt
            .query_map(params![task_id], |row| {
                let tag_id: TagId = row.get(0)?;
                let created_at: String = row.get(1)?;
                let version: String = row.get(2)?;
                Ok((
                    format!("{task_id}:{tag_id}"),
                    lorvex_store::payload_loaders::task_tag_payload(
                        task_id,
                        &tag_id,
                        &version,
                        &created_at,
                    ),
                ))
            })?
            .collect::<Result<Vec<_>, _>>()?;
        snapshots.tag_edges = rows;
    }

    {
        let ids = child_ids_for_task(
            conn,
            "SELECT id FROM task_checklist_items WHERE task_id = ?1 ORDER BY id ASC",
            task_id,
        )?;
        for id in ids {
            let payload = read_entity_payload_snapshot(conn, ENTITY_TASK_CHECKLIST_ITEM, &id)
                .map_err(|err| SyncError::Envelope(err.to_string()))?;
            snapshots.checklist_items.push((id, payload));
        }
    }

    {
        let ids = child_ids_for_task(
            conn,
            "SELECT id FROM task_reminders WHERE task_id = ?1 ORDER BY id ASC",
            task_id,
        )?;
        for id in ids {
            let payload = read_entity_payload_snapshot(conn, ENTITY_TASK_REMINDER, &id)
                .map_err(|err| SyncError::Envelope(err.to_string()))?;
            snapshots.reminders.push((id, payload));
        }
    }

    {
        let mut stmt = conn.prepare_cached(
            "SELECT calendar_event_id, created_at, updated_at, version
             FROM task_calendar_event_links
             WHERE task_id = ?1
             ORDER BY calendar_event_id ASC",
        )?;
        let rows = stmt
            .query_map(params![task_id], |row| {
                let event_id: lorvex_domain::EventId = row.get(0)?;
                let created_at: String = row.get(1)?;
                let updated_at: String = row.get(2)?;
                let version: String = row.get(3)?;
                Ok((
                    format!("{task_id}:{event_id}"),
                    lorvex_store::payload_loaders::task_calendar_event_link_payload(
                        task_id,
                        &event_id,
                        &version,
                        &created_at,
                        &updated_at,
                    ),
                ))
            })?
            .collect::<Result<Vec<_>, _>>()?;
        snapshots.calendar_links = rows;
    }

    Ok(snapshots)
}

/// Run a fully-static `SELECT id FROM <table> WHERE task_id = ?1 ORDER BY
/// id ASC` and collect the ids. The SQL is passed in by the caller as a
/// `&'static str` so the table name is locked at compile-time and the
/// statement plan caches via `prepare_cached` across invocations.
fn child_ids_for_task(
    conn: &Connection,
    sql: &'static str,
    task_id: &TaskId,
) -> StartupTrashPurgeResult<Vec<String>> {
    let mut stmt = conn.prepare_cached(sql)?;
    let ids = stmt
        .query_map(params![task_id], |row| row.get::<_, String>(0))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(SyncError::from)?;
    Ok(ids)
}
