use super::super::super::*;

// ── get_archived_tasks ──────────────────────────────────────────────

/// Hard upper bound on the row count returned to the UI. Mirrors
/// `commands::lists::GET_LIST_TASKS_LIMIT` — the canonical IPC
/// payload cap. Anything beyond this stays at the cap while
/// `total_matching` reports the real count so the UI can render
/// "showing K of N — load more". Without the cap a user with
/// hundreds of trashed tasks would pay the full marshal cost on
/// every Trash-panel open.
const GET_ARCHIVED_TASKS_LIMIT: u32 = 1_000;

/// Pagination/result envelope for `get_archived_tasks`.
///
/// typed alongside #3007-H4 / #3007-H6's typed-IPC
/// push so the TS shape doesn't drift from the Rust shape.
#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct ArchivedTasksResult {
    pub tasks: Vec<Task>,
    pub total_matching: i64,
}

#[tauri::command]
pub fn get_archived_tasks(
    limit: Option<u32>,
    offset: Option<u32>,
) -> Result<ArchivedTasksResult, String> {
    get_archived_tasks_inner(limit, offset).map_err(String::from)
}

fn get_archived_tasks_inner(
    limit: Option<u32>,
    offset: Option<u32>,
) -> Result<ArchivedTasksResult, AppError> {
    let conn = crate::db::get_read_conn()?;
    // Clamp `limit` to the canonical IPC cap so a malicious or
    // mistaken caller cannot ask the renderer to materialize an
    // unbounded payload. Default to the cap when omitted — the Trash
    // panel pages through deliberately.
    let limit = limit
        .unwrap_or(GET_ARCHIVED_TASKS_LIMIT)
        .min(GET_ARCHIVED_TASKS_LIMIT);
    let offset = offset.unwrap_or(0);
    let page = lorvex_store::repositories::task::read::get_archived_tasks(&conn, limit, offset)
        .map_err(AppError::from)?;
    let tasks = crate::commands::tasks_from_task_rows(&conn, page.rows)?;
    Ok(ArchivedTasksResult {
        tasks,
        total_matching: page.total_matching,
    })
}
