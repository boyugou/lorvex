//! Shared focus-aggregate plumbing for the trash / permanent-delete paths.
//!
//! Both archive and permanent-delete need to:
//!   1. Snapshot the set of `current_focus` / `focus_schedule` parent dates
//!      that referenced the task BEFORE the cascade detaches its child rows
//!      (`current_focus_items`, `focus_schedule_blocks`).
//!   2. Re-emit the parent aggregate envelopes after the detach so peers
//!      stop seeing the trashed task in today's focus aggregate.
//!
//! `current_focus` / `focus_schedule` parent rows untouched and re-emitted
//! nothing — peers would still see the trashed task in today's focus
//! aggregate until the next time something else bumped the parent header.
//! Same defect class as #2938.

use rusqlite::Connection;

#[derive(Debug, Default)]
pub(super) struct FocusParentDates {
    pub(super) current_focus: Vec<String>,
    pub(super) focus_schedule: Vec<String>,
}

pub(super) fn collect_focus_parent_dates_for_task(
    conn: &Connection,
    task_id: &str,
) -> Result<FocusParentDates, crate::error::CliError> {
    let current_focus = {
        let mut stmt =
            conn.prepare("SELECT DISTINCT date FROM current_focus_items WHERE task_id = ?1")?;
        let rows: Result<Vec<String>, _> = stmt
            .query_map([task_id], |row| row.get::<_, String>(0))?
            .collect();
        rows?
    };
    let focus_schedule = {
        let mut stmt = conn.prepare(
            "SELECT DISTINCT schedule_date FROM focus_schedule_blocks WHERE task_id = ?1",
        )?;
        let rows: Result<Vec<String>, _> = stmt
            .query_map([task_id], |row| row.get::<_, String>(0))?
            .collect();
        rows?
    };
    Ok(FocusParentDates {
        current_focus,
        focus_schedule,
    })
}
