//! Single-task Jump List operations: remove one task by id and
//! remove every Lorvex task. The original `windows.rs` carried an
//! `index_task` sibling for parity with the macOS file, but the
//! Windows reindex paths never went through it (every entry point
//! mutated `INDEXED_TASKS` directly via `with_tasks`), so the
//! function was dead on this platform — dropped during the
//! folder split.

use super::attributes::rebuild_jump_list;
use super::{jump_list_io_enabled, select_top_tasks, with_tasks};

/// Remove a single task from the Jump List.
pub fn remove_task(task_id: &str) {
    if !jump_list_io_enabled() {
        return;
    }
    let candidates = with_tasks(|tasks| {
        tasks.remove(task_id);
        select_top_tasks(tasks)
    });
    rebuild_jump_list(&candidates);
}

/// Remove all tasks from the Jump List.
pub fn remove_all_tasks() {
    if !jump_list_io_enabled() {
        return;
    }
    with_tasks(|tasks| tasks.clear());
    rebuild_jump_list(&[]);
}
