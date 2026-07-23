use super::enqueue::enqueue_upsert;
use super::*;
use lorvex_domain::ids::TaskId;

pub(super) fn cleanup_plan_refs_after_removal<F>(
    conn: &Connection,
    task_id: &TaskId,
    device_id: &str,
    mint_version: &mut F,
) -> StartupTrashPurgeResult<()>
where
    F: FnMut(&Connection) -> StartupTrashPurgeResult<String>,
{
    let focus_dates: Vec<String> = {
        let mut stmt = conn
            .prepare_cached("SELECT DISTINCT date FROM current_focus_items WHERE task_id = ?1")?;
        let dates = stmt
            .query_map(params![task_id], |row| row.get::<_, String>(0))?
            .collect::<Result<Vec<_>, _>>()?;
        dates
    };
    let schedule_dates: Vec<String> = {
        let mut stmt = conn.prepare_cached(
            "SELECT DISTINCT schedule_date FROM focus_schedule_blocks WHERE task_id = ?1",
        )?;
        let dates = stmt
            .query_map(params![task_id], |row| row.get::<_, String>(0))?
            .collect::<Result<Vec<_>, _>>()?;
        dates
    };

    conn.execute(
        "DELETE FROM current_focus_items WHERE task_id = ?1",
        params![task_id],
    )?;
    conn.execute(
        "DELETE FROM focus_schedule_blocks WHERE task_id = ?1",
        params![task_id],
    )?;

    for date in &focus_dates {
        enqueue_aggregate_upsert(conn, ENTITY_CURRENT_FOCUS, date, device_id, mint_version)?;
    }
    for date in &schedule_dates {
        enqueue_aggregate_upsert(conn, ENTITY_FOCUS_SCHEDULE, date, device_id, mint_version)?;
    }
    Ok(())
}

fn enqueue_aggregate_upsert<F>(
    conn: &Connection,
    entity_type: &str,
    entity_id: &str,
    device_id: &str,
    mint_version: &mut F,
) -> StartupTrashPurgeResult<()>
where
    F: FnMut(&Connection) -> StartupTrashPurgeResult<String>,
{
    let Some(payload) =
        crate::payload_build::aggregate::build_aggregate_payload(conn, entity_type, entity_id)?
    else {
        return Ok(());
    };
    enqueue_upsert(
        conn,
        entity_type,
        entity_id,
        &payload,
        device_id,
        mint_version,
    )
}
