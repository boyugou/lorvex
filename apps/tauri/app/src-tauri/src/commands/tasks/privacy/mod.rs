//! Privacy: clear `raw_input` (originating conversational text) from
//! every task in one transactional pass. The renderer-facing
//! `clear_all_raw_input` Tauri command was removed in #2940-H1 — no UI
//! caller. The transactional `_with_conn` helper stays so the existing
//! rollback-on-enqueue-failure regression test continues to pin the
//! atomicity guarantee, and so a future privacy-panel feature can wire
//! it back up to a command without rewriting the body.

#[cfg(test)]
use rusqlite::params;

#[cfg(test)]
use crate::error::AppResult;

#[cfg(test)]
use crate::commands::{
    enqueue_task_upsert, fetch_ordered_tasks_by_ids, with_immediate_transaction,
};

#[cfg(test)]
#[derive(Debug, serde::Serialize)]
pub struct ClearRawInputResult {
    pub cleared_count: usize,
}

#[cfg(test)]
fn clear_all_raw_input_with_conn(
    conn: &rusqlite::Connection,
    now: &str,
) -> AppResult<ClearRawInputResult> {
    with_immediate_transaction(conn, |conn| clear_all_raw_input_in_transaction(conn, now))
}

#[cfg(test)]
fn clear_all_raw_input_in_transaction(
    conn: &rusqlite::Connection,
    now: &str,
) -> AppResult<ClearRawInputResult> {
    // Collect affected task IDs before the bulk update
    let affected_ids: Vec<String> = conn
        .prepare_cached("SELECT id FROM tasks WHERE raw_input IS NOT NULL")?
        .query_map([], |row| row.get(0))?
        .collect::<Result<_, _>>()?;

    let cleared = conn
        .prepare_cached(
            "UPDATE tasks SET raw_input = NULL, updated_at = ?1 WHERE raw_input IS NOT NULL",
        )?
        .execute(params![now])?;

    // Batch-fetch updated tasks for sync enqueue (avoids N+1 per-task SELECT)
    if !affected_ids.is_empty() {
        let tasks = fetch_ordered_tasks_by_ids(conn, &affected_ids, "raw_input privacy clear")?;
        for task in &tasks {
            enqueue_task_upsert(conn, task)?;
        }
    }

    Ok(ClearRawInputResult {
        cleared_count: cleared,
    })
}

#[cfg(test)]
mod tests;
