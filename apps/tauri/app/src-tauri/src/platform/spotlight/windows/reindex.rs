//! Bulk Jump List reindexing — list-scoped, by-id batches, and the
//! full sweep that rebuilds from every open/someday task in the
//! database. Each entry point mutates the in-memory
//! `INDEXED_TASKS` cache through `with_tasks` and then defers to
//! `attributes::rebuild_jump_list` for the COM-side commit, so the
//! mutex is never held across OS I/O.

use super::attributes::rebuild_jump_list;
use super::query::read_jump_list_rows;
use super::{jump_list_io_enabled, select_top_tasks, with_tasks};

/// Reindex all tasks from the database into the Jump List.
///
/// Called on app startup. Clears existing entries and rebuilds from all
/// open/someday tasks. Completed and cancelled tasks are excluded.
pub fn reindex_all_tasks() {
    if !jump_list_io_enabled() {
        return;
    }
    let conn = match crate::db::get_read_conn() {
        Ok(c) => c,
        Err(e) => {
            super::super::log_spotlight_error(
                "reindex_all_tasks: failed to get DB connection",
                &e.to_string(),
            );
            return;
        }
    };

    let Some(rows) = read_jump_list_rows(
        &conn,
        &super::super::queries::select_all_sql(),
        [],
        "reindex_all_tasks",
    ) else {
        return;
    };

    drop(conn);

    let candidates = with_tasks(|tasks| {
        tasks.clear();
        for row in rows {
            tasks.insert(row.id.clone(), row);
        }
        select_top_tasks(tasks)
    });
    rebuild_jump_list(&candidates);
}

/// Reindex Jump List entries for all open/someday tasks in a given list.
/// Call after list rename/delete to update the `list_name` in task descriptions.
pub fn reindex_tasks_for_list(conn: &rusqlite::Connection, list_id: &str) {
    if !jump_list_io_enabled() {
        return;
    }
    let Some(rows) = read_jump_list_rows(
        conn,
        &super::super::queries::select_by_list_id_sql(),
        rusqlite::params![list_id],
        "reindex_tasks_for_list",
    ) else {
        return;
    };

    let candidates = with_tasks(|tasks| {
        for row in rows {
            tasks.insert(row.id.clone(), row);
        }
        select_top_tasks(tasks)
    });
    rebuild_jump_list(&candidates);
}

/// Reindex Jump List entries for specific tasks by their IDs.
/// Used after list-scoped writes that may change list metadata or task membership.
///
/// Loads the whole batch in a single `SELECT ... WHERE id IN (?, ...)`
/// query before delegating to the already-batched `rebuild_jump_list`,
/// so the per-call cost is one round trip regardless of `task_ids.len()`.
pub fn reindex_tasks_by_ids(conn: &rusqlite::Connection, task_ids: &[String]) {
    if !jump_list_io_enabled() {
        return;
    }
    if task_ids.is_empty() {
        return;
    }
    // shared placeholder + projection helper.
    let sql = super::super::queries::select_by_id_batch_sql(task_ids.len());
    let params = super::super::queries::ids_as_params(task_ids);
    let Some(rows) = read_jump_list_rows(
        conn,
        &sql,
        rusqlite::params_from_iter(params),
        "reindex_tasks_by_ids",
    ) else {
        return;
    };

    let surviving: std::collections::HashSet<String> = rows.iter().map(|r| r.id.clone()).collect();
    let candidates = with_tasks(|tasks| {
        for row in rows {
            tasks.insert(row.id.clone(), row);
        }
        // Remove every requested id that didn't survive the filter.
        for task_id in task_ids {
            if !surviving.contains(task_id) {
                tasks.remove(task_id.as_str());
            }
        }
        select_top_tasks(tasks)
    });
    rebuild_jump_list(&candidates);
}
