use crate::commands::{
    task_list_from_list_row, tasks_from_task_rows, trailing_day_window_bounds_for_conn,
    ListWithCount, Task, TaskList,
};
use crate::db::get_read_conn;
use crate::error::{AppError, AppResult};

#[tauri::command]
pub fn get_all_lists() -> Result<Vec<ListWithCount>, String> {
    get_all_lists_inner().map_err(String::from)
}

fn get_all_lists_inner() -> AppResult<Vec<ListWithCount>> {
    let conn = get_read_conn()?;

    let rows = lorvex_store::repositories::list_repo::get_all_lists_with_counts(&conn)
        .map_err(AppError::from)?;

    Ok(rows
        .into_iter()
        .map(|r| ListWithCount {
            list: task_list_from_list_row(r.list),
            open_count: r.open_count,
        })
        .collect())
}

/// Typed contract for `get_list_with_tasks`. The Rust struct is the
/// single source of truth, so renames / new fields produce a compile
/// error instead of a silent payload drift against the TS-side
/// `ListWithTasks` shape.
///
/// `total_matching` reports the canonical count for
/// the predicate the row trim applied so the UI can offer "showing N
/// of M" + "load more" affordances on a list whose row count exceeds
/// the cap.
#[derive(Debug, serde::Serialize, serde::Deserialize)]
pub struct ListWithTasks {
    pub list: TaskList,
    pub tasks: Vec<Task>,
    pub total_matching: i64,
}

/// Hard upper bound on the row count returned to the UI.
///
/// Aliases `TASK_LIST_RESULT_LIMIT` from `commands::shared::limits`
/// so a single edit covers every task-list IPC payload cap. Anything
/// beyond this returns `total_matching = real_count` while `tasks`
/// stays at the cap so the UI can render "showing K of N — load
/// more".
const GET_LIST_TASKS_LIMIT: u32 = crate::commands::shared::TASK_LIST_RESULT_LIMIT;

#[tauri::command]
pub fn get_list_with_tasks(id: String) -> Result<ListWithTasks, String> {
    get_list_with_tasks_inner(id).map_err(String::from)
}

#[allow(clippy::needless_pass_by_value)] // mirrors Tauri command IPC ownership contract
fn get_list_with_tasks_inner(id: String) -> AppResult<ListWithTasks> {
    let conn = get_read_conn()?;
    let retention_window = trailing_day_window_bounds_for_conn(&conn, 7)?;

    let list_id_typed = lorvex_domain::ListId::from_trusted(id.clone());
    let row = lorvex_store::repositories::list_repo::get_list(&conn, &list_id_typed)
        .map_err(AppError::from)?
        .ok_or_else(|| AppError::NotFound(format!("List {id} not found")))?;
    let list = task_list_from_list_row(row);

    let result = query_list_tasks_with_recent_completed(
        &conn,
        &list_id_typed,
        &retention_window.start_utc,
        &retention_window.end_utc,
        GET_LIST_TASKS_LIMIT,
    )?;

    Ok(ListWithTasks {
        list,
        tasks: result.tasks,
        total_matching: result.total_matching,
    })
}

/// Tauri-side adapter that materializes `Task`-typed rows out of the
/// repository's `TaskRow` envelope and forwards `total_matching`.
pub(crate) struct ListTasksWithRecentCompleted {
    pub tasks: Vec<Task>,
    pub total_matching: i64,
}

pub(crate) fn query_list_tasks_with_recent_completed(
    conn: &rusqlite::Connection,
    list_id: &lorvex_domain::ListId,
    recent_completed_start_utc: &str,
    recent_completed_end_utc: &str,
    limit: u32,
) -> AppResult<ListTasksWithRecentCompleted> {
    let result = lorvex_store::repositories::task::read::get_list_tasks_with_recent_completed(
        conn,
        list_id,
        recent_completed_start_utc,
        recent_completed_end_utc,
        limit,
    )
    .map_err(AppError::from)?;
    let tasks = tasks_from_task_rows(conn, result.rows)?;
    Ok(ListTasksWithRecentCompleted {
        tasks,
        total_matching: result.total_matching,
    })
}
