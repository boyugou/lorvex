use super::models::TaskList;
use crate::error::{AppError, AppResult};

use lorvex_store::repositories::list_repo;

pub(crate) fn list_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<TaskList> {
    Ok(TaskList {
        id: row.get(0)?,
        name: row.get(1)?,
        color: row.get(2)?,
        icon: row.get(3)?,
        description: row.get(4)?,
        ai_notes: row.get(5)?,
        created_at: row.get(6)?,
        updated_at: row.get(7)?,
    })
}

/// Convert a shared `ListRow` from `lorvex_store` to the Tauri `TaskList` model.
///
/// `ListRow::{created_at, updated_at}` are now
/// `SyncTimestamp`. The IPC `TaskList` model still carries `String`
/// timestamps for byte-stable JSON wire-shape with the TypeScript
/// frontend; serialize via `SyncTimestamp::as_string()` which always
/// emits canonical millisecond-Z form.
pub(crate) fn task_list_from_list_row(row: list_repo::ListRow) -> TaskList {
    TaskList {
        id: row.id,
        name: row.name,
        color: row.color,
        icon: row.icon,
        description: row.description,
        ai_notes: row.ai_notes,
        created_at: row.created_at.as_string(),
        updated_at: row.updated_at.as_string(),
    }
}

/// Fetch a list by ID using the shared repository.
///
/// Delegates to `lorvex_store::repositories::list_repo::get_list()` — the
/// single source of truth for list-by-ID lookups.
pub(crate) fn fetch_list_by_id(
    conn: &rusqlite::Connection,
    id: &str,
) -> AppResult<Option<TaskList>> {
    list_repo::get_list(conn, &lorvex_domain::ListId::from_trusted(id.to_string()))
        .map(|opt| opt.map(task_list_from_list_row))
        .map_err(AppError::from)
}
