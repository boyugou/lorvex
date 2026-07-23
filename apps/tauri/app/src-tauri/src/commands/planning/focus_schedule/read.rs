use super::{blocks::query_schedule_blocks, *};

#[tauri::command]
pub fn get_focus_schedule() -> Result<Option<FocusScheduleWithTasks>, String> {
    let conn = get_read_conn()?;
    let today = lorvex_workflow::timezone::today_ymd_for_conn(&conn)
        .map_err(crate::error::AppError::from)
        .map_err(String::from)?;
    get_focus_schedule_with_conn(&conn, &today).map_err(String::from)
}

pub(super) fn get_focus_schedule_with_conn(
    conn: &rusqlite::Connection,
    today: &str,
) -> AppResult<Option<FocusScheduleWithTasks>> {
    let schedule = conn.query_row(
        "SELECT date, rationale, timezone, created_at \
         FROM focus_schedule WHERE date = ?1",
        params![today],
        |row| {
            Ok(FocusScheduleWithTasks {
                date: row.get(0)?,
                blocks: Vec::new(), // filled below from sub-table
                rationale: row.get(1)?,
                timezone: row.get(2)?,
                created_at: row.get(3)?,
                tasks: Vec::new(),
            })
        },
    );
    let schedule = <rusqlite::Result<_> as crate::commands::OptionalExt<_>>::optional(schedule)
        .map_err(AppError::from)?;

    let Some(mut schedule) = schedule else {
        return Ok(None);
    };

    // Derive blocks from sub-table
    schedule.blocks = query_schedule_blocks(conn, &schedule.date)?;

    let task_ids: Vec<String> = schedule
        .blocks
        .iter()
        .filter(|b| {
            // Typed parse keeps the dispatch tied to
            // `FocusBlockType` so it can't drift away from the enum
            // the way a bare `== "task"` literal would.
            lorvex_domain::FocusBlockType::parse(&b.block_type)
                .is_some_and(lorvex_domain::FocusBlockType::requires_task_id)
        })
        .filter_map(|b| b.task_id.clone())
        .collect();

    schedule.tasks = fetch_ordered_tasks_by_ids(conn, &task_ids, "Focus schedule")?;

    Ok(Some(schedule))
}
