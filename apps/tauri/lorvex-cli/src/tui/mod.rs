use lorvex_runtime::get_or_create_device_id;
use rusqlite::{Connection, OptionalExtension};
use std::path::Path;

use crate::commands::shared::today_ymd_for_conn;
use crate::models::{DashboardSnapshot, TaskListItem};
use crate::render::render_task_section;

pub(crate) fn render_tui_dashboard_for_snapshot(snapshot: &DashboardSnapshot) -> String {
    format!(
        "Lorvex TUI\n==========\nToday: {}\nDB: {}\nDevice: {}\nOpen tasks: {}\nOverdue tasks: {}\nToday's focus: {}\nNext task: {}\n{}{}{}",
        snapshot.today,
        snapshot.db_path.display(),
        snapshot.device_id,
        snapshot.open_tasks,
        snapshot.overdue_tasks,
        // `as_deref().unwrap_or("none")` — borrow rather than clone.
        snapshot.current_focus.as_deref().unwrap_or("none"),
        match (&snapshot.next_task, &snapshot.next_task_id) {
            (Some(title), Some(id)) => {
                let short_id = if id.len() > 8 { &id[..8] } else { id };
                format!("{title} [{short_id}]")
            }
            (Some(title), None) => title.clone(),
            _ => "none".to_string(),
        },
        render_task_section("Due today", &snapshot.due_today),
        render_task_section("Upcoming", &snapshot.upcoming),
        render_task_section("Recently completed", &snapshot.recently_completed),
    )
}

pub(crate) fn load_dashboard_snapshot(
    conn: &Connection,
    db_path: &Path,
) -> Result<DashboardSnapshot, crate::error::CliError> {
    // Issue #2994 H8 / #2978-H6 holdout: source "today" from the
    // tz-aware helper that consults the user's stored timezone
    // preference (falling back to system-local), not from
    // `chrono::Local::now()` which ignored the preference outright.
    let today = today_ymd_for_conn(conn)?;
    let device_id = get_or_create_device_id(conn)?;
    let open_tasks: i64 = conn.query_row(
        "SELECT COUNT(*) FROM tasks WHERE status = 'open' AND archived_at IS NULL",
        [],
        |row| row.get(0),
    )?;
    let overdue_tasks = conn.query_row(
        "SELECT COUNT(*) FROM tasks \
         WHERE status = 'open' AND archived_at IS NULL \
           AND due_date IS NOT NULL AND due_date < ?1",
        [&today],
        |row| row.get(0),
    )?;
    // `.ok()` collapsed any DB error (lock
    // contention, schema drift) into `None` so the dashboard silently
    // rendered "none" instead of surfacing the real failure. Use
    // `.optional()?` so a truly missing row is OK but errors still
    // propagate.
    let current_focus: Option<String> = conn
        .query_row(
            "SELECT briefing FROM current_focus WHERE date = ?1",
            [&today],
            |row| row.get(0),
        )
        .optional()?;
    // Canonical task sort per CLAUDE.md core rule #4:
    //   `priority_effective ASC, due_date ASC NULLS LAST, id ASC`
    // ordering ignored priority entirely and let an unprioritised
    // task with a near-term due date jump ahead of a Critical task
    // due tomorrow — divergent from every other "next task" surface
    // in the codebase.
    let next_task_row: Option<(String, String)> = conn
        .query_row(
            "SELECT id, title FROM tasks
             WHERE status = 'open' AND archived_at IS NULL
             ORDER BY priority_effective ASC, due_date ASC NULLS LAST, id ASC
             LIMIT 1",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .optional()?;
    let next_task = next_task_row.as_ref().map(|(_, title)| title.clone());
    let next_task_id = next_task_row.map(|(id, _)| id);
    let due_today = load_task_items(
        conn,
        "SELECT id, title, COALESCE(planned_date, due_date) AS when_value
         FROM tasks
         WHERE status = 'open' AND archived_at IS NULL
           AND COALESCE(planned_date, due_date) = ?1
         ORDER BY priority_effective ASC, updated_at DESC, id ASC
         LIMIT 5",
        &[&today],
    )?;
    let upcoming = load_task_items(
        conn,
        "SELECT id, title, COALESCE(planned_date, due_date) AS when_value
         FROM tasks
         WHERE status = 'open' AND archived_at IS NULL
           AND COALESCE(planned_date, due_date) > ?1
         ORDER BY COALESCE(planned_date, due_date) ASC, priority_effective ASC, updated_at DESC, id ASC
         LIMIT 5",
        &[&today],
    )?;
    let recently_completed = load_task_items(
        conn,
        "SELECT id, title, completed_at AS when_value
         FROM tasks
         WHERE status = 'completed' AND archived_at IS NULL AND completed_at IS NOT NULL
         ORDER BY completed_at DESC, id ASC
         LIMIT 5",
        &[],
    )?;

    Ok(DashboardSnapshot {
        db_path: db_path.to_path_buf(),
        today,
        device_id,
        open_tasks,
        overdue_tasks,
        current_focus,
        next_task,
        next_task_id,
        due_today,
        upcoming,
        recently_completed,
    })
}

fn load_task_items(
    conn: &Connection,
    sql: &str,
    params: &[&dyn rusqlite::ToSql],
) -> Result<Vec<TaskListItem>, crate::error::CliError> {
    let mut stmt = conn.prepare(sql)?;
    let rows = stmt.query_map(params, |row| {
        Ok(TaskListItem {
            id: row.get(0)?,
            title: row.get(1)?,
            when: row.get(2)?,
        })
    })?;
    Ok(rows.collect::<Result<Vec<_>, _>>()?)
}

#[cfg(test)]
mod tests;
