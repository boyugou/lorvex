//! List-domain Tauri commands: CRUD, list browsing, and the
//! "Shelve all" bulk transition. Each submodule corresponds to one
//! lifecycle / read shape so a future add (rename / archive / pin)
//! lands in its own file instead of growing the historic 748-line
//! flat `lists.rs` (#3303 P1 split).

pub(crate) mod create;
pub(crate) mod delete;
pub(crate) mod queries;
pub(crate) mod shelve;
pub(crate) mod update;

#[cfg(test)]
mod tests;

#[allow(unused_imports)]
pub use queries::{get_all_lists, get_list_with_tasks};

use rusqlite::params;

use crate::commands::{list_from_row, TaskList, LIST_COLS};
use crate::error::{AppError, AppResult};

#[cfg(test)]
pub(crate) use delete::delete_list_internal;
#[cfg(test)]
pub(crate) use queries::query_list_tasks_with_recent_completed;
#[cfg(test)]
pub(crate) use update::{update_list_with_conn, UpdateListArgs};

/// Re-read a list through the Tauri `list_from_row` mapper after a
/// shared-repo write so the returned type matches the IPC contract.
///
/// Shared by `create_list` and `update_list_with_conn`; lifted here
/// so the two callers don't carry duplicate copies.
pub(super) fn reload_list_as_task_list(
    conn: &rusqlite::Connection,
    id: &str,
) -> AppResult<TaskList> {
    conn.prepare_cached(&format!("SELECT {LIST_COLS} FROM lists WHERE id = ?1"))
        .map_err(AppError::from)?
        .query_row(params![id], list_from_row)
        .map_err(AppError::from)
}
