use lorvex_domain::naming::STATUS_OPEN;
use rusqlite::{Connection, OptionalExtension};

use crate::models::CurrentFocusView;
use crate::render::task_row_to_summary;

use crate::commands::shared::{load_task_row, today_ymd_for_conn};

pub(super) fn validate_focus_task_ids_exist(
    conn: &Connection,
    task_ids: &[String],
) -> Result<(), crate::error::CliError> {
    for task_id in task_ids {
        let task_id_typed = lorvex_domain::TaskId::from_trusted(task_id.clone());
        load_task_row(conn, &task_id_typed)?;
    }
    Ok(())
}

pub(crate) fn load_current_focus_view(
    conn: &Connection,
) -> Result<Option<CurrentFocusView>, crate::error::CliError> {
    let today = today_ymd_for_conn(conn)?;
    load_current_focus_view_for_date(conn, &today)
}

pub(crate) fn load_current_focus_view_for_date(
    conn: &Connection,
    date: &str,
) -> Result<Option<CurrentFocusView>, crate::error::CliError> {
    type FocusRow = (String, Option<String>, Option<String>, String, String);
    let row: Option<FocusRow> = conn
        .query_row(
            "SELECT date, briefing, timezone, created_at, updated_at FROM current_focus WHERE date = ?1",
            [date],
            |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?, row.get(4)?)),
        )
        .optional()?;

    let Some((date, briefing, timezone, created_at, updated_at)) = row else {
        return Ok(None);
    };

    let all_task_ids = lorvex_store::current_focus_items::query_focus_task_ids(conn, &date)?;
    // Filter to only open tasks — completed/cancelled tasks should not appear in the focus plan.
    let mut task_ids = Vec::new();
    let mut tasks = Vec::new();
    for task_id in &all_task_ids {
        let task_id_typed = lorvex_domain::TaskId::from_trusted(task_id.clone());
        let row = load_task_row(conn, &task_id_typed)?;
        if row.core().status() == STATUS_OPEN {
            task_ids.push(task_id.clone());
            tasks.push(task_row_to_summary(row));
        }
    }

    Ok(Some(CurrentFocusView {
        date,
        briefing,
        timezone,
        created_at,
        updated_at,
        task_ids,
        tasks,
    }))
}
