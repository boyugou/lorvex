use crate::db::get_read_conn;
use crate::error::AppResult;

pub type SyncStatus = lorvex_store::SyncStatusSnapshot;

#[tauri::command]
pub fn get_sync_status() -> Result<SyncStatus, String> {
    let conn = get_read_conn()?;
    load_sync_status_from_conn(&conn).map_err(String::from)
}

pub(crate) fn load_sync_status_from_conn(conn: &rusqlite::Connection) -> AppResult<SyncStatus> {
    lorvex_store::load_sync_status_snapshot(conn).map_err(Into::into)
}
