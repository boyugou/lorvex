//! Rewire focus-plan references from the now-completed parent task
//! onto the freshly spawned successor so today's schedule keeps
//! pointing at the open task. Only forward-looking rows (today or
//! later) are rewired — historical focus rows legitimately reference
//! the completed occurrence and stay pinned to the parent id so the
//! diagnostics / history views remain accurate.
//!
//! The successor_id is a fresh UUIDv7, so it cannot already appear
//! in either focus table — the UPDATE cannot collide with the
//! `UNIQUE(date, task_id)` index on `current_focus_items`.
//!
//! The affected aggregate dates are returned to callers. Surface
//! boundaries decide whether and how to emit audit rows; the workflow
//! layer owns the SQL mutation, not `ai_changelog` side effects.

use rusqlite::{params, Connection};

use lorvex_store::StoreError;

/// Outcome of [`rewire_focus_plan`]. The two date lists travel up
/// to the orchestrator's `SpawnResult` so each Tauri / MCP / CLI
/// surface can stamp a fresh HLC version on the parent aggregate
/// (`focus_schedule` / `current_focus`) and enqueue an upsert
/// envelope. Without this, device A sees today's plan rewired to
/// the successor while device B's focus plan keeps pointing at the
/// now-completed parent — the children mutated locally but the
/// parent's `version` stayed stale, so no sync event ever
/// propagated the change.
pub(super) struct FocusRewireResult {
    pub(super) rewired_focus_schedule_dates: Vec<String>,
    pub(super) rewired_current_focus_dates: Vec<String>,
}

pub(super) fn rewire_focus_plan(
    conn: &Connection,
    parent_id: &str,
    successor_id: &str,
    today_ymd: &str,
) -> Result<FocusRewireResult, StoreError> {
    // collect the distinct dates we touched BEFORE the UPDATE
    // so the caller can stamp a fresh HLC version on each parent aggregate
    // (`focus_schedule` / `current_focus`) and enqueue an upsert envelope.
    let rewired_focus_schedule_dates: Vec<String> = conn
        .prepare_cached(
            "SELECT DISTINCT schedule_date FROM focus_schedule_blocks \
             WHERE task_id = ?1 AND schedule_date >= ?2 \
             ORDER BY schedule_date ASC",
        )?
        .query_map(params![parent_id, today_ymd], |row| row.get::<_, String>(0))?
        .collect::<Result<Vec<_>, _>>()?;
    let rewired_current_focus_dates: Vec<String> = conn
        .prepare_cached(
            "SELECT DISTINCT date FROM current_focus_items \
             WHERE task_id = ?1 AND date >= ?2 \
             ORDER BY date ASC",
        )?
        .query_map(params![parent_id, today_ymd], |row| row.get::<_, String>(0))?
        .collect::<Result<Vec<_>, _>>()?;
    let rewired_focus_blocks = conn
        .prepare_cached(
            "UPDATE focus_schedule_blocks SET task_id = ?1 \
             WHERE task_id = ?2 AND schedule_date >= ?3",
        )?
        .execute(params![successor_id, parent_id, today_ymd])?;
    let rewired_focus_items = conn
        .prepare_cached(
            "UPDATE current_focus_items SET task_id = ?1 \
             WHERE task_id = ?2 AND date >= ?3",
        )?
        .execute(params![successor_id, parent_id, today_ymd])?;
    // gate the per-date COUNT(*) re-probes behind
    // `cfg(debug_assertions)`. The pre-UPDATE `SELECT DISTINCT`
    // queries above remain unconditional because the caller needs
    // the date set for HLC re-stamping (see `SpawnSuccessorOutcome`),
    // but the post-UPDATE invariant check fired
    // `dates.len() * 2` extra prepares + scans on every recurrence
    // rollover in release builds. Wrapping the entire `assert` block
    // (not just the comparand) ensures release builds skip both the
    // SQL prepares AND the closure machinery.
    #[cfg(debug_assertions)]
    {
        debug_assert_eq!(
            rewired_focus_blocks,
            rewired_focus_schedule_dates
                .iter()
                .map(|date| {
                    conn.query_row::<i64, _, _>(
                        "SELECT COUNT(*) FROM focus_schedule_blocks \
                         WHERE task_id = ?1 AND schedule_date = ?2",
                        params![successor_id, date],
                        |row| row.get(0),
                    )
                    .unwrap_or(0)
                })
                .sum::<i64>() as usize,
            "rewired_focus_schedule_dates must enumerate exactly the dates touched by the UPDATE"
        );
        debug_assert_eq!(
            rewired_focus_items,
            rewired_current_focus_dates
                .iter()
                .map(|date| {
                    conn.query_row::<i64, _, _>(
                        "SELECT COUNT(*) FROM current_focus_items \
                         WHERE task_id = ?1 AND date = ?2",
                        params![successor_id, date],
                        |row| row.get(0),
                    )
                    .unwrap_or(0)
                })
                .sum::<i64>() as usize,
            "rewired_current_focus_dates must enumerate exactly the dates touched by the UPDATE"
        );
    }
    // Suppress unused-binding warnings on release builds where the
    // `debug_assert_eq!` block above is the only consumer.
    #[cfg(not(debug_assertions))]
    {
        let _ = rewired_focus_blocks;
        let _ = rewired_focus_items;
    }

    Ok(FocusRewireResult {
        rewired_focus_schedule_dates,
        rewired_current_focus_dates,
    })
}
