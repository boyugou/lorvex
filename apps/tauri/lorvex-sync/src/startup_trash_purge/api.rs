use super::purge::purge_one_archived_task;
use super::*;

pub fn trash_cutoff_iso(retention_days: i64) -> String {
    let cutoff = chrono_now_utc() - chrono::Duration::days(retention_days);
    lorvex_domain::format_sync_timestamp(cutoff)
}

fn chrono_now_utc() -> chrono::DateTime<chrono::Utc> {
    chrono::Utc::now()
}

pub fn run_startup_trash_purge<F>(
    conn: &Connection,
    retention_days: i64,
    mint_version: F,
) -> StartupTrashPurgeResult<StartupTrashPurgeReport>
where
    F: FnMut(&Connection) -> StartupTrashPurgeResult<String>,
{
    let cutoff = trash_cutoff_iso(retention_days);
    let mut mint_version = mint_version;
    purge_archived_tasks_older_than_inner(conn, &cutoff, &mut mint_version)
}

pub fn purge_expired_archived_tasks<F>(
    conn: &Connection,
    retention_days: i64,
    mut mint_version: F,
) -> StartupTrashPurgeResult<StartupTrashPurgeReport>
where
    F: FnMut(&Connection) -> StartupTrashPurgeResult<String>,
{
    let cutoff = trash_cutoff_iso(retention_days);
    purge_archived_tasks_older_than_inner(conn, &cutoff, &mut mint_version)
}

pub fn purge_archived_tasks_older_than<F>(
    conn: &Connection,
    cutoff: &str,
    mint_version: &mut F,
) -> StartupTrashPurgeResult<StartupTrashPurgeReport>
where
    F: FnMut(&Connection) -> StartupTrashPurgeResult<String>,
{
    purge_archived_tasks_older_than_inner(conn, cutoff, mint_version)
}

fn purge_archived_tasks_older_than_inner<F>(
    conn: &Connection,
    cutoff: &str,
    mint_version: &mut F,
) -> StartupTrashPurgeResult<StartupTrashPurgeReport>
where
    F: FnMut(&Connection) -> StartupTrashPurgeResult<String>,
{
    lorvex_store::with_immediate_transaction(conn, |conn| {
        let expired_ids =
            lorvex_store::repositories::task::read::list_archived_task_ids_older_than(
                conn, cutoff,
            )?;

        if expired_ids.is_empty() {
            let remaining = lorvex_store::repositories::task::read::count_archived_tasks(conn)?;
            return Ok(StartupTrashPurgeReport {
                deleted: 0,
                deleted_ids: Vec::new(),
                remaining,
            });
        }

        let device_id = lorvex_runtime::get_or_create_device_id(conn)
            .map_err(lorvex_store::StoreError::from)?;
        let mut deleted_ids = Vec::with_capacity(expired_ids.len());

        for task_id in &expired_ids {
            let task_id_typed = lorvex_domain::ids::TaskId::from_trusted(task_id.clone());
            if purge_one_archived_task(conn, &task_id_typed, &device_id, mint_version)? {
                deleted_ids.push(task_id.clone());
            }
        }

        let remaining = lorvex_store::repositories::task::read::count_archived_tasks(conn)?;
        if !deleted_ids.is_empty() {
            lorvex_runtime::bump_local_change_seq(conn).map_err(lorvex_store::StoreError::from)?;
        }

        Ok(StartupTrashPurgeReport {
            deleted: deleted_ids.len(),
            deleted_ids,
            remaining,
        })
    })
}
