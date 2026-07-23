//! Per-entity seeders that need custom SQL, aggregate building, or
//! runtime enrichment beyond the store-owned simple payload scanner.
//! Streamed to bound peak memory; every helper here is invoked from
//! `super::seed_orchestrator::seed_all_entities` inside its own IMMEDIATE
//! transaction.

use lorvex_domain::naming::{
    ENTITY_CALENDAR_EVENT, ENTITY_CURRENT_FOCUS, ENTITY_DAILY_REVIEW, ENTITY_FOCUS_SCHEDULE,
    ENTITY_PREFERENCE,
};
use lorvex_store::payload_loaders::SimpleSyncSeedKind;

use super::enqueue::{enqueue_list_upsert, enqueue_task_upsert};
use super::seed_helpers::{
    seed_aggregate_ids, seed_aggregate_root_by_date, seed_simple_sync_payloads,
};
use crate::commands::{list_from_row, task_from_row, TaskList, LIST_COLS, TASK_COLS};
use crate::error::{AppError, AppResult};

pub(super) fn seed_lists(conn: &rusqlite::Connection) -> AppResult<i64> {
    let mut stmt = conn
        .prepare_cached(&format!(
            "SELECT {LIST_COLS} FROM lists ORDER BY created_at"
        ))
        .map_err(AppError::from)?;
    let lists: Vec<TaskList> = stmt
        .query_map([], list_from_row)
        .map_err(AppError::from)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| AppError::Internal(format!("Failed to read list row: {e}")))?;
    let count = lists.len() as i64;
    for list in &lists {
        enqueue_list_upsert(conn, list).map_err(|e| {
            AppError::Internal(format!("Failed to enqueue list '{}': {}", list.name, e))
        })?;
    }
    Ok(count)
}

pub(super) fn seed_tasks(conn: &rusqlite::Connection) -> AppResult<i64> {
    // Stream raw task rows from the prepared statement straight into
    // `enqueue_task_upsert` so memory peaks at one task at a time
    // even for a 100k-task user — materialising a fully-enriched
    // `Vec<Task>` for the whole table would cost a multi-GB peak
    // inside the writer transaction. Skip
    // `tasks_from_query`'s `enrich_tasks_all` step because
    // `enqueue_task_upsert` strips `tags`, `depends_on`,
    // `checklist_items`, and `lateness_state` from the envelope —
    // those entities are seeded independently as `task_tags`,
    // `task_dependencies`, and `task_checklist_items` rows.
    let sql = format!("SELECT {TASK_COLS} FROM tasks ORDER BY created_at");
    let mut stmt = conn.prepare_cached(&sql).map_err(AppError::from)?;
    let mut rows = stmt.query([]).map_err(AppError::from)?;
    let mut count: i64 = 0;
    while let Some(row) = rows
        .next()
        .map_err(|e| AppError::Internal(format!("Failed to read task row: {e}")))?
    {
        let task = task_from_row(row)
            .map_err(|e| AppError::Internal(format!("Failed to read task row: {e}")))?;
        enqueue_task_upsert(conn, &task).map_err(|e| {
            AppError::Internal(format!("Failed to enqueue task '{}': {}", task.title, e))
        })?;
        count += 1;
    }
    Ok(count)
}

pub(super) fn seed_preferences(conn: &rusqlite::Connection) -> AppResult<i64> {
    seed_simple_sync_payloads(conn, ENTITY_PREFERENCE, SimpleSyncSeedKind::Preference)
}

pub(super) fn seed_current_focus(conn: &rusqlite::Connection) -> AppResult<i64> {
    seed_aggregate_root_by_date(
        conn,
        ENTITY_CURRENT_FOCUS,
        "SELECT date FROM current_focus ORDER BY date",
    )
}

pub(super) fn seed_daily_reviews(conn: &rusqlite::Connection) -> AppResult<i64> {
    seed_aggregate_root_by_date(
        conn,
        ENTITY_DAILY_REVIEW,
        "SELECT date FROM daily_reviews ORDER BY date",
    )
}

pub(super) fn seed_calendar_events(conn: &rusqlite::Connection) -> AppResult<i64> {
    // route through the canonical aggregate builder so
    // attendees + per-attendee shadow extras (#2317) ride along with
    // the parent payload — same path used by the MCP changelog
    // funnel, the CLI lifecycle paths, and `enqueue_entity_upsert`.
    seed_aggregate_ids(
        conn,
        ENTITY_CALENDAR_EVENT,
        "SELECT id FROM calendar_events ORDER BY start_date",
    )
}

pub(super) fn seed_focus_schedules(conn: &rusqlite::Connection) -> AppResult<i64> {
    seed_aggregate_root_by_date(
        conn,
        ENTITY_FOCUS_SCHEDULE,
        "SELECT date FROM focus_schedule ORDER BY date DESC",
    )
}
